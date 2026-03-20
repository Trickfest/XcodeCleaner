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
                ]
            ),
            simulatorRuntimeManager: StubSimulatorRuntimeManager(),
            simulatorDeviceManager: StubSimulatorDeviceManager(),
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

    @Test("Cleanup executor supports explicit opt-in Xcode log cleanup")
    func executorSupportsOptInXcodeLogCleanup() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedCountedFootprintComponentKinds: [.xcodeLogs],
            selectedSimulatorDeviceUDIDs: []
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: ["/tmp/Logs/Xcode"]),
            pathSizer: StubExecutionPathSizer(sizeByPath: ["/tmp/Logs/Xcode": 80]),
            now: { Date(timeIntervalSince1970: 935) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.succeededCount == 1)
        #expect(report.failedCount == 0)
        #expect(report.totalReclaimedBytes == 80)
        #expect(report.results.first?.item.kind == .countedFootprintComponent)
        #expect(report.results.first?.item.countedFootprintComponentKind == .xcodeLogs)
        #expect(report.results.first?.operation == .moveToTrash)
        #expect(report.results.first?.pathResults.first?.path == "/tmp/Logs/Xcode")
    }

    @Test("Cleanup executor supports explicit opt-in Documentation Cache cleanup")
    func executorSupportsOptInDocumentationCacheCleanup() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedCountedFootprintComponentKinds: [.documentationCache],
            selectedSimulatorDeviceUDIDs: []
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: ["/tmp/Developer/Xcode/DocumentationCache"]),
            pathSizer: StubExecutionPathSizer(sizeByPath: ["/tmp/Developer/Xcode/DocumentationCache": 90]),
            now: { Date(timeIntervalSince1970: 935.5) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.succeededCount == 1)
        #expect(report.failedCount == 0)
        #expect(report.totalReclaimedBytes == 90)
        #expect(report.results.first?.item.kind == .countedFootprintComponent)
        #expect(report.results.first?.item.countedFootprintComponentKind == .documentationCache)
        #expect(report.results.first?.operation == .moveToTrash)
        #expect(report.results.first?.pathResults.first?.path == "/tmp/Developer/Xcode/DocumentationCache")
    }

    @Test("Cleanup executor blocks Documentation Cache cleanup while Xcode is running")
    func executorBlocksDocumentationCacheCleanupWhileXcodeRuns() {
        let snapshot = makeExecutionSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedCountedFootprintComponentKinds: [.documentationCache],
            selectedSimulatorDeviceUDIDs: []
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: ["/tmp/Developer/Xcode/DocumentationCache"]),
            pathSizer: StubExecutionPathSizer(sizeByPath: ["/tmp/Developer/Xcode/DocumentationCache": 90]),
            now: { Date(timeIntervalSince1970: 935.6) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.blockedCount == 1)
        #expect(report.succeededCount == 0)
        #expect(report.totalReclaimedBytes == 0)
        #expect(report.results.first?.item.kind == .countedFootprintComponent)
        #expect(report.results.first?.item.countedFootprintComponentKind == .documentationCache)
        #expect(report.results.first?.status == .blocked)
    }

    @Test("Cleanup executor blocks CoreSimulator log cleanup while simulator tools are running")
    func executorBlocksCoreSimulatorLogCleanupWhileSimulatorToolsRun() {
        let snapshot = makeExecutionSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedCountedFootprintComponentKinds: [.coreSimulatorLogs],
            selectedSimulatorDeviceUDIDs: []
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: ["/tmp/Logs/CoreSimulator"]),
            pathSizer: StubExecutionPathSizer(sizeByPath: ["/tmp/Logs/CoreSimulator": 120]),
            now: { Date(timeIntervalSince1970: 936) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.blockedCount == 1)
        #expect(report.succeededCount == 0)
        #expect(report.totalReclaimedBytes == 0)
        #expect(report.results.first?.item.kind == .countedFootprintComponent)
        #expect(report.results.first?.item.countedFootprintComponentKind == .coreSimulatorLogs)
        #expect(report.results.first?.status == .blocked)
    }

    @Test("Cleanup executor blocks per-runtime simulator cleanup when simulator tools are running")
    func executorBlocksRunningSimulatorRuntimeCleanup() {
        let snapshot = makeExecutionSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedSimulatorDeviceUDIDs: [],
            selectedSimulatorRuntimeIdentifiers: ["runtime-1"],
            selectedXcodeInstallPaths: []
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(
                existingPaths: ["/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime"]
            ),
            pathSizer: StubExecutionPathSizer(
                sizeByPath: ["/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime": 70]
            ),
            now: { Date(timeIntervalSince1970: 940) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.blockedCount == 1)
        #expect(report.succeededCount == 0)
        #expect(report.results.first?.item.kind == .simulatorRuntime)
        #expect(report.results.first?.status == .blocked)
        #expect(report.totalReclaimedBytes == 0)
    }

    @Test("Cleanup executor uses simctl for known simulator device cleanup")
    func executorUsesSimctlForKnownSimulatorDeviceCleanup() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedSimulatorDeviceUDIDs: ["SIM-SHUT"],
            selectedXcodeInstallPaths: []
        )
        let deviceManager = StubSimulatorDeviceManager()

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: []),
            simulatorRuntimeManager: StubSimulatorRuntimeManager(),
            simulatorDeviceManager: deviceManager,
            pathSizer: StubExecutionPathSizer(
                sizeByPath: ["/tmp/CoreSimulator/Devices/SIM-SHUT": 60]
            ),
            now: { Date(timeIntervalSince1970: 944) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.succeededCount == 1)
        #expect(report.failedCount == 0)
        #expect(report.totalReclaimedBytes == 60)
        #expect(report.results.first?.operation == .simctlDelete)
        #expect(report.results.first?.pathResults.first?.operation == .simctlDelete)
        #expect(deviceManager.deletedUDIDs == ["SIM-SHUT"])
    }

    @Test("Cleanup executor uses simctl for known simulator runtime cleanup")
    func executorUsesSimctlForKnownSimulatorRuntimeCleanup() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedSimulatorDeviceUDIDs: [],
            selectedSimulatorRuntimeIdentifiers: ["runtime-1"],
            selectedXcodeInstallPaths: []
        )
        let runtimeManager = StubSimulatorRuntimeManager()

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: []),
            simulatorRuntimeManager: runtimeManager,
            simulatorDeviceManager: StubSimulatorDeviceManager(),
            pathSizer: StubExecutionPathSizer(
                sizeByPath: ["/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime": 70]
            ),
            now: { Date(timeIntervalSince1970: 945) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.succeededCount == 1)
        #expect(report.failedCount == 0)
        #expect(report.totalReclaimedBytes == 70)
        #expect(report.results.first?.operation == .simctlDelete)
        #expect(report.results.first?.pathResults.first?.operation == .simctlDelete)
        #expect(runtimeManager.deletedIdentifiers == ["runtime-delete-1"])
    }

    @Test("Cleanup executor uses simctl for stale simulator runtime cleanup")
    func executorUsesSimctlForStaleSimulatorRuntimeCleanup() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let plan = DryRunPlan(
            generatedAt: Date(timeIntervalSince1970: 946),
            selection: DryRunSelection(
                selectedCategoryKinds: [],
                selectedSimulatorDeviceUDIDs: []
            ),
            items: [
                DryRunPlanItem(
                    kind: .staleSimulatorRuntime,
                    staleArtifactID: "simulatorRuntime:/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime",
                    staleArtifactKind: .simulatorRuntime,
                    title: "Stale Simulator Runtime: iOS 19.0",
                    reclaimableBytes: 70,
                    paths: ["/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime"],
                    ownershipSummary: "Runtime is not referenced by any current simulator device.",
                    safetyClassification: .conditionallySafe
                ),
            ],
            totalReclaimableBytes: 70,
            notes: []
        )
        let runtimeManager = StubSimulatorRuntimeManager()

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: []),
            simulatorRuntimeManager: runtimeManager,
            pathSizer: StubExecutionPathSizer(sizeByPath: [:]),
            now: { Date(timeIntervalSince1970: 947) }
        )

        let report = executor.execute(snapshot: snapshot, plan: plan, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.succeededCount == 1)
        #expect(report.results.first?.operation == .simctlDelete)
        #expect(runtimeManager.deletedIdentifiers == ["runtime-delete-1"])
    }

    @Test("Cleanup executor reports simctl runtime delete failures")
    func executorReportsSimctlRuntimeDeleteFailures() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedSimulatorDeviceUDIDs: [],
            selectedSimulatorRuntimeIdentifiers: ["runtime-1"],
            selectedXcodeInstallPaths: []
        )
        let runtimeManager = StubSimulatorRuntimeManager(failIdentifiers: ["runtime-delete-1"])

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: []),
            simulatorRuntimeManager: runtimeManager,
            pathSizer: StubExecutionPathSizer(sizeByPath: [:]),
            now: { Date(timeIntervalSince1970: 947) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.failedCount == 1)
        #expect(report.succeededCount == 0)
        #expect(report.totalReclaimedBytes == 0)
        #expect(report.results.first?.status == .failed)
        #expect(report.results.first?.pathResults.first?.message.contains("simctl runtime delete failed") == true)
        #expect(report.results.first?.pathResults.first?.message.contains("runtime-delete-1") == true)
        #expect(report.results.first?.pathResults.first?.operation == .simctlDelete)
    }

    @Test("Cleanup executor reports simctl device delete failures")
    func executorReportsSimctlDeviceDeleteFailures() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedSimulatorDeviceUDIDs: ["SIM-SHUT"],
            selectedXcodeInstallPaths: []
        )
        let deviceManager = StubSimulatorDeviceManager(failUDIDs: ["SIM-SHUT"])

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: []),
            simulatorRuntimeManager: StubSimulatorRuntimeManager(),
            simulatorDeviceManager: deviceManager,
            pathSizer: StubExecutionPathSizer(
                sizeByPath: ["/tmp/CoreSimulator/Devices/SIM-SHUT": 60]
            ),
            now: { Date(timeIntervalSince1970: 947) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.failedCount == 1)
        #expect(report.succeededCount == 0)
        #expect(report.totalReclaimedBytes == 0)
        #expect(report.results.first?.status == .failed)
        #expect(report.results.first?.pathResults.first?.message.contains("simctl delete failed") == true)
        #expect(report.results.first?.pathResults.first?.operation == .simctlDelete)
    }

    @Test("Simctl runtime manager waits for both runtime listings to converge after delete")
    func simctlRuntimeManagerWaitsForListingConvergence() throws {
        let deleteIdentifier = "F494D526-FCD7-445B-90AB-C47002D37BDE"
        let runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
        let commandRunner = SequencedCommandRunner(
            responsesByCommand: [
                .init(
                    launchPath: "/usr/bin/xcrun",
                    arguments: ["simctl", "runtime", "delete", deleteIdentifier]
                ): [""],
                .init(
                    launchPath: "/usr/bin/xcrun",
                    arguments: ["simctl", "runtime", "list", "-j"]
                ): [
                    """
                    {
                      "\(deleteIdentifier)": {
                        "identifier": "\(deleteIdentifier)",
                        "runtimeIdentifier": "\(runtimeIdentifier)"
                      }
                    }
                    """,
                    "{}",
                    "{}",
                ],
                .init(
                    launchPath: "/usr/bin/xcrun",
                    arguments: ["simctl", "list", "runtimes", "--json"]
                ): [
                    """
                    {
                      "runtimes": [
                        {
                          "identifier": "\(runtimeIdentifier)"
                        }
                      ]
                    }
                    """,
                    """
                    {
                      "runtimes": []
                    }
                    """,
                ],
            ]
        )
        let sleepRecorder = SleepRecorder()
        let manager = SimctlSimulatorRuntimeManager(
            commandRunner: commandRunner,
            maxConvergenceAttempts: 4,
            convergenceDelaySeconds: 0.01,
            sleep: { sleepRecorder.record($0) }
        )

        try manager.deleteRuntime(
            deleteIdentifier: deleteIdentifier,
            runtimeIdentifier: runtimeIdentifier
        )

        #expect(commandRunner.recordedCommands == [
            .init(
                launchPath: "/usr/bin/xcrun",
                arguments: ["simctl", "runtime", "delete", deleteIdentifier]
            ),
            .init(
                launchPath: "/usr/bin/xcrun",
                arguments: ["simctl", "runtime", "list", "-j"]
            ),
            .init(
                launchPath: "/usr/bin/xcrun",
                arguments: ["simctl", "runtime", "list", "-j"]
            ),
            .init(
                launchPath: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "runtimes", "--json"]
            ),
            .init(
                launchPath: "/usr/bin/xcrun",
                arguments: ["simctl", "runtime", "list", "-j"]
            ),
            .init(
                launchPath: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "runtimes", "--json"]
            ),
        ])
        #expect(sleepRecorder.calls == [0.01, 0.01])
    }

    @Test("Cleanup executor blocks orphaned simulator runtime cleanup as manual-only")
    func executorBlocksOrphanedSimulatorRuntimeCleanup() {
        let snapshot = makeExecutionSnapshot(
            runningXcodeInstances: 0,
            runningSimulatorAppInstances: 0,
            bootedDeviceState: "Shutdown",
            bootedDeviceRunningInstances: 0
        )
        let plan = DryRunPlan(
            generatedAt: Date(timeIntervalSince1970: 948),
            selection: DryRunSelection(
                selectedCategoryKinds: [],
                selectedSimulatorDeviceUDIDs: []
            ),
            items: [
                DryRunPlanItem(
                    kind: .staleSimulatorRuntime,
                    staleArtifactID: "orphanedSimulatorRuntime:/Library/Developer/CoreSimulator/Volumes/ORPHAN/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 19.1.simruntime",
                    staleArtifactKind: .orphanedSimulatorRuntime,
                    title: "Orphaned Simulator Runtime: iOS 19.1",
                    reclaimableBytes: 80,
                    paths: ["/Library/Developer/CoreSimulator/Volumes/ORPHAN/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 19.1.simruntime"],
                    ownershipSummary: "Runtime bundle exists on disk but is not present in the current simulator inventory.",
                    safetyClassification: .conditionallySafe
                ),
            ],
            totalReclaimableBytes: 80,
            notes: []
        )
        let runtimeManager = StubSimulatorRuntimeManager()

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(existingPaths: []),
            simulatorRuntimeManager: runtimeManager,
            pathSizer: StubExecutionPathSizer(sizeByPath: [:]),
            now: { Date(timeIntervalSince1970: 949) }
        )

        let report = executor.execute(snapshot: snapshot, plan: plan, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.blockedCount == 1)
        #expect(report.succeededCount == 0)
        #expect(report.results.first?.status == .blocked)
        #expect(report.results.first?.message.contains("manual cleanup only") == true)
        #expect(runtimeManager.deletedIdentifiers.isEmpty)
    }

    @Test("Cleanup executor uses simctl for known simulator objects inside aggregate Simulator Data cleanup")
    func executorUsesSimctlInsideAggregateSimulatorDataCleanup() {
        let snapshot = makeAggregateSimulatorDataSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [.simulatorData],
            selectedSimulatorDeviceUDIDs: [],
            selectedXcodeInstallPaths: []
        )
        let runtimeManager = StubSimulatorRuntimeManager()
        let deviceManager = StubSimulatorDeviceManager()

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(
                existingPaths: ["/tmp/CoreSimulator/Caches/dyld-cache"],
                moveToTrashFailPaths: []
            ),
            simulatorRuntimeManager: runtimeManager,
            simulatorDeviceManager: deviceManager,
            pathSizer: StubExecutionPathSizer(
                sizeByPath: [
                    "/tmp/CoreSimulator/Devices/SIM-SHUT": 60,
                    "/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime": 70,
                    "/tmp/CoreSimulator/Caches/dyld-cache": 15,
                ]
            ),
            now: { Date(timeIntervalSince1970: 951) }
        )

        let report = executor.execute(snapshot: snapshot, selection: selection, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.succeededCount == 1)
        #expect(report.failedCount == 0)
        #expect(report.totalReclaimedBytes == 145)
        #expect(report.results.first?.operation == .mixed)

        let pathResults = Dictionary(uniqueKeysWithValues: report.results[0].pathResults.map { ($0.path, $0) })
        #expect(pathResults["/tmp/CoreSimulator/Devices/SIM-SHUT"]?.operation == .simctlDelete)
        #expect(pathResults["/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime"]?.operation == .simctlDelete)
        #expect(pathResults["/tmp/CoreSimulator/Caches/dyld-cache"]?.operation == .moveToTrash)
        #expect(deviceManager.deletedUDIDs == ["SIM-SHUT"])
        #expect(runtimeManager.deletedIdentifiers == ["runtime-delete-1"])
    }

    @Test("Cleanup executor allows explicit orphaned simulator device cleanup through stale-artifact plans")
    func executorAllowsOrphanedStaleSimulatorDeviceCleanup() {
        let snapshot = XcodeInventorySnapshot(
            scannedAt: Date(timeIntervalSince1970: 100),
            activeDeveloperDirectoryPath: nil,
            installs: [],
            storage: XcodeStorageUsage(categories: [], totalBytes: 0),
            simulator: SimulatorInventory(devices: [], runtimes: []),
            runtimeTelemetry: RuntimeTelemetry(totalXcodeRunningInstances: 0, totalSimulatorAppRunningInstances: 0)
        )
        let plan = DryRunPlan(
            generatedAt: Date(timeIntervalSince1970: 950),
            selection: DryRunSelection(
                selectedCategoryKinds: [],
                selectedSimulatorDeviceUDIDs: []
            ),
            items: [
                DryRunPlanItem(
                    kind: .staleSimulatorDevice,
                    staleArtifactID: "orphanedSimulatorDevice:/tmp/CoreSimulator/Devices/ORPHAN-SIM-2",
                    staleArtifactKind: .orphanedSimulatorDevice,
                    title: "Orphaned Simulator Device Data: ORPHAN-SIM-2",
                    reclaimableBytes: 90,
                    paths: ["/tmp/CoreSimulator/Devices/ORPHAN-SIM-2"],
                    ownershipSummary: "Directory exists on disk but is not present in the current simulator inventory.",
                    safetyClassification: .conditionallySafe
                ),
            ],
            totalReclaimableBytes: 90,
            notes: []
        )

        let executor = CleanupExecutor(
            fileOperator: StubCleanupFileOperator(
                existingPaths: ["/tmp/CoreSimulator/Devices/ORPHAN-SIM-2"]
            ),
            pathSizer: StubExecutionPathSizer(
                sizeByPath: ["/tmp/CoreSimulator/Devices/ORPHAN-SIM-2": 90]
            ),
            now: { Date(timeIntervalSince1970: 960) }
        )

        let report = executor.execute(snapshot: snapshot, plan: plan, allowDirectDelete: false)

        #expect(report.results.count == 1)
        #expect(report.succeededCount == 1)
        #expect(report.blockedCount == 0)
        #expect(report.totalReclaimedBytes == 90)
        #expect(report.results.first?.item.kind == .staleSimulatorDevice)
        #expect(report.results.first?.status == .succeeded)
        #expect(report.results.first?.pathResults.first?.path == "/tmp/CoreSimulator/Devices/ORPHAN-SIM-2")
    }

}

