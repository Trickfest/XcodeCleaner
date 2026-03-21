import Foundation

public enum CleanupPolicySurface: String, Codable, Sendable {
    case defaultSafe
    case optional
    case explicitOptIn
    case itemizedOnly
    case countedOnly
    case reportOnly
}

public enum CleanupGuardrailRequirement: String, Codable, Sendable {
    case none
    case xcodeStopped
    case simulatorStopped
}

public enum CleanupDeletionMechanism: String, Codable, Sendable {
    case filesystem
    case simctl
    case mixed
    case manualOnly
}

public struct CleanupPolicy: Equatable, Sendable {
    public let title: String
    public let surface: CleanupPolicySurface
    public let guardrail: CleanupGuardrailRequirement
    public let deletionMechanism: CleanupDeletionMechanism
    public let cleanupDescription: String
    public let affectedRootsSummary: String
    public let footprintDescription: String?
    public let defaultSelectedInGUI: Bool
    public let defaultSelectedInPlanningDefaults: Bool

    public init(
        title: String,
        surface: CleanupPolicySurface,
        guardrail: CleanupGuardrailRequirement,
        deletionMechanism: CleanupDeletionMechanism,
        cleanupDescription: String,
        affectedRootsSummary: String,
        footprintDescription: String? = nil,
        defaultSelectedInGUI: Bool = false,
        defaultSelectedInPlanningDefaults: Bool = false
    ) {
        self.title = title
        self.surface = surface
        self.guardrail = guardrail
        self.deletionMechanism = deletionMechanism
        self.cleanupDescription = cleanupDescription
        self.affectedRootsSummary = affectedRootsSummary
        self.footprintDescription = footprintDescription
        self.defaultSelectedInGUI = defaultSelectedInGUI
        self.defaultSelectedInPlanningDefaults = defaultSelectedInPlanningDefaults
    }
}

public enum CleanupPolicies {
    public static func policy(for kind: StorageCategoryKind) -> CleanupPolicy {
        switch kind {
        case .xcodeApplications:
            return CleanupPolicy(
                title: "Xcode Applications",
                surface: .optional,
                guardrail: .xcodeStopped,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes the selected Xcode app bundles.",
                affectedRootsSummary: "Xcode app bundles discovered in standard install locations such as /Applications and ~/Applications",
                footprintDescription: "Xcode application bundles discovered in standard install locations."
            )
        case .derivedData:
            return CleanupPolicy(
                title: "Derived Data",
                surface: .defaultSafe,
                guardrail: .none,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes build products, indexes, and caches created by Xcode builds.",
                affectedRootsSummary: "~/Library/Developer/Xcode/DerivedData",
                footprintDescription: "Derived Data under ~/Library/Developer/Xcode/DerivedData.",
                defaultSelectedInGUI: true,
                defaultSelectedInPlanningDefaults: true
            )
        case .mobileDeviceCrashLogs:
            return CleanupPolicy(
                title: "MobileDevice Crash Logs",
                surface: .optional,
                guardrail: .none,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes crash logs and log captures from connected physical devices.",
                affectedRootsSummary: "~/Library/Logs/CrashReporter/MobileDevice",
                footprintDescription: "MobileDevice crash logs under ~/Library/Logs/CrashReporter/MobileDevice."
            )
        case .archives:
            return CleanupPolicy(
                title: "Archives",
                surface: .defaultSafe,
                guardrail: .none,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes archived app builds stored by Xcode.",
                affectedRootsSummary: "~/Library/Developer/Xcode/Archives",
                footprintDescription: "Archives under ~/Library/Developer/Xcode/Archives.",
                defaultSelectedInGUI: true,
                defaultSelectedInPlanningDefaults: true
            )
        case .deviceSupport:
            return CleanupPolicy(
                title: "Device Support",
                surface: .optional,
                guardrail: .xcodeStopped,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes real-device support caches used for on-device debugging. Xcode recreates them when matching devices connect again.",
                affectedRootsSummary: "~/Library/Developer/Xcode/iOS DeviceSupport",
                footprintDescription: "Physical device support directories under ~/Library/Developer/Xcode/iOS DeviceSupport.",
                defaultSelectedInPlanningDefaults: true
            )
        case .simulatorData:
            return CleanupPolicy(
                title: "Simulator Data",
                surface: .optional,
                guardrail: .simulatorStopped,
                deletionMechanism: .mixed,
                cleanupDescription: "Deletes simulator devices, shared CoreSimulator caches, temp CoreSimulator state, and installed simulator runtimes tracked in CoreSimulator storage. Some system cache/temp roots under /Library may still require manual cleanup.",
                affectedRootsSummary: "~/Library/Developer/CoreSimulator/Devices, ~/Library/Developer/CoreSimulator/Caches, ~/Library/Developer/CoreSimulator/Temp, /Library/Developer/CoreSimulator/Caches, /Library/Developer/CoreSimulator/Temp, and installed runtime locations under /Library/Developer/CoreSimulator",
                footprintDescription: "CoreSimulator device data, runtime bundles, user and system caches, and temp state."
            )
        }
    }

