import Foundation
import Testing
import XcodeInventoryCore
@testable import XcodeCleanerCLI

struct CLIProgressRendererTests {
    @Test("CLI options parse no-progress and help flags")
    func parseOptions() throws {
        let options = try CLIOptions.parse(arguments: ["--no-progress", "--help"])
        #expect(options.suppressProgress == true)
        #expect(options.showHelp == true)
        #expect(options.mode == .snapshot)
    }

    @Test("CLI options parse dry-run with categories and simulator selections")
    func parseDryRunOptions() throws {
        let options = try CLIOptions.parse(arguments: [
            "--dry-run",
            "--plan-category", "derivedData",
            "--plan-category=deviceSupport",
            "--plan-counted-component", "documentationCache",
            "--plan-counted-component", "xcodeLogs",
            "--plan-counted-component=coreSimulatorLogs",
            "--plan-simulator-device", "AAA-BBB",
            "--plan-simulator-device=CCC-DDD",
            "--plan-xcode-install", "/Applications/Xcode-beta.app",
            "--plan-xcode-install=/Applications/Xcode-old.app",
        ])

        #expect(options.mode == .dryRun)
        #expect(options.selectedCategoryKinds == [.derivedData, .deviceSupport])
        #expect(options.selectedCountedFootprintComponentKinds == [.coreSimulatorLogs, .documentationCache, .xcodeLogs])
        #expect(options.selectedSimulatorDeviceUDIDs == ["AAA-BBB", "CCC-DDD"])
        #expect(options.selectedXcodeInstallPaths == ["/Applications/Xcode-beta.app", "/Applications/Xcode-old.app"])
    }

    @Test("Dry-run defaults to safe categories when no explicit selections")
    func parseDryRunDefaults() throws {
        let options = try CLIOptions.parse(arguments: ["--dry-run"])
        #expect(options.mode == .dryRun)
        #expect(Set(options.selectedCategoryKinds) == Set(DryRunSelection.safeCategoryDefaults.selectedCategoryKinds))
        #expect(options.selectedCountedFootprintComponentKinds.isEmpty)
        #expect(options.selectedSimulatorDeviceUDIDs.isEmpty)
        #expect(options.selectedXcodeInstallPaths.isEmpty)
    }

