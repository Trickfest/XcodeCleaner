import Foundation
import SwiftUI
import XcodeInventoryCore

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var snapshot: XcodeInventorySnapshot?
    @Published private(set) var scanProgressFraction: Double = 0
    @Published private(set) var scanPhaseTitle = "Idle"
    @Published private(set) var scanMessage = "Ready"
    @Published private(set) var isExecuting = false
    @Published private(set) var lastExecutionReport: CleanupExecutionReport?
    @Published private(set) var executionStatusMessage = "No cleanup executed yet."
    @Published private(set) var staleArtifactReport: StaleArtifactReport?
    @Published private(set) var lastStaleArtifactExecutionReport: CleanupExecutionReport?
    @Published private(set) var staleArtifactStatusMessage = "No stale/orphaned artifact cleanup executed yet."
    @Published private(set) var lastXcodeSwitchResult: ActiveXcodeSwitchResult?
    @Published private(set) var switchStatusMessage = "No active-Xcode switch executed yet."
    @Published private(set) var automationPolicies: [AutomationPolicy] = []
    @Published private(set) var automationRunHistory: [AutomationPolicyRunRecord] = []
    @Published private(set) var automationAllTimeSummary: AutomationHistoryWindowSummary?
    @Published private(set) var automationTrendSummaries: [AutomationHistoryWindowSummary] = []
    @Published private(set) var automationLastExportPath: String?
    @Published private(set) var automationStatusMessage = "No automation runs yet."

    private let scanner: XcodeInventoryScanner
    private let cleanupExecutor: CleanupExecutor
    private let staleArtifactDetector: StaleArtifactDetector
    private let activeXcodeSwitcher: ActiveXcodeSwitcher
    private let automationStore: any AutomationPolicyStoring
    private let automationRunner: AutomationPolicyRunner
    private var activeScanID = UUID()

    init(
        scanner: XcodeInventoryScanner = XcodeInventoryScanner(),
        cleanupExecutor: CleanupExecutor = CleanupExecutor(),
        staleArtifactDetector: StaleArtifactDetector = StaleArtifactDetector(),
        activeXcodeSwitcher: ActiveXcodeSwitcher = ActiveXcodeSwitcher(),
        automationStore: any AutomationPolicyStoring = JSONAutomationPolicyStore(
            stateDirectoryURL: defaultAutomationStateDirectory()
        ),
        automationRunner: AutomationPolicyRunner = AutomationPolicyRunner()
    ) {
        self.scanner = scanner
        self.cleanupExecutor = cleanupExecutor
        self.staleArtifactDetector = staleArtifactDetector
        self.activeXcodeSwitcher = activeXcodeSwitcher
        self.automationStore = automationStore
        self.automationRunner = automationRunner
    }

    func loadIfNeeded() {
        guard snapshot == nil else {
            return
        }
        reload()
    }

    func reload() {
        isLoading = true
        scanProgressFraction = 0
        scanPhaseTitle = ScanPhase.discoveringXcodeInstalls.title
        scanMessage = "Starting scan..."
        let scanID = UUID()
        activeScanID = scanID
        let scanner = self.scanner
        let staleArtifactDetector = self.staleArtifactDetector

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = scanner.scan { progress in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeScanID == scanID else {
                        return
                    }
                    self.scanProgressFraction = progress.fractionCompleted
                    self.scanPhaseTitle = progress.phase.title
                    self.scanMessage = progress.message
                }
            }
            let staleArtifactReport = staleArtifactDetector.detect(snapshot: snapshot)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeScanID == scanID else {
                    return
                }
                self.snapshot = snapshot
                self.staleArtifactReport = staleArtifactReport
                self.scanProgressFraction = 1
                self.scanPhaseTitle = ScanPhase.finalizingSnapshot.title
                self.scanMessage = "Scan complete"
                self.loadAutomationState()
                self.isLoading = false
            }
        }
    }

    func loadAutomationState() {
        do {
            let policies = try automationStore.loadPolicies()
            automationPolicies = policies.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            let fullHistory = try automationStore.loadRunHistory()
            automationRunHistory = Array(fullHistory.prefix(20))
            automationAllTimeSummary = makeAllTimeSummary(from: fullHistory)
            automationTrendSummaries = AutomationHistoryTrends.summaries(records: fullHistory)
        } catch {
            automationStatusMessage = "Failed to load automation state: \(error.localizedDescription)"
        }
    }

    func execute(selection: DryRunSelection, allowDirectDelete: Bool, requireToolsStopped: Bool) {
        guard let snapshot else {
            executionStatusMessage = "No scan snapshot available for cleanup execution."
            return
        }
        guard !isExecuting else {
            return
        }

        isExecuting = true
        executionStatusMessage = "Executing cleanup plan..."
        let executor = cleanupExecutor

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = executor.execute(
                snapshot: snapshot,
                selection: selection,
                allowDirectDelete: allowDirectDelete,
                requireToolsStopped: requireToolsStopped
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.lastExecutionReport = report
                self.executionStatusMessage = "Cleanup complete. Reclaimed \(ByteCountFormatter.string(fromByteCount: report.totalReclaimedBytes, countStyle: .file))."
                self.isExecuting = false
                self.reload()
            }
        }
    }

    func executeStaleArtifactCleanup(
        selectedCandidateIDs: [String],
        allowDirectDelete: Bool,
        requireToolsStopped: Bool
    ) {
        guard let snapshot else {
            staleArtifactStatusMessage = "No scan snapshot available for stale/orphaned artifact cleanup."
            return
        }
        guard !isExecuting else {
            return
        }

        let report = staleArtifactReport ?? staleArtifactDetector.detect(snapshot: snapshot)
        let plan = StaleArtifactPlanner.makePlan(
            snapshot: snapshot,
            report: report,
            selectedCandidateIDs: selectedCandidateIDs,
            now: Date(),
            defaultToAllCandidatesWhenSelectionEmpty: false
        )
        guard !plan.items.isEmpty else {
            staleArtifactStatusMessage = "No stale/orphaned artifacts selected for cleanup."
            return
        }

        isExecuting = true
        staleArtifactStatusMessage = "Executing stale/orphaned artifact cleanup..."
        let executor = cleanupExecutor

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let executionReport = executor.execute(
                snapshot: snapshot,
                plan: plan,
                allowDirectDelete: allowDirectDelete,
                requireToolsStopped: requireToolsStopped
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.lastStaleArtifactExecutionReport = executionReport
                if let skippedReason = executionReport.skippedReason {
                    self.staleArtifactStatusMessage = skippedReason
                } else {
                    self.staleArtifactStatusMessage = "Stale/orphaned cleanup complete. Reclaimed \(ByteCountFormatter.string(fromByteCount: executionReport.totalReclaimedBytes, countStyle: .file))."
                }
                self.isExecuting = false
                self.reload()
            }
        }
    }

    func switchActiveXcode(targetInstallPath: String) {
        guard let snapshot else {
            switchStatusMessage = "No scan snapshot available to switch active Xcode."
            return
        }
        let normalizedTarget = URL(filePath: targetInstallPath).standardizedFileURL.resolvingSymlinksInPath().path
        if let targetInstall = snapshot.installs.first(where: {
            URL(filePath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path == normalizedTarget
        }), targetInstall.isActive {
            switchStatusMessage = "Selected Xcode is already active. Choose a different install to switch."
            return
        }

        switchStatusMessage = "Switching active Xcode..."
        let switcher = activeXcodeSwitcher
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = switcher.switchActiveXcode(
                snapshot: snapshot,
                targetInstallPath: targetInstallPath
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.lastXcodeSwitchResult = result
                self.switchStatusMessage = result.message
                self.reload()
            }
        }
    }

    func createAutomationPolicy(
        name: String,
        categoryKinds: [StorageCategoryKind],
        everyHours: Int?,
        minAgeDays: Int?,
        minTotalReclaimBytes: Int64?,
        skipIfToolsRunning: Bool,
        allowDirectDelete: Bool
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            automationStatusMessage = "Automation policy name is required."
            return
        }
        if let everyHours, everyHours <= 0 {
            automationStatusMessage = "Automation schedule must be greater than zero hours."
            return
        }
        if let minAgeDays, minAgeDays <= 0 {
            automationStatusMessage = "Minimum age must be greater than zero days."
            return
        }
        if let minTotalReclaimBytes, minTotalReclaimBytes < 0 {
            automationStatusMessage = "Minimum reclaim bytes cannot be negative."
            return
        }

        do {
            var policies = try automationStore.loadPolicies()
            let now = Date()
            let categories = categoryKinds.isEmpty
                ? guiDefaultCleanupCategoryKinds
                : categoryKinds
            let policy = AutomationPolicy(
                name: trimmedName,
                schedule: everyHours.map { .everyHours($0) } ?? .manualOnly,
                selection: DryRunSelection(
                    selectedCategoryKinds: categories,
                    selectedSimulatorDeviceUDIDs: [],
                    selectedXcodeInstallPaths: []
                ),
                minAgeDays: minAgeDays,
                minTotalReclaimBytes: minTotalReclaimBytes,
                skipIfToolsRunning: skipIfToolsRunning,
                allowDirectDelete: allowDirectDelete,
                createdAt: now,
                updatedAt: now
            )
            policies.append(policy)
            try automationStore.savePolicies(policies)
            automationStatusMessage = "Created automation policy '\(policy.name)'."
            loadAutomationState()
        } catch {
            automationStatusMessage = "Failed to create automation policy: \(error.localizedDescription)"
        }
    }

    func setAutomationPolicyEnabled(policyID: String, isEnabled: Bool) {
        do {
            var policies = try automationStore.loadPolicies()
            guard let index = policies.firstIndex(where: { $0.id == policyID }) else {
                automationStatusMessage = "Automation policy not found."
                return
            }
            policies[index].isEnabled = isEnabled
            policies[index].updatedAt = Date()
            try automationStore.savePolicies(policies)
            automationStatusMessage = isEnabled
                ? "Enabled automation policy '\(policies[index].name)'."
                : "Disabled automation policy '\(policies[index].name)'."
            loadAutomationState()
        } catch {
            automationStatusMessage = "Failed to update automation policy: \(error.localizedDescription)"
        }
    }

    func deleteAutomationPolicy(policyID: String) {
        do {
            var policies = try automationStore.loadPolicies()
            guard let index = policies.firstIndex(where: { $0.id == policyID }) else {
                automationStatusMessage = "Automation policy not found."
                return
            }
            let name = policies[index].name
            policies.remove(at: index)
            try automationStore.savePolicies(policies)
            automationStatusMessage = "Deleted automation policy '\(name)'."
            loadAutomationState()
        } catch {
            automationStatusMessage = "Failed to delete automation policy: \(error.localizedDescription)"
        }
    }

    func runAutomationPolicyNow(policyID: String) {
        guard !isExecuting else {
            return
        }

        guard let currentSnapshot = snapshot else {
            automationStatusMessage = "No scan snapshot available. Refresh and try again."
            return
        }
        let policy: AutomationPolicy
        do {
            let policies = try automationStore.loadPolicies()
            guard let matched = policies.first(where: { $0.id == policyID }) else {
                automationStatusMessage = "Automation policy not found."
                return
            }
            policy = matched
        } catch {
            automationStatusMessage = "Failed to load automation policies: \(error.localizedDescription)"
            return
        }

        isExecuting = true
        automationStatusMessage = "Running automation policy..."
        let runner = automationRunner

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let record = runner.run(
                policy: policy,
                snapshot: currentSnapshot,
                trigger: .manual
            )

            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                do {
                    var policies = try self.automationStore.loadPolicies()
                    try self.automationStore.appendRunHistory(record)
                    if let index = policies.firstIndex(where: { $0.id == record.policyID }) {
                        policies[index] = AutomationPolicies.applyRunRecord(record, to: policies[index])
                        try self.automationStore.savePolicies(policies)
                    }
                    self.automationStatusMessage = record.message
                    if let report = record.executionReport {
                        self.lastExecutionReport = report
                        self.executionStatusMessage = "Automation run complete. Reclaimed \(ByteCountFormatter.string(fromByteCount: report.totalReclaimedBytes, countStyle: .file))."
                    }
                    self.loadAutomationState()
                    self.reload()
                } catch {
                    self.automationStatusMessage = "Automation run failed: \(error.localizedDescription)"
                }
                self.isExecuting = false
            }
        }
    }

    func runDueAutomationPoliciesNow() {
        guard !isExecuting else {
            return
        }
        guard let currentSnapshot = snapshot else {
            automationStatusMessage = "No scan snapshot available. Refresh and try again."
            return
        }
        let duePolicies: [AutomationPolicy]
        do {
            duePolicies = AutomationPolicies.duePolicies(
                from: try automationStore.loadPolicies(),
                now: Date()
            )
        } catch {
            automationStatusMessage = "Failed to load automation policies: \(error.localizedDescription)"
            return
        }
        guard !duePolicies.isEmpty else {
            automationStatusMessage = "No due automation policies."
            return
        }

        isExecuting = true
        automationStatusMessage = "Running due automation policies..."
        let runner = automationRunner

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let records = duePolicies.map { policy in
                runner.run(policy: policy, snapshot: currentSnapshot, trigger: .scheduled)
            }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                do {
                    var policies = try self.automationStore.loadPolicies()
                    var didExecute = false
                    for record in records {
                        try self.automationStore.appendRunHistory(record)
                        if let index = policies.firstIndex(where: { $0.id == record.policyID }) {
                            policies[index] = AutomationPolicies.applyRunRecord(record, to: policies[index])
                        }
                        if record.status == .executed {
                            didExecute = true
                        }
                        if let report = record.executionReport {
                            self.lastExecutionReport = report
                        }
                    }
                    try self.automationStore.savePolicies(policies)
                    self.automationStatusMessage = didExecute
                        ? "Due automation policies finished."
                        : "Due automation policies were evaluated; no cleanup executed."
                    self.loadAutomationState()
                    self.reload()
                } catch {
                    self.automationStatusMessage = "Due automation run failed: \(error.localizedDescription)"
                }
                self.isExecuting = false
            }
        }
    }

    func exportAutomationHistoryJSON() {
        do {
            let history = try automationStore.loadRunHistory()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            let outputURL = try writeAutomationExport(data: data, baseFileName: "automation-history", fileExtension: "json")
            automationLastExportPath = outputURL.path
            automationStatusMessage = "Exported automation history JSON (\(history.count) runs) to \(outputURL.path)."
        } catch {
            automationStatusMessage = "Failed to export automation history JSON: \(error.localizedDescription)"
        }
    }

    func exportAutomationHistoryCSV() {
        do {
            let history = try automationStore.loadRunHistory()
            let csv = AutomationHistoryCSVExporter.export(records: history)
            guard let data = csv.data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            let outputURL = try writeAutomationExport(data: data, baseFileName: "automation-history", fileExtension: "csv")
            automationLastExportPath = outputURL.path
            automationStatusMessage = "Exported automation history CSV (\(history.count) runs) to \(outputURL.path)."
        } catch {
            automationStatusMessage = "Failed to export automation history CSV: \(error.localizedDescription)"
        }
    }

    func exportAutomationTrendsJSON() {
        do {
            let history = try automationStore.loadRunHistory()
            let summaries = AutomationHistoryTrends.summaries(records: history)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summaries)
            let outputURL = try writeAutomationExport(data: data, baseFileName: "automation-trends", fileExtension: "json")
            automationLastExportPath = outputURL.path
            automationStatusMessage = "Exported automation trends JSON (\(summaries.count) window(s)) to \(outputURL.path)."
        } catch {
            automationStatusMessage = "Failed to export automation trends JSON: \(error.localizedDescription)"
        }
    }

    func exportAutomationTrendsCSV() {
        do {
            let history = try automationStore.loadRunHistory()
            let summaries = AutomationHistoryTrends.summaries(records: history)
            let csv = AutomationTrendCSVExporter.export(summaries: summaries)
            guard let data = csv.data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            let outputURL = try writeAutomationExport(data: data, baseFileName: "automation-trends", fileExtension: "csv")
            automationLastExportPath = outputURL.path
            automationStatusMessage = "Exported automation trends CSV (\(summaries.count) window(s)) to \(outputURL.path)."
        } catch {
            automationStatusMessage = "Failed to export automation trends CSV: \(error.localizedDescription)"
        }
    }

    private func writeAutomationExport(data: Data, baseFileName: String, fileExtension: String) throws -> URL {
        let directoryURL = defaultAutomationStateDirectory()
            .appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let timestamp = Self.exportTimestampFormatter.string(from: Date())
        let outputURL = directoryURL.appendingPathComponent("\(baseFileName)-\(timestamp).\(fileExtension)", isDirectory: false)
        try data.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private static let exportTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private func makeAllTimeSummary(from records: [AutomationPolicyRunRecord]) -> AutomationHistoryWindowSummary? {
        guard !records.isEmpty else {
            return nil
        }
        let executed = records.filter { $0.status == .executed }.count
        let skipped = records.filter { $0.status == .skipped }.count
        let failed = records.filter { $0.status == .failed }.count
        let reclaimed = records.reduce(Int64(0)) { partial, record in
            partial + record.totalReclaimedBytes
        }
        return AutomationHistoryWindowSummary(
            windowDays: 0,
            totalRuns: records.count,
            executedRuns: executed,
            skippedRuns: skipped,
            failedRuns: failed,
            totalReclaimedBytes: reclaimed
        )
    }
}
