import SwiftUI
import XcodeInventoryCore

struct CleanupSectionView: View {
    @ObservedObject var viewModel: InventoryViewModel
    let snapshot: XcodeInventorySnapshot

    @State private var selectionState = CleanupSelectionState()

    var body: some View {
        let selection = selectionState.selection(for: snapshot)
        let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)
        let staleArtifactReport = viewModel.staleArtifactReport ?? StaleArtifactReport(
            generatedAt: snapshot.scannedAt,
            candidates: [],
            totalReclaimableBytes: 0,
            notes: []
        )
        let selectedStaleArtifactIDs = selectionState.selectedStaleArtifactIDs(from: staleArtifactReport)
        let staleArtifactPlan = StaleArtifactPlanner.makePlan(
            snapshot: snapshot,
            report: staleArtifactReport,
            selectedCandidateIDs: selectedStaleArtifactIDs,
            now: Date(),
            defaultToAllCandidatesWhenSelectionEmpty: false
        )
        let simulatorRuntimeByIdentifier = Dictionary(
            uniqueKeysWithValues: snapshot.simulator.runtimes.map { ($0.identifier, $0) }
        )
        let runtimeStaleReasonsByIdentifier = AppPresentation.simulatorRuntimeStaleReasonsByIdentifier(in: snapshot)
        let deviceStaleReasonsByUDID = AppPresentation.simulatorDeviceStaleReasonsByUDID(in: snapshot)
        let runningXcodeInstances = snapshot.runtimeTelemetry.totalXcodeRunningInstances
        let runningSimulatorAppInstances = snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances
        let bootedSimulatorDeviceCount = snapshot.simulator.devices.filter { device in
            if device.runningInstanceCount > 0 {
                return true
            }
            let state = device.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return state == "booted" || state == "booting"
        }.count
        let runningToolsDetected =
            runningXcodeInstances > 0 ||
            runningSimulatorAppInstances > 0 ||
            bootedSimulatorDeviceCount > 0
        let executeBlockedByRunningTools = selectionState.blockCleanupWhileToolsRunning && runningToolsDetected

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cleanupWorkflowCard(
                    selection: selection,
                    plan: plan,
                    runningXcodeInstances: runningXcodeInstances,
                    runningSimulatorAppInstances: runningSimulatorAppInstances,
                    bootedSimulatorDeviceCount: bootedSimulatorDeviceCount,
                    executeBlockedByRunningTools: executeBlockedByRunningTools
                )

                selectionScopeCard(
                    simulatorRuntimeByIdentifier: simulatorRuntimeByIdentifier,
                    runtimeStaleReasonsByIdentifier: runtimeStaleReasonsByIdentifier,
                    deviceStaleReasonsByUDID: deviceStaleReasonsByUDID
                )

