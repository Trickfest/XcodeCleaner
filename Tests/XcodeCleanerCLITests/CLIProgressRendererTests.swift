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
    }

    @Test("CLI options parse dry-run with categories and simulator selections")
    func parseDryRunOptions() throws {
        let options = try CLIOptions.parse(arguments: [
            "--dry-run",
            "--plan-category", "derivedData",
            "--plan-category=deviceSupport",
            "--plan-simulator-device", "AAA-BBB",
            "--plan-simulator-device=CCC-DDD",
        ])

        #expect(options.dryRun == true)
        #expect(options.selectedCategoryKinds == [.derivedData, .deviceSupport])
        #expect(options.selectedSimulatorDeviceUDIDs == ["AAA-BBB", "CCC-DDD"])
    }

    @Test("Dry-run defaults to safe categories when no explicit selections")
    func parseDryRunDefaults() throws {
        let options = try CLIOptions.parse(arguments: ["--dry-run"])
        #expect(options.dryRun == true)
        #expect(Set(options.selectedCategoryKinds) == Set(DryRunSelection.safeCategoryDefaults.selectedCategoryKinds))
        #expect(options.selectedSimulatorDeviceUDIDs.isEmpty)
    }

    @Test("Plan selectors require dry-run mode")
    func parseSelectorsRequireDryRun() {
        #expect(throws: CLIOptionsError.requiresDryRun) {
            try CLIOptions.parse(arguments: ["--plan-category", "derivedData"])
        }
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
