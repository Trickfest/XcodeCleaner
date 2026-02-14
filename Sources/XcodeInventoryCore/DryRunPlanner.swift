import Foundation

public enum DryRunPlanner {
    public static func makePlan(
        snapshot: XcodeInventorySnapshot,
        selection: DryRunSelection,
        now: Date = Date()
    ) -> DryRunPlan {
        var notes: [String] = []
        var selectedKinds = Set(selection.selectedCategoryKinds)
        let selectedDeviceUDIDs = Set(selection.selectedSimulatorDeviceUDIDs)

        // Prevent inaccurate double counting when users select both aggregate simulator data
        // and specific simulator devices in one plan.
        if selectedKinds.contains(.simulatorData), !selectedDeviceUDIDs.isEmpty {
            selectedKinds.remove(.simulatorData)
            notes.append("Removed aggregate Simulator Data category to avoid double counting with selected simulator devices.")
        }

        var items: [DryRunPlanItem] = []

        for category in snapshot.storage.categories {
            guard selectedKinds.contains(category.kind) else {
                continue
            }

            items.append(
                DryRunPlanItem(
                    kind: .storageCategory,
                    title: category.title,
                    reclaimableBytes: category.bytes,
                    paths: category.paths,
                    ownershipSummary: category.ownershipSummary,
                    safetyClassification: category.safetyClassification
                )
            )
        }

        let devicesByUDID = Dictionary(uniqueKeysWithValues: snapshot.simulator.devices.map { ($0.udid, $0) })
        for udid in selectedDeviceUDIDs.sorted() {
            guard let device = devicesByUDID[udid] else {
                notes.append("Selected simulator device \(udid) was not found in the current scan snapshot.")
                continue
            }

            items.append(
                DryRunPlanItem(
                    kind: .simulatorDevice,
                    title: "Simulator Device: \(device.name) (\(device.udid))",
                    reclaimableBytes: device.sizeInBytes,
                    paths: [device.dataPath],
                    ownershipSummary: device.ownershipSummary,
                    safetyClassification: device.safetyClassification
                )
            )
        }

        items.sort { lhs, rhs in
            if lhs.reclaimableBytes != rhs.reclaimableBytes {
                return lhs.reclaimableBytes > rhs.reclaimableBytes
            }
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let totalReclaimableBytes = items.reduce(Int64(0)) { partial, item in
            partial + item.reclaimableBytes
        }

        if items.isEmpty {
            notes.append("No items selected for dry-run planning.")
        }

        return DryRunPlan(
            generatedAt: now,
            selection: DryRunSelection(
                selectedCategoryKinds: Array(selectedKinds).sorted { $0.rawValue < $1.rawValue },
                selectedSimulatorDeviceUDIDs: selection.selectedSimulatorDeviceUDIDs
            ),
            items: items,
            totalReclaimableBytes: totalReclaimableBytes,
            notes: notes
        )
    }
}