    @Test("Plan selectors require dry-run or execute mode")
    func parseSelectorsRequirePlanningMode() {
        #expect(throws: CLIOptionsError.requiresPlanningMode) {
            try CLIOptions.parse(arguments: ["--plan-category", "derivedData"])
        }
    }

    @Test("CLI options parse execute mode with direct delete")
    func parseExecuteOptions() throws {
        let options = try CLIOptions.parse(arguments: [
            "--execute",
            "--allow-direct-delete",
            "--skip-if-tools-running",
            "--plan-simulator-device", "AAA-BBB",
            "--plan-xcode-install", "/Applications/Xcode-16.0.app",
        ])

        #expect(options.mode == .execute)
        #expect(options.allowDirectDelete == true)
        #expect(options.skipIfToolsRunning == true)
        #expect(options.selectedSimulatorDeviceUDIDs == ["AAA-BBB"])
        #expect(options.selectedXcodeInstallPaths == ["/Applications/Xcode-16.0.app"])
    }

    @Test("CLI options reject conflicting dry-run and execute flags")
    func parseConflictingModes() {
        #expect(throws: CLIOptionsError.conflictingModes) {
            try CLIOptions.parse(arguments: ["--dry-run", "--execute"])
        }
    }

    @Test("allow-direct-delete requires execute mode")
    func parseAllowDirectDeleteRequiresExecute() {
        #expect(throws: CLIOptionsError.requiresExecute("--allow-direct-delete")) {
            try CLIOptions.parse(arguments: ["--allow-direct-delete"])
        }
    }

    @Test("skip-if-tools-running requires execute mode")
    func parseSkipIfToolsRunningRequiresExecute() {
        #expect(throws: CLIOptionsError.requiresExecute("--skip-if-tools-running")) {
            try CLIOptions.parse(arguments: ["--skip-if-tools-running"])
        }
    }

    @Test("CLI options parse list stale artifacts mode")
    func parseListStaleArtifactsMode() throws {
        let options = try CLIOptions.parse(arguments: ["--list-stale-artifacts"])
        #expect(options.mode == .listStaleArtifacts)
    }

    @Test("CLI options parse clean stale artifacts mode")
    func parseCleanStaleArtifactsMode() throws {
        let options = try CLIOptions.parse(arguments: [
            "--clean-stale-artifacts",
            "--stale-artifact", "simulatorRuntime:/tmp/runtime.simruntime",
            "--stale-artifact=orphanedSimulatorDevice:/tmp/home/Library/Developer/CoreSimulator/Devices/ORPHAN-SIM-2",
            "--allow-direct-delete",
            "--skip-if-tools-running",
        ])
        #expect(options.mode == .cleanStaleArtifacts)
        #expect(options.allowDirectDelete == true)
        #expect(options.skipIfToolsRunning == true)
        #expect(options.selectedStaleArtifactIDs == [
            "orphanedSimulatorDevice:/tmp/home/Library/Developer/CoreSimulator/Devices/ORPHAN-SIM-2",
            "simulatorRuntime:/tmp/runtime.simruntime",
        ])
    }

    @Test("stale-artifact selector requires clean-stale-artifacts mode")
    func parseStaleArtifactSelectorRequiresMode() {
        #expect(throws: CLIOptionsError.requiresCleanStaleArtifacts) {
            try CLIOptions.parse(arguments: ["--stale-artifact", "id-1"])
        }
    }

    @Test("switch-active-xcode parses as dedicated mode")
    func parseSwitchActiveXcodeMode() throws {
        let options = try CLIOptions.parse(arguments: ["--switch-active-xcode", "/Applications/Xcode.app"])
        #expect(options.mode == .switchActiveXcode)
        #expect(options.switchActiveXcodePath == "/Applications/Xcode.app")
    }

    @Test("CLI options reject unknown argument")
    func parseUnknownOption() {
        #expect(throws: CLIOptionsError.self) {
            try CLIOptions.parse(arguments: ["--unknown"])
        }
    }

    @Test("Bar mode renders carriage-return updates and newline on finish")
    func barRendering() {
        var output = ""
        let renderer = CLIProgressRenderer(
            suppressProgress: false,
            stderrIsTTY: true,
            terminalColumnsProvider: { 100 },
            environment: ["TERM": "xterm-256color"],
            writeToStandardError: { output += $0 }
        )

        renderer.handle(progress: ScanProgress(
            phase: .discoveringXcodeInstalls,
            fractionCompleted: 0.12,
            message: "Locating installs"
        ))
        renderer.handle(progress: ScanProgress(
            phase: .finalizingSnapshot,
            fractionCompleted: 1,
            message: "Scan complete"
        ))
        renderer.finish()

        #expect(output.contains("\r"))
        #expect(output.hasSuffix("\n"))
        #expect(output.contains("100%"))
    }

    @Test("Line mode is used for non-interactive stderr")
    func lineRenderingFallback() {
        var output = ""
        let renderer = CLIProgressRenderer(
            suppressProgress: false,
            stderrIsTTY: false,
            terminalColumnsProvider: { nil },
            environment: [:],
            writeToStandardError: { output += $0 }
        )

        renderer.handle(progress: ScanProgress(
            phase: .sizingStorageCategories,
            fractionCompleted: 0.58,
            message: "Storage category sizing complete"
        ))

        #expect(!output.contains("\r"))
        #expect(output.contains("[ 58%]"))
        #expect(output.hasSuffix("\n"))
    }

    @Test("No-progress mode suppresses all output")
    func noProgressSuppression() {
        var output = ""
        let renderer = CLIProgressRenderer(
            suppressProgress: true,
            stderrIsTTY: true,
            terminalColumnsProvider: { 80 },
            environment: ["TERM": "xterm-256color"],
            writeToStandardError: { output += $0 }
        )

        renderer.handle(progress: ScanProgress(
            phase: .discoveringXcodeInstalls,
            fractionCompleted: 0.2,
            message: "Locating installs"
        ))
        renderer.finish()

        #expect(output.isEmpty)
    }
}