private final class StubSimulatorRuntimeManager: SimulatorRuntimeManaging {
    private(set) var deletedIdentifiers: [String] = []
    let failIdentifiers: Set<String>

    init(failIdentifiers: Set<String> = []) {
        self.failIdentifiers = failIdentifiers
    }

    func deleteRuntime(deleteIdentifier: String, runtimeIdentifier: String) throws {
        if failIdentifiers.contains(deleteIdentifier) {
            throw StubCleanupError.removeItemFailed
        }
        deletedIdentifiers.append(deleteIdentifier)
    }
}

private final class SequencedCommandRunner: CommandRunning {
    struct Key: Hashable {
        let launchPath: String
        let arguments: [String]
    }

    private var responsesByCommand: [Key: [String]]
    private(set) var recordedCommands: [Key] = []

    init(responsesByCommand: [Key: [String]]) {
        self.responsesByCommand = responsesByCommand
    }

    func run(launchPath: String, arguments: [String]) throws -> String {
        let key = Key(launchPath: launchPath, arguments: arguments)
        recordedCommands.append(key)
        guard var responses = responsesByCommand[key], !responses.isEmpty else {
            throw SequencedCommandRunnerError.unsupportedCommand
        }
        let response = responses.removeFirst()
        responsesByCommand[key] = responses
        return response
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private(set) var calls: [TimeInterval] = []

    func record(_ interval: TimeInterval) {
        calls.append(interval)
    }
}

private final class StubSimulatorDeviceManager: SimulatorDeviceManaging {
    private(set) var deletedUDIDs: [String] = []
    let failUDIDs: Set<String>

