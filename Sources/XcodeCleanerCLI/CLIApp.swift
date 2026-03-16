import Foundation
import Darwin
import XcodeInventoryCore

struct XcodeCleanerCLIApp {
    static func run(arguments: [String], environment: [String: String]) -> Int32 {
        do {
            if arguments.first == "automation" {
                return try runAutomationSubcommand(
                    arguments: Array(arguments.dropFirst()),
                    environment: environment
                )
            }

            let options = try CLIOptions.parse(arguments: arguments)
            if options.showHelp {
                printUsage()
                return 0
            }

            let snapshot = scanSnapshot(
                suppressProgress: options.suppressProgress,
                environment: environment
            )

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
            } else if options.mode == .listStaleArtifacts {
                let staleReport = StaleArtifactDetector().detect(snapshot: snapshot)
                data = try encoder.encode(staleReport)
            } else if options.mode == .cleanStaleArtifacts {
                let staleReport = StaleArtifactDetector().detect(snapshot: snapshot)
                let plan = StaleArtifactPlanner.makePlan(
                    snapshot: snapshot,
                    report: staleReport,
                    selectedCandidateIDs: options.selectedStaleArtifactIDs,
                    now: Date()
                )
                if options.skipIfToolsRunning,
                   let skipReason = skipReasonForRunningTools(in: snapshot) {
                    writeToStandardError("info: \(skipReason) Skipping stale cleanup due to --skip-if-tools-running.\n")
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
            } else if options.mode == .switchActiveXcode {
                guard let switchPath = options.switchActiveXcodePath else {
                    throw CLIOptionsError.missingValue("--switch-active-xcode")
                }
                let switchResult = ActiveXcodeSwitcher().switchActiveXcode(
                    snapshot: snapshot,
                    targetInstallPath: switchPath
                )
                data = try encoder.encode(switchResult)
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
        } catch let error as AutomationCLIError {
            writeToStandardError("error: \(error.localizedDescription)\n")
            printAutomationUsage(toStandardError: true)
            return 2
        } catch {
            writeToStandardError("error: \(error.localizedDescription)\n")
            return 1
        }
    }

    private static func scanSnapshot(
        suppressProgress: Bool,
        environment: [String: String]
    ) -> XcodeInventorySnapshot {
        let progressRenderer = CLIProgressRenderer(
            suppressProgress: suppressProgress,
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
        return snapshot
    }

    private static func runAutomationSubcommand(
        arguments: [String],
        environment: [String: String]
    ) throws -> Int32 {
        if arguments.isEmpty
            || arguments == ["--help"]
            || arguments == ["-h"]
            || arguments == ["help"] {
            printAutomationUsage()
            return 0
        }

        let options = try AutomationCLIOptions.parse(arguments: arguments)
        let store = JSONAutomationPolicyStore(stateDirectoryURL: automationStateDirectory(environment: environment))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        switch options.command {
        case .list:
            let policies = try store.loadPolicies()
            try printEncoded(policies, with: encoder, outputPath: options.outputPath)
            return 0
        case .create:
            var policies = try store.loadPolicies()
            let now = Date()
            let categories = options.categories.isEmpty
                ? DryRunSelection.safeCategoryDefaults.selectedCategoryKinds
                : options.categories
            let policy = AutomationPolicy(
                name: options.name ?? "Untitled Policy",
                schedule: options.everyHours.map { .everyHours($0) } ?? .manualOnly,
                selection: DryRunSelection(
                    selectedCategoryKinds: categories,
                    selectedSimulatorDeviceUDIDs: [],
                    selectedXcodeInstallPaths: []
                ),
                minAgeDays: options.minAgeDays,
                minTotalReclaimBytes: options.minTotalBytes,
                skipIfToolsRunning: options.skipIfToolsRunning,
                allowDirectDelete: options.allowDirectDelete,
                createdAt: now,
                updatedAt: now
            )
            policies.append(policy)
            policies.sort { $0.createdAt < $1.createdAt }
            try store.savePolicies(policies)
            try printEncoded(policy, with: encoder, outputPath: options.outputPath)
            return 0
        case .run:
            guard let policyID = options.policyID else {
                throw AutomationCLIError.missingRequiredOption("--id")
            }
            var policies = try store.loadPolicies()
            guard let policyIndex = policies.firstIndex(where: { $0.id == policyID }) else {
                throw AutomationCLIError.policyNotFound(policyID)
            }
            let snapshot = scanSnapshot(
                suppressProgress: options.suppressProgress,
                environment: environment
            )
            let runner = AutomationPolicyRunner()
            let record = runner.run(
                policy: policies[policyIndex],
                snapshot: snapshot,
                trigger: .manual
            )
            try store.appendRunHistory(record)
            policies[policyIndex] = AutomationPolicies.applyRunRecord(record, to: policies[policyIndex])
            try store.savePolicies(policies)
            try printEncoded(record, with: encoder, outputPath: options.outputPath)
            return record.status == .failed ? 1 : 0
        case .runDue:
            var policies = try store.loadPolicies()
            let duePolicies = AutomationPolicies.duePolicies(from: policies, now: Date())
            if duePolicies.isEmpty {
                try printEncoded([AutomationPolicyRunRecord](), with: encoder, outputPath: options.outputPath)
                return 0
            }

            let snapshot = scanSnapshot(
                suppressProgress: options.suppressProgress,
                environment: environment
            )
            let runner = AutomationPolicyRunner()
            var records: [AutomationPolicyRunRecord] = []
            var didFail = false

            for policy in duePolicies {
                let record = runner.run(policy: policy, snapshot: snapshot, trigger: .scheduled)
                records.append(record)
                try store.appendRunHistory(record)
                if let index = policies.firstIndex(where: { $0.id == policy.id }) {
                    policies[index] = AutomationPolicies.applyRunRecord(record, to: policies[index])
                }
                if record.status == .failed {
                    didFail = true
                }
            }
            try store.savePolicies(policies)
            try printEncoded(records, with: encoder, outputPath: options.outputPath)
            return didFail ? 1 : 0
        case .history:
            var history = try store.loadRunHistory()
            if let limit = options.limit, limit >= 0 {
                history = Array(history.prefix(limit))
            }
            switch options.outputFormat {
            case .json:
                try printEncoded(history, with: encoder, outputPath: options.outputPath)
            case .csv:
                let csv = AutomationHistoryCSVExporter.export(records: history)
                try writeText(csv, outputPath: options.outputPath)
            }
            return 0
        case .trends:
            let history = try store.loadRunHistory()
            let windows = options.trendDays.isEmpty ? [7, 30] : options.trendDays
            let summaries = AutomationHistoryTrends.summaries(records: history, windowsInDays: windows)
            switch options.outputFormat {
            case .json:
                try printEncoded(summaries, with: encoder, outputPath: options.outputPath)
            case .csv:
                let csv = AutomationTrendCSVExporter.export(summaries: summaries)
                try writeText(csv, outputPath: options.outputPath)
            }
            return 0
        }
    }

    private static func printEncoded<T: Encodable>(
        _ value: T,
        with encoder: JSONEncoder,
        outputPath: String? = nil
    ) throws {
        let data = try encoder.encode(value)
        if let outputPath, !outputPath.isEmpty {
            try writeData(data, outputPath: outputPath)
            return
        }
        if let output = String(data: data, encoding: .utf8) {
            print(output)
        }
    }

    private static func writeText(_ text: String, outputPath: String?) throws {
        if let outputPath, !outputPath.isEmpty {
            guard let data = text.data(using: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try writeData(data, outputPath: outputPath)
            return
        }
        print(text)
    }

    private static func writeData(_ data: Data, outputPath: String) throws {
        let outputURL = URL(filePath: outputPath, directoryHint: .notDirectory)
        let parentURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try data.write(to: outputURL, options: [.atomic])
    }

    private static func automationStateDirectory(environment: [String: String]) -> URL {
        if let override = environment["XCODECLEANER_STATE_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
            .appendingPathComponent(".xcodecleaner", isDirectory: true)
    }
}

private enum AutomationCommand: String {
    case list
    case create
    case run
    case runDue = "run-due"
    case history
    case trends
}

private enum AutomationOutputFormat: String {
    case json
    case csv
}

private struct AutomationCLIOptions {
    let command: AutomationCommand
    let suppressProgress: Bool
    let name: String?
    let policyID: String?
    let categories: [StorageCategoryKind]
    let everyHours: Int?
    let minAgeDays: Int?
    let minTotalBytes: Int64?
    let skipIfToolsRunning: Bool
    let allowDirectDelete: Bool
    let limit: Int?
    let outputFormat: AutomationOutputFormat
    let outputPath: String?
    let trendDays: [Int]

    static func parse(arguments: [String]) throws -> AutomationCLIOptions {
        guard let commandString = arguments.first,
              let command = AutomationCommand(rawValue: commandString) else {
            throw AutomationCLIError.missingCommand
        }

        var suppressProgress = false
        var name: String?
        var policyID: String?
        var categories: [StorageCategoryKind] = []
        var everyHours: Int?
        var minAgeDays: Int?
        var minTotalBytes: Int64?
        var skipIfToolsRunning = true
        var allowDirectDelete = false
        var limit: Int?
        var outputFormat: AutomationOutputFormat = .json
        var outputPath: String?
        var trendDays: [Int] = []

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--no-progress":
                suppressProgress = true
            case "--name":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--name")
                }
                name = arguments[index + 1]
                index += 1
            case "--id":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--id")
                }
                policyID = arguments[index + 1]
                index += 1
            case "--category":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--category")
                }
                let raw = arguments[index + 1]
                guard let category = StorageCategoryKind(rawValue: raw) else {
                    throw AutomationCLIError.invalidCategory(raw)
                }
                categories.append(category)
                index += 1
            case "--every-hours":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--every-hours")
                }
                guard let value = Int(arguments[index + 1]), value > 0 else {
                    throw AutomationCLIError.invalidValue("--every-hours")
                }
                everyHours = value
                index += 1
            case "--min-age-days":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--min-age-days")
                }
                guard let value = Int(arguments[index + 1]), value > 0 else {
                    throw AutomationCLIError.invalidValue("--min-age-days")
                }
                minAgeDays = value
                index += 1
            case "--min-total-bytes":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--min-total-bytes")
                }
                guard let value = Int64(arguments[index + 1]), value >= 0 else {
                    throw AutomationCLIError.invalidValue("--min-total-bytes")
                }
                minTotalBytes = value
                index += 1
            case "--allow-direct-delete":
                allowDirectDelete = true
            case "--skip-if-tools-running":
                skipIfToolsRunning = true
            case "--no-skip-if-tools-running":
                skipIfToolsRunning = false
            case "--limit":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--limit")
                }
                guard let value = Int(arguments[index + 1]), value >= 0 else {
                    throw AutomationCLIError.invalidValue("--limit")
                }
                limit = value
                index += 1
            case "--format":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--format")
                }
                let raw = arguments[index + 1]
                guard let format = AutomationOutputFormat(rawValue: raw) else {
                    throw AutomationCLIError.invalidValue("--format")
                }
                outputFormat = format
                index += 1
            case "--output":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--output")
                }
                outputPath = arguments[index + 1]
                index += 1
            case "--days":
                guard index + 1 < arguments.count else {
                    throw AutomationCLIError.missingRequiredOption("--days")
                }
                guard let value = Int(arguments[index + 1]), value > 0 else {
                    throw AutomationCLIError.invalidValue("--days")
                }
                trendDays.append(value)
                index += 1
            default:
                throw AutomationCLIError.unrecognizedArgument(argument)
            }
            index += 1
        }

        switch command {
        case .create:
            guard let name, !name.isEmpty else {
                throw AutomationCLIError.missingRequiredOption("--name")
            }
        case .run:
            guard let policyID, !policyID.isEmpty else {
                throw AutomationCLIError.missingRequiredOption("--id")
            }
        case .history:
            break
        case .trends:
            break
        case .runDue, .list:
            break
        }

        if !trendDays.isEmpty, command != .trends {
            throw AutomationCLIError.unsupportedOptionForCommand("--days", command.rawValue)
        }
        if command == .trends, limit != nil {
            throw AutomationCLIError.unsupportedOptionForCommand("--limit", command.rawValue)
        }
        if command != .history, command != .trends, outputFormat != .json {
            throw AutomationCLIError.unsupportedOptionForCommand("--format", command.rawValue)
        }

        return AutomationCLIOptions(
            command: command,
            suppressProgress: suppressProgress,
            name: name,
            policyID: policyID,
            categories: Array(Set(categories)).sorted { $0.rawValue < $1.rawValue },
            everyHours: everyHours,
            minAgeDays: minAgeDays,
            minTotalBytes: minTotalBytes,
            skipIfToolsRunning: skipIfToolsRunning,
            allowDirectDelete: allowDirectDelete,
            limit: limit,
            outputFormat: outputFormat,
            outputPath: outputPath,
            trendDays: Array(Set(trendDays)).sorted()
        )
    }
}