    public static func policy(for kind: CountedFootprintComponentKind) -> CleanupPolicy {
        switch kind {
        case .documentationCache:
            return CleanupPolicy(
                title: "Documentation Cache",
                surface: .explicitOptIn,
                guardrail: .xcodeStopped,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes downloaded Xcode documentation cache. Xcode can recreate it later if needed.",
                affectedRootsSummary: "~/Library/Developer/Xcode/DocumentationCache",
                footprintDescription: "Documentation cache under ~/Library/Developer/Xcode/DocumentationCache.",
                defaultSelectedInPlanningDefaults: false
            )
        case .developerPackages:
            return CleanupPolicy(
                title: "Developer Packages",
                surface: .countedOnly,
                guardrail: .none,
                deletionMechanism: .manualOnly,
                cleanupDescription: "Included in Total Xcode Footprint only in this build.",
                affectedRootsSummary: "~/Library/Developer/Packages",
                footprintDescription: "Developer packages under ~/Library/Developer/Packages."
            )
        case .xcodeLogs:
            return CleanupPolicy(
                title: "Xcode Logs",
                surface: .explicitOptIn,
                guardrail: .xcodeStopped,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes Xcode logs and result history stored outside DerivedData. Keep them if you still need recent diagnostics.",
                affectedRootsSummary: "~/Library/Logs/Xcode",
                footprintDescription: "Xcode logs under ~/Library/Logs/Xcode."
            )
        case .coreSimulatorLogs:
            return CleanupPolicy(
                title: "CoreSimulator Logs",
                surface: .explicitOptIn,
                guardrail: .simulatorStopped,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes CoreSimulator log history. Keep these logs if you still need recent simulator diagnostics.",
                affectedRootsSummary: "~/Library/Logs/CoreSimulator",
                footprintDescription: "CoreSimulator logs under ~/Library/Logs/CoreSimulator."
            )
        case .dvtDownloads:
            return CleanupPolicy(
                title: "Developer Tool Downloads",
                surface: .countedOnly,
                guardrail: .none,
                deletionMechanism: .manualOnly,
                cleanupDescription: "Included in Total Xcode Footprint only in this build.",
                affectedRootsSummary: "~/Library/Developer/DVTDownloads",
                footprintDescription: "Developer tool downloads under ~/Library/Developer/DVTDownloads."
            )
        case .xcpgDevices:
            return CleanupPolicy(
                title: "Playground Device Set",
                surface: .countedOnly,
                guardrail: .none,
                deletionMechanism: .manualOnly,
                cleanupDescription: "Included in Total Xcode Footprint only in this build.",
                affectedRootsSummary: "~/Library/Developer/XCPGDevices",
                footprintDescription: "Xcode Playground/CoreSimulator device-set state under ~/Library/Developer/XCPGDevices."
            )
        case .xcTestDevices:
            return CleanupPolicy(
                title: "XCTest Devices",
                surface: .countedOnly,
                guardrail: .none,
                deletionMechanism: .manualOnly,
                cleanupDescription: "Included in Total Xcode Footprint only in this build.",
                affectedRootsSummary: "~/Library/Developer/XCTestDevices",
                footprintDescription: "XCTest device-set state under ~/Library/Developer/XCTestDevices."
            )
        case .additionalXcodeState:
            return CleanupPolicy(
                title: "Additional Xcode State",
                surface: .countedOnly,
                guardrail: .none,
                deletionMechanism: .manualOnly,
                cleanupDescription: "Included in Total Xcode Footprint only in this build.",
                affectedRootsSummary: "~/Library/Developer/Xcode",
                footprintDescription: "Additional standard Xcode-managed state under ~/Library/Developer/Xcode, such as UserData, DocumentationIndex, and Xcode mapping files."
            )
        }
    }

    public static func policy(for kind: StaleArtifactKind) -> CleanupPolicy {
        switch kind {
        case .simulatorRuntime:
            return CleanupPolicy(
                title: "Stale Simulator Runtimes",
                surface: .explicitOptIn,
                guardrail: .simulatorStopped,
                deletionMechanism: .simctl,
                cleanupDescription: "Deletes simulator runtimes that are no longer needed by the devices in the current simulator inventory.",
                affectedRootsSummary: "Installed simulator runtime bundle paths reported by simctl."
            )
        case .orphanedSimulatorRuntime:
            return CleanupPolicy(
                title: "Orphaned Simulator Runtimes",
                surface: .reportOnly,
                guardrail: .simulatorStopped,
                deletionMechanism: .manualOnly,
                cleanupDescription: "Reported for manual cleanup because CoreSimulator no longer tracks them.",
                affectedRootsSummary: "On-disk simulator runtime bundles that do not appear in the current simulator inventory."
            )
        case .orphanedSimulatorDevice:
            return CleanupPolicy(
                title: "Orphaned Simulator Device Data",
                surface: .explicitOptIn,
                guardrail: .simulatorStopped,
                deletionMechanism: .filesystem,
                cleanupDescription: "Deletes leftover simulator device data directories that are no longer tracked by CoreSimulator.",
                affectedRootsSummary: "~/Library/Developer/CoreSimulator/Devices orphan directories."
            )
        }
    }

    public static var defaultGUICategoryKinds: [StorageCategoryKind] {
        StorageCategoryKind.allCases.filter { policy(for: $0).defaultSelectedInGUI }
    }

    public static var defaultPlanningCategoryKinds: [StorageCategoryKind] {
        StorageCategoryKind.allCases.filter { policy(for: $0).defaultSelectedInPlanningDefaults }
    }

    public static var explicitOptInCountedFootprintComponentKinds: [CountedFootprintComponentKind] {
        CountedFootprintComponentKind.allCases.filter { policy(for: $0).surface == .explicitOptIn }
    }
}