    init(failUDIDs: Set<String> = []) {
        self.failUDIDs = failUDIDs
    }

    func deleteDevice(udid: String) throws {
        if failUDIDs.contains(udid) {
            throw StubCleanupError.removeItemFailed
        }
        deletedUDIDs.append(udid)
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

private enum SequencedCommandRunnerError: Error {
    case unsupportedCommand
}

private func makeExecutionSnapshot(
    runningXcodeInstances: Int = 1,
    runningSimulatorAppInstances: Int = 1,
    bootedDeviceState: String = "Booted",
    bootedDeviceRunningInstances: Int = 1
) -> XcodeInventorySnapshot {
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
                state: bootedDeviceState,
                isAvailable: true,
                dataPath: "/tmp/CoreSimulator/Devices/SIM-BOOT",
                sizeInBytes: 50,
                runningInstanceCount: bootedDeviceRunningInstances,
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
        runtimes: [
            SimulatorRuntimeRecord(
                identifier: "runtime-1",
                deleteIdentifier: "runtime-delete-1",
                name: "iOS 19.0",
                version: "19.0",
                isAvailable: true,
                bundlePath: "/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime",
                sizeInBytes: 70,
                ownershipSummary: "Owned by CoreSimulator runtime files",
                safetyClassification: .conditionallySafe
            ),
        ]
    )

    let countedOnlyComponents = [
        CountedFootprintComponentUsage(
            kind: .documentationCache,
            title: "Documentation Cache",
            bytes: 90,
            paths: ["/tmp/Developer/Xcode/DocumentationCache"],
            ownershipSummary: "Counted in total footprint only; owned by downloaded Xcode documentation cache."
        ),
        CountedFootprintComponentUsage(
            kind: .xcodeLogs,
            title: "Xcode Logs",
            bytes: 80,
            paths: ["/tmp/Logs/Xcode"],
            ownershipSummary: "Counted in total footprint only; owned by Xcode log history."
        ),
        CountedFootprintComponentUsage(
            kind: .coreSimulatorLogs,
            title: "CoreSimulator Logs",
            bytes: 120,
            paths: ["/tmp/Logs/CoreSimulator"],
            ownershipSummary: "Counted in total footprint only; owned by CoreSimulator log history."
        ),
    ]

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 100),
        activeDeveloperDirectoryPath: "/Applications/Xcode-Active.app/Contents/Developer",
        installs: installs,
        storage: XcodeStorageUsage(
            categories: categories,
            countedOnlyComponents: countedOnlyComponents,
            totalBytes: 930
        ),
        simulator: simulator,
        runtimeTelemetry: RuntimeTelemetry(
            totalXcodeRunningInstances: runningXcodeInstances,
            totalSimulatorAppRunningInstances: runningSimulatorAppInstances
        )
    )
}

