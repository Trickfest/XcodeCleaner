import Foundation
import Testing
@testable import XcodeInventoryCore

struct XcodeInventoryScannerTests {
    @Test("Simctl runtime listing provider captures delete-specific runtime identifiers and filters stale volume-backed runtime entries")
    func simctlRuntimeListingProviderCapturesDeleteIdentifiers() {
        let commandRunner = StubCommandRunner(
            responses: [
                StubCommandRunner.Key(
                    launchPath: "/usr/bin/xcrun",
                    arguments: ["simctl", "list", "devices", "--json"]
                ): """
                {
                  "devices": {
                    "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
                      {
                        "udid": "SIM-001",
                        "name": "iPhone 17",
                        "state": "Shutdown",
                        "isAvailable": true
                      }
                    ]
                  }
                }
                """,
                StubCommandRunner.Key(
                    launchPath: "/usr/bin/xcrun",
                    arguments: ["simctl", "list", "runtimes", "--json"]
                ): """
                {
                  "runtimes": [
                    {
                      "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                      "name": "iOS 26.0",
                      "version": "26.0.1",
                      "isAvailable": true,
                      "bundlePath": "/Library/Developer/CoreSimulator/Volumes/iOS_23A8464/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.0.simruntime"
                    },
                    {
                      "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                      "name": "iOS 17.0",
                      "version": "17.0",
                      "isAvailable": true,
                      "bundlePath": "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime"
                    },
                    {
                      "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
                      "name": "iOS 18.0",
                      "version": "18.0",
                      "isAvailable": true,
                      "bundlePath": "/Library/Developer/CoreSimulator/Volumes/iOS_STALE/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime"
                    }
                  ]
                }
                """,
                StubCommandRunner.Key(
                    launchPath: "/usr/bin/xcrun",
                    arguments: ["simctl", "runtime", "list", "-j"]
                ): """
                {
                  "F494D526-FCD7-445B-90AB-C47002D37BDE": {
                    "identifier": "F494D526-FCD7-445B-90AB-C47002D37BDE",
                    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                    "runtimeBundlePath": "/Library/Developer/CoreSimulator/Volumes/iOS_23A8464/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.0.simruntime",
                    "version": "26.0.1"
                  }
                }
                """,
            ]
        )

        let provider = SimctlSimulatorListingProvider(commandRunner: commandRunner)

        let listing = provider.simulatorListing()

        #expect(listing.devices.count == 1)
        #expect(listing.devices.first?.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
        #expect(listing.runtimes.count == 2)
        #expect(listing.runtimes.first?.identifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
        #expect(listing.runtimes.first?.deleteIdentifier == "F494D526-FCD7-445B-90AB-C47002D37BDE")
        #expect(listing.runtimes.contains(where: {
            $0.identifier == "com.apple.CoreSimulator.SimRuntime.iOS-17-0" && $0.deleteIdentifier == nil
        }))
        #expect(listing.runtimes.contains(where: { $0.identifier == "com.apple.CoreSimulator.SimRuntime.iOS-18-0" }) == false)
    }

    @Test("Scanner suppresses simulator runtimes whose bundle paths are already gone on disk")
    func scannerSuppressesRuntimesWithMissingBundlePaths() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)
        let existingRuntimePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23C54/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.2.simruntime"
        let deletedRuntimePath = "/Library/Developer/CoreSimulator/Volumes/iOS_STALE/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.6.simruntime"

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: []),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [
                existingRuntimePath: 18109272064,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(
                    devices: [],
                    runtimes: [
                        SimulatorRuntimeListingRecord(
                            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
                            deleteIdentifier: "runtime-delete-26-2",
                            name: "iOS 26.2",
                            version: "26.2",
                            isAvailable: true,
                            bundlePath: existingRuntimePath
                        ),
                        SimulatorRuntimeListingRecord(
                            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
                            deleteIdentifier: "runtime-delete-18-6",
                            name: "iOS 18.6",
                            version: "18.6",
                            isAvailable: true,
                            bundlePath: deletedRuntimePath
                        ),
                    ]
                )
            )
        )

        let snapshot = scanner.scan()

        #expect(snapshot.simulator.runtimes.map(\.identifier) == ["com.apple.CoreSimulator.SimRuntime.iOS-26-2"])
        #expect(snapshot.simulator.runtimes.map(\.bundlePath) == [existingRuntimePath])
        let simulatorData = try #require(snapshot.storage.categories.first(where: { $0.kind == .simulatorData }))
        #expect(simulatorData.paths.contains(existingRuntimePath))
        #expect(simulatorData.paths.contains(deletedRuntimePath) == false)
    }

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
        let mobileDeviceCrashLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/CrashReporter/MobileDevice", isDirectory: true)
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
        let systemSimulatorCachesPath = "/Library/Developer/CoreSimulator/Caches"
        let legacyRuntimeRootPath = "/Library/Developer/CoreSimulator/Profiles/Runtimes"
        let runtime18BundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23A8464/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime"
        let runtime17BundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23C54/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime"
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
                mobileDeviceCrashLogsPath: 450,
                deviceSupportPath: 500,
                simulatorDevicesPath: 600,
                simulatorCachesPath: 700,
                systemSimulatorCachesPath: 80,
                legacyRuntimeRootPath: 900,
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
        #expect(snapshot.storage.totalBytes == 6_440)
        #expect(snapshot.storage.categories.count == 6)
        #expect(snapshot.storage.countedOnlyComponents.count == 8)
        #expect(snapshot.storage.categories[0].kind == .xcodeApplications)
        #expect(snapshot.storage.categories[0].bytes == 3_000)
        #expect(snapshot.storage.categories[0].safetyClassification == .destructive)
        #expect(snapshot.storage.categories[1].kind == .simulatorData)
        #expect(snapshot.storage.categories[1].bytes == 1_790)
        #expect(snapshot.storage.categories[1].safetyClassification == .conditionallySafe)
        #expect(Set(snapshot.storage.categories[1].paths) == Set([
            simulatorCachesPath,
            systemSimulatorCachesPath,
            runtime18BundlePath,
            runtime17BundlePath,
            simulatorDevice1Path,
            simulatorDevice2Path,
        ]))
        #expect(snapshot.storage.categories[1].paths.contains(simulatorDevicesPath) == false)
        #expect(snapshot.storage.categories[1].paths.contains("/Library/Developer/CoreSimulator/Profiles/Runtimes") == false)
        #expect(bytes(for: .deviceSupport, in: snapshot) == 500)
        #expect(bytes(for: .mobileDeviceCrashLogs, in: snapshot) == 450)
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
        #expect(snapshot.storage.countedOnlyComponents.allSatisfy { $0.bytes == 0 })
    }

    @Test("Scanner counts additional footprint components without expanding cleanup categories")
    func scannerCountsAdditionalFootprintComponentsSeparately() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

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
        let documentationCachePath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DocumentationCache", isDirectory: true)
            .path
        let packagesPath = fakeHome
            .appendingPathComponent("Library/Developer/Packages", isDirectory: true)
            .path
        let xcodeLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/Xcode", isDirectory: true)
            .path
        let coreSimulatorLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/CoreSimulator", isDirectory: true)
            .path
        let dvtDownloadsPath = fakeHome
            .appendingPathComponent("Library/Developer/DVTDownloads", isDirectory: true)
            .path
        let xcpgDevicesPath = fakeHome
            .appendingPathComponent("Library/Developer/XCPGDevices", isDirectory: true)
            .path
        let xcTestDevicesPath = fakeHome
            .appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true)
            .path
        let userDataPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/UserData", isDirectory: true)
            .path
        let documentationIndexPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DocumentationIndex", isDirectory: true)
            .path
        let sdkMappingPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/SDKToSimulatorIndexMapping.plist", isDirectory: false)
            .path
        let metalMappingPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/XcodeToMetalToolchainIndexMapping.plist", isDirectory: false)
            .path

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: []),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [
                derivedDataPath: 100,
                archivesPath: 200,
                deviceSupportPath: 300,
                documentationCachePath: 500,
                packagesPath: 600,
                xcodeLogsPath: 700,
                coreSimulatorLogsPath: 800,
                dvtDownloadsPath: 0,
                xcpgDevicesPath: 0,
                xcTestDevicesPath: 0,
                userDataPath: 50,
                documentationIndexPath: 10,
                sdkMappingPath: 4,
                metalMappingPath: 2,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(devices: [], runtimes: [])
            ),
            now: { Date(timeIntervalSince1970: 300) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.storage.categories.count == 6)
        #expect(snapshot.storage.categories.contains(where: { $0.title == "Documentation Cache" }) == false)
        #expect(snapshot.storage.categories.contains(where: { $0.title == "Developer Packages" }) == false)
        #expect(snapshot.storage.categories.contains(where: { $0.title == "Xcode Logs" }) == false)
        #expect(snapshot.storage.categories.contains(where: { $0.title == "CoreSimulator Logs" }) == false)
        #expect(snapshot.storage.totalBytes == 3_266)
        #expect(snapshot.storage.countedOnlyComponents.count == 8)
        #expect(countedComponentBytes(for: .documentationCache, in: snapshot) == 500)
        #expect(countedComponentBytes(for: .developerPackages, in: snapshot) == 600)
        #expect(countedComponentBytes(for: .xcodeLogs, in: snapshot) == 700)
        #expect(countedComponentBytes(for: .coreSimulatorLogs, in: snapshot) == 800)
        #expect(countedComponentBytes(for: .dvtDownloads, in: snapshot) == 0)
        #expect(countedComponentBytes(for: .xcpgDevices, in: snapshot) == 0)
        #expect(countedComponentBytes(for: .xcTestDevices, in: snapshot) == 0)
        #expect(countedComponentBytes(for: .additionalXcodeState, in: snapshot) == 66)
        #expect(countedComponentPaths(for: .xcodeLogs, in: snapshot) == [xcodeLogsPath])
        #expect(countedComponentPaths(for: .coreSimulatorLogs, in: snapshot) == [coreSimulatorLogsPath])
        #expect(countedComponentPaths(for: .dvtDownloads, in: snapshot) == [dvtDownloadsPath])
        #expect(countedComponentPaths(for: .xcpgDevices, in: snapshot) == [xcpgDevicesPath])
        #expect(countedComponentPaths(for: .xcTestDevices, in: snapshot) == [xcTestDevicesPath])
    }

    @Test("Scanner sizes Simulator Data from explicit device and runtime paths plus cache roots")
    func scannerSizesSimulatorAggregateFromExplicitPaths() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)
        let simulatorDevicesRootPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
            .path
        let simulatorCachesPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)
            .path
        let simulatorTempPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Temp", isDirectory: true)
            .path
        let systemSimulatorCachesPath = "/Library/Developer/CoreSimulator/Caches"
        let systemSimulatorTempPath = "/Library/Developer/CoreSimulator/Temp"
        let legacyRuntimeRootPath = "/Library/Developer/CoreSimulator/Profiles/Runtimes"
        let simulatorDevice1Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/SIM-001", isDirectory: true)
            .path
        let simulatorDevice2Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/SIM-002", isDirectory: true)
            .path
        let runtimeBundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23A8464/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime"

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: []),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [
                simulatorDevicesRootPath: 9_000,
                simulatorCachesPath: 50,
                simulatorTempPath: 30,
                systemSimulatorCachesPath: 60,
                systemSimulatorTempPath: 40,
                legacyRuntimeRootPath: 8_000,
                simulatorDevice1Path: 100,
                simulatorDevice2Path: 200,
                runtimeBundlePath: 400,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(
                    devices: [
                        SimulatorDeviceListingRecord(
                            udid: "SIM-001",
                            name: "iPhone 15",
                            runtimeIdentifier: "runtime-1",
                            state: "Shutdown",
                            isAvailable: true
                        ),
                        SimulatorDeviceListingRecord(
                            udid: "SIM-002",
                            name: "iPhone 15 Pro",
                            runtimeIdentifier: "runtime-1",
                            state: "Shutdown",
                            isAvailable: true
                        ),
                    ],
                    runtimes: [
                        SimulatorRuntimeListingRecord(
                            identifier: "runtime-1",
                            name: "iOS 18.0",
                            version: "18.0",
                            isAvailable: true,
                            bundlePath: runtimeBundlePath
                        ),
                    ]
                )
            ),
            now: { Date(timeIntervalSince1970: 300) }
        )

        let snapshot = scanner.scan()
        let simulatorCategory = snapshot.storage.categories.first(where: { $0.kind == .simulatorData })!

        #expect(simulatorCategory.bytes == 880)
        #expect(Set(simulatorCategory.paths) == Set([
            simulatorCachesPath,
            simulatorTempPath,
            systemSimulatorCachesPath,
            systemSimulatorTempPath,
            simulatorDevice1Path,
            simulatorDevice2Path,
            runtimeBundlePath,
        ]))
        #expect(simulatorCategory.paths.contains(simulatorDevicesRootPath) == false)
        #expect(simulatorCategory.paths.contains(legacyRuntimeRootPath) == false)
        #expect(snapshot.simulator.devices.map(\.sizeInBytes) == [100, 200])
        #expect(snapshot.simulator.runtimes.map(\.sizeInBytes) == [400])
        #expect(snapshot.storage.totalBytes == 880)
    }

    @Test("Scanner total footprint includes volume-backed runtime bundles and ignores oversized legacy parent roots")
    func scannerTotalFootprintUsesVolumeBackedRuntimesAcrossMixedStorage() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)
        let derivedDataPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            .path
        let archivesPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
            .path
        let mobileDeviceCrashLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/CrashReporter/MobileDevice", isDirectory: true)
            .path
        let deviceSupportPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
            .path
        let documentationCachePath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DocumentationCache", isDirectory: true)
            .path
        let packagesPath = fakeHome
            .appendingPathComponent("Library/Developer/Packages", isDirectory: true)
            .path
        let simulatorDevicesRootPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
            .path
        let simulatorCachesPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)
            .path
        let systemSimulatorCachesPath = "/Library/Developer/CoreSimulator/Caches"
        let legacyRuntimeRootPath = "/Library/Developer/CoreSimulator/Profiles/Runtimes"
        let simulatorDevice1Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/SIM-001", isDirectory: true)
            .path
        let simulatorDevice2Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/SIM-002", isDirectory: true)
            .path
        let runtime18BundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23A8464/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime"
        let runtime17BundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23C54/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime"

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: []),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [
                derivedDataPath: 200,
                archivesPath: 300,
                mobileDeviceCrashLogsPath: 400,
                deviceSupportPath: 500,
                documentationCachePath: 600,
                packagesPath: 700,
                simulatorDevicesRootPath: 90_000,
                simulatorCachesPath: 50,
                systemSimulatorCachesPath: 60,
                legacyRuntimeRootPath: 80_000,
                simulatorDevice1Path: 100,
                simulatorDevice2Path: 200,
                runtime18BundlePath: 400,
                runtime17BundlePath: 500,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(
                    devices: [
                        SimulatorDeviceListingRecord(
                            udid: "SIM-001",
                            name: "iPhone 15",
                            runtimeIdentifier: "runtime-1",
                            state: "Shutdown",
                            isAvailable: true
                        ),
                        SimulatorDeviceListingRecord(
                            udid: "SIM-002",
                            name: "iPhone 15 Pro",
                            runtimeIdentifier: "runtime-2",
                            state: "Shutdown",
                            isAvailable: true
                        ),
                    ],
                    runtimes: [
                        SimulatorRuntimeListingRecord(
                            identifier: "runtime-1",
                            name: "iOS 18.0",
                            version: "18.0",
                            isAvailable: true,
                            bundlePath: runtime18BundlePath
                        ),
                        SimulatorRuntimeListingRecord(
                            identifier: "runtime-2",
                            name: "iOS 17.0",
                            version: "17.0",
                            isAvailable: true,
                            bundlePath: runtime17BundlePath
                        ),
                    ]
                )
            ),
            now: { Date(timeIntervalSince1970: 301) }
        )

        let snapshot = scanner.scan()
        let simulatorCategory = try #require(snapshot.storage.categories.first(where: { $0.kind == .simulatorData }))

        #expect(simulatorCategory.bytes == 1_310)
        #expect(snapshot.storage.totalBytes == 4_010)
        #expect(countedComponentBytes(for: .documentationCache, in: snapshot) == 600)
        #expect(countedComponentBytes(for: .developerPackages, in: snapshot) == 700)
        #expect(simulatorCategory.paths.contains(simulatorDevicesRootPath) == false)
        #expect(simulatorCategory.paths.contains(legacyRuntimeRootPath) == false)
        #expect(Set(simulatorCategory.paths) == Set([
            simulatorCachesPath,
            systemSimulatorCachesPath,
            simulatorDevice1Path,
            simulatorDevice2Path,
            runtime18BundlePath,
            runtime17BundlePath,
        ]))
    }

    @Test("Scanner total footprint equals tracked category plus counted-component bytes across mixed roots")
    func scannerTotalFootprintInvariantMatchesTrackedRoots() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)
        let xcodeApp = try makeFakeXcodeApp(
            in: sandbox.url,
            name: "Xcode-26.0",
            bundleIdentifier: "com.apple.dt.Xcode",
            shortVersion: "26.0",
            bundleVersion: "17A300",
            xcodeBuild: "17A300"
        )
        let derivedDataPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            .path
        let archivesPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
            .path
        let mobileDeviceCrashLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/CrashReporter/MobileDevice", isDirectory: true)
            .path
        let deviceSupportPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
            .path
        let simulatorCachesPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)
            .path
        let systemSimulatorCachesPath = "/Library/Developer/CoreSimulator/Caches"
        let simulatorDevicePath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/SIM-001", isDirectory: true)
            .path
        let runtimeBundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23A8464/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime"
        let documentationCachePath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DocumentationCache", isDirectory: true)
            .path
        let packagesPath = fakeHome
            .appendingPathComponent("Library/Developer/Packages", isDirectory: true)
            .path
        let xcodeLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/Xcode", isDirectory: true)
            .path
        let coreSimulatorLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/CoreSimulator", isDirectory: true)
            .path
        let userDataPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/UserData", isDirectory: true)
            .path
        let documentationIndexPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DocumentationIndex", isDirectory: true)
            .path
        let sdkMappingPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/SDKToSimulatorIndexMapping.plist", isDirectory: false)
            .path
        let metalMappingPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/XcodeToMetalToolchainIndexMapping.plist", isDirectory: false)
            .path

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: [xcodeApp]),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [
                xcodeApp.path: 1_000,
                derivedDataPath: 100,
                archivesPath: 200,
                mobileDeviceCrashLogsPath: 300,
                deviceSupportPath: 400,
                simulatorCachesPath: 50,
                systemSimulatorCachesPath: 60,
                simulatorDevicePath: 70,
                runtimeBundlePath: 80,
                documentationCachePath: 90,
                packagesPath: 110,
                xcodeLogsPath: 120,
                coreSimulatorLogsPath: 130,
                userDataPath: 10,
                documentationIndexPath: 5,
                sdkMappingPath: 2,
                metalMappingPath: 1,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(
                    devices: [
                        SimulatorDeviceListingRecord(
                            udid: "SIM-001",
                            name: "iPhone 15",
                            runtimeIdentifier: "runtime-1",
                            state: "Shutdown",
                            isAvailable: true
                        ),
                    ],
                    runtimes: [
                        SimulatorRuntimeListingRecord(
                            identifier: "runtime-1",
                            name: "iOS 18.0",
                            version: "18.0",
                            isAvailable: true,
                            bundlePath: runtimeBundlePath
                        ),
                    ]
                )
            ),
            now: { Date(timeIntervalSince1970: 302) }
        )

        let snapshot = scanner.scan()
        let categorySum = snapshot.storage.categories.reduce(Int64(0)) { $0 + $1.bytes }
        let countedComponentSum = snapshot.storage.countedOnlyComponents.reduce(Int64(0)) { $0 + $1.bytes }

        #expect(bytes(for: .xcodeApplications, in: snapshot) == 1_000)
        #expect(bytes(for: .derivedData, in: snapshot) == 100)
        #expect(bytes(for: .archives, in: snapshot) == 200)
        #expect(bytes(for: .mobileDeviceCrashLogs, in: snapshot) == 300)
        #expect(bytes(for: .deviceSupport, in: snapshot) == 400)
        #expect(bytes(for: .simulatorData, in: snapshot) == 260)
        #expect(countedComponentBytes(for: .documentationCache, in: snapshot) == 90)
        #expect(countedComponentBytes(for: .developerPackages, in: snapshot) == 110)
        #expect(countedComponentBytes(for: .xcodeLogs, in: snapshot) == 120)
        #expect(countedComponentBytes(for: .coreSimulatorLogs, in: snapshot) == 130)
        #expect(countedComponentBytes(for: .additionalXcodeState, in: snapshot) == 18)
        #expect(categorySum == 2_260)
        #expect(countedComponentSum == 468)
        #expect(snapshot.storage.totalBytes == 2_728)
        #expect(snapshot.storage.totalBytes == categorySum + countedComponentSum)
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

    @Test("Scanner enumerates physical Device Support directories across naming styles")
    func scannerEnumeratesPhysicalDeviceSupportDirectories() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)
        let deviceSupportRoot = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
        let directory18 = deviceSupportRoot.appendingPathComponent("18.0 (22A123)", isDirectory: true)
        let directory17 = deviceSupportRoot.appendingPathComponent("17.5 (21F90) arm64e", isDirectory: true)
        let directory26 = deviceSupportRoot.appendingPathComponent("iPhone17,2 26.3 (23D127)", isDirectory: true)
        let directoryFallback = deviceSupportRoot.appendingPathComponent("LegacySupport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory18, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory17, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory26, withIntermediateDirectories: true)
        try writePropertyList(
            [
                "Version": "16.7",
                "BuildVersion": "20H19",
                "ProductType": "iPhone12,1",
            ],
            to: directoryFallback.appendingPathComponent("Info.plist")
        )

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: []),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [
                deviceSupportRoot.path: 1_400,
                directory26.path: 300,
                directory18.path: 500,
                directory17.path: 400,
                directoryFallback.path: 200,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(devices: [], runtimes: [])
            ),
            now: { Date(timeIntervalSince1970: 200) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.physicalDeviceSupportDirectories.count == 4)
        #expect(snapshot.physicalDeviceSupportDirectories.first?.name == "iPhone17,2 26.3 (23D127)")

        let recordsByName = Dictionary(
            uniqueKeysWithValues: snapshot.physicalDeviceSupportDirectories.map { ($0.name, $0) }
        )

        #expect(recordsByName["18.0 (22A123)"]?.parsedOSVersion == "18.0")
        #expect(recordsByName["18.0 (22A123)"]?.parsedBuild == "22A123")
        #expect(recordsByName["18.0 (22A123)"]?.parsedDescriptor == nil)
        #expect(recordsByName["18.0 (22A123)"]?.sizeInBytes == 500)

        #expect(recordsByName["17.5 (21F90) arm64e"]?.parsedOSVersion == "17.5")
        #expect(recordsByName["17.5 (21F90) arm64e"]?.parsedBuild == "21F90")
        #expect(recordsByName["17.5 (21F90) arm64e"]?.parsedDescriptor == "arm64e")
        #expect(recordsByName["17.5 (21F90) arm64e"]?.sizeInBytes == 400)

        #expect(recordsByName["iPhone17,2 26.3 (23D127)"]?.parsedOSVersion == "26.3")
        #expect(recordsByName["iPhone17,2 26.3 (23D127)"]?.parsedBuild == "23D127")
        #expect(recordsByName["iPhone17,2 26.3 (23D127)"]?.parsedDescriptor == "iPhone17,2")
        #expect(recordsByName["iPhone17,2 26.3 (23D127)"]?.sizeInBytes == 300)

        #expect(recordsByName["LegacySupport"]?.parsedOSVersion == "16.7")
        #expect(recordsByName["LegacySupport"]?.parsedBuild == "20H19")
        #expect(recordsByName["LegacySupport"]?.parsedDescriptor == "iPhone12,1")
        #expect(recordsByName["LegacySupport"]?.sizeInBytes == 200)
    }

    @Test("Scanner prefers parseable Device Support folder metadata over conflicting Info.plist values")
    func scannerPrefersDeviceSupportFolderMetadataWhenAvailable() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)
        let deviceSupportRoot = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
        let conflictingDirectory = deviceSupportRoot
            .appendingPathComponent("iPhone17,2 26.3 (23D127)", isDirectory: true)
        try FileManager.default.createDirectory(at: conflictingDirectory, withIntermediateDirectories: true)
        try writePropertyList(
            [
                "Version": "26.0",
                "BuildVersion": "23A111",
                "ProductType": "iPhone18,3",
            ],
            to: conflictingDirectory.appendingPathComponent("Info.plist")
        )

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: []),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: nil),
            pathSizer: StubPathSizer(sizeByPath: [
                deviceSupportRoot.path: 300,
                conflictingDirectory.path: 300,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(devices: [], runtimes: [])
            ),
            now: { Date(timeIntervalSince1970: 200) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.physicalDeviceSupportDirectories.count == 1)
        let record = try #require(snapshot.physicalDeviceSupportDirectories.first)
        #expect(record.name == "iPhone17,2 26.3 (23D127)")
        #expect(record.parsedOSVersion == "26.3")
        #expect(record.parsedBuild == "23D127")
        #expect(record.parsedDescriptor == "iPhone17,2")
        #expect(record.sizeInBytes == 300)
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
            .loadingSimulatorListing,
            .buildingSimulatorInventory,
            .sizingStorageCategories,
            .computingRuntimeTelemetry,
            .finalizingSnapshot,
        ])
    }

    @Test("Scanner emits incremental progress within long-running sizing phases")
    func scannerProgressUpdatesIncrementallyWithinHeavyPhases() throws {
        let sandbox = try TemporaryDirectory.make()
        defer { sandbox.cleanup() }

        let xcodeStable = try makeFakeXcodeApp(
            in: sandbox.url,
            name: "Xcode-26.2",
            bundleIdentifier: "com.apple.dt.Xcode",
            shortVersion: "26.2",
            bundleVersion: "17B400",
            xcodeBuild: "17B400"
        )
        let xcodeBeta = try makeFakeXcodeApp(
            in: sandbox.url,
            name: "Xcode-26.3-beta",
            bundleIdentifier: "com.apple.dt.XcodeBeta",
            shortVersion: "26.3",
            bundleVersion: "17C500",
            xcodeBuild: "17C500"
        )

        let fakeHome = sandbox.url.appendingPathComponent("fake-home", isDirectory: true)
        let derivedDataPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            .path
        let archivesPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
            .path
        let mobileDeviceCrashLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/CrashReporter/MobileDevice", isDirectory: true)
            .path
        let deviceSupportPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
            .path
        let documentationCachePath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DocumentationCache", isDirectory: true)
            .path
        let packagesPath = fakeHome
            .appendingPathComponent("Library/Developer/Packages", isDirectory: true)
            .path
        let xcodeLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/Xcode", isDirectory: true)
            .path
        let coreSimulatorLogsPath = fakeHome
            .appendingPathComponent("Library/Logs/CoreSimulator", isDirectory: true)
            .path
        let dvtDownloadsPath = fakeHome
            .appendingPathComponent("Library/Developer/DVTDownloads", isDirectory: true)
            .path
        let xcpgDevicesPath = fakeHome
            .appendingPathComponent("Library/Developer/XCPGDevices", isDirectory: true)
            .path
        let xcTestDevicesPath = fakeHome
            .appendingPathComponent("Library/Developer/XCTestDevices", isDirectory: true)
            .path
        let userDataPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/UserData", isDirectory: true)
            .path
        let documentationIndexPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/DocumentationIndex", isDirectory: true)
            .path
        let sdkMappingPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/SDKToSimulatorIndexMapping.plist", isDirectory: false)
            .path
        let metalMappingPath = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/XcodeToMetalToolchainIndexMapping.plist", isDirectory: false)
            .path
        let simulatorCachesPath = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)
            .path
        let systemSimulatorCachesPath = "/Library/Developer/CoreSimulator/Caches"
        let runtime18BundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23A8464/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime"
        let runtime17BundlePath = "/Library/Developer/CoreSimulator/Volumes/iOS_23C54/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime"
        let simulatorDevice1UDID = "SIM-DEVICE-1"
        let simulatorDevice2UDID = "SIM-DEVICE-2"
        let simulatorDevice3UDID = "SIM-DEVICE-3"
        let simulatorDevice1Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(simulatorDevice1UDID)", isDirectory: true)
            .path
        let simulatorDevice2Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(simulatorDevice2UDID)", isDirectory: true)
            .path
        let simulatorDevice3Path = fakeHome
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(simulatorDevice3UDID)", isDirectory: true)
            .path
        let deviceSupportDirectory1Path = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/26.2 (23C54)", isDirectory: true)
            .path
        let deviceSupportDirectory2Path = fakeHome
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,2 26.3 (23D127)", isDirectory: true)
            .path

        try FileManager.default.createDirectory(atPath: deviceSupportDirectory1Path, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: deviceSupportDirectory2Path, withIntermediateDirectories: true)

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: [xcodeStable, xcodeBeta]),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: xcodeStable.appendingPathComponent("Contents/Developer", isDirectory: true)),
            pathSizer: StubPathSizer(sizeByPath: [
                xcodeStable.path: 1_000,
                xcodeBeta.path: 1_200,
                derivedDataPath: 300,
                archivesPath: 200,
                mobileDeviceCrashLogsPath: 50,
                deviceSupportPath: 700,
                documentationCachePath: 80,
                packagesPath: 70,
                xcodeLogsPath: 60,
                coreSimulatorLogsPath: 55,
                dvtDownloadsPath: 40,
                xcpgDevicesPath: 30,
                xcTestDevicesPath: 20,
                userDataPath: 10,
                documentationIndexPath: 9,
                sdkMappingPath: 8,
                metalMappingPath: 7,
                simulatorCachesPath: 90,
                systemSimulatorCachesPath: 91,
                runtime18BundlePath: 450,
                runtime17BundlePath: 350,
                simulatorDevice1Path: 120,
                simulatorDevice2Path: 110,
                simulatorDevice3Path: 100,
                deviceSupportDirectory1Path: 400,
                deviceSupportDirectory2Path: 300,
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            runningApplicationsProvider: StubRunningApplicationsProvider(records: []),
            simulatorListingProvider: StubSimulatorListingProvider(
                listing: SimulatorListing(
                    devices: [
                        SimulatorDeviceListingRecord(
                            udid: simulatorDevice1UDID,
                            name: "iPhone 16 Pro",
                            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
                            state: "Shutdown",
                            isAvailable: true
                        ),
                        SimulatorDeviceListingRecord(
                            udid: simulatorDevice2UDID,
                            name: "iPhone 15",
                            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                            state: "Booted",
                            isAvailable: true
                        ),
                        SimulatorDeviceListingRecord(
                            udid: simulatorDevice3UDID,
                            name: "iPad Pro",
                            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
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
                            isAvailable: true,
                            bundlePath: runtime17BundlePath
                        ),
                    ]
                )
            ),
            now: { Date(timeIntervalSince1970: 300) }
        )

        var updates: [ScanProgress] = []
        _ = scanner.scan { updates.append($0) }

        let installUpdates = updates.filter { $0.phase == .sizingXcodeInstalls }
        let inventoryUpdates = updates.filter { $0.phase == .buildingSimulatorInventory }
        let storageUpdates = updates.filter { $0.phase == .sizingStorageCategories }

        #expect(installUpdates.count >= 2)
        #expect(inventoryUpdates.count > 2)
        #expect(storageUpdates.count > 10)
        #expect(inventoryUpdates.contains(where: { $0.message.contains("simulator runtime") }))
        #expect(inventoryUpdates.contains(where: { $0.message.contains("simulator device") }))
        #expect(storageUpdates.contains(where: { $0.message.contains("Simulator Data") }))
        #expect(storageUpdates.contains(where: { $0.message.contains("Documentation Cache") }))
        #expect(storageUpdates.contains(where: { $0.message.contains("device support directory") }))

        for index in 1..<updates.count {
            #expect(updates[index].fractionCompleted >= updates[index - 1].fractionCompleted)
        }
        #expect(updates.last?.fractionCompleted == 1)
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

    @Test("Dry-run planner supports explicit opt-in counted cleanup components")
    func dryRunPlannerSupportsOptInCountedCleanupComponents() {
        let snapshot = makePlanningSnapshot()
        let selection = DryRunSelection(
            selectedCategoryKinds: [],
            selectedCountedFootprintComponentKinds: [.documentationCache, .xcodeLogs, .coreSimulatorLogs],
            selectedSimulatorDeviceUDIDs: []
        )

        let plan = DryRunPlanner.makePlan(snapshot: snapshot, selection: selection)

        #expect(plan.items.count == 3)
        #expect(plan.selection.selectedCategoryKinds.isEmpty)
        #expect(plan.selection.selectedCountedFootprintComponentKinds == [.coreSimulatorLogs, .documentationCache, .xcodeLogs])
        #expect(plan.items.map(\.kind).allSatisfy { $0 == .countedFootprintComponent })
        #expect(plan.items.map(\.title) == ["CoreSimulator Logs", "Documentation Cache", "Xcode Logs"])
        #expect(plan.items[0].paths == ["/tmp/Logs/CoreSimulator"])
        #expect(plan.items[1].paths == ["/tmp/Developer/Xcode/DocumentationCache"])
        #expect(plan.items[2].paths == ["/tmp/Logs/Xcode"])
        #expect(plan.totalReclaimableBytes == 8_192)
        #expect(plan.notes.isEmpty)
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

    @Test("Dry-run planner supports per-directory physical Device Support selection in main plan")
    func dryRunPlannerPhysicalDeviceSupportSelection() {
        let baseSnapshot = makePlanningSnapshot()
        let snapshot = XcodeInventorySnapshot(
            scannedAt: baseSnapshot.scannedAt,
            activeDeveloperDirectoryPath: baseSnapshot.activeDeveloperDirectoryPath,
            installs: baseSnapshot.installs,
            storage: XcodeStorageUsage(
                categories: baseSnapshot.storage.categories + [
                    StorageCategoryUsage(
                        kind: .deviceSupport,
                        title: "Device Support",
                        bytes: 1_000,
                        paths: ["/tmp/DeviceSupport"],
                        ownershipSummary: "Owned by physical-device support files",
                        safetyClassification: .regenerable
                    ),
                ],
                totalBytes: baseSnapshot.storage.totalBytes + 1_000
            ),
            physicalDeviceSupportDirectories: [
                PhysicalDeviceSupportDirectoryRecord(
                    name: "16.4 (20E247)",
                    path: "/tmp/DeviceSupport/16.4 (20E247)",
                    sizeInBytes: 300,
                    modifiedAt: Date(timeIntervalSince1970: 600),
                    parsedOSVersion: "16.4",
                    parsedBuild: "20E247",
                    parsedDescriptor: nil
                ),
            ],
            simulator: baseSnapshot.simulator,
            runtimeTelemetry: baseSnapshot.runtimeTelemetry
        )

        let selection = DryRunSelection(
            selectedCategoryKinds: [.deviceSupport],
            selectedSimulatorDeviceUDIDs: [],
            selectedSimulatorRuntimeIdentifiers: [],
            selectedPhysicalDeviceSupportDirectoryPaths: ["/tmp/DeviceSupport/16.4 (20E247)"]
        )

        let plan = DryRunPlanner.makePlan(
            snapshot: snapshot,
            selection: selection
        )

        #expect(plan.items.count == 1)
        #expect(plan.items[0].kind == .deviceSupportDirectory)
        #expect(plan.items[0].paths == ["/tmp/DeviceSupport/16.4 (20E247)"])
        #expect(plan.totalReclaimableBytes == 300)
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

private final class StubCommandRunner: CommandRunning {
    struct Key: Hashable {
        let launchPath: String
        let arguments: [String]
    }

    let responses: [Key: String]

    init(responses: [Key: String]) {
        self.responses = responses
    }

    func run(launchPath: String, arguments: [String]) throws -> String {
        let key = Key(launchPath: launchPath, arguments: arguments)
        guard let response = responses[key] else {
            throw StubCommandRunnerError.unsupportedCommand(key)
        }
        return response
    }
}

private enum StubCommandRunnerError: Error {
    case unsupportedCommand(StubCommandRunner.Key)
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

private func writePropertyList(_ dictionary: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: dictionary,
        format: .xml,
        options: 0
    )
    try plistData.write(to: url)
}

private func bytes(for kind: StorageCategoryKind, in snapshot: XcodeInventorySnapshot) -> Int64 {
    snapshot.storage.categories.first(where: { $0.kind == kind })?.bytes ?? -1
}

private func countedComponentBytes(
    for kind: CountedFootprintComponentKind,
    in snapshot: XcodeInventorySnapshot
) -> Int64 {
    snapshot.storage.countedOnlyComponents.first(where: { $0.kind == kind })?.bytes ?? -1
}

private func countedComponentPaths(
    for kind: CountedFootprintComponentKind,
    in snapshot: XcodeInventorySnapshot
) -> [String] {
    snapshot.storage.countedOnlyComponents.first(where: { $0.kind == kind })?.paths ?? []
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
            bytes: 20_480,
            paths: [
                "/tmp/CoreSimulator/Caches",
                "/tmp/CoreSimulator/Devices/SIM-1",
                "/tmp/CoreSimulator/Profiles/Runtimes/iOS-18.simruntime",
            ],
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

    let countedOnlyComponents = [
        CountedFootprintComponentUsage(
            kind: .documentationCache,
            title: "Documentation Cache",
            bytes: 2_560,
            paths: ["/tmp/Developer/Xcode/DocumentationCache"],
            ownershipSummary: "Counted in total footprint only; owned by downloaded Xcode documentation cache."
        ),
        CountedFootprintComponentUsage(
            kind: .xcodeLogs,
            title: "Xcode Logs",
            bytes: 1_536,
            paths: ["/tmp/Logs/Xcode"],
            ownershipSummary: "Counted in total footprint only; owned by Xcode log history."
        ),
        CountedFootprintComponentUsage(
            kind: .coreSimulatorLogs,
            title: "CoreSimulator Logs",
            bytes: 4_096,
            paths: ["/tmp/Logs/CoreSimulator"],
            ownershipSummary: "Counted in total footprint only; owned by CoreSimulator log history."
        ),
    ]

    return XcodeInventorySnapshot(
        scannedAt: Date(timeIntervalSince1970: 10),
        activeDeveloperDirectoryPath: nil,
        installs: [],
        storage: XcodeStorageUsage(
            categories: categories,
            countedOnlyComponents: countedOnlyComponents,
            totalBytes: 31_744
        ),
        simulator: simulator,
        runtimeTelemetry: RuntimeTelemetry(totalXcodeRunningInstances: 0, totalSimulatorAppRunningInstances: 0)
    )
}
