import Foundation
import Testing
@testable import XcodeInventoryCore

struct ModificationToolsTests {
    @Test("Stale artifact detector finds stale simulator runtimes and older Device Support directories")
    func detectStaleArtifacts() {
        let snapshot = makeModificationSnapshot()
        let detector = StaleArtifactDetector(
            directoryLister: StubDirectoryLister(
                childrenByDirectory: [
                    "/tmp/DeviceSupport": [
                        URL(filePath: "/tmp/DeviceSupport/18.0 (22A123)", directoryHint: .isDirectory),
                        URL(filePath: "/tmp/DeviceSupport/17.5 (21F90)", directoryHint: .isDirectory),
                        URL(filePath: "/tmp/DeviceSupport/16.4 (20E247)", directoryHint: .isDirectory),
                        URL(filePath: "/tmp/DeviceSupport/Unknown", directoryHint: .isDirectory),
                    ]
                ]
            ),
            pathSizer: StubModificationPathSizer(
                sizeByPath: [
                    "/tmp/DeviceSupport/16.4 (20E247)": 300,
                ]
            ),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let report = detector.detect(snapshot: snapshot)

        #expect(report.generatedAt == Date(timeIntervalSince1970: 1_000))
        #expect(report.candidates.count == 2)
        #expect(report.totalReclaimableBytes == 300 + 500)
        #expect(report.candidates.contains(where: { $0.kind == .simulatorRuntime && $0.path == "/tmp/Runtime-17.simruntime" }))
        #expect(report.candidates.contains(where: { $0.kind == .deviceSupportDirectory && $0.path == "/tmp/DeviceSupport/16.4 (20E247)" }))
    }

    @Test("Stale artifact planner selects requested IDs and builds deterministic plan")
    func staleArtifactPlannerSelection() {
        let snapshot = makeModificationSnapshot()
        let report = StaleArtifactReport(
            generatedAt: Date(timeIntervalSince1970: 10),
            candidates: [
                StaleArtifactCandidate(
                    id: "simulatorRuntime:/tmp/Runtime-17.simruntime",
                    kind: .simulatorRuntime,
                    title: "Stale Simulator Runtime: iOS 17.0",
                    path: "/tmp/Runtime-17.simruntime",
                    reclaimableBytes: 500,
                    reason: "Unused.",
                    safetyClassification: .conditionallySafe
                ),
                StaleArtifactCandidate(
                    id: "deviceSupportDirectory:/tmp/DeviceSupport/16.4 (20E247)",
                    kind: .deviceSupportDirectory,
                    title: "Stale Device Support: 16.4 (20E247)",
                    path: "/tmp/DeviceSupport/16.4 (20E247)",
                    reclaimableBytes: 300,
                    reason: "Older Device Support directory.",
                    safetyClassification: .regenerable
                ),
            ],
            totalReclaimableBytes: 800,
            notes: []
        )

        let plan = StaleArtifactPlanner.makePlan(
            snapshot: snapshot,
            report: report,
            selectedCandidateIDs: ["deviceSupportDirectory:/tmp/DeviceSupport/16.4 (20E247)"],
            now: Date(timeIntervalSince1970: 20)
        )

        #expect(plan.generatedAt == Date(timeIntervalSince1970: 20))
        #expect(plan.items.count == 1)
        #expect(plan.items[0].kind == .staleDeviceSupport)
        #expect(plan.items[0].staleArtifactID == "deviceSupportDirectory:/tmp/DeviceSupport/16.4 (20E247)")
        #expect(plan.totalReclaimableBytes == 300)
    }

    @Test("Active Xcode switcher succeeds and verifies xcode-select output")
    func switchActiveXcodeSuccess() {
        let snapshot = makeSwitchSnapshot(runningCount: 0)
        let runner = StubSwitchCommandRunner(activeDeveloperDirectoryPath: "/Applications/Xcode-16.0.app/Contents/Developer")
        let switcher = ActiveXcodeSwitcher(commandRunner: runner, now: { Date(timeIntervalSince1970: 30) })

        let result = switcher.switchActiveXcode(
            snapshot: snapshot,
            targetInstallPath: "/Applications/Xcode-16.1.app"
        )

        #expect(result.status == .succeeded)
        #expect(result.newActiveDeveloperDirectoryPath == "/Applications/Xcode-16.1.app/Contents/Developer")
    }

    @Test("Active Xcode switcher blocks when target install is running")
    func switchActiveXcodeBlockedByRunningTarget() {
        let snapshot = makeSwitchSnapshot(runningCount: 1)
        let runner = StubSwitchCommandRunner(activeDeveloperDirectoryPath: "/Applications/Xcode-16.0.app/Contents/Developer")
        let switcher = ActiveXcodeSwitcher(commandRunner: runner, now: { Date(timeIntervalSince1970: 40) })

        let result = switcher.switchActiveXcode(
            snapshot: snapshot,
            targetInstallPath: "/Applications/Xcode-16.1.app"
        )

        #expect(result.status == .blocked)
        #expect(result.message.contains("running"))
    }
}

private struct StubDirectoryLister: DirectoryListing {
    let childrenByDirectory: [String: [URL]]

