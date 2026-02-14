import Foundation
import XcodeInventoryCore

enum CLICommandMode: Equatable {
    case snapshot
    case dryRun
    case execute
}

struct CLIOptions: Equatable {
    let suppressProgress: Bool
    let showHelp: Bool
    let mode: CLICommandMode
    let allowDirectDelete: Bool
    let skipIfToolsRunning: Bool
    let selectedCategoryKinds: [StorageCategoryKind]
    let selectedSimulatorDeviceUDIDs: [String]
    let selectedXcodeInstallPaths: [String]

    static func parse(arguments: [String]) throws -> CLIOptions {
        var suppressProgress = false
        var showHelp = false
        var dryRun = false
        var execute = false
        var allowDirectDelete = false
        var skipIfToolsRunning = false
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
            case "--allow-direct-delete":
                allowDirectDelete = true
            case "--skip-if-tools-running":
                skipIfToolsRunning = true
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
                } else {
                    throw CLIOptionsError.unrecognizedArgument(argument)
                }
            }

            index += 1
        }

        if dryRun, execute {
            throw CLIOptionsError.conflictingModes
        }

        if allowDirectDelete, !execute {
            throw CLIOptionsError.requiresExecute("--allow-direct-delete")
        }

        if skipIfToolsRunning, !execute {
            throw CLIOptionsError.requiresExecute("--skip-if-tools-running")
        }

        if (dryRun || execute),
           selectedCategoryKinds.isEmpty,
           selectedSimulatorDeviceUDIDs.isEmpty,
           selectedXcodeInstallPaths.isEmpty {
            selectedCategoryKinds = DryRunSelection.safeCategoryDefaults.selectedCategoryKinds
        }

        if !dryRun,
           !execute,
           (!selectedCategoryKinds.isEmpty
               || !selectedSimulatorDeviceUDIDs.isEmpty
               || !selectedXcodeInstallPaths.isEmpty) {
            throw CLIOptionsError.requiresPlanningMode
        }

        let mode: CLICommandMode = execute ? .execute : (dryRun ? .dryRun : .snapshot)
        return CLIOptions(
            suppressProgress: suppressProgress,
            showHelp: showHelp,
            mode: mode,
            allowDirectDelete: allowDirectDelete,
            skipIfToolsRunning: skipIfToolsRunning,
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
            return "\(option) requires --execute"
        }
    }
}
