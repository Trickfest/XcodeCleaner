import Foundation

public protocol CleanupFileOperating {
    func fileExists(at url: URL) -> Bool
    func moveToTrash(at url: URL) throws
    func removeItem(at url: URL) throws
}

public struct FileManagerCleanupFileOperator: CleanupFileOperating {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func moveToTrash(at url: URL) throws {
        _ = try fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}

public struct CleanupExecutor: @unchecked Sendable {
    private let fileOperator: CleanupFileOperating
    private let pathSizer: PathSizing
    private let now: () -> Date

    public init(
        fileOperator: CleanupFileOperating = FileManagerCleanupFileOperator(),
        pathSizer: PathSizing = FileSystemPathSizer(),
        now: @escaping () -> Date = Date.init
    ) {
        self.fileOperator = fileOperator
        self.pathSizer = pathSizer
        self.now = now
    }

    public func execute(
        snapshot: XcodeInventorySnapshot,
        selection: DryRunSelection,
        allowDirectDelete: Bool = false,
        requireToolsStopped: Bool = false
    ) -> CleanupExecutionReport {
        let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection, now: now())
        return execute(
            snapshot: snapshot,
            plan: plan,
            allowDirectDelete: allowDirectDelete,
            requireToolsStopped: requireToolsStopped
        )
    }

    public func execute(
        snapshot: XcodeInventorySnapshot,
        plan: DryRunPlan,
        allowDirectDelete: Bool = false,
        requireToolsStopped: Bool = false
    ) -> CleanupExecutionReport {
        if requireToolsStopped, let reason = runningToolsBlockReason(in: snapshot) {
            return CleanupExecutionReport(
                executedAt: now(),
                allowDirectDelete: allowDirectDelete,
                skippedReason: reason,
                selection: plan.selection,
                plan: plan,
                results: [],
                totalReclaimedBytes: 0,
                succeededCount: 0,
                partiallySucceededCount: 0,
                blockedCount: 0,
                failedCount: 0
            )
        }

        let allowlistedRoots = allowlistedRoots(from: snapshot)
        var results: [CleanupActionResult] = []

        for item in plan.items {
            if let reason = blockReason(for: item, in: snapshot) {
                let blockedPaths = item.paths.map {
                    CleanupPathResult(
                        path: $0,
                        status: .blocked,
                        operation: .none,
                        reclaimedBytes: 0,
                        message: reason
                    )
                }
                results.append(
                    CleanupActionResult(
                        item: item,
                        status: .blocked,
                        operation: .none,
                        reclaimedBytes: 0,
                        message: reason,
                        pathResults: blockedPaths,
                        recordedAt: now()
                    )
                )
                continue
            }

            let pathResults = item.paths.map { path in
                executePath(
                    path: path,
                    allowlistedRoots: allowlistedRoots,
                    allowDirectDelete: allowDirectDelete
                )
            }
            results.append(
                summarize(item: item, pathResults: pathResults)
            )
        }

        let totalReclaimedBytes = results.reduce(Int64(0)) { partial, result in
            partial + result.reclaimedBytes
        }

        return CleanupExecutionReport(
            executedAt: now(),
            allowDirectDelete: allowDirectDelete,
            selection: plan.selection,
            plan: plan,
            results: results,
            totalReclaimedBytes: totalReclaimedBytes,
            succeededCount: results.filter { $0.status == .succeeded }.count,
            partiallySucceededCount: results.filter { $0.status == .partiallySucceeded }.count,
            blockedCount: results.filter { $0.status == .blocked }.count,
            failedCount: results.filter { $0.status == .failed }.count
        )
    }

    private func executePath(
        path: String,
        allowlistedRoots: Set<String>,
        allowDirectDelete: Bool
    ) -> CleanupPathResult {
        let normalizedPath = normalize(path: path)
        guard isAllowed(path: normalizedPath, allowlistedRoots: allowlistedRoots) else {
            return CleanupPathResult(
                path: normalizedPath,
                status: .blocked,
                operation: .none,
                reclaimedBytes: 0,
                message: "Blocked: path is outside allowlisted cleanup roots."
            )
        }

        let url = URL(filePath: normalizedPath, directoryHint: .inferFromPath)
        guard fileOperator.fileExists(at: url) else {
            return CleanupPathResult(
                path: normalizedPath,
                status: .skippedMissing,
                operation: .none,
                reclaimedBytes: 0,
                message: "Skipped: path does not exist."
            )
        }

        let reclaimableBytes = pathSizer.allocatedSize(at: url)
        do {
            try fileOperator.moveToTrash(at: url)
            return CleanupPathResult(
                path: normalizedPath,
                status: .succeeded,
                operation: .moveToTrash,
                reclaimedBytes: reclaimableBytes,
                message: "Moved to Trash."
            )
        } catch {
            guard allowDirectDelete else {
                return CleanupPathResult(
                    path: normalizedPath,
                    status: .failed,
                    operation: .none,
                    reclaimedBytes: 0,
                    message: "Failed to move to Trash. Retry with direct delete enabled. Error: \(error.localizedDescription)"
                )
            }

            do {
                try fileOperator.removeItem(at: url)
                return CleanupPathResult(
                    path: normalizedPath,
                    status: .succeeded,
                    operation: .directDelete,
                    reclaimedBytes: reclaimableBytes,
                    message: "Deleted directly after trash move failed."
                )
            } catch {
                return CleanupPathResult(
                    path: normalizedPath,
                    status: .failed,
                    operation: .none,
                    reclaimedBytes: 0,
                    message: "Failed to delete path directly. Error: \(error.localizedDescription)"
                )
            }
        }
    }

