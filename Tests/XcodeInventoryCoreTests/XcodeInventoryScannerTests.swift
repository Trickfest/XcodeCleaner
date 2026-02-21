import Foundation
import Testing
@testable import XcodeInventoryCore

struct XcodeInventoryScannerTests {
    @Test("Scanner discovers installs, deduplicates paths, and marks active install")
    func scannerDiscoversAndMarksActiveInstall() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let xcode16 = try makeFakeXcodeApp(
            in: sandbox.url,
            name: "Xcode-16.0",
            bundleIdentifier: "com.apple.dt.Xcode",
            shortVersion: "16.0",
            bundleVersion: "16A100",
            xcodeBuild: "16A100"
        )
        let xcodeBeta = try makeFakeXcodeApp(
            in: sandbox.url,
            name: "Xcode-16.1-beta",
            bundleIdentifier: "com.apple.dt.XcodeBeta",
            shortVersion: "16.1",
            bundleVersion: "16B500",
            xcodeBuild: "16B500"
        )

        let activeDeveloperDirectory = xcodeBeta.appendingPathComponent("Contents/Developer", isDirectory: true)
        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)

        let derivedDataPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            .path
        let archivesPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
            .path
        let deviceSupportPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
            .path
        let simulatorDevicesPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
            .path
        let simulatorCachesPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)
            .path
        let simulatorRuntimesPath = "/Library/Developer/CoreSimulator/Profiles/Runtimes"
        let runtime18BundlePath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes/iOS-18.simruntime", isDirectory: true)
            .path
        let runtime17BundlePath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes/iOS-17.simruntime", isDirectory: true)
            .path
        let simulatorDevice1UDID = "1111-AAAA-2222-BBBB"
        let simulatorDevice2UDID = "3333-CCCC-4444-DDDD"
        let simulatorDevice1Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(simulatorDevice1UDID)", isDirectory: true)
            .path
        let simulatorDevice2Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(simulatorDevice2UDID)", isDirectory: true)
            .path

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: [xcode16, xcode16, xcodeBeta]),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: activeDeveloperDirectory),
            pathSizer: StubPathSizer(sizeByPath: [
                xcode16.path: 1_000,
                xcodeBeta.path: 2_000,
                derivedDataPath: 300,
                archivesPath: 400,
                deviceSupportPath: 500,
                simulatorDevicesPath: 600,
                simulatorCachesPath: 700,
                simulatorRuntimesPath: 800,
                runtime18BundlePath: 450,
                runtime17BundlePath: 350,
                simulatorDevice1Path: 120,
                simulatorDevice2Path: 90,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: [
                RunningApplicationRecord(
                    bundleIdentifier: "com.apple.dt.Xcode",
                    bundlePath: xcodeBeta.path,
                    executablePath: nil,
                    processIdentifier: 1001
                ),
                RunningApplicationRecord(
                    bundleIdentifier: "com.apple.dt.Xcode",
                    bundlePath: xcodeBeta.path,
                    executablePath: nil,
                    processIdentifier: 1002
                ),
                RunningApplicationRecord(
                    bundleIdentifier: "com.apple.dt.Xcode",
                    bundlePath: xcode16.path,
                    executablePath: nil,
                    processIdentifier: 1003
                ),
                RunningApplicationRecord(
                    bundleIdentifier: nil,
                    bundlePath: xcodeBeta.path,
                    executablePath: "\(xcodeBeta.path)/Contents/MacOS/XcodeHelper",
                    processIdentifier: 1004
                ),
                RunningApplicationRecord(
                    bundleIdentifier: "com.apple.iphonesimulator",
                    bundlePath: "/Applications/Simulator.app",
                    executablePath: nil,
                    processIdentifier: 2001
                ),
                RunningApplicationRecord(
                    bundleIdentifier: nil,
                    bundlePath: "/Applications/Simulator.app",
                    executablePath: "/Applications/Simulator.app/Contents/MacOS/SimulatorTrampoline",
                    processIdentifier: 2002
                ),
            ]),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(
                    devices: [
                        SimulatorDeviceListingRecord(
                            udid: simulatorDevice1UDID,
                            name: "iPhone 15 Pro",
                            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
                            state: "Booted",
                            isAvailable: true
                        ),
                        SimulatorDeviceListingRecord(
                            udid: simulatorDevice2UDID,
                            name: "iPhone 14",
                            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                            state: "Shutdown",
                            isAvailable: true
                        ),
                    ],
                    runtimes: [
                        SimulatorRuntimeListingRecord(
                            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
                            name: "iOS 18.0",
                            version: "18.0",
                            isAvailable: true,
                            bundlePath: runtime18BundlePath
                        ),
                        SimulatorRuntimeListingRecord(
                            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                            name: "iOS 17.0",
                            version: "17.0",
                            isAvailable: false,
                            bundlePath: runtime17BundlePath
                        ),
                    ]
                )
            ),
            now: { Date(timeIntervalSince1970: 42) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.installs.count == 2)
        #expect(snapshot.activeDeveloperDirectoryPath == activeDeveloperDirectory.path)
        #expect(snapshot.installs.filter(\.isActive).count == 1)
        #expect(snapshot.installs.first?.displayName == "Xcode-16.1-beta")
        #expect(snapshot.installs.first?.version == "16.1")
        #expect(snapshot.installs.first?.build == "16B500")
        #expect(snapshot.installs.first?.runningInstanceCount == 2)
        #expect(snapshot.installs.first?.sizeInBytes == 2_000)
        #expect(snapshot.installs.first?.ownershipSummary == "Owned by this Xcode installation bundle")
        #expect(snapshot.installs.first?.safetyClassification == .destructive)
        #expect(snapshot.storage.totalBytes == 6_300)
        #expect(snapshot.storage.categories.count == 5)
        #expect(snapshot.storage.categories[0].kind == .xcodeApplications)
        #expect(snapshot.storage.categories[0].bytes == 3_000)
        #expect(snapshot.storage.categories[0].safetyClassification == .destructive)
        #expect(snapshot.storage.categories[1].kind == .simulatorData)
        #expect(snapshot.storage.categories[1].bytes == 2_100)
        #expect(snapshot.storage.categories[1].safetyClassification == .conditionallySafe)
        #expect(bytes(for: .deviceSupport, in: snapshot) == 500)
        #expect(bytes(for: .archives, in: snapshot) == 400)
        #expect(bytes(for: .derivedData, in: snapshot) == 300)
        #expect(snapshot.runtimeTelemetry.totalXcodeRunningInstances == 3)
        #expect(snapshot.runtimeTelemetry.totalSimulatorAppRunningInstances == 1)
        #expect(snapshot.simulator.runtimes.count == 2)
        #expect(snapshot.simulator.runtimes[0].name == "iOS 18.0")
        #expect(snapshot.simulator.runtimes[0].sizeInBytes == 450)
        #expect(snapshot.simulator.devices.count == 2)
        #expect(snapshot.simulator.devices[0].name == "iPhone 15 Pro")
        #expect(snapshot.simulator.devices[0].runtimeName == "iOS 18.0")
        #expect(snapshot.simulator.devices[0].runningInstanceCount == 1)
        #expect(snapshot.simulator.devices[0].safetyClassification == .conditionallySafe)
        #expect(snapshot.simulator.devices[1].runningInstanceCount == 0)
    }

    @Test("Scanner falls back to CFBundleVersion when DTXcodeBuild is missing")
    func scannerBuildFallback() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let xcode = try makeFakeXcodeApp(
            in: sandbox.url,
            name: "Xcode-15.4",
            bundleIdentifier: "com.apple.dt.Xcode",
            shortVersion: "15.4",
            bundleVersion: "15F31d",
            xcodeBuild: nil
        )

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: [xcode]),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [xcode.path: 512]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: sandbox.url),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(devices: [], runtimes: [])
            ),
            now: { Date(timeIntervalSince1970: 99) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.installs.count == 1)
        #expect(snapshot.installs[0].build == "15F31d")
        #expect(snapshot.installs[0].version == "15.4")
        #expect(snapshot.installs[0].sizeInBytes == 512)
        #expect(snapshot.installs[0].runningInstanceCount == 0)
        #expect(bytes(for: .xcodeApplications, in: snapshot) == 512)
        #expect(snapshot.runtimeTelemetry.totalXcodeRunningInstances == 0)
        #expect(snapshot.simulator.devices.isEmpty)
    }

    @Test("Scanner emits monotonic progress updates with stable phase order")
    func scannerProgressUpdates() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let xcode = try makeFakeXcodeApp(
            in: sandbox.url,
            name: "Xcode-26.0",
            bundleIdentifier: "com.apple.dt.Xcode",
            shortVersion: "26.0",
            bundleVersion: "17A300",
            xcodeBuild: "17A300"
        )

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: [xcode]),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [xcode.path: 100]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: sandbox.url),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(devices: [], runtimes: [])
            ),
            now: { Date(timeIntervalSince1970: 200) }
        )

        var updates: [ScanProgress] = []
        _ = scanner.scan { progress in
            updates.append(progress)
        }

        #expect(!updates.isEmpty)
        #expect(updates.first?.phase == .discoveringXcodeInstalls)
        #expect(updates.last?.phase == .finalizingSnapshot)
        #expect(updates.last?.fractionCompleted == 1)

        for index in 1..<updates.count {
            #expect(updates[index].fractionCompleted >= updates[index - 1].fractionCompleted)
        }

        let phaseOrder = deduplicatedPhases(updates.map(\.phase))
        #expect(phaseOrder == [
            .discoveringXcodeInstalls,
            .sizingXcodeInstalls,
            .sizingStorageCategories,
            .loadingSimulatorListing,
            .buildingSimulatorInventory,
            .computingRuntimeTelemetry,
            .finalizingSnapshot,
        ])
    }

    @Test("Dry-run planner returns exact path preview and reclaim estimate")
    func dryRunPlannerPreviewAndTotals() {
        let snapshot = makePlanningSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [.derivedData, .archives],
            selectedSimulatorDeviceUDIDs: ["SIM-1"]
        )

        let plan = DryRunPlanner.makePlan(
            snapshot: snapshot,
            selection: selection,
            now: Date(timeIntervalSince1970: 500)
        )

        #expect(plan.items.count == 3)
        #expect(plan.totalReclaimableBytes == 1_024 + 2_048 + 4_096)
        #expect(plan.generatedAt == Date(timeIntervalSince1970: 500))
        #expect(plan.items.contains(where: { $0.title == "Derived Data" && $0.paths == ["/tmp/DerivedData"] }))
        #expect(plan.items.contains(where: { $0.title == "Archives" && $0.paths == ["/tmp/Archives"] }))
        #expect(plan.items.contains(where: { $0.title.contains("Simulator Device: iPhone 15") && $0.paths == ["/tmp/CoreSimulator/Devices/SIM-1"] }))
    }

    @Test("Dry-run planner avoids simulator double counting when device and aggregate are both selected")
    func dryRunPlannerSimulatorOverlapGuard() {
        let snapshot = makePlanningSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [.simulatorData],
            selectedSimulatorDeviceUDIDs: ["SIM-1"]
        )

        let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)

        #expect(plan.items.count == 1)
        #expect(plan.items[0].kind == .simulatorDevice)
        #expect(plan.items[0].reclaimableBytes == 4_096)
        #expect(plan.totalReclaimableBytes == 4_096)
        #expect(plan.notes.contains(where: { $0.contains("double counting") }))
        #expect(plan.selection.selectedCategoryKinds.isEmpty)
    }

    @Test("Dry-run planner supports per-runtime simulator selection and avoids aggregate double counting")
    func dryRunPlannerRuntimeOverlapGuard() {
        let snapshot = makePlanningSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [.simulatorData],
            selectedSimulatorDeviceUDIDs: [],
            selectedSimulatorRuntimeIdentifiers: ["runtime-1"]
        )

        let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)

        #expect(plan.items.count == 1)
        #expect(plan.items[0].kind == .simulatorRuntime)
        #expect(plan.items[0].paths == ["/tmp/CoreSimulator/Profiles/Runtimes/iOS-18.simruntime"])
        #expect(plan.items[0].reclaimableBytes == 16_384)
        #expect(plan.totalReclaimableBytes == 16_384)
        #expect(plan.notes.contains(where: { $0.contains("double counting") }))
        #expect(plan.selection.selectedCategoryKinds.isEmpty)
    }
}