private func makeAggregateSimulatorDataSnapshot() -> XcodeInventorySnapshot {
    let simulator = SimulatorInventory(
        devices: [
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
        runtimes: [
            SimulatorRuntimeRecord(
                identifier: "runtime-1",
                deleteIdentifier: "runtime-delete-1",
                name: "iOS 19.0",
                version: "19.0",
                isAvailable: true,
                bundlePath: "/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime",
                sizeInBytes: 70,
                ownershipSummary: "Owned by CoreSimulator runtime files",
                safetyClassification: .conditionallySafe
            ),
        ]
    )

    let storage = XcodeStorageUsage(
        categories: [
            StorageCategoryUsage(
                kind: .simulatorData,
                title: "Simulator Data",
                bytes: 145,
                paths: [
                    "/tmp/CoreSimulator/Devices/SIM-SHUT",
                    "/tmp/CoreSimulator/Profiles/Runtimes/iOS-19.simruntime",
                    "/tmp/CoreSimulator/Caches/dyld-cache",
                ],
                ownershipSummary: "Owned by CoreSimulator devices, runtimes, and caches",
                safetyClassification: .conditionallySafe
            ),
        ],
        totalBytes: 145
    )

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 200),
        activeDeveloperDirectoryPath: nil,
        installs: [],
        storage: storage,
        simulator: simulator,
        runtimeTelemetry: RuntimeTelemetry(totalXcodeRunningInstances: 0, totalSimulatorAppRunningInstances: 0)
    )
}

private func normalize(path: String) -> String {
    URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
}