private enum AutomationCLIError: LocalizedError {
    case missingCommand
    case missingRequiredOption(String)
    case invalidCategory(String)
    case invalidValue(String)
    case unrecognizedArgument(String)
    case policyNotFound(String)
    case unsupportedOptionForCommand(String, String)

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "missing automation command; expected one of: list, create, run, run-due, history, trends"
        case .missingRequiredOption(let option):
            return "missing required option value for \(option)"
        case .invalidCategory(let value):
            let available = StorageCategoryKind.allCases.map(\.rawValue).joined(separator: ", ")
            return "invalid category '\(value)'; expected one of: \(available)"
        case .invalidValue(let option):
            return "invalid value for \(option)"
        case .unrecognizedArgument(let argument):
            return "unrecognized argument '\(argument)'"
        case .policyNotFound(let policyID):
            return "automation policy '\(policyID)' was not found"
        case .unsupportedOptionForCommand(let option, let command):
            return "\(option) is not supported for automation command '\(command)'"
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
                           [--list-stale-artifacts]
                           [--clean-stale-artifacts [--stale-artifact <id> ...] [--allow-direct-delete] [--skip-if-tools-running]]
                           [--switch-active-xcode <path>]

    Options:
      --no-progress                  Suppress progress output
      --dry-run                      Output dry-run plan JSON instead of snapshot JSON
      --execute                      Execute selected plan and output execution report JSON
      --list-stale-artifacts         Output stale/orphaned simulator and device support candidate JSON
      --clean-stale-artifacts        Execute cleanup for cleanable stale/orphaned artifacts (all by default)
      --stale-artifact <id>          Include specific cleanable stale artifact candidate ID for cleanup
      --switch-active-xcode <path>   Switch active Xcode to the selected install path
      --allow-direct-delete          Allow direct delete fallback when move-to-trash fails (execute/clean-stale modes)
      --skip-if-tools-running        Skip execute/clean-stale when Xcode or the Simulator app is currently running
      --plan-category <kind>         Include storage category in dry-run plan
      --plan-simulator-device <udid> Include simulator device (UDID) in dry-run plan
      --plan-xcode-install <path>    Include specific Xcode app bundle path in plan
      --help                         Show this help message