private struct StubDiscoverer: XcodeApplicationDiscovering {
    let urls: [URL]

    func discoverXcodeApplicationURLs() -> [URL] {
        urls
    }
}

private struct StubActiveDeveloperProvider: ActiveDeveloperDirectoryProviding {
    let url: URL?

    func activeDeveloperDirectoryURL() -> URL? {
        url
    }
}

private struct StubPathSizer: PathSizing {
    let sizeByPath: [String: Int64]

    func fileExists(at url: URL) -> Bool {
        sizeByPath[normalize(url: url)] != nil
    }

    func allocatedSize(at url: URL) -> Int64 {
        sizeByPath[normalize(url: url)] ?? 0
    }

    private func normalize(url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct StubHomeDirectoryProvider: HomeDirectoryProviding {
    let url: URL

    func homeDirectoryURL() -> URL {
        url
    }
}

private struct StubRunningApplicationsProvider: RunningApplicationsProviding {
    let records: [RunningApplicationRecord]

    func runningApplications() -> [RunningApplicationRecord] {
        records
    }
}

private struct StubSimulatorListingProvider: SimulatorListingProviding {
    let listing: SimulatorListing

    func simulatorListing() -> SimulatorListing {
        listing
    }
}

private struct TemporaryDirectory {
    let url: URL

    static func make() throws -> TemporaryDirectory {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XcodeInventoryScannerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TemporaryDirectory(url: url)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

private func makeFakeXcodeApp(
    in root: URL,
    name: String,
    bundleIdentifier: String,
    shortVersion: String,
    bundleVersion: String,
    xcodeBuild: String?
) throws -> URL {
    let appURL = root.appendingPathComponent(name).appendingPathExtension("app")
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let developerURL = contentsURL.appendingPathComponent("Developer", isDirectory: true)

    try FileManager.default.createDirectory(at: developerURL, withIntermediateDirectories: true)

    var plist: [String: Any] = [
        "CFBundleName": name,
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleShortVersionString": shortVersion,
        "CFBundleVersion": bundleVersion,
    ]
    if let xcodeBuild {
        plist["DTXcodeBuild"] = xcodeBuild
    }

    let plistData = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .xml,
        options: 0
    )
    try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

    return appURL
}

private func bytes(for kind: StorageCategoryKind, in snapshot: XcodeInventorySnapshot) -> Int64 {
    snapshot.storage.categories.first(where: { $0.kind == kind })?.bytes ?? -1
}

private func deduplicatedPhases(_ phases: [ScanPhase]) -> [ScanPhase] {
    var result: [ScanPhase] = []
    for phase in phases where result.last != phase {
        result.append(phase)
    }
    return result
}

private func makePlanningSnapshot() -> XcodeInventorySnapshot {
    let categories = [
        StorageCategoryUsage(
            kind: .derivedData,
            title: "Derived Data",
            bytes: 1_024,
            paths: ["/tmp/DerivedData"],
            ownershipSummary: "Owned by local project build artifacts",
            safetyClassification: .regenerable
        ),
        StorageCategoryUsage(
            kind: .archives,
            title: "Archives",
            bytes: 2_048,
            paths: ["/tmp/Archives"],
            ownershipSummary: "Owned by archived local build outputs",
            safetyClassification: .conditionallySafe
        ),
        StorageCategoryUsage(
            kind: .simulatorData,
            title: "Simulator Data",
            bytes: 8_192,
            paths: ["/tmp/CoreSimulator/Devices", "/tmp/CoreSimulator/Caches"],
            ownershipSummary: "Owned by CoreSimulator runtimes and device sandboxes",
            safetyClassification: .conditionallySafe
        ),
    ]

    let simulator = SimulatorInventory(
        devices: [
            SimulatorDeviceRecord(
                udid: "SIM-1",
                name: "iPhone 15",
                runtimeIdentifier: "runtime-1",
                runtimeName: "iOS 18.0",
                state: "Shutdown",
                isAvailable: true,
                dataPath: "/tmp/CoreSimulator/Devices/SIM-1",
                sizeInBytes: 4_096,
                runningInstanceCount: 0,
                ownershipSummary: "Owned by simulator device data for iOS 18.0",
                safetyClassification: .conditionallySafe
            ),
        ],
        runtimes: [
            SimulatorRuntimeRecord(
                identifier: "runtime-1",
                name: "iOS 18.0",
                version: "18.0",
                isAvailable: true,
                bundlePath: "/tmp/CoreSimulator/Profiles/Runtimes/iOS-18.simruntime",
                sizeInBytes: 16_384,
                ownershipSummary: "Owned by CoreSimulator runtime files",
                safetyClassification: .conditionallySafe
            )
        ]
    )

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 10),
        activeDeveloperDirectoryPath: nil,
        installs: [],
        storage: XcodeStorageUsage(categories: categories, totalBytes: 11_264),
        simulator: simulator,
        runtimeTelemetry: RuntimeTelemetry(totalXcodeRunningInstances: 0, totalSimulatorAppRunningInstances: 0)
    )
}
