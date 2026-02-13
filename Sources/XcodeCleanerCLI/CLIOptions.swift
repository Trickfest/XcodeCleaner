import Foundation

struct CLIOptions: Equatable {
    let suppressProgress: Bool
    let showHelp: Bool

    static func parse(arguments: [String]) throws -> CLIOptions {
        var suppressProgress = false
        var showHelp = false

        for argument in arguments {
            switch argument {
            case "--no-progress":
                suppressProgress = true
            case "--help", "-h":
                showHelp = true
            default:
                throw CLIOptionsError.unrecognizedArgument(argument)
            }
        }

        return CLIOptions(suppressProgress: suppressProgress, showHelp: showHelp)
    }
}

enum CLIOptionsError: LocalizedError, Equatable {
    case unrecognizedArgument(String)

    var errorDescription: String? {
        switch self {
        case .unrecognizedArgument(let argument):
            return "unrecognized argument '\(argument)'"
        }
    }
}
