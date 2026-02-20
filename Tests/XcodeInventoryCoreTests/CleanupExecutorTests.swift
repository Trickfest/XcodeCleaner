import Foundation
import Testing
@testable import XcodeInventoryCore

struct CleanupExecutorTests {
    @Test("Dry-run planner supports per-install Xcode selection and avoids aggregate double counting")
    func plannerSupportsPerInstallXcodeSelection() {
        let snapshot = makeExecutionSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [.xcodeApplications],
            selectedSimulatorDeviceUDIDs: [],
            selectedXcodeInstallPaths: ["/Applications/Xcode-Old.app"]
        )

        let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)

        #expect(plan.items.count == 1)
        #expect(plan.items[0].kind == .xcodeInstall)
        #expect(plan.items[0].paths == ["/Applications/Xcode-Old.app"])
        #expect(plan.notes.contains(where: { $0.contains("double counting") }))
        #expect(plan.selection.selectedCategoryKinds.isEmpty)
    }

    @Test("Cleanup executor enforces active/running Xcode and booted simulator guardrails")
    func executorGuardrails() {
        let snapshot = makeExecutionSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedSimulatorDeviceUDIDs: ["SIM-SHUT", "SIM-BOOT"],
            selectedXcodeInstallPaths: [
                "/Applications/Xcode-Old.app",
                "/Applications/Xcode-Active.app",
                "/Applications/Xcode-Running.app",
            ]
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(
                existingPaths: [
                    "/Applications/Xcode-Old.app",
                    "/tmp/CoreSimulator/Devices/SIM-SHUT",
                ]
            ),
            pathSizer: StubExecutionPathSizer(
                sizeByPath: [
                    "/Applications/Xcode-Old.app": 200,
                    "/tmp/CoreSimulator/Devices/SIM-SHUT": 60,
                ]
            ),
            now: { Date(timeIntervalSince1970: 900) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.succeededCount == 2)
        #expect(report.blockedCount == 3)
        #expect(report.failedCount == 0)
        #expect(report.totalReclaimedBytes == 260)

        let statuses = Dictionary(uniqueKeysWithValues: report.results.map { ($0.item.title, $0.status) })
        #expect(statuses["Xcode Install: Xcode-Old 16.0 (16A100)"] == .succeeded)
        #expect(statuses["Xcode Install: Xcode-Active 16.1 (16B200)"] == .blocked)
        #expect(statuses["Xcode Install: Xcode-Running 16.2 (16C300)"] == .blocked)
        #expect(statuses["Simulator Device: iPhone 16 (SIM-SHUT)"] == .succeeded)
        #expect(statuses["Simulator Device: iPhone 16 Pro (SIM-BOOT)"] == .blocked)
    }

    @Test("Cleanup executor uses direct-delete fallback only when enabled")
    func executorDirectDeleteFallback() {
        let snapshot = makeExecutionSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [.derivedData],
            selectedSimulatorDeviceUDIDs: [],
            selectedXcodeInstallPaths: []
        )
        let path = "/tmp/DerivedData"

        let executorWithoutFallback = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(
                existingPaths: [path],
                moveToTrashFailPaths: [path]
            ),
            pathSizer: StubExecutionPathSizer(sizeByPath: [path: 40]),
            now: { Date(timeIntervalSince1970: 910) }
        )
        let withoutFallbackReport = executorWithoutFallback.execute(
            snapshot: snapshot,
            selection: selection,
            allowDirectDelete: false
        )

        #expect(withoutFallbackReport.failedCount == 1)
        #expect(withoutFallbackReport.totalReclaimedBytes == 0)
        #expect(withoutFallbackReport.results.first?.operation == CleanupOperation.none)

        let executorWithFallback = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(
                existingPaths: [path],
                moveToTrashFailPaths: [path]
            ),
            pathSizer: StubExecutionPathSizer(sizeByPath: [path: 40]),
            now: { Date(timeIntervalSince1970: 920) }
        )
        let withFallbackReport = executorWithFallback.execute(
            snapshot: snapshot,
            selection: selection,
            allowDirectDelete: true
        )

        #expect(withFallbackReport.succeededCount == 1)
        #expect(withFallbackReport.totalReclaimedBytes == 40)
        #expect(withFallbackReport.results.first?.operation == .directDelete)
    }

    @Test("Cleanup executor can globally block cleanup when tools are running")
    func executorGlobalRunningToolsBlock() {
        let snapshot = makeExecutionSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [.derivedData],
            selectedSimulatorDeviceUDIDs: [],
            selectedXcodeInstallPaths: []
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: ["/tmp/DerivedData"]),
            pathSizer: StubExecutionPathSizer(sizeByPath: ["/tmp/DerivedData": 40]),
            now: { Date(timeIntervalSince1970: 930) }
        )

        let report = executor.execute(
            snapshot: snapshot,
            selection: selection,
            allowDirectDelete: false,
            requireToolsStopped: true
        )

        #expect(report.skippedReason != nil)
        #expect(report.results.isEmpty)
        #expect(report.succeededCount == 0)
        #expect(report.blockedCount == 0)
        #expect(report.totalReclaimedBytes == 0)
    }
}

private struct StubCleanupFileOperator: CleanupFileOperating {
    let existingPaths: Set<String>
    let moveToTrashFailPaths: Set<String>
    let directDeleteFailPaths: Set<String>

