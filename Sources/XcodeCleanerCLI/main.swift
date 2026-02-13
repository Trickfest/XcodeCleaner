import Darwin
import Foundation

let exitCode = XcodeCleanerCLIApp.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: ProcessInfo.processInfo.environment
)
Darwin.exit(exitCode)