    private func summarize(item: DryRunPlanItem, pathResults: [CleanupPathResult]) -> CleanupActionResult {
        let succeeded = pathResults.filter { $0.status == .succeeded }.count
        let blocked = pathResults.filter { $0.status == .blocked }.count
        let failed = pathResults.filter { $0.status == .failed }.count
        let skipped = pathResults.filter { $0.status == .skippedMissing }.count
        let reclaimedBytes = pathResults.reduce(Int64(0)) { partial, result in
            partial + result.reclaimedBytes
        }

        let status: CleanupActionStatus
        if failed > 0 && succeeded > 0 {
            status = .partiallySucceeded
        } else if failed > 0 {
            status = .failed
        } else if blocked > 0 && succeeded > 0 {
            status = .partiallySucceeded
        } else if blocked > 0 {
            status = .blocked
        } else {
            status = .succeeded
        }

        let successfulOperations = Set(
            pathResults
                .filter { $0.status == .succeeded }
                .map(\.operation)
                .filter { $0 != .none }
        )
        let operation: CleanupOperation
        if successfulOperations.isEmpty {
            operation = .none
        } else if successfulOperations.count == 1 {
            operation = successfulOperations.first ?? .none
        } else {
            operation = .mixed
        }

        return CleanupActionResult(
            item: item,
            status: status,
            operation: operation,
            reclaimedBytes: reclaimedBytes,
            message: "Paths succeeded: \(succeeded), blocked: \(blocked), failed: \(failed), missing: \(skipped).",
            pathResults: pathResults,
            recordedAt: now()
        )
    }

    private func blockReason(for item: DryRunPlanItem, in snapshot: XcodeInventorySnapshot) -> String? {
        switch item.kind {
        case .storageCategory:
            guard let categoryKind = item.storageCategoryKind else {
                return nil
            }
            switch categoryKind {
            case .xcodeApplications:
                if snapshot.installs.contains(where: \.isActive) {
                    return "Blocked: active Xcode install is included in aggregate Xcode Applications cleanup."
                }
                if snapshot.installs.contains(where: { $0.runningInstanceCount > 0 }) {
                    return "Blocked: one or more Xcode installs are currently running."
                }
            case .simulatorData:
                if snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances > 0
                    || snapshot.simulator.devices.contains(where: simulatorDeviceIsRunning) {
                    return "Blocked: simulator data cleanup requires Simulator app and booted devices to be stopped."
                }
            case .derivedData, .archives, .deviceSupport:
                break
            }
            return nil
        case .simulatorDevice:
            let selectedPaths = Set(item.paths.map(normalize(path:)))
            if let device = snapshot.simulator.devices.first(where: { selectedPaths.contains(normalize(path: $0.dataPath)) }) {
                if simulatorDeviceIsRunning(device) {
                    return "Blocked: simulator device \(device.name) (\(device.udid)) is running/booted."
                }
            }
            return nil
        case .simulatorRuntime:
            if snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances > 0
                || snapshot.simulator.devices.contains(where: simulatorDeviceIsRunning) {
                return "Blocked: close Simulator and shut down booted devices before deleting simulator runtimes."
            }
            return nil
        case .xcodeInstall:
            let selectedPaths = Set(item.paths.map(normalize(path:)))
            if let install = snapshot.installs.first(where: { selectedPaths.contains(normalize(path: $0.path)) }) {
                if install.isActive {
                    return "Blocked: \(install.displayName) is the active developer directory selection."
                }
                if install.runningInstanceCount > 0 {
                    return "Blocked: \(install.displayName) has \(install.runningInstanceCount) running instance(s)."
                }
            }
            return nil
        case .staleSimulatorRuntime:
            if snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances > 0
                || snapshot.simulator.devices.contains(where: simulatorDeviceIsRunning) {
                return "Blocked: close Simulator and shut down booted devices before deleting stale runtime artifacts."
            }
            return nil
        case .staleDeviceSupport:
            if snapshot.runtimeTelemetry.totalXcodeRunningInstances > 0 {
                return "Blocked: close running Xcode instances before deleting stale Device Support artifacts."
            }
            return nil
        }
    }

    private func allowlistedRoots(from snapshot: XcodeInventorySnapshot) -> Set<String> {
        var roots = Set<String>()
        for path in snapshot.storage.categories.flatMap(\.paths) {
            roots.insert(normalize(path: path))
        }
        for path in snapshot.installs.map(\.path) {
            roots.insert(normalize(path: path))
        }
        for path in snapshot.simulator.devices.map(\.dataPath) {
            roots.insert(normalize(path: path))
        }
        for path in snapshot.simulator.runtimes.compactMap(\.bundlePath) {
            roots.insert(normalize(path: path))
        }
        return roots
    }

    private func isAllowed(path: String, allowlistedRoots: Set<String>) -> Bool {
        for root in allowlistedRoots {
            if path == root || path.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }

    private func simulatorDeviceIsRunning(_ device: SimulatorDeviceRecord) -> Bool {
        if device.runningInstanceCount > 0 {
            return true
        }
        let state = device.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state == "booted" || state == "booting"
    }

    private func runningToolsBlockReason(in snapshot: XcodeInventorySnapshot) -> String? {
        let runningXcode = snapshot.runtimeTelemetry.totalXcodeRunningInstances
        let runningSimulatorApp = snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances
        let bootedDevices = snapshot.simulator.devices.filter(simulatorDeviceIsRunning).count

        guard runningXcode > 0 || runningSimulatorApp > 0 || bootedDevices > 0 else {
            return nil
        }

        return "Blocked: running tools detected (Xcode: \(runningXcode), Simulator app: \(runningSimulatorApp), booted devices: \(bootedDevices)). Close tools or disable 'Block cleanup while tools are running'."
    }

    private func normalize(path: String) -> String {
        URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
