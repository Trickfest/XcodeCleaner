import SwiftUI

struct AppStatusStripView: View {
    @ObservedObject var viewModel: InventoryViewModel
    let selectedSection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedSection.title)
                    .font(.headline)
                Spacer()
                if let snapshot = viewModel.snapshot {
                    Text("Last scan: \(AppPresentation.formatDateTime(snapshot.scannedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if viewModel.isLoading {
                ScanProgressView(
                    scanProgressFraction: viewModel.scanProgressFraction,
                    scanPhaseTitle: viewModel.scanPhaseTitle,
                    scanMessage: viewModel.scanMessage
                )
            } else {
                Text("\(viewModel.scanPhaseTitle): \(viewModel.scanMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScanProgressView: View {
    let scanProgressFraction: Double
    let scanPhaseTitle: String
    let scanMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scanning")
                    .font(.headline)
                Spacer()
                Text("\(Int((scanProgressFraction * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: scanProgressFraction)
            Text(scanPhaseTitle)
                .font(.callout.weight(.medium))
            Text(scanMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
