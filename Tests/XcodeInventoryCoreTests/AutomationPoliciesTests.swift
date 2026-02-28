import Foundation
import Testing
@testable import XcodeInventoryCore

struct AutomationPoliciesTests {
    @Test("Due policy selection honors schedule, enabled state, and cadence")
    func duePolicySelection() {
        let now = Date(timeIntervalSince1970: 10_000)
        let duePolicy = AutomationPolicy(
            id: "due-1",
            name: "Due Policy",
            schedule: .everyHours(2),
            selection: DryRunSelection.safeCategoryDefaults,
            lastEvaluatedRunAt: now.addingTimeInterval(-3 * 3_600),
            lastSuccessfulRunAt: now.addingTimeInterval(-3 * 3_600)
        )
        let notDuePolicy = AutomationPolicy(
            id: "not-due-1",
            name: "Not Due Policy",
            schedule: .everyHours(4),
            selection: DryRunSelection.safeCategoryDefaults,
            lastEvaluatedRunAt: now.addingTimeInterval(-1 * 3_600),
            lastSuccessfulRunAt: now.addingTimeInterval(-1 * 3_600)
        )
        let manualPolicy = AutomationPolicy(
            id: "manual-1",
            name: "Manual",
            schedule: .manualOnly,
            selection: DryRunSelection.safeCategoryDefaults
        )
        let disabledPolicy = AutomationPolicy(
            id: "disabled-1",
            name: "Disabled",
            isEnabled: false,
            schedule: .everyHours(1),
            selection: DryRunSelection.safeCategoryDefaults,
            lastEvaluatedRunAt: now.addingTimeInterval(-5 * 3_600),
            lastSuccessfulRunAt: now.addingTimeInterval(-5 * 3_600)
        )

        let due = AutomationPolicies.duePolicies(
            from: [duePolicy, notDuePolicy, manualPolicy, disabledPolicy],
            now: now
        )

        #expect(due.map(\.id) == ["due-1"])
    }

    @Test("Automation runner skips when Xcode/Simulator is running and policy requires closed tools")
    func runnerSkipsWhenToolsAreRunning() {
        let snapshot = makeAutomationSnapshot(
            xcodeRunningCount: 1,
            simulatorAppRunningCount: 0,
            simulatorDeviceState: "Shutdown"
        )
        let policy = AutomationPolicy(
            name: "Skip Running Tools",
            schedule: .manualOnly,
            selection: DryRunSelection(
                selectedCategoryKinds: [.derivedData],
                selectedSimulatorDeviceUDIDs: [],
                selectedXcodeInstallPaths: []
            ),
            skipIfToolsRunning: true
        )

        let runner = AutomationPolicyRunner(
            cleanupExecutor: CleanupExecutor(
                fileOperator: AutomationStubCleanupFileOperator(existingPaths: ["/tmp/DerivedData-Old"]),
                pathSizer: AutomationStubPathSizer(sizeByPath: ["/tmp/DerivedData-Old": 256]),
                now: { Date(timeIntervalSince1970: 2_000) }
            ),
            pathMetadataProvider: AutomationStubPathMetadataProvider(modificationDatesByPath: [:]),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let record = runner.run(policy: policy, snapshot: snapshot, trigger: .manual)

        #expect(record.status == .skipped)
        #expect(record.skippedReason?.contains("running tools") == true)
        #expect(record.advancesSchedule == false)
        #expect(record.executionReport == nil)
    }

    @Test("Automation runner executes eligible policy and records reclaimed bytes")
    func runnerExecutesEligiblePolicy() {
        let snapshot = makeAutomationSnapshot(
            xcodeRunningCount: 0,
            simulatorAppRunningCount: 0,
            simulatorDeviceState: "Shutdown"
        )
        let policy = AutomationPolicy(
            name: "Execute DerivedData",
            schedule: .manualOnly,
            selection: DryRunSelection(
                selectedCategoryKinds: [.derivedData],
                selectedSimulatorDeviceUDIDs: [],
                selectedXcodeInstallPaths: []
            ),
            skipIfToolsRunning: true,
            allowDirectDelete: false
        )

        let runner = AutomationPolicyRunner(
            cleanupExecutor: CleanupExecutor(
                fileOperator: AutomationStubCleanupFileOperator(existingPaths: ["/tmp/DerivedData-Old"]),
                pathSizer: AutomationStubPathSizer(sizeByPath: ["/tmp/DerivedData-Old": 256]),
                now: { Date(timeIntervalSince1970: 3_000) }
            ),
            pathMetadataProvider: AutomationStubPathMetadataProvider(
                modificationDatesByPath: [
                    "/tmp/DerivedData-Old": Date(timeIntervalSince1970: 100)
                ]
            ),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        let record = runner.run(policy: policy, snapshot: snapshot, trigger: .manual)

        #expect(record.status == .executed)
        #expect(record.advancesSchedule == true)
        #expect(record.totalReclaimedBytes == 256)
        #expect(record.executionReport?.succeededCount == 1)
    }

    @Test("Automation runner enforces min total reclaim and min age thresholds")
    func runnerThresholds() {
        let snapshot = makeAutomationSnapshot(
            xcodeRunningCount: 0,
            simulatorAppRunningCount: 0,
            simulatorDeviceState: "Shutdown"
        )
        let baseSelection = DryRunSelection(
            selectedCategoryKinds: [.derivedData],
            selectedSimulatorDeviceUDIDs: [],
            selectedXcodeInstallPaths: []
        )

        let thresholdPolicy = AutomationPolicy(
            name: "Threshold",
            schedule: .manualOnly,
            selection: baseSelection,
            minTotalReclaimBytes: 1_000
        )
        let agePolicy = AutomationPolicy(
            name: "Min Age",
            schedule: .manualOnly,
            selection: baseSelection,
            minAgeDays: 7
        )

        let runner = AutomationPolicyRunner(
            cleanupExecutor: CleanupExecutor(
                fileOperator: AutomationStubCleanupFileOperator(existingPaths: ["/tmp/DerivedData-Old"]),
                pathSizer: AutomationStubPathSizer(sizeByPath: ["/tmp/DerivedData-Old": 256]),
                now: { Date(timeIntervalSince1970: 10_000) }
            ),
            pathMetadataProvider: AutomationStubPathMetadataProvider(
                modificationDatesByPath: [
                    "/tmp/DerivedData-Old": Date(timeIntervalSince1970: 9_500)
                ]
            ),
            now: { Date(timeIntervalSince1970: 10_000) }
        )

        let thresholdRecord = runner.run(policy: thresholdPolicy, snapshot: snapshot, trigger: .manual)
        #expect(thresholdRecord.status == .skipped)
        #expect(thresholdRecord.message.contains("threshold") == true)
        #expect(thresholdRecord.advancesSchedule == true)

        let ageRecord = runner.run(policy: agePolicy, snapshot: snapshot, trigger: .manual)
        #expect(ageRecord.status == .skipped)
        #expect(ageRecord.message.contains("no eligible cleanup items") == true)
        #expect(ageRecord.advancesSchedule == true)
    }

    @Test("JSON automation policy store round-trips policies and run history")
    func jsonStoreRoundTrip() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcodecleaner-automation-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = JSONAutomationPolicyStore(stateDirectoryURL: tempDirectory)

        let policy = AutomationPolicy(
            id: "policy-1",
            name: "Nightly",
            schedule: .everyHours(12),
            selection: DryRunSelection.safeCategoryDefaults,
            lastEvaluatedRunAt: Date(timeIntervalSince1970: 900),
            lastSuccessfulRunAt: Date(timeIntervalSince1970: 800)
        )
        try store.savePolicies([policy])

        let loadedPolicies = try store.loadPolicies()
        #expect(loadedPolicies.count == 1)
        #expect(loadedPolicies[0].id == "policy-1")
        #expect(loadedPolicies[0].lastEvaluatedRunAt == Date(timeIntervalSince1970: 900))
        #expect(loadedPolicies[0].lastSuccessfulRunAt == Date(timeIntervalSince1970: 800))

        let runRecord = AutomationPolicyRunRecord(
            runID: "run-1",
            policyID: "policy-1",
            policyName: "Nightly",
            trigger: .scheduled,
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_005),
            status: .skipped,
            skippedReason: "Running tools",
            message: "Running tools",
            totalReclaimedBytes: 0,
            executionReport: nil
        )
        try store.appendRunHistory(runRecord)

        let history = try store.loadRunHistory()
        #expect(history.count == 1)
        #expect(history[0].runID == "run-1")
    }

}

