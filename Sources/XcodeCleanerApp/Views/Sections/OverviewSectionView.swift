import SwiftUI
import XcodeInventoryCore

struct OverviewSectionView: View {
    @ObservedObject var viewModel: InventoryViewModel
    let snapshot: XcodeInventorySnapshot

    @State private var selectedSwitchInstallPath = ""
    @State private var showingFootprintHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                runtimeTelemetryView
                storageOverviewView
                installInventoryView
                activeXcodeSwitchPanel
                simulatorInventoryView
            }
        }
        .onAppear {
            synchronizeSelectedSwitchInstallPath()
        }
        .onChange(of: snapshot.scannedAt) { _, _ in
            synchronizeSelectedSwitchInstallPath()
        }
    }

    private var runtimeTelemetryView: some View {
        let runtimeStaleReasonsByIdentifier = AppPresentation.simulatorRuntimeStaleReasonsByIdentifier(in: snapshot)
        let deviceStaleReasonsByUDID = AppPresentation.simulatorDeviceStaleReasonsByUDID(in: snapshot)
        let orphanedSimulatorArtifactCount = AppPresentation.orphanedSimulatorArtifactCount(
            in: viewModel.staleArtifactReport
        )
        let staleRuntimeCount = snapshot.simulator.runtimes.filter { runtime in
            !(runtimeStaleReasonsByIdentifier[runtime.identifier] ?? []).isEmpty
        }.count
        let staleDeviceCount = snapshot.simulator.devices.filter { device in
            !(deviceStaleReasonsByUDID[device.udid] ?? []).isEmpty
        }.count

        return VStack(alignment: .leading, spacing: 6) {
            Text("Runtime Telemetry")
                .font(.headline)
            HStack(spacing: 12) {
                Text("Running Xcode instances: \(snapshot.runtimeTelemetry.totalXcodeRunningInstances)")
                Text("Running Simulator app instances: \(snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances)")
                Text("Stale runtimes: \(staleRuntimeCount)")
                Text("Stale devices: \(staleDeviceCount)")
                Text("Orphaned simulator artifacts: \(orphanedSimulatorArtifactCount)")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var storageOverviewView: some View {
        let additionalFootprintComponents = AppPresentation.visibleAdditionalFootprintComponents(in: snapshot.storage)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Storage Overview")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Total Xcode Footprint: \(AppPresentation.formatBytes(snapshot.storage.totalBytes))")
                    .font(.title3.weight(.semibold))
                Button {
                    showingFootprintHelp = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingFootprintHelp, arrowEdge: .bottom) {
                    footprintHelpPopover
                }
            }

            ForEach(snapshot.storage.categories) { category in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text(AppPresentation.formatBytes(category.bytes))
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
                        .foregroundStyle(AppPresentation.color(for: category.safetyClassification))
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if !additionalFootprintComponents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Additional Xcode Footprint Components")
                        .font(.subheadline.weight(.semibold))
                    Text("These components contribute to Total Xcode Footprint. Some are explicit opt-in cleanup targets; others are counted only in this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(additionalFootprintComponents) { component in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(component.title)
                                Spacer()
                                Text(AppPresentation.formatBytes(component.bytes))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout.weight(.medium))

                            if !component.paths.isEmpty {
                                Text(component.paths.joined(separator: "\n"))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            Text("Ownership: \(component.ownershipSummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(AppPresentation.additionalFootprintComponentNote(for: component.kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var footprintHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total Xcode Footprint")
                .font(.headline)
            Text(AppPresentation.totalFootprintDefinition)
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Currently counted in this build")
                    .font(.subheadline.weight(.semibold))
                ForEach(
                    Array(AppPresentation.totalFootprintIncludedItems(for: snapshot.storage).enumerated()),
                    id: \.offset
                ) { _, item in
                    Text("• \(item)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Not counted")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(AppPresentation.totalFootprintExcludedItems.enumerated()), id: \.offset) { _, item in
                    Text("• \(item)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(AppPresentation.totalFootprintCleanupNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 440, alignment: .leading)
    }

    private var installInventoryView: some View {
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
                        Text(AppPresentation.formatBytes(install.sizeInBytes))
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
                        .foregroundStyle(AppPresentation.color(for: install.safetyClassification))
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var activeXcodeSwitchPanel: some View {
        let hasAlternateInstall = snapshot.installs.contains(where: { !$0.isActive })
        let selectedInstall = snapshot.installs.first(where: { $0.path == selectedSwitchInstallPath })
        let selectedInstallIsActive = selectedInstall?.isActive ?? false
        let switchActionEnabled =
            hasAlternateInstall &&
            !selectedSwitchInstallPath.isEmpty &&
            !selectedInstallIsActive &&
            !viewModel.isLoading &&
            !viewModel.isExecuting

        return VStack(alignment: .leading, spacing: 10) {
            Text("Active Xcode Switch")
                .font(.subheadline.weight(.semibold))

            if snapshot.installs.isEmpty {
                Text("No Xcode installs available to switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Target Xcode", selection: $selectedSwitchInstallPath) {
                    ForEach(snapshot.installs) { install in
                        Text("\(install.displayName) (\(install.version ?? "Unknown"), \(install.build ?? "Unknown"))")
                            .tag(install.path)
                    }
                }

                Button("Switch Active Xcode") {
                    viewModel.switchActiveXcode(targetInstallPath: selectedSwitchInstallPath)
                }
                .disabled(!switchActionEnabled)

                if !hasAlternateInstall {
                    Text("No alternate Xcode installs found. Install another Xcode to enable switching.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if selectedInstallIsActive {
                    Text("Selected Xcode is already active. Choose a different install to switch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.switchStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let switchResult = viewModel.lastXcodeSwitchResult {
                    Text("Result: \(switchResult.status.rawValue) | New active: \(switchResult.newActiveDeveloperDirectoryPath ?? "Unknown")")
                        .font(.caption.monospaced())
                        .foregroundStyle(AppPresentation.color(for: switchResult.status))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var simulatorInventoryView: some View {
        let runtimeStaleReasonsByIdentifier = AppPresentation.simulatorRuntimeStaleReasonsByIdentifier(in: snapshot)
        let deviceStaleReasonsByUDID = AppPresentation.simulatorDeviceStaleReasonsByUDID(in: snapshot)
        let orphanedSimulatorArtifactCount = AppPresentation.orphanedSimulatorArtifactCount(
            in: viewModel.staleArtifactReport
        )
        let orphanedRuntimeCandidates = AppPresentation.orphanedSimulatorRuntimeCandidates(
            in: viewModel.staleArtifactReport
        )
        let staleRuntimeCount = snapshot.simulator.runtimes.filter { runtime in
            !(runtimeStaleReasonsByIdentifier[runtime.identifier] ?? []).isEmpty
        }.count
        let staleDeviceCount = snapshot.simulator.devices.filter { device in
            !(deviceStaleReasonsByUDID[device.udid] ?? []).isEmpty
        }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Simulator Inventory")
                .font(.headline)

            Text("Devices: \(snapshot.simulator.devices.count), Runtimes: \(snapshot.simulator.runtimes.count), Stale devices: \(staleDeviceCount), Stale runtimes: \(staleRuntimeCount), Orphaned simulator artifacts: \(orphanedSimulatorArtifactCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            if !orphanedRuntimeCandidates.isEmpty {
                Text("Orphaned simulator runtimes are reported here for manual cleanup; the app does not delete them.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if orphanedSimulatorArtifactCount > 0 {
                Text("Review orphaned simulator artifacts in Cleanup > Stale And Orphaned Artifacts.")
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if !orphanedRuntimeCandidates.isEmpty {
                Text("Orphaned Simulator Runtimes")
                    .font(.subheadline.weight(.semibold))
                ForEach(orphanedRuntimeCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.title)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(AppPresentation.formatBytes(candidate.reclaimableBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(candidate.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(candidate.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Manual cleanup only")
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Text("Simulator Runtimes")
                .font(.subheadline.weight(.semibold))
            ForEach(snapshot.simulator.runtimes) { runtime in
                let staleReasons = runtimeStaleReasonsByIdentifier[runtime.identifier] ?? []
                let isStale = !staleReasons.isEmpty
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(runtime.name)
                            .font(.callout.weight(.medium))
                        if isStale {
                            Text("STALE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        Text(AppPresentation.formatBytes(runtime.sizeInBytes))
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
                    if isStale {
                        Text("Stale: \(AppPresentation.runtimeStaleSummary(staleReasons))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Safety: \(runtime.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(AppPresentation.color(for: runtime.safetyClassification))
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Simulator Devices")
                .font(.subheadline.weight(.semibold))
            ForEach(snapshot.simulator.devices) { device in
                let staleReasons = deviceStaleReasonsByUDID[device.udid] ?? []
                let isStale = !staleReasons.isEmpty
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
                        if isStale {
                            Text("STALE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(AppPresentation.formatBytes(device.sizeInBytes))
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
                    if isStale {
                        Text("Stale: \(AppPresentation.deviceStaleSummary(staleReasons))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Safety: \(device.safetyClassification.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(AppPresentation.color(for: device.safetyClassification))
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func synchronizeSelectedSwitchInstallPath() {
        let availablePaths = Set(snapshot.installs.map(\.path))
        guard selectedSwitchInstallPath.isEmpty || !availablePaths.contains(selectedSwitchInstallPath) else {
            return
        }
        selectedSwitchInstallPath = snapshot.installs.first(where: { !$0.isActive })?.path
            ?? snapshot.installs.first?.path
            ?? ""
    }
}
