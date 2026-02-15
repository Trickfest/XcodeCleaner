import Foundation
import Testing
@testable import XcodeInventoryCore

struct AutomationHistoryReportingTests {
    @Test("History trends summarize run counts and reclaimed bytes per time window")
    func trendsSummaries() {
        let now = Date(timeIntervalSince1970: 10_000)
        let records = [
            makeRecord(
                runID: "run-1",
                status: .executed,
                reclaimedBytes: 400,
                startedAt: now.addingTimeInterval(-1 * 86_400)
            ),
            makeRecord(
                runID: "run-2",
                status: .skipped,
                reclaimedBytes: 0,
                startedAt: now.addingTimeInterval(-6 * 86_400)
            ),
            makeRecord(
                runID: "run-3",
                status: .failed,
                reclaimedBytes: 0,
                startedAt: now.addingTimeInterval(-15 * 86_400)
            ),
        ]

        let summaries = AutomationHistoryTrends.summaries(
            records: records,
            windowsInDays: [7, 30],
            now: now
        )

        #expect(summaries.count == 2)
        #expect(summaries[0].windowDays == 7)
        #expect(summaries[0].totalRuns == 2)
        #expect(summaries[0].executedRuns == 1)
        #expect(summaries[0].skippedRuns == 1)
        #expect(summaries[0].failedRuns == 0)
        #expect(summaries[0].totalReclaimedBytes == 400)

        #expect(summaries[1].windowDays == 30)
        #expect(summaries[1].totalRuns == 3)
        #expect(summaries[1].executedRuns == 1)
        #expect(summaries[1].skippedRuns == 1)
        #expect(summaries[1].failedRuns == 1)
        #expect(summaries[1].totalReclaimedBytes == 400)
    }

    @Test("CSV exporter emits header and escapes quoted/comma content")
    func csvExport() {
        let record = AutomationPolicyRunRecord(
            runID: "run-1",
            policyID: "policy-1",
            policyName: "Nightly, Beta \"Track\"",
            trigger: .manual,
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_005),
            status: .executed,
            skippedReason: nil,
            message: "Done, reclaimed \"400\" bytes",
            totalReclaimedBytes: 400,
            executionReport: nil
        )

        let csv = AutomationHistoryCSVExporter.export(records: [record])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count == 2)
        #expect(lines[0] == "runID,policyID,policyName,trigger,status,startedAt,finishedAt,totalReclaimedBytes,skippedReason,message")
        #expect(lines[1].contains("\"Nightly, Beta \"\"Track\"\"\""))
        #expect(lines[1].contains("\"Done, reclaimed \"\"400\"\" bytes\""))
    }

    @Test("Trend CSV exporter emits numeric summary rows")
    func trendCSVExport() {
        let summaries = [
            AutomationHistoryWindowSummary(
                windowDays: 7,
                totalRuns: 5,
                executedRuns: 3,
                skippedRuns: 1,
                failedRuns: 1,
                totalReclaimedBytes: 1_024
            ),
            AutomationHistoryWindowSummary(
                windowDays: 30,
                totalRuns: 10,
                executedRuns: 7,
                skippedRuns: 2,
                failedRuns: 1,
                totalReclaimedBytes: 8_192
            ),
        ]

        let csv = AutomationTrendCSVExporter.export(summaries: summaries)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count == 3)
        #expect(lines[0] == "windowDays,totalRuns,executedRuns,skippedRuns,failedRuns,totalReclaimedBytes")
        #expect(lines[1] == "7,5,3,1,1,1024")
        #expect(lines[2] == "30,10,7,2,1,8192")
    }
}

private func makeRecord(
    runID: String,
    status: AutomationRunStatus,
    reclaimedBytes: Int64,
    startedAt: Date
) -> AutomationPolicyRunRecord {
    AutomationPolicyRunRecord(
        runID: runID,
        policyID: "policy-1",
        policyName: "Policy",
        trigger: .scheduled,
        startedAt: startedAt,
        finishedAt: startedAt.addingTimeInterval(1),
        status: status,
        skippedReason: status == .skipped ? "Skipped" : nil,
        message: "Message",
        totalReclaimedBytes: reclaimedBytes,
        executionReport: nil
    )
}
