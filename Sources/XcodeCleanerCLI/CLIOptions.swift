import Foundation
import XcodeInventoryCore

struct CLIOptions: Equatable {
    let suppressProgress: Bool
    let showHelp: Bool
    let dryRun: Bool
    let selectedCategoryKinds: [StorageCategoryKind]
    let selectedSimulatorDeviceUDIDs: [String]

    static func parse(arguments: [String]) throws -> CLIOptions {
        var suppressProgress = false
        var showHelp = false
        var dryRun = false
        var selectedCategoryKinds: [StorageCategoryKind] = []
        var selectedSimulatorDeviceUDIDs: [String] = []

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
                } else {
                    throw CLIOptionsError.unrecognizedArgument(argument)
                }
            }

            index += 1
        }

        if dryRun, selectedCategoryKinds.isEmpty, selectedSimulatorDeviceUDIDs.isEmpty {
            selectedCategoryKinds = DryRunSelection.safeCategoryDefaults.selectedCategoryKinds
        }

        if !dryRun, (!selectedCategoryKinds.isEmpty || !selectedSimulatorDeviceUDIDs.isEmpty) {
            throw CLIOptionsError.requiresDryRun
        }

        return CLIOptions(
            suppressProgress: suppressProgress,
            showHelp: showHelp,
            dryRun: dryRun,
            selectedCategoryKinds: Array(Set(selectedCategoryKinds)).sorted { $0.rawValue < $1.rawValue },
            selectedSimulatorDeviceUDIDs: Array(Set(selectedSimulatorDeviceUDIDs)).sorted()
        )
    }
}

enum CLIOptionsError: LocalizedError, Equatable {
    case unrecognizedArgument(String)
    case missingValue(String)
    case invalidCategory(String)
    case requiresDryRun

    var errorDescription: String? {
        switch self {
        case .unrecognizedArgument(let argument):
            return "unrecognized argument '\(argument)'"
        case .missingValue(let option):
            return "missing value for \(option)"
        case .invalidCategory(let value):
            let available = StorageCategoryKind.allCases.map(\.rawValue).joined(separator: ", ")
            return "invalid category '\(value)'; expected one of: \(available)"
        case .requiresDryRun:
            return "--plan-category and --plan-simulator-device require --dry-run"
        }
    }
}