    init(
        existingPaths: Set<String>,
        moveToTrashFailPaths: Set<String> = [],
        directDeleteFailPaths: Set<String> = []
    ) {
        self.existingPaths = Set(existingPaths.map(normalize(path:)))
        self.moveToTrashFailPaths = Set(moveToTrashFailPaths.map(normalize(path:)))
        self.directDeleteFailPaths = Set(directDeleteFailPaths.map(normalize(path:)))
    }

    func fileExists(at url: URL) -> Bool {
        existingPaths.contains(normalize(path: url.path))
    }

    func moveToTrash(at url: URL) throws {
        if moveToTrashFailPaths.contains(normalize(path: url.path)) {
            throw StubCleanupError.moveToTrashFailed
        }
    }

    func removeItem(at url: URL) throws {
        if directDeleteFailPaths.contains(normalize(path: url.path)) {
            throw StubCleanupError.removeItemFailed
        }
    }
}

private struct StubExecutionPathSizer: PathSizing {
    let sizeByPath: [String: Int64]

    func fileExists(at url: URL) -> Bool {
        sizeByPath[normalize(path: url.path)] != nil
    }

    func allocatedSize(at url: URL) -> Int64 {
        sizeByPath[normalize(path: url.path)] ?? 0
    }
}

private enum StubCleanupError: Error {
    case moveToTrashFailed
    case removeItemFailed
}

private func makeExecutionSnapshot() -> XcodeInventorySnapshot {
    let categories = [
        StorageCategoryUsage(
            kind: .xcodeApplications,
            title: "Xcode Applications",
            bytes: 600,
            paths: [
                "/Applications/Xcode-Active.app",
                "/Applications/Xcode-Old.app",
                "/Applications/Xcode-Running.app",
            ],
            ownershipSummary: "Owned by individual Xcode installation bundles",
            safetyClassification: .destructive
        ),
        StorageCategoryUsage(
            kind: .derivedData,
            title: "Derived Data",
            bytes: 40,
            paths: ["/tmp/DerivedData"],
            ownershipSummary: "Owned by local project build artifacts",
            safetyClassification: .regenerable
        ),
    ]

    let installs = [
        XcodeInstall(
            displayName: "Xcode-Active",
            bundleIdentifier: "com.apple.dt.Xcode",
            version: "16.1",
            build: "16B200",
            path: "/Applications/Xcode-Active.app",
            developerDirectoryPath: "/Applications/Xcode-Active.app/Contents/Developer",
            isActive: true,
            runningInstanceCount: 0,
            sizeInBytes: 300,
            ownershipSummary: "Owned by this Xcode installation bundle",
            safetyClassification: .destructive
        ),
        XcodeInstall(
            displayName: "Xcode-Old",
            bundleIdentifier: "com.apple.dt.Xcode",
            version: "16.0",
            build: "16A100",
            path: "/Applications/Xcode-Old.app",
            developerDirectoryPath: "/Applications/Xcode-Old.app/Contents/Developer",
            isActive: false,
            runningInstanceCount: 0,
            sizeInBytes: 200,
            ownershipSummary: "Owned by this Xcode installation bundle",
            safetyClassification: .destructive
        ),
        XcodeInstall(
            displayName: "Xcode-Running",
            bundleIdentifier: "com.apple.dt.Xcode",
            version: "16.2",
            build: "16C300",
            path: "/Applications/Xcode-Running.app",
            developerDirectoryPath: "/Applications/Xcode-Running.app/Contents/Developer",
            isActive: false,
            runningInstanceCount: 1,
            sizeInBytes: 100,
            ownershipSummary: "Owned by this Xcode installation bundle",
            safetyClassification: .destructive
        ),
    ]

    let simulator = SimulatorInventory(
        devices: [
            SimulatorDeviceRecord(
                udid: "SIM-BOOT",
                name: "iPhone 16 Pro",
                runtimeIdentifier: "runtime-1",
                runtimeName: "iOS 19.0",
                state: "Booted",
                isAvailable: true,
                dataPath: "/tmp/CoreSimulator/Devices/SIM-BOOT",
                sizeInBytes: 50,
                runningInstanceCount: 1,
                ownershipSummary: "Owned by simulator device data",
                safetyClassification: .conditionallySafe
            ),
            SimulatorDeviceRecord(
                udid: "SIM-SHUT",
                name: "iPhone 16",
                runtimeIdentifier: "runtime-1",
                runtimeName: "iOS 19.0",
                state: "Shutdown",
                isAvailable: true,
                dataPath: "/tmp/CoreSimulator/Devices/SIM-SHUT",
                sizeInBytes: 60,
                runningInstanceCount: 0,
                ownershipSummary: "Owned by simulator device data",
                safetyClassification: .conditionallySafe
            ),
        ],
        runtimes: []
    )

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 100),
        activeDeveloperDirectoryPath: "/Applications/Xcode-Active.app/Contents/Developer",
        installs: installs,
        storage: XcodeStorageUsage(categories: categories, totalBytes: 640),
        simulator: simulator,
        runtimeTelemetry: RuntimeTelemetry(totalXcodeRunningInstances: 1, totalSimulatorAppRunningInstances: 1)
    )
}

private func normalize(path: String) -> String {
    URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
}
