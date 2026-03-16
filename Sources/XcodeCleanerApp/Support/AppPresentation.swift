import Foundation
import SwiftUI
import XcodeInventoryCore

let guiDefaultCleanupCategoryKinds: [StorageCategoryKind] = [
    .derivedData,
    .archives,
]

func defaultAutomationStateDirectory() -> URL {
    URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        .appendingPathComponent(".xcodecleaner", isDirectory: true)
}

@MainActor
enum AppPresentation {
    static var appVersionDisplay: String {
        let fallbackVersion = "1.0"
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let version = bundleVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyValue ?? fallbackVersion
        return "Version \(version)"
    }

    static func title(for kind: StorageCategoryKind) -> String {
        switch kind {
        case .xcodeApplications:
            return "Xcode Applications"
        case .derivedData:
            return "Derived Data"
        case .mobileDeviceCrashLogs:
            return "MobileDevice Crash Logs"
        case .archives:
            return "Archives"
        case .deviceSupport:
            return "Device Support"
        case .simulatorData:
            return "Simulator Data"
        }
    }

    static func cleanupCategoryHelpText(for kind: StorageCategoryKind) -> String {
        switch kind {
        case .xcodeApplications:
            return "Xcode app bundles"
        case .derivedData:
            return "Build products and indexes"
        case .mobileDeviceCrashLogs:
            return "Crash/log history from connected physical devices"
        case .archives:
            return "Archived app builds"
        case .deviceSupport:
            return "All physical device support folders (CLI aggregate mode)"
        case .simulatorData:
            return "CoreSimulator devices/caches/runtimes"
        }
    }

    static func simulatorRuntimeStaleReasonsByIdentifier(
        in snapshot: XcodeInventorySnapshot
    ) -> [String: [SimulatorRuntimeStaleReason]] {
        var result: [String: [SimulatorRuntimeStaleReason]] = [:]
        for runtime in snapshot.simulator.runtimes {
            result[runtime.identifier] = SimulatorStaleness.runtimeStaleReasons(
                for: runtime,
                devices: snapshot.simulator.devices
            )
        }
        return result
    }

    static func simulatorDeviceStaleReasonsByUDID(
        in snapshot: XcodeInventorySnapshot
    ) -> [String: [SimulatorDeviceStaleReason]] {
        let runtimeByIdentifier = Dictionary(
            uniqueKeysWithValues: snapshot.simulator.runtimes.map { ($0.identifier, $0) }
        )
        var result: [String: [SimulatorDeviceStaleReason]] = [:]
        for device in snapshot.simulator.devices {
            result[device.udid] = SimulatorStaleness.deviceStaleReasons(
                for: device,
                runtimeByIdentifier: runtimeByIdentifier
            )
        }
        return result
    }

    static func runtimeStaleSummary(_ reasons: [SimulatorRuntimeStaleReason]) -> String {
        reasons.map { reason in
            switch reason {
            case .unavailable:
                return "runtime unavailable"
            case .unreferencedByAnyDevice:
                return "not referenced by any simulator device"
            }
        }
        .joined(separator: ", ")
    }

    static func deviceStaleSummary(_ reasons: [SimulatorDeviceStaleReason]) -> String {
        reasons.map { reason in
            switch reason {
            case .unavailable:
                return "device unavailable"
            case .runtimeMissing:
                return "runtime missing from scan"
            case .runtimeUnavailable:
                return "runtime unavailable"
            }
        }
        .joined(separator: ", ")
    }

    static func orphanedSimulatorArtifactCount(in report: StaleArtifactReport?) -> Int {
        guard let report else {
            return 0
        }
        return report.candidates.filter { candidate in
            switch candidate.kind {
            case .orphanedSimulatorRuntime, .orphanedSimulatorDevice:
                return true
            case .simulatorRuntime, .deviceSupportDirectory:
                return false
            }
        }.count
    }

    static func staleArtifactGroupTitle(for kind: StaleArtifactKind) -> String {
        switch kind {
        case .simulatorRuntime:
            return "Stale Simulator Runtimes"
        case .orphanedSimulatorRuntime:
            return "Orphaned Simulator Runtimes"
        case .orphanedSimulatorDevice:
            return "Orphaned Simulator Device Data"
        case .deviceSupportDirectory:
            return "Stale Device Support Directories"
        }
    }

    static func staleArtifactBadgeText(for kind: StaleArtifactKind) -> String {
        switch kind {
        case .simulatorRuntime, .deviceSupportDirectory:
            return "STALE"
        case .orphanedSimulatorRuntime, .orphanedSimulatorDevice:
            return "ORPHANED"
        }
    }

    static func staleArtifactBadgeColor(for kind: StaleArtifactKind) -> Color {
        switch kind {
        case .simulatorRuntime, .deviceSupportDirectory:
            return Color.orange.opacity(0.2)
        case .orphanedSimulatorRuntime, .orphanedSimulatorDevice:
            return Color.red.opacity(0.18)
        }
    }

