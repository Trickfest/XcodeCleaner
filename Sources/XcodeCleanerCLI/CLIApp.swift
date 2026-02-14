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

            let data: Data
            if options.mode == .dryRun || options.mode == .execute {
                let selection = DryRunSelection(
                    selectedCategoryKinds: options.selectedCategoryKinds,
                    selectedSimulatorDeviceUDIDs: options.selectedSimulatorDeviceUDIDs,
                    selectedXcodeInstallPaths: options.selectedXcodeInstallPaths
                )
                if options.mode == .dryRun {
                    let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)
                    data = try encoder.encode(plan)
                } else {
                    let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)
                    if options.skipIfToolsRunning,
                       let skipReason = skipReasonForRunningTools(in: snapshot) {
                        writeToStandardError("info: \(skipReason) Skipping execute due to --skip-if-tools-running.\n")
                        let report = CleanupExecutionReport(
                            executedAt: Date(),
                            allowDirectDelete: options.allowDirectDelete,
                            skippedReason: skipReason,
                            selection: plan.selection,
                            plan: plan,
                            results: [],
                            totalReclaimedBytes: 0,
                            succeededCount: 0,
                            partiallySucceededCount: 0,
                            blockedCount: 0,
                            failedCount: 0
                        )
                        data = try encoder.encode(report)
                    } else {
                        let report = CleanupExecutor().execute(
                            snapshot: snapshot,
                            plan: plan,
                            allowDirectDelete: options.allowDirectDelete
                        )
                        data = try encoder.encode(report)
                    }
                }
            } else {
                data = try encoder.encode(snapshot)
            }
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
    let categoryValues = StorageCategoryKind.allCases.map(\.rawValue).joined(separator: ", ")
    let usage = """
    Usage: xcodecleaner-cli [--no-progress] [--help] [--dry-run|--execute [--allow-direct-delete] [--skip-if-tools-running] [--plan-category <kind> ...] [--plan-simulator-device <udid> ...] [--plan-xcode-install <path> ...]]

    Options:
      --no-progress                  Suppress progress output
      --dry-run                      Output dry-run plan JSON instead of snapshot JSON
      --execute                      Execute selected plan and output execution report JSON
      --allow-direct-delete          Allow direct delete fallback when move-to-trash fails (execute mode only)
      --skip-if-tools-running        Skip execute when Xcode or Simulator is currently running
      --plan-category <kind>         Include storage category in dry-run plan
      --plan-simulator-device <udid> Include simulator device (UDID) in dry-run plan
      --plan-xcode-install <path>    Include specific Xcode app bundle path in plan
      --help                         Show this help message

    Storage Categories:
      \(categoryValues)
    """
    if toStandardError {
        writeToStandardError("\(usage)\n")
    } else {
        print(usage)
    }
}

private func skipReasonForRunningTools(in snapshot: XcodeInventorySnapshot) -> String? {
    let runningXcodeCount = snapshot.runtimeTelemetry.totalXcodeRunningInstances
    let runningSimulatorAppCount = snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances
    let bootedDeviceCount = snapshot.simulator.devices.filter { device in
        let state = device.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return device.runningInstanceCount > 0 || state == "booted" || state == "booting"
    }.count

    guard runningXcodeCount > 0 || runningSimulatorAppCount > 0 || bootedDeviceCount > 0 else {
        return nil
    }

    return "Detected running tools (Xcode instances: \(runningXcodeCount), Simulator app instances: \(runningSimulatorAppCount), booted simulator devices: \(bootedDeviceCount))."
}
