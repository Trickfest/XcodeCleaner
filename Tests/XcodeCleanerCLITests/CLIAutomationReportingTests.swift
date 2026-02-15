import Foundation
import Testing
import XcodeInventoryCore
@testable import XcodeCleanerCLI

struct CLIAutomationReportingTests {
    @Test("automation history supports CSV export to file")
    func automationHistoryCSVExport() throws {
        let stateDirectory = makeTempDirectory(prefix: "xcodecleaner-cli-history")
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let store = JSONAutomationPolicyStore(stateDirectoryURL: stateDirectory)
        try store.appendRunHistory(makeRecord(runID: "run-1", status: .executed, reclaimedBytes: 512))

        let outputPath = stateDirectory.appendingPathComponent("history.csv", isDirectory: false).path
        let exitCode = XcodeCleanerCLIApp.run(
            arguments: [
                "automation", "history",
                "--format", "csv",
                "--output", outputPath,
            ],
            environment: ["XCODECLEANER_STATE_DIR": stateDirectory.path]
        )

        #expect(exitCode == 0)

        let contents = try String(contentsOf: URL(filePath: outputPath), encoding: .utf8)
        #expect(contents.contains("runID,policyID,policyName,trigger,status"))
        #expect(contents.contains("\"run-1\""))
    }

    @Test("automation trends supports default windows and CSV export")
    func automationTrendsCSVExport() throws {
        let stateDirectory = makeTempDirectory(prefix: "xcodecleaner-cli-trends")
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let store = JSONAutomationPolicyStore(stateDirectoryURL: stateDirectory)
        try store.appendRunHistory(makeRecord(runID: "run-2", status: .executed, reclaimedBytes: 128))

        let outputPath = stateDirectory.appendingPathComponent("trends.csv", isDirectory: false).path
        let exitCode = XcodeCleanerCLIApp.run(
            arguments: [
                "automation", "trends",
                "--format", "csv",
                "--output", outputPath,
            ],
            environment: ["XCODECLEANER_STATE_DIR": stateDirectory.path]
        )

        #expect(exitCode == 0)

        let contents = try String(contentsOf: URL(filePath: outputPath), encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0] == "windowDays,totalRuns,executedRuns,skippedRuns,failedRuns,totalReclaimedBytes")
        #expect(lines[1].hasPrefix("7,"))
        #expect(lines[2].hasPrefix("30,"))
    }

    @Test("automation trends rejects unsupported --limit option")
    func automationTrendsRejectsLimit() {
        let stateDirectory = makeTempDirectory(prefix: "xcodecleaner-cli-trends-error")
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let exitCode = XcodeCleanerCLIApp.run(
            arguments: ["automation", "trends", "--limit", "1"],
            environment: ["XCODECLEANER_STATE_DIR": stateDirectory.path]
        )

        #expect(exitCode == 2)
    }
}

private func makeRecord(runID: String, status: AutomationRunStatus, reclaimedBytes: Int64) -> AutomationPolicyRunRecord {
    AutomationPolicyRunRecord(
        runID: runID,
        policyID: "policy-test",
        policyName: "Policy Test",
        trigger: .manual,
        startedAt: Date(timeIntervalSince1970: 1_000),
        finishedAt: Date(timeIntervalSince1970: 1_001),
        status: status,
        skippedReason: status == .skipped ? "Skipped for test" : nil,
        message: "Test run",
        totalReclaimedBytes: reclaimedBytes,
        executionReport: nil
    )
}

private func makeTempDirectory(prefix: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