    func childDirectoryURLs(at directoryURL: URL) -> [URL] {
        childrenByDirectory[normalize(path: directoryURL.path)] ?? []
    }
}

private struct StubModificationPathSizer: PathSizing {
    let sizeByPath: [String: Int64]

    func fileExists(at url: URL) -> Bool {
        sizeByPath[normalize(path: url.path)] != nil
    }

    func allocatedSize(at url: URL) -> Int64 {
        sizeByPath[normalize(path: url.path)] ?? 0
    }
}

private final class StubSwitchCommandRunner: CommandRunning {
    private var activeDeveloperDirectoryPath: String

    init(activeDeveloperDirectoryPath: String) {
        self.activeDeveloperDirectoryPath = normalize(path: activeDeveloperDirectoryPath)
    }

    func run(launchPath: String, arguments: [String]) throws -> String {
        if launchPath == "/usr/bin/xcode-select", arguments == ["-p"] {
            return "\(activeDeveloperDirectoryPath)\n"
        }

        if launchPath == "/usr/bin/xcode-select",
           arguments.count == 2,
           arguments[0] == "--switch" {
            activeDeveloperDirectoryPath = normalize(path: arguments[1])
            return ""
        }

        throw StubCommandError.unsupportedCommand
    }
}

private enum StubCommandError: Error {
    case unsupportedCommand
}

private func makeModificationSnapshot() -> XcodeInventorySnapshot {
    let runtimes = [
        SimulatorRuntimeRecord(
            identifier: "runtime-18",
            name: "iOS 18.0",
            version: "18.0",
            isAvailable: true,
            bundlePath: "/tmp/Runtime-18.simruntime",
            sizeInBytes: 600,
            ownershipSummary: "Owned by runtime files",
            safetyClassification: .conditionallySafe
        ),
        SimulatorRuntimeRecord(
            identifier: "runtime-17",
            name: "iOS 17.0",
            version: "17.0",
            isAvailable: false,
            bundlePath: "/tmp/Runtime-17.simruntime",
            sizeInBytes: 500,
            ownershipSummary: "Owned by runtime files",
            safetyClassification: .conditionallySafe
        ),
    ]

    let devices = [
        SimulatorDeviceRecord(
            udid: "SIM-1",
            name: "iPhone 16",
            runtimeIdentifier: "runtime-18",
            runtimeName: "iOS 18.0",
            state: "Shutdown",
            isAvailable: true,
            dataPath: "/tmp/Devices/SIM-1",
            sizeInBytes: 100,
            runningInstanceCount: 0,
            ownershipSummary: "Owned by device data",
            safetyClassification: .conditionallySafe
        ),
    ]

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 0),
        activeDeveloperDirectoryPath: "/Applications/Xcode-16.0.app/Contents/Developer",
        installs: [],
        storage: XcodeStorageUsage(
            categories: [
                StorageCategoryUsage(
                    kind: .deviceSupport,
                    title: "Device Support",
                    bytes: 1_000,
                    paths: ["/tmp/DeviceSupport"],
                    ownershipSummary: "Owned by DeviceSupport",
                    safetyClassification: .regenerable
                ),
            ],
            totalBytes: 1_000
        ),
        simulator: SimulatorInventory(devices: devices, runtimes: runtimes),
        runtimeTelemetry: RuntimeTelemetry(totalXcodeRunningInstances: 0, totalSimulatorAppRunningInstances: 0)
    )
}

private func makeSwitchSnapshot(runningCount: Int) -> XcodeInventorySnapshot {
    let installs = [
        XcodeInstall(
            displayName: "Xcode-16.0",
            bundleIdentifier: "com.apple.dt.Xcode",
            version: "16.0",
            build: "16A100",
            path: "/Applications/Xcode-16.0.app",
            developerDirectoryPath: "/Applications/Xcode-16.0.app/Contents/Developer",
            isActive: true,
            runningInstanceCount: 0,
            sizeInBytes: 1_000,
            ownershipSummary: "Owned by this Xcode installation bundle",
            safetyClassification: .destructive
        ),
        XcodeInstall(
            displayName: "Xcode-16.1",
            bundleIdentifier: "com.apple.dt.Xcode",
            version: "16.1",
            build: "16B200",
            path: "/Applications/Xcode-16.1.app",
            developerDirectoryPath: "/Applications/Xcode-16.1.app/Contents/Developer",
            isActive: false,
            runningInstanceCount: runningCount,
            sizeInBytes: 1_100,
            ownershipSummary: "Owned by this Xcode installation bundle",
            safetyClassification: .destructive
        ),
    ]

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 0),
        activeDeveloperDirectoryPath: "/Applications/Xcode-16.0.app/Contents/Developer",
        installs: installs,
        storage: XcodeStorageUsage(categories: [], totalBytes: 0),
        simulator: SimulatorInventory(devices: [], runtimes: []),
        runtimeTelemetry: RuntimeTelemetry(totalXcodeRunningInstances: runningCount, totalSimulatorAppRunningInstances: 0)
    )
}

private func normalize(path: String) -> String {
    URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
}
