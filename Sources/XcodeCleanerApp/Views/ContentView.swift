import SwiftUI
import XcodeInventoryCore

struct ContentView: View {
    @ObservedObject var viewModel: InventoryViewModel
    @State private var selectedSection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Sections")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                header
                AppStatusStripView(viewModel: viewModel, selectedSection: selectedSection)
                Divider()
                sectionContent
            }
            .padding(20)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("XcodeCleaner")
                    .font(.largeTitle.bold())
                Text("Version 0.90")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                viewModel.reload()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.isLoading || viewModel.isExecuting)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if let snapshot = viewModel.snapshot {
            switch selectedSection {
            case .overview:
                OverviewSectionView(viewModel: viewModel, snapshot: snapshot)
            case .cleanup:
                CleanupSectionView(viewModel: viewModel, snapshot: snapshot)
            case .automation:
                AutomationSectionView(
                    viewModel: viewModel,
                    openReportsSection: { selectedSection = .reports }
                )
            case .reports:
                ReportsSectionView(viewModel: viewModel)
            }
        } else if viewModel.isLoading {
            Text("Scanning...")
                .foregroundStyle(.secondary)
        } else {
            Text("No scan data yet.")
                .foregroundStyle(.secondary)
        }
    }
}