                staleArtifactWorkflowCard(
                    report: staleArtifactReport,
                    plan: staleArtifactPlan,
                    executeBlockedByRunningTools: executeBlockedByRunningTools,
                    runningXcodeInstances: runningXcodeInstances,
                    runningSimulatorAppInstances: runningSimulatorAppInstances,
                    bootedSimulatorDeviceCount: bootedSimulatorDeviceCount
                )
            }
        }
    }

    private func cleanupWorkflowCard(
        selection: DryRunSelection,
        plan: DryRunPlan,
        runningXcodeInstances: Int,
        runningSimulatorAppInstances: Int,
        bootedSimulatorDeviceCount: Int,
        executeBlockedByRunningTools: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleanup Workflow")
                        .font(.headline)
                    Text("Review the planned cleanup and execute when ready. Adjust scope in the section below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Estimated reclaim")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppPresentation.formatBytes(plan.totalReclaimableBytes))
                        .font(.title3.weight(.semibold))
                    Text("Planned items: \(plan.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !plan.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan notes")
                        .font(.callout.weight(.medium))
                    ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Planned Items")
                .font(.subheadline.weight(.semibold))
            if plan.items.isEmpty {
                Text("No dry-run items selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plan.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(AppPresentation.formatBytes(item.reclaimableBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("Kind: \(item.kind.rawValue), Safety: \(item.safetyClassification.rawValue)\(item.storageCategoryKind.map { ", Category: \($0.rawValue)" } ?? "")")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPresentation.color(for: item.safetyClassification))
                        Text("Ownership: \(item.ownershipSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !item.paths.isEmpty {
                            Text(item.paths.joined(separator: "\n"))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Execute Options and Status")
                    .font(.subheadline.weight(.semibold))
                Toggle(
                    "Block cleanup while Xcode or the Simulator app is running (recommended)",
                    isOn: $selectionState.blockCleanupWhileToolsRunning
                )
                .font(.callout)
                Toggle(
                    "Allow direct delete fallback when move-to-trash fails",
                    isOn: $selectionState.allowDirectDeleteFallback
                )
                .font(.callout)

                HStack(spacing: 10) {
                    Button("Execute Cleanup") {
                        viewModel.execute(
                            selection: selection,
                            allowDirectDelete: selectionState.allowDirectDeleteFallback,
                            requireToolsStopped: selectionState.blockCleanupWhileToolsRunning
                        )
                    }
                    .disabled(
                        plan.items.isEmpty ||
                        viewModel.isExecuting ||
                        viewModel.isLoading ||
                        executeBlockedByRunningTools
                    )

                    if viewModel.isExecuting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Executing cleanup...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if executeBlockedByRunningTools {
                        Text("Cleanup is blocked while tools are running (Xcode: \(runningXcodeInstances), Simulator app: \(runningSimulatorAppInstances), booted devices: \(bootedSimulatorDeviceCount)). Close tools or disable the block option.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(viewModel.executionStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let report = viewModel.lastExecutionReport {
                ExecutionReportView(report: report)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func selectionScopeCard(
        simulatorRuntimeByIdentifier: [String: SimulatorRuntimeRecord],
        runtimeStaleReasonsByIdentifier: [String: [SimulatorRuntimeStaleReason]],
        deviceStaleReasonsByUDID: [String: [SimulatorDeviceStaleReason]]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select Cleanup Scope")
                .font(.subheadline.weight(.semibold))

            Text("Categories")
                .font(.callout.weight(.medium))
            Text("Xcode app uninstall and physical device support directory cleanup are managed in the itemized sections below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(snapshot.storage.categories.filter { category in
                category.kind != .xcodeApplications && category.kind != .deviceSupport
            }) { category in
                Toggle(isOn: categoryBinding(for: category.kind)) {
                    HStack {
                        Text(category.title)
                        Text(AppPresentation.cleanupCategoryHelpText(for: category.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(AppPresentation.formatBytes(category.bytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Simulator Artifacts")
                .font(.callout.weight(.medium))
            Text("CoreSimulator runtimes and per-device data. Stale items are marked inline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Simulator Runtimes")
                    .font(.callout.weight(.medium))
                Text("Deletes selected known runtimes via simctl. Blocked while the Simulator app or booted devices are running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if snapshot.simulator.runtimes.isEmpty {
                Text("No simulator runtimes found in this scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.simulator.runtimes) { runtime in
                    let staleReasons = runtimeStaleReasonsByIdentifier[runtime.identifier] ?? []
                    let isStale = !staleReasons.isEmpty
                    let hasBundlePath = runtime.bundlePath != nil
                    Toggle(isOn: simulatorRuntimeBinding(for: runtime.identifier)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(runtime.name)
                                    if isStale {
                                        Text("STALE")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                Text("Version: \(runtime.version ?? "Unknown") | Available: \(runtime.isAvailable ? "Yes" : "No")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Identifier: \(runtime.identifier)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let bundlePath = runtime.bundlePath {
                                    Text(bundlePath)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                } else {
                                    Text("No bundle path available in snapshot; runtime cannot be selected for cleanup.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if isStale {
                                    Text("Stale: \(AppPresentation.runtimeStaleSummary(staleReasons))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(AppPresentation.formatBytes(runtime.sizeInBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!hasBundlePath)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Simulator Devices")
                    .font(.callout.weight(.medium))
                Text("Deletes selected registered simulator devices via simctl, including their apps/files/state, but not simulator runtimes or caches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if snapshot.simulator.devices.isEmpty {
                Text("No simulator devices found in this scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.simulator.devices) { device in
                    let runtime = simulatorRuntimeByIdentifier[device.runtimeIdentifier]
                    let runtimeName = runtime?.name ?? device.runtimeName ?? device.runtimeIdentifier
                    let runtimeVersion = runtime?.version ?? "Unknown"
                    let stateLabel = device.runningInstanceCount > 0
                        ? "\(device.state) (running x\(device.runningInstanceCount))"
                        : device.state
                    let staleReasons = deviceStaleReasonsByUDID[device.udid] ?? []
                    let isStale = !staleReasons.isEmpty
                    Toggle(isOn: simulatorDeviceBinding(for: device.udid)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(device.name)
                                    if device.runningInstanceCount > 0 {
                                        Text("RUNNING")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    if isStale {
                                        Text("STALE")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                Text("Runtime: \(runtimeName) | Version: \(runtimeVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("State: \(stateLabel) | Available: \(device.isAvailable ? "Yes" : "No")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("UDID: \(device.udid)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if isStale {
                                    Text("Stale: \(AppPresentation.deviceStaleSummary(staleReasons))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(AppPresentation.formatBytes(device.sizeInBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Xcode Installs")
                .font(.callout.weight(.medium))
            if snapshot.installs.isEmpty {
                Text("No Xcode installs found in this scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.installs) { install in
                    Toggle(isOn: xcodeInstallBinding(for: install.path)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(install.displayName)
                                Text("Version: \(install.version ?? "Unknown"), Build: \(install.build ?? "Unknown")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(install.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Text(AppPresentation.formatBytes(install.sizeInBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Physical Device Support Directories")
                    .font(.callout.weight(.medium))
            }
            Text("Real-device debug/symbol caches under iOS DeviceSupport (not simulator data). Deleting selected folders removes only those caches; Xcode regenerates them when matching devices reconnect (first debug may be slower).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if snapshot.physicalDeviceSupportDirectories.isEmpty {
                Text("No physical device support directories detected in this scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.physicalDeviceSupportDirectories) { directory in
                    Toggle(isOn: physicalDeviceSupportBinding(for: directory.path)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(directory.name)
                                Text(AppPresentation.physicalDeviceSupportDirectoryMetadata(directory, scannedAt: snapshot.scannedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(directory.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Text(AppPresentation.formatBytes(directory.sizeInBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func staleArtifactWorkflowCard(
        report: StaleArtifactReport,
        plan: DryRunPlan,
        executeBlockedByRunningTools: Bool,
        runningXcodeInstances: Int,
        runningSimulatorAppInstances: Int,
        bootedSimulatorDeviceCount: Int
    ) -> some View {
        let groupedCandidates = Dictionary(grouping: report.candidates, by: \.kind)
        let orderedKinds = groupedCandidates.keys.sorted { lhs, rhs in
            let lhsOrder = AppPresentation.staleArtifactGroupOrder(for: lhs)
            let rhsOrder = AppPresentation.staleArtifactGroupOrder(for: rhs)
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.rawValue < rhs.rawValue
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stale And Orphaned Artifacts")
                        .font(.headline)
                    Text("Explicit leftover simulator and device support artifacts. Nothing is preselected; review and opt in before cleanup. Orphaned simulator runtimes are report-only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Selected reclaim")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppPresentation.formatBytes(plan.totalReclaimableBytes))
                        .font(.title3.weight(.semibold))
                    Text("Detected: \(report.candidates.count) | Selected: \(plan.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !report.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detection notes")
                        .font(.callout.weight(.medium))
                    ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if report.candidates.isEmpty {
                Text("No stale or orphaned artifacts detected in the current scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orderedKinds, id: \.rawValue) { kind in
                    if let candidates = groupedCandidates[kind] {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppPresentation.staleArtifactGroupTitle(for: kind))
                                .font(.callout.weight(.medium))
                            ForEach(candidates) { candidate in
                                let isReportOnly = AppPresentation.staleArtifactIsReportOnly(candidate.kind)
                                Toggle(isOn: staleArtifactBinding(for: candidate.id)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(candidate.title)
                                                Text(AppPresentation.staleArtifactBadgeText(for: candidate.kind))
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(AppPresentation.staleArtifactBadgeColor(for: candidate.kind))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            Text(candidate.reason)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(candidate.path)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                            Text("Safety: \(candidate.safetyClassification.rawValue)")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(AppPresentation.color(for: candidate.safetyClassification))
                                            if let actionHint = AppPresentation.staleArtifactActionHint(for: candidate.kind) {
                                                Text(actionHint)
                                                    .font(.caption)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        Spacer()
                                        Text(AppPresentation.formatBytes(candidate.reclaimableBytes))
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(isReportOnly)
                            }
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Dedicated Cleanup")
                    .font(.subheadline.weight(.semibold))
                Text("Uses the execute options above and runs through the stale-artifact cleanup path rather than the normal cleanup plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Clean Selected Stale/Orphaned Artifacts") {
                        viewModel.executeStaleArtifactCleanup(
                            selectedCandidateIDs: selectionState.selectedStaleArtifactIDs(from: report),
                            allowDirectDelete: selectionState.allowDirectDeleteFallback,
                            requireToolsStopped: selectionState.blockCleanupWhileToolsRunning
                        )
                    }
                    .disabled(
                        plan.items.isEmpty ||
                        viewModel.isExecuting ||
                        viewModel.isLoading ||
                        executeBlockedByRunningTools
                    )

                    if viewModel.isExecuting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Executing stale/orphaned cleanup...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if executeBlockedByRunningTools {
                        Text("Stale/orphaned cleanup is blocked while tools are running (Xcode: \(runningXcodeInstances), Simulator app: \(runningSimulatorAppInstances), booted devices: \(bootedSimulatorDeviceCount)). Close tools or disable the block option above.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(viewModel.staleArtifactStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let report = viewModel.lastStaleArtifactExecutionReport {
                ExecutionReportView(title: "Last Stale/Orphaned Cleanup", report: report)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func categoryBinding(for kind: StorageCategoryKind) -> Binding<Bool> {
        Binding(
            get: { selectionState.selectedCategoryKinds.contains(kind) },
            set: { isSelected in
                if isSelected {
                    selectionState.selectedCategoryKinds.insert(kind)
                } else {
                    selectionState.selectedCategoryKinds.remove(kind)
                }
            }
        )
    }

    private func simulatorRuntimeBinding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { selectionState.selectedSimulatorRuntimeIdentifiers.contains(identifier) },
            set: { isSelected in
                if isSelected {
                    selectionState.selectedSimulatorRuntimeIdentifiers.insert(identifier)
                } else {
                    selectionState.selectedSimulatorRuntimeIdentifiers.remove(identifier)
                }
            }
        )
    }

    private func simulatorDeviceBinding(for udid: String) -> Binding<Bool> {
        Binding(
            get: { selectionState.selectedSimulatorDeviceUDIDs.contains(udid) },
            set: { isSelected in
                if isSelected {
                    selectionState.selectedSimulatorDeviceUDIDs.insert(udid)
                } else {
                    selectionState.selectedSimulatorDeviceUDIDs.remove(udid)
                }
            }
        )
    }

    private func xcodeInstallBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectionState.selectedXcodeInstallPaths.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectionState.selectedXcodeInstallPaths.insert(path)
                } else {
                    selectionState.selectedXcodeInstallPaths.remove(path)
                }
            }
        )
    }

    private func physicalDeviceSupportBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectionState.selectedPhysicalDeviceSupportDirectoryPaths.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectionState.selectedPhysicalDeviceSupportDirectoryPaths.insert(path)
                } else {
                    selectionState.selectedPhysicalDeviceSupportDirectoryPaths.remove(path)
                }
            }
        )
    }

    private func staleArtifactBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectionState.selectedStaleArtifactIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectionState.selectedStaleArtifactIDs.insert(id)
                } else {
                    selectionState.selectedStaleArtifactIDs.remove(id)
                }
            }
        )
    }
}
