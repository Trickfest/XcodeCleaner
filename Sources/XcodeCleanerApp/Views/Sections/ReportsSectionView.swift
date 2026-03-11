import SwiftUI

struct ReportsSectionView: View {
    @ObservedObject var viewModel: InventoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reports")
                    .font(.headline)
                Text("Centralized history, trend summaries, and export actions for automation and cleanup runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                reportsStatusPanel

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        AutomationRunSummariesPanel(
                            viewModel: viewModel,
                            title: "Automation Trend Summaries"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        AutomationRecentRunsPanel(
                            viewModel: viewModel,
                            title: "Automation Run History",
                            maxRows: 12
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        AutomationRunSummariesPanel(
                            viewModel: viewModel,
                            title: "Automation Trend Summaries"
                        )
                        AutomationRecentRunsPanel(
                            viewModel: viewModel,
                            title: "Automation Run History",
                            maxRows: 12
                        )
                    }
                }

                ReportsExportsPanel(viewModel: viewModel)

                if let report = viewModel.lastExecutionReport {
                    ExecutionReportView(report: report)
                } else {
                    Text("No cleanup execution report available yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reportsStatusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report Status")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Text("History loaded: \(viewModel.automationRunHistory.count)")
                    .font(.caption.monospacedDigit())
                Text("Trend windows: \(viewModel.automationTrendSummaries.count)")
                    .font(.caption.monospacedDigit())
                if let report = viewModel.lastExecutionReport {
                    Text("Last cleanup reclaimed: \(AppPresentation.formatBytes(report.totalReclaimedBytes))")
                        .font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(.secondary)

            if let exportPath = viewModel.automationLastExportPath {
                Text("Last export: \(exportPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("No export has been generated in this session yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
