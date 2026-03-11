import SwiftUI

struct AutomationRunSummariesPanel: View {
    @ObservedObject var viewModel: InventoryViewModel
    var title = "Run Summaries"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if let allTime = viewModel.automationAllTimeSummary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All-time")
                        .font(.callout.weight(.medium))
                    Text(
                        "Runs: \(allTime.totalRuns) | Executed: \(allTime.executedRuns) | Skipped: \(allTime.skippedRuns) | Failed: \(allTime.failedRuns) | Reclaimed: \(AppPresentation.formatBytes(allTime.totalReclaimedBytes))"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No all-time summary yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.automationTrendSummaries.isEmpty {
                Text("No trend windows available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.automationTrendSummaries, id: \.windowDays) { summary in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last \(summary.windowDays) day(s)")
                            .font(.callout.weight(.medium))
                        Text(
                            "Runs: \(summary.totalRuns) | Executed: \(summary.executedRuns) | Skipped: \(summary.skippedRuns) | Failed: \(summary.failedRuns) | Reclaimed: \(AppPresentation.formatBytes(summary.totalReclaimedBytes))"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AutomationRecentRunsPanel: View {
    @ObservedObject var viewModel: InventoryViewModel
    var title = "Recent Runs"
    var maxRows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if viewModel.automationRunHistory.isEmpty {
                Text("No automation run history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.automationRunHistory.prefix(maxRows))) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.policyName)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(record.status.rawValue.uppercased())
                                .font(.caption.monospaced())
                                .foregroundStyle(AppPresentation.color(for: record.status))
                            Text(AppPresentation.formatBytes(record.totalReclaimedBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("Trigger: \(record.trigger.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Started: \(AppPresentation.formatDateTime(record.startedAt)) | Finished: \(AppPresentation.formatDateTime(record.finishedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(record.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ReportsExportsPanel: View {
    @ObservedObject var viewModel: InventoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Actions")
                .font(.subheadline.weight(.semibold))
            Text("Export automation history and trend summaries in JSON or CSV.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("History JSON") {
                    viewModel.exportAutomationHistoryJSON()
                }
                Button("History CSV") {
                    viewModel.exportAutomationHistoryCSV()
                }
                Button("Trends JSON") {
                    viewModel.exportAutomationTrendsJSON()
                }
                Button("Trends CSV") {
                    viewModel.exportAutomationTrendsCSV()
                }
            }
            .disabled(viewModel.isExecuting || viewModel.isLoading)

            if let exportPath = viewModel.automationLastExportPath {
                Text("Last export: \(exportPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
