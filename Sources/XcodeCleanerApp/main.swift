import SwiftUI
import XcodeInventoryCore

@main
struct XcodeCleanerApp: App {
    @StateObject private var viewModel = InventoryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 560)
                .task {
                    viewModel.loadIfNeeded()
                }
        }
    }
}

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var snapshot: XcodeInventorySnapshot?

    private let scanner: XcodeInventoryScanner

    init(scanner: XcodeInventoryScanner = XcodeInventoryScanner()) {
        self.scanner = scanner
    }

    func loadIfNeeded() {
        guard snapshot == nil else {
            return
        }
        reload()
    }

    func reload() {
        isLoading = true
        snapshot = scanner.scan()
        isLoading = false
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: InventoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            if viewModel.isLoading {
                ProgressView("Scanning for Xcode installations...")
            } else if let snapshot = viewModel.snapshot {
                inventoryView(snapshot: snapshot)
            } else {
                Text("No scan data yet.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("XcodeCleaner")
                    .font(.largeTitle.bold())
                Text("Sprint 1: Read-only inventory")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                viewModel.reload()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }

    @ViewBuilder
    private func inventoryView(snapshot: XcodeInventorySnapshot) -> some View {
        Text("Detected Xcode installs: \(snapshot.installs.count)")
            .font(.headline)

        if let activePath = snapshot.activeDeveloperDirectoryPath {
            Text("Active Developer Directory: \(activePath)")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        } else {
            Text("Active Developer Directory: Unknown")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        List(snapshot.installs) { install in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(install.displayName)
                        .font(.title3.weight(.semibold))
                    if install.isActive {
                        Text("ACTIVE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 10) {
                    Text("Version: \(install.version ?? "Unknown")")
                    Text("Build: \(install.build ?? "Unknown")")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Text(install.path)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
