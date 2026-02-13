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
    @Published private(set) var scanProgressFraction: Double = 0
    @Published private(set) var scanPhaseTitle = "Idle"
    @Published private(set) var scanMessage = "Ready"

    private let scanner: XcodeInventoryScanner
    private var activeScanID = UUID()

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
        scanProgressFraction = 0
        scanPhaseTitle = ScanPhase.discoveringXcodeInstalls.title
        scanMessage = "Starting scan..."
        let scanID = UUID()
        activeScanID = scanID
        let scanner = self.scanner

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = scanner.scan { progress in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeScanID == scanID else {
                        return
                    }
                    self.scanProgressFraction = progress.fractionCompleted
                    self.scanPhaseTitle = progress.phase.title
                    self.scanMessage = progress.message
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeScanID == scanID else {
                    return
                }
                self.snapshot = snapshot
                self.scanProgressFraction = 1
                self.scanPhaseTitle = ScanPhase.finalizingSnapshot.title
                self.scanMessage = "Scan complete"
                self.isLoading = false
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: InventoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            if viewModel.isLoading {
                scanProgressView
                if let snapshot = viewModel.snapshot {
                    Divider()
                    inventoryView(snapshot: snapshot)
                }
            } else if let snapshot = viewModel.snapshot {
                inventoryView(snapshot: snapshot)
            } else {
                Text("No scan data yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("XcodeCleaner")
                    .font(.largeTitle.bold())
                Text("Sprint 3: Inventory + storage + runtime telemetry")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                viewModel.reload()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }

    private var scanProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scanning")
                    .font(.headline)
                Spacer()
                Text("\(Int((viewModel.scanProgressFraction * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: viewModel.scanProgressFraction)
            Text(viewModel.scanPhaseTitle)
                .font(.callout.weight(.medium))
            Text(viewModel.scanMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func inventoryView(snapshot: XcodeInventorySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                runtimeTelemetryView(snapshot: snapshot)
                storageOverviewView(snapshot: snapshot)
                installInventoryView(snapshot: snapshot)
                simulatorInventoryView(snapshot: snapshot)
            }
        }
    }

    private func runtimeTelemetryView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runtime Telemetry")
                .font(.headline)
            HStack(spacing: 12) {
                Text("Running Xcode instances: \(snapshot.runtimeTelemetry.totalXcodeRunningInstances)")
                Text("Running Simulator app instances: \(snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances)")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func storageOverviewView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage Overview")
                .font(.headline)
            Text("Total Xcode Footprint: \(formatBytes(snapshot.storage.totalBytes))")
                .font(.title3.weight(.semibold))

            ForEach(snapshot.storage.categories) { category in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text(formatBytes(category.bytes))
                            .font(.callout.monospacedDigit())
                    }
                    .font(.callout.weight(.medium))

                    if !category.paths.isEmpty {
                        Text(category.paths.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Text("Ownership: \(category.ownershipSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Safety: \(category.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: category.safetyClassification))
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func installInventoryView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Xcode installs: \(snapshot.installs.count)")
                .font(.headline)

            if let activePath = snapshot.activeDeveloperDirectoryPath {
                Text("Active Developer Directory: \(activePath)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Active Developer Directory: Unknown")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(snapshot.installs) { install in
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
                        if install.runningInstanceCount > 0 {
                            Text("RUNNING x\(install.runningInstanceCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        Text(formatBytes(install.sizeInBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
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

                    Text("Ownership: \(install.ownershipSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Safety: \(install.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: install.safetyClassification))
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func simulatorInventoryView(snapshot: XcodeInventorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulator Inventory")
                .font(.headline)

            Text("Devices: \(snapshot.simulator.devices.count), Runtimes: \(snapshot.simulator.runtimes.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("Simulator Runtimes")
                .font(.subheadline.weight(.semibold))
            ForEach(snapshot.simulator.runtimes) { runtime in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(runtime.name)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(formatBytes(runtime.sizeInBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Identifier: \(runtime.identifier)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Version: \(runtime.version ?? "Unknown"), Available: \(runtime.isAvailable ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let bundlePath = runtime.bundlePath {
                        Text(bundlePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Safety: \(runtime.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: runtime.safetyClassification))
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Simulator Devices")
                .font(.subheadline.weight(.semibold))
            ForEach(snapshot.simulator.devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name)
                            .font(.callout.weight(.medium))
                        Spacer()
                        if device.runningInstanceCount > 0 {
                            Text("RUNNING x\(device.runningInstanceCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(formatBytes(device.sizeInBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Runtime: \(device.runtimeName ?? device.runtimeIdentifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("State: \(device.state), Available: \(device.isAvailable ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("UDID: \(device.udid)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(device.dataPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Safety: \(device.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: device.safetyClassification))
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func color(for safetyClassification: SafetyClassification) -> Color {
        switch safetyClassification {
        case .regenerable:
            return .green
        case .conditionallySafe:
            return .orange
        case .destructive:
            return .red
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