    static func staleArtifactIsReportOnly(_ kind: StaleArtifactKind) -> Bool {
        kind == .orphanedSimulatorRuntime
    }

    static func staleArtifactActionHint(for kind: StaleArtifactKind) -> String? {
        switch kind {
        case .orphanedSimulatorRuntime:
            return "Manual cleanup only. The app reports the path but does not delete orphaned runtimes."
        case .simulatorRuntime, .orphanedSimulatorDevice, .deviceSupportDirectory:
            return nil
        }
    }

    static func staleArtifactGroupOrder(for kind: StaleArtifactKind) -> Int {
        switch kind {
        case .simulatorRuntime:
            return 0
        case .orphanedSimulatorRuntime:
            return 1
        case .orphanedSimulatorDevice:
            return 2
        case .deviceSupportDirectory:
            return 3
        }
    }

    static func orphanedSimulatorRuntimeCandidates(in report: StaleArtifactReport?) -> [StaleArtifactCandidate] {
        guard let report else {
            return []
        }
        return report.candidates.filter { $0.kind == .orphanedSimulatorRuntime }
    }

    static func cleanupOperationLabel(_ operation: CleanupOperation) -> String {
        switch operation {
        case .moveToTrash:
            return "moveToTrash"
        case .directDelete:
            return "directDelete"
        case .simctlDelete:
            return "simctlDelete"
        case .mixed:
            return "mixed"
        case .none:
            return "none"
        }
    }

    static func physicalDeviceSupportDirectoryMetadata(
        _ directory: PhysicalDeviceSupportDirectoryRecord,
        scannedAt: Date
    ) -> String {
        var segments: [String] = []
        if let osVersion = directory.parsedOSVersion {
            segments.append("OS Version: \(osVersion)")
        }
        if let build = directory.parsedBuild {
            segments.append("Build: \(build)")
        }
        if let descriptor = directory.parsedDescriptor {
            segments.append("Details: \(descriptor)")
        }
        if let modifiedAt = directory.modifiedAt {
            segments.append("Modified: \(formatDateTime(modifiedAt))")
            segments.append("Age: \(relativeAgeString(from: modifiedAt, referenceDate: scannedAt))")
        } else {
            segments.append("Modified: Unknown")
        }
        return segments.joined(separator: " | ")
    }

    static func relativeAgeString(from date: Date, referenceDate: Date) -> String {
        let text = relativeDateFormatter.localizedString(for: date, relativeTo: referenceDate)
        return text.replacingOccurrences(of: "in 0 seconds", with: "just now")
    }

    static func isAutomationPolicyDueNow(_ policy: AutomationPolicy) -> Bool {
        AutomationPolicies.duePolicies(from: [policy], now: Date()).isEmpty == false
    }

    static func formattedSchedule(for policy: AutomationPolicy) -> String {
        switch policy.schedule {
        case .manualOnly:
            return "Manual only"
        case .everyHours(let hours):
            if let lastRun = policy.lastEvaluatedRunAt {
                let nextDue = lastRun.addingTimeInterval(Double(hours) * 3_600)
                return "Every \(hours)h (next due: \(formatDateTime(nextDue)))"
            }
            return "Every \(hours)h (next due: now)"
        }
    }

    static func formatDateTime(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }
        return dateTimeFormatter.string(from: date)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func color(for safetyClassification: SafetyClassification) -> Color {
        switch safetyClassification {
        case .regenerable:
            return .green
        case .conditionallySafe:
            return .orange
        case .destructive:
            return .red
        }
    }

    static func color(for status: CleanupActionStatus) -> Color {
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

    static func color(for status: ActiveXcodeSwitchStatus) -> Color {
        switch status {
        case .succeeded:
            return .green
        case .blocked:
            return .orange
        case .failed:
            return .red
        }
    }

    static func color(for status: AutomationRunStatus) -> Color {
        switch status {
        case .executed:
            return .green
        case .skipped:
            return .orange
        case .failed:
            return .red
        }
    }

    static func automationStatusTone(for message: String, isExecuting: Bool) -> AutomationStatusTone {
        if isExecuting {
            return .active
        }

        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("failed") || normalized.contains("error") {
            return .failure
        }
        if normalized.contains("skipped") {
            return .warning
        }
        if normalized.contains("finished")
            || normalized.contains("complete")
            || normalized.contains("created")
            || normalized.contains("deleted")
            || normalized.contains("enabled")
            || normalized.contains("disabled")
            || normalized.contains("exported")
            || normalized.contains("reclaimed") {
            return .success
        }
        return .neutral
    }

    static func automationStatusSymbol(for tone: AutomationStatusTone) -> String {
        switch tone {
        case .active:
            return "clock.arrow.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .neutral:
            return "info.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }

    static func color(for tone: AutomationStatusTone) -> Color {
        switch tone {
        case .active:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .neutral:
            return .secondary
        case .failure:
            return .red
        }
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

private extension String {
    var nonEmptyValue: String? {
        isEmpty ? nil : self
    }
}

enum AutomationStatusTone {
    case active
    case success
    case warning
    case neutral
    case failure
}
