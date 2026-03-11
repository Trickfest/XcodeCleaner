import SwiftUI
import XcodeInventoryCore

struct ExecutionReportView: View {
    let report: CleanupExecutionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Cleanup Execution")
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
                        Text(result.status.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPresentation.color(for: result.status))
                        Text(AppPresentation.formatBytes(result.reclaimedBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(result.pathResults) { pathResult in
                        Text("\(pathResult.status.rawValue): \(pathResult.path) (\(pathResult.operation.rawValue), \(AppPresentation.formatBytes(pathResult.reclaimedBytes)))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