    Automation:
      xcodecleaner-cli automation list [--output <path>]
      xcodecleaner-cli automation create --name <name> [--category <kind> ...] [--every-hours <n>] [--min-age-days <n>] [--min-total-bytes <bytes>] [--allow-direct-delete] [--no-skip-if-tools-running] [--output <path>]
      xcodecleaner-cli automation run --id <policy-id> [--no-progress] [--output <path>]
      xcodecleaner-cli automation run-due [--no-progress] [--output <path>]
      xcodecleaner-cli automation history [--limit <n>] [--format json|csv] [--output <path>]
      xcodecleaner-cli automation trends [--days <n> ...] [--format json|csv] [--output <path>]

    Storage Categories:
      \(categoryValues)

    Category semantics:
      - xcodeApplications: Aggregate delete of selected Xcode app bundle paths.
      - derivedData: Build products and indexes under ~/Library/Developer/Xcode/DerivedData.
      - mobileDeviceCrashLogs: Crash/log capture folders under ~/Library/Logs/CrashReporter/MobileDevice.
      - archives: Archived app builds under ~/Library/Developer/Xcode/Archives.
      - deviceSupport: Aggregate delete of all physical-device support directories under ~/Library/Developer/Xcode/iOS DeviceSupport.
      - simulatorData: Aggregate delete of CoreSimulator devices/caches/runtimes roots. Known registered devices and runtimes are removed via simctl when possible.
    """
    if toStandardError {
        writeToStandardError("\(usage)\n")
    } else {
        print(usage)
    }
}

func printAutomationUsage(toStandardError: Bool = false) {
    let categoryValues = StorageCategoryKind.allCases.map(\.rawValue).joined(separator: ", ")
    let usage = """
    Usage:
      xcodecleaner-cli automation list [--output <path>]
      xcodecleaner-cli automation create --name <name> [--category <kind> ...] [--every-hours <n>] [--min-age-days <n>] [--min-total-bytes <bytes>] [--allow-direct-delete] [--no-skip-if-tools-running] [--output <path>]
      xcodecleaner-cli automation run --id <policy-id> [--no-progress] [--output <path>]
      xcodecleaner-cli automation run-due [--no-progress] [--output <path>]
      xcodecleaner-cli automation history [--limit <n>] [--format json|csv] [--output <path>]
      xcodecleaner-cli automation trends [--days <n> ...] [--format json|csv] [--output <path>]

    Notes:
      - If no categories are provided during create, safe defaults are used.
      - Supported categories: \(categoryValues)
      - deviceSupport in automation/CLI is aggregate cleanup of all iOS DeviceSupport directories.
      - Schedule:
        - Omit --every-hours for manual-only policy.
        - Provide --every-hours for scheduled policy cadence.
      - history/trends default to JSON output; pass --format csv for CSV.
      - trends defaults to 7-day and 30-day windows unless --days is provided.
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
