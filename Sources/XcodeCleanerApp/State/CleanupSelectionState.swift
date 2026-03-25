import XcodeInventoryCore

struct CleanupSelectionState: Equatable, Sendable {
    var selectedCategoryKinds = Set(guiDefaultCleanupCategoryKinds)
    var selectedCountedFootprintComponentKinds: Set<CountedFootprintComponentKind> = []
    var selectedSimulatorDeviceUDIDs: Set<String> = []
    var selectedSimulatorRuntimeIdentifiers: Set<String> = []
    var selectedXcodeInstallPaths: Set<String> = []
    var selectedPhysicalDeviceSupportDirectoryPaths: Set<String> = []
    var selectedStaleArtifactIDs: Set<String> = []
    var allowDirectDeleteFallback = false
    var blockCleanupWhileToolsRunning = true

    func selection(for snapshot: XcodeInventorySnapshot) -> DryRunSelection {
        let availableCountedComponentKinds = Set(
            snapshot.storage.countedOnlyComponents
                .filter { CleanupPolicies.policy(for: $0.kind).surface == .explicitOptIn && !$0.paths.isEmpty }
                .map(\.kind)
        )
        let availableDeviceUDIDs = Set(snapshot.simulator.devices.map(\.udid))
        let availableRuntimeIdentifiers = Set(snapshot.simulator.runtimes.map(\.identifier))
        let availableInstallPaths = Set(snapshot.installs.map(\.path))
        let availablePhysicalDeviceSupportPaths = Set(snapshot.physicalDeviceSupportDirectories.map(\.path))

        return DryRunSelection(
            selectedCategoryKinds: Array(selectedCategoryKinds),
            selectedCountedFootprintComponentKinds: Array(
                selectedCountedFootprintComponentKinds.intersection(availableCountedComponentKinds)
            ),
            selectedSimulatorDeviceUDIDs: Array(selectedSimulatorDeviceUDIDs.intersection(availableDeviceUDIDs)),
            selectedSimulatorRuntimeIdentifiers: Array(selectedSimulatorRuntimeIdentifiers.intersection(availableRuntimeIdentifiers)),
            selectedPhysicalDeviceSupportDirectoryPaths: Array(
                selectedPhysicalDeviceSupportDirectoryPaths.intersection(availablePhysicalDeviceSupportPaths)
            ),
            selectedXcodeInstallPaths: Array(selectedXcodeInstallPaths.intersection(availableInstallPaths))
        )
    }

    func selectedStaleArtifactIDs(from report: StaleArtifactReport) -> [String] {
        let availableIDs = Set(report.candidates.map(\.id))
        return Array(selectedStaleArtifactIDs.intersection(availableIDs)).sorted()
    }
}
