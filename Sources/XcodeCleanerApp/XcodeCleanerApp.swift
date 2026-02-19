import AppKit
import SwiftUI
import XcodeInventoryCore

@main
struct XcodeCleanerApp: App {
    @StateObject private var viewModel = InventoryViewModel()
    @NSApplicationDelegateAdaptor(AppLaunchActivationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 560)
                .task {
                    viewModel.loadIfNeeded()
                }
        }
    }
}

final class AppLaunchActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Xcode may briefly keep focus while attaching the debugger, so retry activation a few times.
        let delays: [DispatchTimeInterval] = [.milliseconds(0), .milliseconds(120), .milliseconds(350)]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApplication.shared.setActivationPolicy(.regular)
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
                NSApplication.shared.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}

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

            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeScanID == scanID else {
                    return
                }
                self.snapshot = snapshot
                self.staleArtifactReport = self.staleArtifactDetector.detect(snapshot: snapshot)
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

    func execute(selection: DryRunSelection, allowDirectDelete: Bool) {
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
                allowDirectDelete: allowDirectDelete
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

    func switchActiveXcode(targetInstallPath: String) {
        guard let snapshot else {
            switchStatusMessage = "No scan snapshot available to switch active Xcode."
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

    func executeStaleCleanup(selectedCandidateIDs: [String], allowDirectDelete: Bool) {
        guard let snapshot else {
            executionStatusMessage = "No scan snapshot available for stale cleanup."
            return
        }
        guard !isExecuting else {
            return
        }

        let staleReport = staleArtifactReport ?? staleArtifactDetector.detect(snapshot: snapshot)
        let plan = StaleArtifactPlanner.makePlan(
            snapshot: snapshot,
            report: staleReport,
            selectedCandidateIDs: selectedCandidateIDs,
            now: Date()
        )
        guard !plan.items.isEmpty else {
            executionStatusMessage = "No stale artifacts selected for cleanup."
            return
        }

        isExecuting = true
        executionStatusMessage = "Executing stale artifact cleanup..."
        let executor = cleanupExecutor

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = executor.execute(
                snapshot: snapshot,
                plan: plan,
                allowDirectDelete: allowDirectDelete
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.lastExecutionReport = report
                self.executionStatusMessage = "Stale cleanup complete. Reclaimed \(ByteCountFormatter.string(fromByteCount: report.totalReclaimedBytes, countStyle: .file))."
                self.isExecuting = false
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
                ? DryRunSelection.safeCategoryDefaults.selectedCategoryKinds
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
                    if record.status == .executed,
                       let index = policies.firstIndex(where: { $0.id == record.policyID }) {
                        policies[index].lastSuccessfulRunAt = record.finishedAt
                        policies[index].updatedAt = record.finishedAt
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
                        if record.status == .executed {
                            didExecute = true
                            if let index = policies.firstIndex(where: { $0.id == record.policyID }) {
                                policies[index].lastSuccessfulRunAt = record.finishedAt
                                policies[index].updatedAt = record.finishedAt
                            }
                            if let report = record.executionReport {
                                self.lastExecutionReport = report
                            }
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

private func defaultAutomationStateDirectory() -> URL {
    URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        .appendingPathComponent(".xcodecleaner", isDirectory: true)
}

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case automation
    case tools
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .cleanup:
            return "Cleanup"
        case .automation:
            return "Automation"
        case .tools:
            return "Tools"
        case .reports:
            return "Reports"
        }
    }

    var symbol: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.50percent"
        case .cleanup:
            return "trash"
        case .automation:
            return "clock.arrow.circlepath"
        case .tools:
            return "wrench.and.screwdriver"
        case .reports:
            return "doc.text"
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: InventoryViewModel
    @State private var selectedCategoryKinds: Set<StorageCategoryKind> = Set(DryRunSelection.safeCategoryDefaults.selectedCategoryKinds)
    @State private var selectedSimulatorDeviceUDIDs: Set<String> = []
    @State private var selectedXcodeInstallPaths: Set<String> = []
    @State private var allowDirectDeleteFallback = false
    @State private var selectedSwitchInstallPath: String = ""
    @State private var selectedStaleArtifactIDs: Set<String> = []
    @State private var newPolicyName = ""
    @State private var newPolicyEveryHours = ""
    @State private var newPolicyMinAgeDays = ""
    @State private var newPolicyMinTotalBytes = ""
    @State private var newPolicyCategoryKinds: Set<StorageCategoryKind> = Set(DryRunSelection.safeCategoryDefaults.selectedCategoryKinds)
    @State private var newPolicySkipIfToolsRunning = true
    @State private var newPolicyAllowDirectDelete = false
    @State private var automationFormError: String?
    @State private var selectedSection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Sections")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                header
                statusStrip
                Divider()
                sectionContent
            }
            .padding(20)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("XcodeCleaner")
                    .font(.largeTitle.bold())
                Text("Sprint 10 Chunks 4-5: Tools and reports consolidation")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                viewModel.reload()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }

    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedSection.title)
                    .font(.headline)
                Spacer()
                if let snapshot = viewModel.snapshot {
                    Text("Last scan: \(formatDateTime(snapshot.scannedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if viewModel.isLoading {
                scanProgressView
            } else {
                Text("\(viewModel.scanPhaseTitle): \(viewModel.scanMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scanProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scanning")
                    .font(.headline)
                Spacer()
                Text("\(Int((viewModel.scanProgressFraction * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: viewModel.scanProgressFraction)
            Text(viewModel.scanPhaseTitle)
                .font(.callout.weight(.medium))
            Text(viewModel.scanMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if let snapshot = viewModel.snapshot {
            switch selectedSection {
            case .overview:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        runtimeTelemetryView(snapshot: snapshot)
                        storageOverviewView(snapshot: snapshot)
                        installInventoryView(snapshot: snapshot)
                        simulatorInventoryView(snapshot: snapshot)
                    }
                }
            case .cleanup:
                cleanupWorkflowView(snapshot: snapshot)
            case .automation:
                ScrollView {
                    automationPoliciesView()
                }
            case .tools:
                ScrollView {
                    modificationToolsView(snapshot: snapshot)
                }
            case .reports:
                ScrollView {
                    reportsView()
                }
            }
        } else if viewModel.isLoading {
            Text("Scanning...")
                .foregroundStyle(.secondary)
        } else {
            Text("No scan data yet.")
                .foregroundStyle(.secondary)
        }
    }

    private func reportsView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reports")
                .font(.headline)
            Text("Centralized history, trend summaries, and export actions for automation and cleanup runs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            reportsStatusPanel()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    automationRunSummariesPanel(title: "Automation Trend Summaries")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    automationRecentRunsPanel(title: "Automation Run History", maxRows: 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    automationRunSummariesPanel(title: "Automation Trend Summaries")
                    automationRecentRunsPanel(title: "Automation Run History", maxRows: 12)
                }
            }

            reportsExportsPanel()

            if let report = viewModel.lastExecutionReport {
                executionReportView(report)
            } else {
                Text("No cleanup execution report available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reportsStatusPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report Status")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Text("History loaded: \(viewModel.automationRunHistory.count)")
                    .font(.caption.monospacedDigit())
                Text("Trend windows: \(viewModel.automationTrendSummaries.count)")
                    .font(.caption.monospacedDigit())
                if let report = viewModel.lastExecutionReport {
                    Text("Last cleanup reclaimed: \(formatBytes(report.totalReclaimedBytes))")
                        .font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(.secondary)

            if let exportPath = viewModel.automationLastExportPath {
                Text("Last export: \(exportPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("No export has been generated in this session yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func modificationToolsView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools")
                .font(.headline)
            Text("Operational utilities for active-Xcode switching and stale artifact cleanup.")
                .font(.caption)
                .foregroundStyle(.secondary)

            toolsRuntimeSummaryPanel(snapshot: snapshot)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    activeXcodeSwitchPanel(snapshot: snapshot)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    staleArtifactManagementPanel()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    activeXcodeSwitchPanel(snapshot: snapshot)
                    staleArtifactManagementPanel()
                }
            }
        }
    }

    private func toolsRuntimeSummaryPanel(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runtime Summary")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Text("Running Xcode instances: \(snapshot.runtimeTelemetry.totalXcodeRunningInstances)")
                Text("Running Simulator instances: \(snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances)")
                Text("Stale selected: \(selectedStaleArtifactIDs.count)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func activeXcodeSwitchPanel(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Xcode Switch")
                .font(.subheadline.weight(.semibold))

            if snapshot.installs.isEmpty {
                Text("No Xcode installs available to switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Target Xcode", selection: $selectedSwitchInstallPath) {
                    ForEach(snapshot.installs) { install in
                        Text("\(install.displayName) (\(install.version ?? "Unknown"), \(install.build ?? "Unknown"))")
                            .tag(install.path)
                    }
                }
                .onAppear {
                    if selectedSwitchInstallPath.isEmpty {
                        selectedSwitchInstallPath = snapshot.installs.first(where: { !$0.isActive })?.path
                            ?? snapshot.installs.first?.path
                            ?? ""
                    }
                }

                Button("Switch Active Xcode") {
                    viewModel.switchActiveXcode(targetInstallPath: selectedSwitchInstallPath)
                }
                .disabled(selectedSwitchInstallPath.isEmpty || viewModel.isLoading || viewModel.isExecuting)

                Text(viewModel.switchStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let switchResult = viewModel.lastXcodeSwitchResult {
                    Text("Result: \(switchResult.status.rawValue) | New active: \(switchResult.newActiveDeveloperDirectoryPath ?? "Unknown")")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: switchResult.status))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func staleArtifactManagementPanel() -> some View {
        let staleReport = viewModel.staleArtifactReport

        return VStack(alignment: .leading, spacing: 10) {
            Text("Stale Runtime / Device Support")
                .font(.subheadline.weight(.semibold))

            if let staleReport {
                Text("Candidates: \(staleReport.candidates.count) | Selected: \(selectedStaleArtifactIDs.count) | Estimated reclaim: \(formatBytes(staleReport.totalReclaimableBytes))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Toggle("Allow direct delete fallback when move-to-trash fails", isOn: $allowDirectDeleteFallback)
                    .font(.caption)

                if staleReport.candidates.isEmpty {
                    Text("No stale candidates detected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(staleReport.candidates) { candidate in
                        Toggle(
                            isOn: Binding(
                                get: { selectedStaleArtifactIDs.contains(candidate.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedStaleArtifactIDs.insert(candidate.id)
                                    } else {
                                        selectedStaleArtifactIDs.remove(candidate.id)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(candidate.title)
                                    Spacer()
                                    Text(formatBytes(candidate.reclaimableBytes))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text("Kind: \(candidate.kind.rawValue), Safety: \(candidate.safetyClassification.rawValue)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(color(for: candidate.safetyClassification))
                                Text(candidate.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text(candidate.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Clean Selected Stale Artifacts") {
                        viewModel.executeStaleCleanup(
                            selectedCandidateIDs: Array(selectedStaleArtifactIDs),
                            allowDirectDelete: allowDirectDeleteFallback
                        )
                    }
                    .disabled(staleReport.candidates.isEmpty || selectedStaleArtifactIDs.isEmpty || viewModel.isExecuting || viewModel.isLoading)

                    Button("Select All") {
                        selectedStaleArtifactIDs = Set(staleReport.candidates.map(\.id))
                    }
                    .disabled(staleReport.candidates.isEmpty)

                    Button("Clear Selection") {
                        selectedStaleArtifactIDs.removeAll()
                    }
                    .disabled(selectedStaleArtifactIDs.isEmpty)
                }

                if !staleReport.notes.isEmpty {
                    ForEach(Array(staleReport.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Stale artifact report not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func cleanupWorkflowView(snapshot: XcodeInventorySnapshot) -> some View {
        let selection = DryRunSelection(
            selectedCategoryKinds: Array(selectedCategoryKinds),
            selectedSimulatorDeviceUDIDs: Array(selectedSimulatorDeviceUDIDs),
            selectedXcodeInstallPaths: Array(selectedXcodeInstallPaths)
        )
        let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleanup Workflow")
                        .font(.headline)
                    Text("Step 1: Select scope  ->  Step 2: Review plan  ->  Step 3: Execute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Estimated reclaim")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatBytes(plan.totalReclaimableBytes))
                        .font(.title3.weight(.semibold))
                }
                Button("Execute Cleanup") {
                    viewModel.execute(selection: selection, allowDirectDelete: allowDirectDeleteFallback)
                }
                .disabled(plan.items.isEmpty || viewModel.isExecuting || viewModel.isLoading)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Step 1 - Select Cleanup Scope")
                            .font(.subheadline.weight(.semibold))

                        Text("Categories")
                            .font(.callout.weight(.medium))
                        ForEach(snapshot.storage.categories) { category in
                            Toggle(
                                isOn: Binding(
                                    get: { selectedCategoryKinds.contains(category.kind) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedCategoryKinds.insert(category.kind)
                                        } else {
                                            selectedCategoryKinds.remove(category.kind)
                                        }
                                    }
                                )
                            ) {
                                HStack {
                                    Text(category.title)
                                    Spacer()
                                    Text(formatBytes(category.bytes))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Text("Simulator Devices")
                            .font(.callout.weight(.medium))
                        if snapshot.simulator.devices.isEmpty {
                            Text("No simulator devices found in this scan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.simulator.devices) { device in
                                Toggle(
                                    isOn: Binding(
                                        get: { selectedSimulatorDeviceUDIDs.contains(device.udid) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedSimulatorDeviceUDIDs.insert(device.udid)
                                            } else {
                                                selectedSimulatorDeviceUDIDs.remove(device.udid)
                                            }
                                        }
                                    )
                                ) {
                                    HStack {
                                        Text(device.name)
                                        Spacer()
                                        Text(formatBytes(device.sizeInBytes))
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        Text("Xcode Installs")
                            .font(.callout.weight(.medium))
                        if snapshot.installs.isEmpty {
                            Text("No Xcode installs found in this scan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.installs) { install in
                                Toggle(
                                    isOn: Binding(
                                        get: { selectedXcodeInstallPaths.contains(install.path) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedXcodeInstallPaths.insert(install.path)
                                            } else {
                                                selectedXcodeInstallPaths.remove(install.path)
                                            }
                                        }
                                    )
                                ) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(install.displayName)
                                            Text("Version: \(install.version ?? "Unknown"), Build: \(install.build ?? "Unknown")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(install.path)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .textSelection(.enabled)
                                        }
                                        Spacer()
                                        Text(formatBytes(install.sizeInBytes))
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Step 2 - Review Dry-Run Plan")
                            .font(.subheadline.weight(.semibold))
                        Text("Planned items: \(plan.items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        if !plan.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Plan notes")
                                    .font(.callout.weight(.medium))
                                ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if plan.items.isEmpty {
                            Text("No dry-run items selected.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(plan.items) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.title)
                                            .font(.callout.weight(.medium))
                                        Spacer()
                                        Text(formatBytes(item.reclaimableBytes))
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Kind: \(item.kind.rawValue), Safety: \(item.safetyClassification.rawValue)\(item.storageCategoryKind.map { ", Category: \($0.rawValue)" } ?? "")")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(color(for: item.safetyClassification))
                                    Text("Ownership: \(item.ownershipSummary)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !item.paths.isEmpty {
                                        Text(item.paths.joined(separator: "\n"))
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(8)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Step 3 - Execute Options and Status")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Allow direct delete fallback when move-to-trash fails", isOn: $allowDirectDeleteFallback)
                            .font(.callout)

                        if viewModel.isExecuting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Executing cleanup...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(viewModel.executionStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    if let report = viewModel.lastExecutionReport {
                        executionReportView(report)
                    }
                }
            }
        }
    }

    private func automationPoliciesView() -> some View {
        let duePolicyCount = AutomationPolicies.duePolicies(
            from: viewModel.automationPolicies,
            now: Date()
        ).count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Automation Center")
                .font(.headline)
            Text("Manage policy lifecycle, execution, and reporting in one workflow-focused section.")
                .font(.caption)
                .foregroundStyle(.secondary)

            automationOperationsPanel(duePolicyCount: duePolicyCount)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    automationPolicyListPanel()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    automationPolicyCreatePanel()
                        .frame(width: 360, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    automationPolicyListPanel()
                    automationPolicyCreatePanel()
                }
            }

            automationReportingShortcutPanel()
        }
    }

    private func automationOperationsPanel(duePolicyCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Operations")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isExecuting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Policies: \(viewModel.automationPolicies.count)")
                    .font(.caption.monospacedDigit())
                Text("Due now: \(duePolicyCount)")
                    .font(.caption.monospacedDigit())
                Text("History loaded: \(viewModel.automationRunHistory.count)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            Text(viewModel.automationStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Run Due Policies Now") {
                    viewModel.runDueAutomationPoliciesNow()
                }
                .disabled(viewModel.isExecuting || viewModel.isLoading)

                Button("Refresh Automation Data") {
                    viewModel.loadAutomationState()
                }
                .disabled(viewModel.isExecuting || viewModel.isLoading)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func automationPolicyListPanel() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configured Policies (\(viewModel.automationPolicies.count))")
                .font(.subheadline.weight(.semibold))

            if viewModel.automationPolicies.isEmpty {
                Text("No automation policies yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.automationPolicies) { policy in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(policy.name)
                                .font(.callout.weight(.medium))
                            Spacer()
                            if isAutomationPolicyDueNow(policy) {
                                Text("DUE")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text(policy.isEnabled ? "ENABLED" : "DISABLED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(policy.isEnabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text("Schedule: \(formattedSchedule(for: policy))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Categories: \(policy.selection.selectedCategoryKinds.map(title(for:)).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Skip if tools running: \(policy.skipIfToolsRunning ? "Yes" : "No"), Direct delete fallback: \(policy.allowDirectDelete ? "Yes" : "No")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let minAgeDays = policy.minAgeDays {
                            Text("Minimum age: \(minAgeDays) day(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let minBytes = policy.minTotalReclaimBytes {
                            Text("Minimum reclaim: \(formatBytes(minBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Last successful run: \(formatDateTime(policy.lastSuccessfulRunAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Toggle(
                                isOn: Binding(
                                    get: { policy.isEnabled },
                                    set: { newValue in
                                        viewModel.setAutomationPolicyEnabled(
                                            policyID: policy.id,
                                            isEnabled: newValue
                                        )
                                    }
                                )
                            ) {
                                Text("Enabled")
                            }
                            .toggleStyle(.switch)

                            Button("Run Now") {
                                viewModel.runAutomationPolicyNow(policyID: policy.id)
                            }
                            .disabled(viewModel.isExecuting || viewModel.isLoading)

                            Button(role: .destructive) {
                                viewModel.deleteAutomationPolicy(policyID: policy.id)
                            } label: {
                                Text("Delete")
                            }
                            .disabled(viewModel.isExecuting || viewModel.isLoading)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func automationPolicyCreatePanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Policy")
                .font(.subheadline.weight(.semibold))

            TextField("Policy name", text: $newPolicyName)
                .textFieldStyle(.roundedBorder)

            TextField("Every hours (blank = manual only)", text: $newPolicyEveryHours)
                .textFieldStyle(.roundedBorder)
            TextField("Min age days", text: $newPolicyMinAgeDays)
                .textFieldStyle(.roundedBorder)
            TextField("Min reclaim bytes", text: $newPolicyMinTotalBytes)
                .textFieldStyle(.roundedBorder)

            Text("Categories")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(StorageCategoryKind.allCases, id: \.rawValue) { kind in
                Toggle(
                    isOn: Binding(
                        get: { newPolicyCategoryKinds.contains(kind) },
                        set: { isSelected in
                            if isSelected {
                                newPolicyCategoryKinds.insert(kind)
                            } else {
                                newPolicyCategoryKinds.remove(kind)
                            }
                        }
                    )
                ) {
                    Text(title(for: kind))
                }
            }

            Toggle("Skip if Xcode/Simulator is running", isOn: $newPolicySkipIfToolsRunning)
            Toggle("Allow direct delete fallback", isOn: $newPolicyAllowDirectDelete)

            if let automationFormError {
                Text(automationFormError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Create Automation Policy") {
                createPolicyFromForm()
            }
            .disabled(viewModel.isExecuting || viewModel.isLoading)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func automationReportingShortcutPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reporting and Exports")
                .font(.subheadline.weight(.semibold))
            Text("Run history, trend summaries, and export actions are now centralized in the Reports section.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Reports Section") {
                selectedSection = .reports
            }
            .disabled(selectedSection == .reports)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func automationRunSummariesPanel(title: String = "Run Summaries") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if let allTime = viewModel.automationAllTimeSummary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All-time")
                        .font(.callout.weight(.medium))
                    Text(
                        "Runs: \(allTime.totalRuns) | Executed: \(allTime.executedRuns) | Skipped: \(allTime.skippedRuns) | Failed: \(allTime.failedRuns) | Reclaimed: \(formatBytes(allTime.totalReclaimedBytes))"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No all-time summary yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.automationTrendSummaries.isEmpty {
                Text("No trend windows available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.automationTrendSummaries, id: \.windowDays) { summary in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last \(summary.windowDays) day(s)")
                            .font(.callout.weight(.medium))
                        Text(
                            "Runs: \(summary.totalRuns) | Executed: \(summary.executedRuns) | Skipped: \(summary.skippedRuns) | Failed: \(summary.failedRuns) | Reclaimed: \(formatBytes(summary.totalReclaimedBytes))"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func automationRecentRunsPanel(title: String = "Recent Runs", maxRows: Int = 8) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if viewModel.automationRunHistory.isEmpty {
                Text("No automation run history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.automationRunHistory.prefix(maxRows))) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.policyName)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(record.status.rawValue.uppercased())
                                .font(.caption.monospaced())
                                .foregroundStyle(color(for: record.status))
                            Text(formatBytes(record.totalReclaimedBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("Trigger: \(record.trigger.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Started: \(formatDateTime(record.startedAt)) | Finished: \(formatDateTime(record.finishedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(record.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func reportsExportsPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Actions")
                .font(.subheadline.weight(.semibold))
            Text("Export automation history and trend summaries in JSON or CSV.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("History JSON") {
                    viewModel.exportAutomationHistoryJSON()
                }
                Button("History CSV") {
                    viewModel.exportAutomationHistoryCSV()
                }
                Button("Trends JSON") {
                    viewModel.exportAutomationTrendsJSON()
                }
                Button("Trends CSV") {
                    viewModel.exportAutomationTrendsCSV()
                }
            }
            .disabled(viewModel.isExecuting || viewModel.isLoading)

            if let exportPath = viewModel.automationLastExportPath {
                Text("Last export: \(exportPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func runtimeTelemetryView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runtime Telemetry")
                .font(.headline)
            HStack(spacing: 12) {
                Text("Running Xcode instances: \(snapshot.runtimeTelemetry.totalXcodeRunningInstances)")
                Text("Running Simulator app instances: \(snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances)")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func storageOverviewView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage Overview")
                .font(.headline)
            Text("Total Xcode Footprint: \(formatBytes(snapshot.storage.totalBytes))")
                .font(.title3.weight(.semibold))

            ForEach(snapshot.storage.categories) { category in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text(formatBytes(category.bytes))
                            .font(.callout.monospacedDigit())
                    }
                    .font(.callout.weight(.medium))

                    if !category.paths.isEmpty {
                        Text(category.paths.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Text("Ownership: \(category.ownershipSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Safety: \(category.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: category.safetyClassification))
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func installInventoryView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Xcode installs: \(snapshot.installs.count)")
                .font(.headline)

            if let activePath = snapshot.activeDeveloperDirectoryPath {
                Text("Active Developer Directory: \(activePath)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Active Developer Directory: Unknown")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(snapshot.installs) { install in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(install.displayName)
                            .font(.title3.weight(.semibold))
                        if install.isActive {
                            Text("ACTIVE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if install.runningInstanceCount > 0 {
                            Text("RUNNING x\(install.runningInstanceCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        Text(formatBytes(install.sizeInBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Text("Version: \(install.version ?? "Unknown")")
                        Text("Build: \(install.build ?? "Unknown")")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Text(install.path)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)

                    Text("Ownership: \(install.ownershipSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Safety: \(install.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: install.safetyClassification))
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func simulatorInventoryView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulator Inventory")
                .font(.headline)

            Text("Devices: \(snapshot.simulator.devices.count), Runtimes: \(snapshot.simulator.runtimes.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("Simulator Runtimes")
                .font(.subheadline.weight(.semibold))
            ForEach(snapshot.simulator.runtimes) { runtime in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(runtime.name)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(formatBytes(runtime.sizeInBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Identifier: \(runtime.identifier)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Version: \(runtime.version ?? "Unknown"), Available: \(runtime.isAvailable ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let bundlePath = runtime.bundlePath {
                        Text(bundlePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Safety: \(runtime.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: runtime.safetyClassification))
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Simulator Devices")
                .font(.subheadline.weight(.semibold))
            ForEach(snapshot.simulator.devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name)
                            .font(.callout.weight(.medium))
                        Spacer()
                        if device.runningInstanceCount > 0 {
                            Text("RUNNING x\(device.runningInstanceCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(formatBytes(device.sizeInBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Runtime: \(device.runtimeName ?? device.runtimeIdentifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("State: \(device.state), Available: \(device.isAvailable ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("UDID: \(device.udid)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(device.dataPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Safety: \(device.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: device.safetyClassification))
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func executionReportView(_ report: CleanupExecutionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Cleanup Execution")
                .font(.headline)
            Text(
                "Reclaimed: \(formatBytes(report.totalReclaimedBytes)) | Succeeded: \(report.succeededCount) | Partial: \(report.partiallySucceededCount) | Blocked: \(report.blockedCount) | Failed: \(report.failedCount)"
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)

            ForEach(report.results) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(result.item.title)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(result.status.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(color(for: result.status))
                        Text(formatBytes(result.reclaimedBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(result.pathResults) { pathResult in
                        Text("\(pathResult.status.rawValue): \(pathResult.path) (\(pathResult.operation.rawValue), \(formatBytes(pathResult.reclaimedBytes)))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func createPolicyFromForm() {
        let trimmedName = newPolicyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            automationFormError = "Policy name is required."
            return
        }

        let everyHoursResult = parsePositiveInt(from: newPolicyEveryHours)
        switch everyHoursResult {
        case .invalid:
            automationFormError = "Every hours must be a positive whole number."
            return
        case .none, .value:
            break
        }

        let minAgeDaysResult = parsePositiveInt(from: newPolicyMinAgeDays)
        switch minAgeDaysResult {
        case .invalid:
            automationFormError = "Minimum age days must be a positive whole number."
            return
        case .none, .value:
            break
        }

        let minBytesResult = parseNonNegativeInt64(from: newPolicyMinTotalBytes)
        switch minBytesResult {
        case .invalid:
            automationFormError = "Minimum reclaim bytes must be a non-negative whole number."
            return
        case .none, .value:
            break
        }

        automationFormError = nil
        viewModel.createAutomationPolicy(
            name: trimmedName,
            categoryKinds: Array(newPolicyCategoryKinds).sorted { $0.rawValue < $1.rawValue },
            everyHours: everyHoursResult.value,
            minAgeDays: minAgeDaysResult.value,
            minTotalReclaimBytes: minBytesResult.value,
            skipIfToolsRunning: newPolicySkipIfToolsRunning,
            allowDirectDelete: newPolicyAllowDirectDelete
        )

        newPolicyName = ""
        newPolicyEveryHours = ""
        newPolicyMinAgeDays = ""
        newPolicyMinTotalBytes = ""
    }

    private func title(for kind: StorageCategoryKind) -> String {
        switch kind {
        case .xcodeApplications:
            return "Xcode Applications"
        case .derivedData:
            return "Derived Data"
        case .archives:
            return "Archives"
        case .deviceSupport:
            return "Device Support"
        case .simulatorData:
            return "Simulator Data"
        }
    }

    private func isAutomationPolicyDueNow(_ policy: AutomationPolicy) -> Bool {
        AutomationPolicies.duePolicies(from: [policy], now: Date()).isEmpty == false
    }

    private func formattedSchedule(for policy: AutomationPolicy) -> String {
        switch policy.schedule {
        case .manualOnly:
            return "Manual only"
        case .everyHours(let hours):
            if let lastRun = policy.lastSuccessfulRunAt {
                let nextDue = lastRun.addingTimeInterval(Double(hours) * 3_600)
                return "Every \(hours)h (next due: \(formatDateTime(nextDue)))"
            }
            return "Every \(hours)h (next due: now)"
        }
    }

    private func formatDateTime(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }
        return Self.dateTimeFormatter.string(from: date)
    }

    private enum ParsedIntResult<T> {
        case none
        case value(T)
        case invalid

        var value: T? {
            switch self {
            case .value(let value):
                return value
            case .none, .invalid:
                return nil
            }
        }
    }

    private func parsePositiveInt(from text: String) -> ParsedIntResult<Int> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .none
        }
        guard let value = Int(trimmed), value > 0 else {
            return .invalid
        }
        return .value(value)
    }

    private func parseNonNegativeInt64(from text: String) -> ParsedIntResult<Int64> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .none
        }
        guard let value = Int64(trimmed), value >= 0 else {
            return .invalid
        }
        return .value(value)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func color(for safetyClassification: SafetyClassification) -> Color {
        switch safetyClassification {
        case .regenerable:
            return .green
        case .conditionallySafe:
            return .orange
        case .destructive:
            return .red
        }
    }

    private func color(for status: CleanupActionStatus) -> Color {
        switch status {
        case .succeeded:
            return .green
        case .partiallySucceeded:
            return .orange
        case .blocked:
            return .yellow
        case .failed:
            return .red
        }
    }

    private func color(for status: ActiveXcodeSwitchStatus) -> Color {
        switch status {
        case .succeeded:
            return .green
        case .blocked:
            return .orange
        case .failed:
            return .red
        }
    }

    private func color(for status: AutomationRunStatus) -> Color {
        switch status {
        case .executed:
            return .green
        case .skipped:
            return .orange
        case .failed:
            return .red
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
