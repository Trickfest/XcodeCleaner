import Foundation
import XcodeInventoryCore

enum CLICommandMode: Equatable {
    case snapshot
    case dryRun
    case execute
    case listStaleArtifacts
    case cleanStaleArtifacts
    case switchActiveXcode
}

struct CLIOptions: Equatable {
    let suppressProgress: Bool
    let showHelp: Bool
    let mode: CLICommandMode
    let allowDirectDelete: Bool
    let skipIfToolsRunning: Bool
    let switchActiveXcodePath: String?
    let selectedStaleArtifactIDs: [String]
    let selectedCategoryKinds: [StorageCategoryKind]
    let selectedSimulatorDeviceUDIDs: [String]
    let selectedXcodeInstallPaths: [String]

    static func parse(arguments: [String]) throws -> CLIOptions {
        var suppressProgress = false
        var showHelp = false
        var dryRun = false
        var execute = false
        var listStaleArtifacts = false
        var cleanStaleArtifacts = false
        var switchActiveXcodePath: String?
        var allowDirectDelete = false
        var skipIfToolsRunning = false
        var selectedStaleArtifactIDs: [String] = []
        var selectedCategoryKinds: [StorageCategoryKind] = []
        var selectedSimulatorDeviceUDIDs: [String] = []
        var selectedXcodeInstallPaths: [String] = []

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--no-progress":
                suppressProgress = true
            case "--help", "-h":
                showHelp = true
            case "--dry-run":
                dryRun = true
            case "--execute":
                execute = true
            case "--list-stale-artifacts":
                listStaleArtifacts = true
            case "--clean-stale-artifacts":
                cleanStaleArtifacts = true
            case "--switch-active-xcode":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CLIOptionsError.missingValue(argument)
                }
                switchActiveXcodePath = arguments[valueIndex]
                index += 1
            case "--allow-direct-delete":
                allowDirectDelete = true
            case "--skip-if-tools-running":
                skipIfToolsRunning = true
            case "--stale-artifact":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CLIOptionsError.missingValue(argument)
                }
                selectedStaleArtifactIDs.append(arguments[valueIndex])
                index += 1
            case "--plan-category":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CLIOptionsError.missingValue(argument)
                }
                let value = arguments[valueIndex]
                guard let kind = StorageCategoryKind(rawValue: value) else {
                    throw CLIOptionsError.invalidCategory(value)
                }
                selectedCategoryKinds.append(kind)
                index += 1
            case "--plan-simulator-device":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CLIOptionsError.missingValue(argument)
                }
                selectedSimulatorDeviceUDIDs.append(arguments[valueIndex])
                index += 1
            case "--plan-xcode-install":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CLIOptionsError.missingValue(argument)
                }
                selectedXcodeInstallPaths.append(arguments[valueIndex])
                index += 1
            default:
                if argument.hasPrefix("--plan-category=") {
                    let value = String(argument.dropFirst("--plan-category=".count))
                    guard let kind = StorageCategoryKind(rawValue: value) else {
                        throw CLIOptionsError.invalidCategory(value)
                    }
                    selectedCategoryKinds.append(kind)
                } else if argument.hasPrefix("--plan-simulator-device=") {
                    let value = String(argument.dropFirst("--plan-simulator-device=".count))
                    selectedSimulatorDeviceUDIDs.append(value)
                } else if argument.hasPrefix("--plan-xcode-install=") {
                    let value = String(argument.dropFirst("--plan-xcode-install=".count))
                    selectedXcodeInstallPaths.append(value)
                } else if argument.hasPrefix("--switch-active-xcode=") {
                    let value = String(argument.dropFirst("--switch-active-xcode=".count))
                    switchActiveXcodePath = value
                } else if argument.hasPrefix("--stale-artifact=") {
                    let value = String(argument.dropFirst("--stale-artifact=".count))
                    selectedStaleArtifactIDs.append(value)
                } else {
                    throw CLIOptionsError.unrecognizedArgument(argument)
                }
            }

            index += 1
        }

        let primaryModeCount = [dryRun, execute, listStaleArtifacts, cleanStaleArtifacts, switchActiveXcodePath != nil]
            .filter { $0 }
            .count
        if primaryModeCount > 1 {
            throw CLIOptionsError.conflictingModes
        }

        if allowDirectDelete, !(execute || cleanStaleArtifacts) {
            throw CLIOptionsError.requiresExecute("--allow-direct-delete")
        }

        if skipIfToolsRunning, !(execute || cleanStaleArtifacts) {
            throw CLIOptionsError.requiresExecute("--skip-if-tools-running")
        }

        if !cleanStaleArtifacts, !selectedStaleArtifactIDs.isEmpty {
            throw CLIOptionsError.requiresCleanStaleArtifacts
        }

        if (dryRun || execute),
           selectedCategoryKinds.isEmpty,
           selectedSimulatorDeviceUDIDs.isEmpty,
           selectedXcodeInstallPaths.isEmpty {
            selectedCategoryKinds = DryRunSelection.safeCategoryDefaults.selectedCategoryKinds
        }

        if !(dryRun || execute),
           (!selectedCategoryKinds.isEmpty
               || !selectedSimulatorDeviceUDIDs.isEmpty
               || !selectedXcodeInstallPaths.isEmpty) {
            throw CLIOptionsError.requiresPlanningMode
        }

        let mode: CLICommandMode
        if execute {
            mode = .execute
        } else if dryRun {
            mode = .dryRun
        } else if listStaleArtifacts {
            mode = .listStaleArtifacts
        } else if cleanStaleArtifacts {
            mode = .cleanStaleArtifacts
        } else if switchActiveXcodePath != nil {
            mode = .switchActiveXcode
        } else {
            mode = .snapshot
        }

        return CLIOptions(
            suppressProgress: suppressProgress,
            showHelp: showHelp,
            mode: mode,
            allowDirectDelete: allowDirectDelete,
            skipIfToolsRunning: skipIfToolsRunning,
            switchActiveXcodePath: switchActiveXcodePath,
            selectedStaleArtifactIDs: Array(Set(selectedStaleArtifactIDs)).sorted(),
            selectedCategoryKinds: Array(Set(selectedCategoryKinds)).sorted { $0.rawValue < $1.rawValue },
            selectedSimulatorDeviceUDIDs: Array(Set(selectedSimulatorDeviceUDIDs)).sorted(),
            selectedXcodeInstallPaths: Array(Set(selectedXcodeInstallPaths)).sorted()
        )
    }
}

enum CLIOptionsError: LocalizedError, Equatable {
    case unrecognizedArgument(String)
    case missingValue(String)
    case invalidCategory(String)
    case conflictingModes
    case requiresPlanningMode
    case requiresExecute(String)
    case requiresCleanStaleArtifacts

    var errorDescription: String? {
        switch self {
        case .unrecognizedArgument(let argument):
            return "unrecognized argument '\(argument)'"
        case .missingValue(let option):
            return "missing value for \(option)"
        case .invalidCategory(let value):
            let available = StorageCategoryKind.allCases.map(\.rawValue).joined(separator: ", ")
            return "invalid category '\(value)'; expected one of: \(available)"
        case .conflictingModes:
            return "--dry-run and --execute cannot be used together"
        case .requiresPlanningMode:
            return "--plan-category, --plan-simulator-device, and --plan-xcode-install require --dry-run or --execute"
        case .requiresExecute(let option):
            return "\(option) requires --execute or --clean-stale-artifacts"
        case .requiresCleanStaleArtifacts:
            return "--stale-artifact requires --clean-stale-artifacts"
        }
    }
}
