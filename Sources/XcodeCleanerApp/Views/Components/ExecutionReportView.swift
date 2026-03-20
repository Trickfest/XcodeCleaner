import SwiftUI
import XcodeInventoryCore

struct ExecutionReportView: View {
    var title = "Last Cleanup Execution"
    let report: CleanupExecutionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(
                "Reclaimed: \(AppPresentation.formatBytes(report.totalReclaimedBytes)) | Succeeded: \(report.succeededCount) | Partial: \(report.partiallySucceededCount) | Blocked: \(report.blockedCount) | Failed: \(report.failedCount)"
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)

            if let skippedReason = report.skippedReason {
                Text(skippedReason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(report.results) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(result.item.title)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(AppPresentation.cleanupActionStatusLabel(result.status))
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPresentation.color(for: result.status))
                        Text(AppPresentation.formatBytes(result.reclaimedBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.status == .failed ? AppPresentation.color(for: result.status) : .secondary)

                    ForEach(result.pathResults) { pathResult in
                        Text("\(AppPresentation.cleanupPathStatusLabel(pathResult.status)): \(pathResult.path) (\(AppPresentation.cleanupOperationLabel(pathResult.operation)), \(AppPresentation.formatBytes(pathResult.reclaimedBytes)))")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPresentation.color(for: pathResult.status))
                            .textSelection(.enabled)

                        if !pathResult.message.isEmpty {
                            Text(pathResult.message)
                                .font(.caption)
                                .foregroundStyle(pathResult.status == .failed ? AppPresentation.color(for: pathResult.status) : .secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
