import Foundation

public enum AutomationTrigger: String, Codable, Sendable {
    case manual
    case scheduled
}

public enum AutomationPolicySchedule: Codable, Equatable, Sendable {
    case manualOnly
    case everyHours(Int)

    public var summary: String {
        switch self {
        case .manualOnly:
            return "Manual only"
        case .everyHours(let hours):
            return "Every \(hours) hour(s)"
        }
    }
}

public struct AutomationPolicy: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var isEnabled: Bool
    public var schedule: AutomationPolicySchedule
    public var selection: DryRunSelection
    public var minAgeDays: Int?
    public var minTotalReclaimBytes: Int64?
    public var skipIfToolsRunning: Bool
    public var allowDirectDelete: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var lastEvaluatedRunAt: Date?
    public var lastSuccessfulRunAt: Date?

    public init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        schedule: AutomationPolicySchedule,
        selection: DryRunSelection,
        minAgeDays: Int? = nil,
        minTotalReclaimBytes: Int64? = nil,
        skipIfToolsRunning: Bool = true,
        allowDirectDelete: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastEvaluatedRunAt: Date? = nil,
        lastSuccessfulRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.schedule = schedule
        self.selection = selection
        self.minAgeDays = minAgeDays
        self.minTotalReclaimBytes = minTotalReclaimBytes
        self.skipIfToolsRunning = skipIfToolsRunning
        self.allowDirectDelete = allowDirectDelete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEvaluatedRunAt = lastEvaluatedRunAt
        self.lastSuccessfulRunAt = lastSuccessfulRunAt
    }
}

public enum AutomationRunStatus: String, Codable, Sendable {
    case executed
    case skipped
    case failed
}

public struct AutomationPolicyRunRecord: Codable, Equatable, Identifiable, Sendable {
    public let runID: String
    public var id: String { runID }
    public let policyID: String
    public let policyName: String
    public let trigger: AutomationTrigger
    public let startedAt: Date
    public let finishedAt: Date
    public let status: AutomationRunStatus
    public let skippedReason: String?
    public let message: String
    public let totalReclaimedBytes: Int64
    public let advancesSchedule: Bool
    public let executionReport: CleanupExecutionReport?

    public init(
        runID: String = UUID().uuidString,
        policyID: String,
        policyName: String,
        trigger: AutomationTrigger,
        startedAt: Date,
        finishedAt: Date,
        status: AutomationRunStatus,
        skippedReason: String?,
        message: String,
        totalReclaimedBytes: Int64,
        advancesSchedule: Bool = false,
        executionReport: CleanupExecutionReport?
    ) {
        self.runID = runID
        self.policyID = policyID
        self.policyName = policyName
        self.trigger = trigger
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.skippedReason = skippedReason
        self.message = message
        self.totalReclaimedBytes = totalReclaimedBytes
        self.advancesSchedule = advancesSchedule
        self.executionReport = executionReport
    }
}

public protocol AutomationPolicyStoring {
    func loadPolicies() throws -> [AutomationPolicy]
    func savePolicies(_ policies: [AutomationPolicy]) throws
    func loadRunHistory() throws -> [AutomationPolicyRunRecord]
    func appendRunHistory(_ record: AutomationPolicyRunRecord) throws
}

