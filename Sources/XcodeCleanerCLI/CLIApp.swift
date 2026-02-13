import Foundation
import Darwin
import XcodeInventoryCore

struct XcodeCleanerCLIApp {
    static func run(arguments: [String], environment: [String: String]) -> Int32 {
        do {
            let options = try CLIOptions.parse(arguments: arguments)
            if options.showHelp {
                printUsage()
                return 0
            }

            let progressRenderer = CLIProgressRenderer(
                suppressProgress: options.suppressProgress,
                stderrIsTTY: isTTY(fileDescriptor: FileHandle.standardError.fileDescriptor),
                terminalColumnsProvider: { terminalWidth(fileDescriptor: FileHandle.standardError.fileDescriptor, environment: environment) },
                environment: environment,
                writeToStandardError: writeToStandardError
            )

            let scanner = XcodeInventoryScanner()
            let snapshot = scanner.scan { progress in
                progressRenderer.handle(progress: progress)
            }
            progressRenderer.finish()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(snapshot)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return 0
        } catch let error as CLIOptionsError {
            writeToStandardError("error: \(error.localizedDescription)\n")
            printUsage(toStandardError: true)
            return 2
        } catch {
            writeToStandardError("error: \(error.localizedDescription)\n")
            return 1
        }
    }
}

func writeToStandardError(_ text: String) {
    guard let data = text.data(using: .utf8) else {
        return
    }
    FileHandle.standardError.write(data)
}

func isTTY(fileDescriptor: Int32) -> Bool {
    Darwin.isatty(fileDescriptor) != 0
}

func terminalWidth(fileDescriptor: Int32, environment: [String: String]) -> Int? {
    if let columnsValue = environment["COLUMNS"],
       let columns = Int(columnsValue), columns > 0 {
        return columns
    }

    var windowSize = winsize()
    guard ioctl(fileDescriptor, TIOCGWINSZ, &windowSize) == 0 else {
        return nil
    }
    let columns = Int(windowSize.ws_col)
    return columns > 0 ? columns : nil
}

func printUsage(toStandardError: Bool = false) {
    let usage = """
    Usage: xcodecleaner-cli [--no-progress] [--help]

    Options:
      --no-progress   Suppress progress output
      --help          Show this help message
    """
    if toStandardError {
        writeToStandardError("\(usage)\n")
    } else {
        print(usage)
    }
}