private func makeAutomationSnapshot(
    xcodeRunningCount: Int,
    simulatorAppRunningCount: Int,
    simulatorDeviceState: String
) -> XcodeInventorySnapshot {
    let categories = [
        StorageCategoryUsage(
            kind: .derivedData,
            title: "Derived Data",
            bytes: 256,
            paths: ["/tmp/DerivedData-Old"],
            ownershipSummary: "Owned by local project build artifacts",
            safetyClassification: .regenerable
        ),
    ]

    let simulatorDevices = [
        SimulatorDeviceRecord(
            udid: "SIM-001",
            name: "iPhone 16",
            runtimeIdentifier: "runtime-ios-19",
            runtimeName: "iOS 19.0",
            state: simulatorDeviceState,
            isAvailable: true,
            dataPath: "/tmp/CoreSimulator/Devices/SIM-001",
            sizeInBytes: 10,
            runningInstanceCount: simulatorDeviceState.lowercased() == "booted" ? 1 : 0,
            ownershipSummary: "Owned by simulator device data",
            safetyClassification: .conditionallySafe
        ),
    ]

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 1_000),
        activeDeveloperDirectoryPath: "/Applications/Xcode.app/Contents/Developer",
        installs: [],
        storage: XcodeStorageUsage(categories: categories, totalBytes: 256),
        simulator: SimulatorInventory(devices: simulatorDevices, runtimes: []),
        runtimeTelemetry: RuntimeTelemetry(
            totalXcodeRunningInstances: xcodeRunningCount,
            totalSimulatorAppRunningInstances: simulatorAppRunningCount
        )
    )
}

private struct AutomationStubCleanupFileOperator: CleanupFileOperating {
    let existingPaths: Set<String>

    init(existingPaths: Set<String>) {
        self.existingPaths = Set(existingPaths.map(normalize(path:)))
    }

    func fileExists(at url: URL) -> Bool {
        existingPaths.contains(normalize(path: url.path))
    }

    func moveToTrash(at url: URL) throws {
        // No-op for test doubles.
    }

    func removeItem(at url: URL) throws {
        // No-op for test doubles.
    }
}

private struct AutomationStubPathSizer: PathSizing {
    let sizeByPath: [String: Int64]

    func fileExists(at url: URL) -> Bool {
        sizeByPath[normalize(path: url.path)] != nil
    }

    func allocatedSize(at url: URL) -> Int64 {
        sizeByPath[normalize(path: url.path)] ?? 0
    }
}

private struct AutomationStubPathMetadataProvider: PathMetadataProviding {
    let modificationDatesByPath: [String: Date]

    func fileExists(at url: URL) -> Bool {
        modificationDatesByPath[normalize(path: url.path)] != nil
    }

    func modificationDate(at url: URL) -> Date? {
        modificationDatesByPath[normalize(path: url.path)]
    }
}

private func normalize(path: String) -> String {
    URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
}