public struct JSONAutomationPolicyStore: AutomationPolicyStoring {
    private let stateDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stateDirectoryURL: URL) {
        self.stateDirectoryURL = stateDirectoryURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadPolicies() throws -> [AutomationPolicy] {
        try loadArray(AutomationPolicy.self, from: policiesFileURL)
    }

    public func savePolicies(_ policies: [AutomationPolicy]) throws {
        try saveArray(policies, to: policiesFileURL)
    }

    public func loadRunHistory() throws -> [AutomationPolicyRunRecord] {
        try loadArray(AutomationPolicyRunRecord.self, from: runHistoryFileURL)
    }

    public func appendRunHistory(_ record: AutomationPolicyRunRecord) throws {
        var history = try loadRunHistory()
        history.append(record)
        history.sort { $0.startedAt > $1.startedAt }
        try saveArray(history, to: runHistoryFileURL)
    }

    private var policiesFileURL: URL {
        stateDirectoryURL.appendingPathComponent("automation-policies.json", isDirectory: false)
    }

    private var runHistoryFileURL: URL {
        stateDirectoryURL.appendingPathComponent("automation-run-history.json", isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: stateDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func loadArray<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([T].self, from: data)
    }

    private func saveArray<T: Encodable>(_ values: [T], to fileURL: URL) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(values)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public protocol PathMetadataProviding {
    func fileExists(at url: URL) -> Bool
    func modificationDate(at url: URL) -> Date?
}

public struct FileSystemPathMetadataProvider: PathMetadataProviding {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func modificationDate(at url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }
}

public enum AutomationPolicies {
    public static func duePolicies(from policies: [AutomationPolicy], now: Date = Date()) -> [AutomationPolicy] {
        policies.filter { policy in
            guard policy.isEnabled else {
                return false
            }
            switch policy.schedule {
            case .manualOnly:
                return false
            case .everyHours(let hours):
                guard hours > 0 else {
                    return false
                }
                guard let lastRun = policy.lastEvaluatedRunAt else {
                    return true
                }
                return now.timeIntervalSince(lastRun) >= Double(hours * 3600)
            }
        }
    }

    public static func applyRunRecord(_ record: AutomationPolicyRunRecord, to policy: AutomationPolicy) -> AutomationPolicy {
        var updated = policy
        if record.advancesSchedule {
            updated.lastEvaluatedRunAt = record.finishedAt
            updated.updatedAt = record.finishedAt
        }
        if record.status == .executed {
            updated.lastSuccessfulRunAt = record.finishedAt
            updated.updatedAt = record.finishedAt
        }
        return updated
    }
}

public struct AutomationPolicyRunner: @unchecked Sendable {
    private let cleanupExecutor: CleanupExecutor
    private let pathMetadataProvider: PathMetadataProviding
    private let now: () -> Date

    public init(
        cleanupExecutor: CleanupExecutor = CleanupExecutor(),
        pathMetadataProvider: PathMetadataProviding = FileSystemPathMetadataProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.cleanupExecutor = cleanupExecutor
        self.pathMetadataProvider = pathMetadataProvider
        self.now = now
    }

    public func run(
        policy: AutomationPolicy,
        snapshot: XcodeInventorySnapshot,
        trigger: AutomationTrigger
    ) -> AutomationPolicyRunRecord {
        let startedAt = now()

        if !policy.isEnabled {
            return skippedRecord(
                policy: policy,
                trigger: trigger,
                startedAt: startedAt,
                reason: "Policy is disabled.",
                advancesSchedule: false
            )
        }

        if policy.skipIfToolsRunning, let reason = runningToolsSkipReason(snapshot: snapshot) {
            return skippedRecord(
                policy: policy,
                trigger: trigger,
                startedAt: startedAt,
                reason: reason,
                advancesSchedule: false
            )
        }

        var plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: policy.selection, now: startedAt)

        if let minAgeDays = policy.minAgeDays, minAgeDays > 0 {
            plan = applyingAgeThreshold(minAgeDays: minAgeDays, to: plan)
        }

        if plan.items.isEmpty {
            return skippedRecord(
                policy: policy,
                trigger: trigger,
                startedAt: startedAt,
                reason: "Policy produced no eligible cleanup items.",
                advancesSchedule: true
            )
        }

        if let minTotal = policy.minTotalReclaimBytes, plan.totalReclaimableBytes < minTotal {
            return skippedRecord(
                policy: policy,
                trigger: trigger,
                startedAt: startedAt,
                reason: "Policy minimum reclaim threshold not met (\(plan.totalReclaimableBytes) < \(minTotal)).",
                advancesSchedule: true
            )
        }

        let executionReport = cleanupExecutor.execute(
            snapshot: snapshot,
            plan: plan,
            allowDirectDelete: policy.allowDirectDelete
        )
        let status: AutomationRunStatus
        if executionReport.failedCount > 0 && executionReport.succeededCount == 0 && executionReport.partiallySucceededCount == 0 {
            status = .failed
        } else {
            status = .executed
        }

        return AutomationPolicyRunRecord(
            policyID: policy.id,
            policyName: policy.name,
            trigger: trigger,
            startedAt: startedAt,
            finishedAt: now(),
            status: status,
            skippedReason: nil,
            message: "Run complete. Reclaimed \(executionReport.totalReclaimedBytes) bytes.",
            totalReclaimedBytes: executionReport.totalReclaimedBytes,
            advancesSchedule: status == .executed,
            executionReport: executionReport
        )
    }

    private func skippedRecord(
        policy: AutomationPolicy,
        trigger: AutomationTrigger,
        startedAt: Date,
        reason: String,
        advancesSchedule: Bool
    ) -> AutomationPolicyRunRecord {
        AutomationPolicyRunRecord(
            policyID: policy.id,
            policyName: policy.name,
            trigger: trigger,
            startedAt: startedAt,
            finishedAt: now(),
            status: .skipped,
            skippedReason: reason,
            message: reason,
            totalReclaimedBytes: 0,
            advancesSchedule: advancesSchedule,
            executionReport: nil
        )
    }

    private func runningToolsSkipReason(snapshot: XcodeInventorySnapshot) -> String? {
        let runningXcode = snapshot.runtimeTelemetry.totalXcodeRunningInstances
        let runningSimulatorApp = snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances
        let bootedDevices = snapshot.simulator.devices.filter { device in
            if device.runningInstanceCount > 0 {
                return true
            }
            let state = device.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return state == "booted" || state == "booting"
        }.count

        guard runningXcode > 0 || runningSimulatorApp > 0 || bootedDevices > 0 else {
            return nil
        }
        return "Skipped: running tools detected (Xcode: \(runningXcode), Simulator app: \(runningSimulatorApp), booted devices: \(bootedDevices))."
    }

    private func applyingAgeThreshold(minAgeDays: Int, to plan: DryRunPlan) -> DryRunPlan {
        let cutoff = now().addingTimeInterval(-Double(minAgeDays) * 86_400)

        let keptItems = plan.items.filter { item in
            guard !item.paths.isEmpty else {
                return false
            }
            for path in item.paths {
                let url = URL(filePath: path, directoryHint: .inferFromPath)
                guard pathMetadataProvider.fileExists(at: url),
                      let modifiedAt = pathMetadataProvider.modificationDate(at: url) else {
                    return false
                }
                if modifiedAt > cutoff {
                    return false
                }
            }
            return true
        }

        let removedCount = plan.items.count - keptItems.count
        var notes = plan.notes
        notes.append("Applied minAgeDays=\(minAgeDays); removed \(removedCount) item(s) newer than threshold.")

        let total = keptItems.reduce(Int64(0)) { partial, item in
            partial + item.reclaimableBytes
        }

        return DryRunPlan(
            generatedAt: plan.generatedAt,
            selection: plan.selection,
            items: keptItems,
            totalReclaimableBytes: total,
            notes: notes
        )
    }
}

public struct AutomationHistoryWindowSummary: Codable, Equatable, Sendable {
    public let windowDays: Int
    public let totalRuns: Int
    public let executedRuns: Int
    public let skippedRuns: Int
    public let failedRuns: Int
    public let totalReclaimedBytes: Int64

    public init(
        windowDays: Int,
        totalRuns: Int,
        executedRuns: Int,
        skippedRuns: Int,
        failedRuns: Int,
        totalReclaimedBytes: Int64
    ) {
        self.windowDays = windowDays
        self.totalRuns = totalRuns
        self.executedRuns = executedRuns
        self.skippedRuns = skippedRuns
        self.failedRuns = failedRuns
        self.totalReclaimedBytes = totalReclaimedBytes
    }
}

public enum AutomationHistoryTrends {
    public static func summaries(
        records: [AutomationPolicyRunRecord],
        windowsInDays: [Int] = [7, 30],
        now: Date = Date()
    ) -> [AutomationHistoryWindowSummary] {
        windowsInDays
            .filter { $0 > 0 }
            .map { windowDays in
                let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
                let windowRecords = records.filter { $0.startedAt >= cutoff }

                let executed = windowRecords.filter { $0.status == .executed }.count
                let skipped = windowRecords.filter { $0.status == .skipped }.count
                let failed = windowRecords.filter { $0.status == .failed }.count
                let reclaimed = windowRecords.reduce(Int64(0)) { partial, record in
                    partial + record.totalReclaimedBytes
                }

                return AutomationHistoryWindowSummary(
                    windowDays: windowDays,
                    totalRuns: windowRecords.count,
                    executedRuns: executed,
                    skippedRuns: skipped,
                    failedRuns: failed,
                    totalReclaimedBytes: reclaimed
                )
            }
    }
}

public enum AutomationHistoryCSVExporter {
    public static func export(records: [AutomationPolicyRunRecord]) -> String {
        var lines: [String] = []
        lines.append([
            "runID",
            "policyID",
            "policyName",
            "trigger",
            "status",
            "startedAt",
            "finishedAt",
            "totalReclaimedBytes",
            "skippedReason",
            "message",
        ].joined(separator: ","))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for record in records {
            let columns = [
                record.runID,
                record.policyID,
                record.policyName,
                record.trigger.rawValue,
                record.status.rawValue,
                formatter.string(from: record.startedAt),
                formatter.string(from: record.finishedAt),
                String(record.totalReclaimedBytes),
                record.skippedReason ?? "",
                record.message,
            ]
            lines.append(columns.map(escapedCSVField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escapedCSVField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

public enum AutomationTrendCSVExporter {
    public static func export(summaries: [AutomationHistoryWindowSummary]) -> String {
        var lines: [String] = []
        lines.append("windowDays,totalRuns,executedRuns,skippedRuns,failedRuns,totalReclaimedBytes")
        for summary in summaries {
            lines.append([
                String(summary.windowDays),
                String(summary.totalRuns),
                String(summary.executedRuns),
                String(summary.skippedRuns),
                String(summary.failedRuns),
                String(summary.totalReclaimedBytes),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
