import AppKit
import Foundation

public protocol XcodeApplicationDiscovering {
    func discoverXcodeApplicationURLs() -> [URL]
}

public protocol ActiveDeveloperDirectoryProviding {
    func activeDeveloperDirectoryURL() -> URL?
}

public protocol InfoPlistReading {
    func readInfoPlist(at appURL: URL) -> [String: Any]
}

public protocol CommandRunning {
    func run(launchPath: String, arguments: [String]) throws -> String
}

public protocol PathSizing {
    func fileExists(at url: URL) -> Bool
    func allocatedSize(at url: URL) -> Int64
}

public protocol HomeDirectoryProviding {
    func homeDirectoryURL() -> URL
}

public struct RunningApplicationRecord: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let bundlePath: String?
    public let executablePath: String?
    public let processIdentifier: Int32

    public init(bundleIdentifier: String?, bundlePath: String?, executablePath: String?, processIdentifier: Int32) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.executablePath = executablePath
        self.processIdentifier = processIdentifier
    }
}

public protocol RunningApplicationsProviding {
    func runningApplications() -> [RunningApplicationRecord]
}

public struct SimulatorDeviceListingRecord: Equatable, Sendable {
    public let udid: String
    public let name: String
    public let runtimeIdentifier: String
    public let state: String
    public let isAvailable: Bool

    public init(udid: String, name: String, runtimeIdentifier: String, state: String, isAvailable: Bool) {
        self.udid = udid
        self.name = name
        self.runtimeIdentifier = runtimeIdentifier
        self.state = state
        self.isAvailable = isAvailable
    }
}

public struct SimulatorRuntimeListingRecord: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String?
    public let isAvailable: Bool
    public let bundlePath: String?

    public init(identifier: String, name: String, version: String?, isAvailable: Bool, bundlePath: String?) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.isAvailable = isAvailable
        self.bundlePath = bundlePath
    }
}

public struct SimulatorListing: Equatable, Sendable {
    public let devices: [SimulatorDeviceListingRecord]
    public let runtimes: [SimulatorRuntimeListingRecord]

    public init(devices: [SimulatorDeviceListingRecord], runtimes: [SimulatorRuntimeListingRecord]) {
        self.devices = devices
        self.runtimes = runtimes
    }
}

public protocol SimulatorListingProviding {
    func simulatorListing() -> SimulatorListing
}

public struct XcodeInventoryScanner: @unchecked Sendable {
    private let applicationDiscoverer: XcodeApplicationDiscovering
    private let activeDeveloperDirectoryProvider: ActiveDeveloperDirectoryProviding
    private let infoPlistReader: InfoPlistReading
    private let pathSizer: PathSizing
    private let homeDirectoryProvider: HomeDirectoryProviding
    private let runningApplicationsProvider: RunningApplicationsProviding
    private let simulatorListingProvider: SimulatorListingProviding
    private let now: () -> Date

    public init(
        applicationDiscoverer: XcodeApplicationDiscovering = SystemXcodeApplicationDiscoverer(),
        activeDeveloperDirectoryProvider: ActiveDeveloperDirectoryProviding = XcodeSelectActiveDeveloperDirectoryProvider(),
        infoPlistReader: InfoPlistReading = InfoPlistFileReader(),
        pathSizer: PathSizing = FileSystemPathSizer(),
        homeDirectoryProvider: HomeDirectoryProviding = CurrentUserHomeDirectoryProvider(),
        runningApplicationsProvider: RunningApplicationsProviding = SystemRunningApplicationsProvider(),
        simulatorListingProvider: SimulatorListingProviding = SimctlSimulatorListingProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.applicationDiscoverer = applicationDiscoverer
        self.activeDeveloperDirectoryProvider = activeDeveloperDirectoryProvider
        self.infoPlistReader = infoPlistReader
        self.pathSizer = pathSizer
        self.homeDirectoryProvider = homeDirectoryProvider
        self.runningApplicationsProvider = runningApplicationsProvider
        self.simulatorListingProvider = simulatorListingProvider
        self.now = now
    }

    public func scan(progressHandler: ((ScanProgress) -> Void)? = nil) -> XcodeInventorySnapshot {
        func emitProgress(_ phase: ScanPhase, _ fraction: Double, _ message: String) {
            progressHandler?(ScanProgress(phase: phase, fractionCompleted: fraction, message: message))
        }

        emitProgress(.discoveringXcodeInstalls, 0.01, "Locating Xcode application bundles")
        let activeDeveloperDirectoryURL = activeDeveloperDirectoryProvider.activeDeveloperDirectoryURL()
        let activeDeveloperDirectoryPath = normalizedPath(for: activeDeveloperDirectoryURL)

        let runningApplications = runningApplicationsProvider.runningApplications()
        let xcodeRunningCountsByPath = runningXcodeInstanceCountByInstallPath(from: runningApplications)

        let discoveredApplications = deduplicatedApplicationURLs(from: applicationDiscoverer.discoverXcodeApplicationURLs())
        emitProgress(
            .discoveringXcodeInstalls,
            0.10,
            "Discovered \(discoveredApplications.count) Xcode install(s)"
        )

        let sizingInstallFractionStart = 0.10
        let sizingInstallFractionEnd = 0.35
        var installs = discoveredApplications.enumerated()
            .map { index, appURL -> XcodeInstall in
                let info = infoPlistReader.readInfoPlist(at: appURL)
                let displayName = (info[InfoPlistKeys.bundleDisplayName] as? String)
                    ?? (info[InfoPlistKeys.bundleName] as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent
                let version = info[InfoPlistKeys.shortVersion] as? String
                let build = (info[InfoPlistKeys.xcodeBuild] as? String)
                    ?? (info[InfoPlistKeys.bundleVersion] as? String)
                let bundleIdentifier = info[InfoPlistKeys.bundleIdentifier] as? String

                let developerDirectoryURL = appURL.appendingPathComponent("Contents/Developer", isDirectory: true)
                let developerDirectoryPath = normalizedPath(for: developerDirectoryURL) ?? developerDirectoryURL.path
                let installPath = normalizedPath(for: appURL) ?? appURL.path
                let runningInstanceCount = xcodeRunningCountsByPath[installPath] ?? 0

                return XcodeInstall(
                    displayName: displayName,
                    bundleIdentifier: bundleIdentifier,
                    version: version,
                    build: build,
                    path: installPath,
                    developerDirectoryPath: developerDirectoryPath,
                    isActive: matchesActiveDeveloperDirectory(
                        activeDeveloperDirectoryPath: activeDeveloperDirectoryPath,
                        installDeveloperDirectoryPath: developerDirectoryPath
                    ),
                    runningInstanceCount: runningInstanceCount,
                    sizeInBytes: pathSizer.allocatedSize(at: appURL),
                    ownershipSummary: "Owned by this Xcode installation bundle",
                    safetyClassification: .destructive
                )
            }
        if discoveredApplications.isEmpty {
            emitProgress(.sizingXcodeInstalls, sizingInstallFractionEnd, "No Xcode installs found")
        } else {
            for index in discoveredApplications.indices {
                let progress = sizingInstallFractionStart
                    + (Double(index + 1) / Double(discoveredApplications.count))
                    * (sizingInstallFractionEnd - sizingInstallFractionStart)
                emitProgress(
                    .sizingXcodeInstalls,
                    progress,
                    "Processed Xcode install \(index + 1) of \(discoveredApplications.count)"
                )
            }
        }
        installs = installs.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive
                }
                if lhs.runningInstanceCount != rhs.runningInstanceCount {
                    return lhs.runningInstanceCount > rhs.runningInstanceCount
                }
                if lhs.displayName != rhs.displayName {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }

        emitProgress(.sizingStorageCategories, 0.40, "Sizing storage categories")
        let storage = buildStorageUsage(installs: installs)
        emitProgress(.sizingStorageCategories, 0.58, "Storage category sizing complete")

        emitProgress(.loadingSimulatorListing, 0.62, "Loading simulator device/runtime listing")
        let simulatorListing = simulatorListingProvider.simulatorListing()
        emitProgress(.loadingSimulatorListing, 0.68, "Loaded simulator device/runtime listing")

        emitProgress(.buildingSimulatorInventory, 0.74, "Building simulator inventory records")
        let simulatorInventory = buildSimulatorInventory(from: simulatorListing)
        emitProgress(
            .buildingSimulatorInventory,
            0.86,
            "Built \(simulatorInventory.devices.count) device and \(simulatorInventory.runtimes.count) runtime records"
        )

        emitProgress(.computingRuntimeTelemetry, 0.92, "Computing runtime telemetry")
        let runtimeTelemetry = RuntimeTelemetry(
            totalXcodeRunningInstances: installs.reduce(0) { $0 + $1.runningInstanceCount },
            totalSimulatorAppRunningInstances: runningSimulatorAppInstanceCount(from: runningApplications)
        )
        emitProgress(
            .computingRuntimeTelemetry,
            0.97,
            "Telemetry complete (Xcode: \(runtimeTelemetry.totalXcodeRunningInstances), Simulator app: \(runtimeTelemetry.totalSimulatorAppRunningInstances))"
        )

        emitProgress(.finalizingSnapshot, 0.99, "Finalizing snapshot")
        let snapshot = XcodeInventorySnapshot(
            scannedAt: now(),
            activeDeveloperDirectoryPath: activeDeveloperDirectoryPath,
            installs: installs,
            storage: storage,
            simulator: simulatorInventory,
            runtimeTelemetry: runtimeTelemetry
        )
        emitProgress(.finalizingSnapshot, 1.0, "Scan complete")
        return snapshot
    }

    private func buildStorageUsage(installs: [XcodeInstall]) -> XcodeStorageUsage {
        let homeDirectoryURL = homeDirectoryProvider.homeDirectoryURL()
        let simulatorPaths = [
            homeDirectoryURL.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true),
            URL(filePath: "/Library/Developer/CoreSimulator/Profiles/Runtimes", directoryHint: .isDirectory),
        ]

        let categories = [
            makeCategory(
                kind: .xcodeApplications,
                title: "Xcode Applications",
                paths: installs.map { URL(filePath: $0.path, directoryHint: .isDirectory) },
                ownershipSummary: "Owned by individual Xcode installation bundles",
                safetyClassification: .destructive
            ),
            makeCategory(
                kind: .derivedData,
                title: "Derived Data",
                paths: [homeDirectoryURL.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)],
                ownershipSummary: "Owned by local project build artifacts",
                safetyClassification: .regenerable
            ),
            makeCategory(
                kind: .mobileDeviceCrashLogs,
                title: "MobileDevice Crash Logs",
                paths: [homeDirectoryURL.appendingPathComponent("Library/Logs/CrashReporter/MobileDevice", isDirectory: true)],
                ownershipSummary: "Owned by local crash and diagnostic logs captured from connected physical devices",
                safetyClassification: .conditionallySafe
            ),
            makeCategory(
                kind: .archives,
                title: "Archives",
                paths: [homeDirectoryURL.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)],
                ownershipSummary: "Owned by archived local build outputs",
                safetyClassification: .conditionallySafe
            ),
            makeCategory(
                kind: .deviceSupport,
                title: "Device Support",
                paths: [homeDirectoryURL.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)],
                ownershipSummary: "Owned by local support files for connected devices",
                safetyClassification: .regenerable
            ),
            makeCategory(
                kind: .simulatorData,
                title: "Simulator Data",
                paths: simulatorPaths,
                ownershipSummary: "Owned by CoreSimulator runtimes and device sandboxes",
                safetyClassification: .conditionallySafe
            ),
        ]
        .sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes {
                return lhs.bytes > rhs.bytes
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let totalBytes = categories.reduce(Int64(0)) { partialResult, category in
            partialResult + category.bytes
        }

        return XcodeStorageUsage(categories: categories, totalBytes: totalBytes)
    }

    private func buildSimulatorInventory(from listing: SimulatorListing) -> SimulatorInventory {
        let homeDirectoryURL = homeDirectoryProvider.homeDirectoryURL()
        let simulatorDeviceRoot = homeDirectoryURL.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)

        let runtimes = listing.runtimes
            .map { runtime -> SimulatorRuntimeRecord in
                let bundlePath = runtime.bundlePath.flatMap { path in
                    normalizedPath(for: URL(filePath: path, directoryHint: .isDirectory)) ?? path
                }
                let sizeInBytes: Int64
                if let bundlePath {
                    let url = URL(filePath: bundlePath, directoryHint: .isDirectory)
                    sizeInBytes = pathSizer.fileExists(at: url) ? pathSizer.allocatedSize(at: url) : 0
                } else {
                    sizeInBytes = 0
                }

                return SimulatorRuntimeRecord(
                    identifier: runtime.identifier,
                    name: runtime.name,
                    version: runtime.version,
                    isAvailable: runtime.isAvailable,
                    bundlePath: bundlePath,
                    sizeInBytes: sizeInBytes,
                    ownershipSummary: "Owned by CoreSimulator runtime files",
                    safetyClassification: .conditionallySafe
                )
            }
            .sorted { lhs, rhs in
                if lhs.isAvailable != rhs.isAvailable {
                    return lhs.isAvailable
                }
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.identifier.localizedCaseInsensitiveCompare(rhs.identifier) == .orderedAscending
            }

        let runtimeNamesByIdentifier = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.identifier, $0.name) })

        let devices = listing.devices
            .map { device -> SimulatorDeviceRecord in
                let dataPathURL = simulatorDeviceRoot.appendingPathComponent(device.udid, isDirectory: true)
                let normalizedDataPath = normalizedPath(for: dataPathURL) ?? dataPathURL.path
                let sizeInBytes = pathSizer.fileExists(at: dataPathURL) ? pathSizer.allocatedSize(at: dataPathURL) : 0
                let isRunning = isBootedState(device.state)
                let runtimeName = runtimeNamesByIdentifier[device.runtimeIdentifier]
                let ownership = runtimeName.map { "Owned by simulator device data for \($0)" }
                    ?? "Owned by simulator device data"

                return SimulatorDeviceRecord(
                    udid: device.udid,
                    name: device.name,
                    runtimeIdentifier: device.runtimeIdentifier,
                    runtimeName: runtimeName,
                    state: device.state,
                    isAvailable: device.isAvailable,
                    dataPath: normalizedDataPath,
                    sizeInBytes: sizeInBytes,
                    runningInstanceCount: isRunning ? 1 : 0,
                    ownershipSummary: ownership,
                    safetyClassification: .conditionallySafe
                )
            }
            .sorted { lhs, rhs in
                if lhs.runningInstanceCount != rhs.runningInstanceCount {
                    return lhs.runningInstanceCount > rhs.runningInstanceCount
                }
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.udid.localizedCaseInsensitiveCompare(rhs.udid) == .orderedAscending
            }

        return SimulatorInventory(devices: devices, runtimes: runtimes)
    }

    private func makeCategory(
        kind: StorageCategoryKind,
        title: String,
        paths: [URL],
        ownershipSummary: String,
        safetyClassification: SafetyClassification
    ) -> StorageCategoryUsage {
        var seen = Set<String>()
        var existingPaths: [String] = []
        var bytes = Int64(0)

        for pathURL in paths {
            let normalized = normalizedPath(for: pathURL) ?? pathURL.path
            guard seen.insert(normalized).inserted else {
                continue
            }
            guard pathSizer.fileExists(at: pathURL) else {
                continue
            }
            existingPaths.append(normalized)
            bytes += pathSizer.allocatedSize(at: pathURL)
        }

        return StorageCategoryUsage(
            kind: kind,
            title: title,
            bytes: bytes,
            paths: existingPaths,
            ownershipSummary: ownershipSummary,
            safetyClassification: safetyClassification
        )
    }

    private func runningXcodeInstanceCountByInstallPath(from runningApplications: [RunningApplicationRecord]) -> [String: Int] {
        var result: [String: Int] = [:]
        for record in runningApplications {
            guard let bundlePath = xcodeBundlePath(for: record),
                  isLikelyXcodeApplication(record: record, bundlePath: bundlePath) else {
                continue
            }
            result[bundlePath, default: 0] += 1
        }
        return result
    }

    private func runningSimulatorAppInstanceCount(from runningApplications: [RunningApplicationRecord]) -> Int {
        Set(
            runningApplications.compactMap { record -> Int32? in
                isSimulatorApplication(record: record) ? record.processIdentifier : nil
            }
        ).count
    }

    private func xcodeBundlePath(for record: RunningApplicationRecord) -> String? {
        if let path = record.bundlePath {
            return normalizedPath(for: URL(filePath: path, directoryHint: .isDirectory))
        }
        guard let executablePath = record.executablePath else {
            return nil
        }
        let executableURL = URL(filePath: executablePath)
        let appURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard appURL.pathExtension == "app" else {
            return nil
        }
        return normalizedPath(for: appURL)
    }

    private func isLikelyXcodeApplication(record: RunningApplicationRecord, bundlePath: String) -> Bool {
        let bundleIdentifier = record.bundleIdentifier
        if bundleIdentifier == "com.apple.dt.Xcode" || bundleIdentifier == "com.apple.dt.XcodeBeta" {
            return true
        }

        // Fallback for unusual process metadata: only treat the main Xcode executable as an app instance.
        guard bundleIdentifier == nil else {
            return false
        }
        guard let executablePath = record.executablePath else {
            return false
        }
        let executableName = URL(filePath: executablePath).lastPathComponent.lowercased()
        guard executableName == "xcode" else {
            return false
        }

        let lowercasedName = URL(filePath: bundlePath).lastPathComponent.lowercased()
        return lowercasedName.hasPrefix("xcode")
    }

    private func isSimulatorApplication(record: RunningApplicationRecord) -> Bool {
        if record.bundleIdentifier == "com.apple.iphonesimulator" {
            return true
        }

        guard record.bundleIdentifier == nil else {
            return false
        }

        if let executablePath = record.executablePath {
            let normalizedExecutablePath = URL(filePath: executablePath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            return normalizedExecutablePath.hasSuffix("/Simulator.app/Contents/MacOS/Simulator")
        }

        if let bundlePath = record.bundlePath {
            return URL(filePath: bundlePath).lastPathComponent == "Simulator.app"
        }

        return false
    }

    private func isBootedState(_ state: String) -> Bool {
        let lowered = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered == "booted" || lowered == "booting"
    }

    private func deduplicatedApplicationURLs(from applicationURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for applicationURL in applicationURLs {
            guard applicationURL.pathExtension == "app" else {
                continue
            }
            let path = normalizedPath(for: applicationURL) ?? applicationURL.path
            if seen.insert(path).inserted {
                result.append(applicationURL)
            }
        }
        return result
    }

    private func normalizedPath(for url: URL?) -> String? {
        guard let url else {
            return nil
        }
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func matchesActiveDeveloperDirectory(
        activeDeveloperDirectoryPath: String?,
        installDeveloperDirectoryPath: String
    ) -> Bool {
        guard let activeDeveloperDirectoryPath else {
            return false
        }
        return activeDeveloperDirectoryPath == installDeveloperDirectoryPath
            || activeDeveloperDirectoryPath.hasPrefix(installDeveloperDirectoryPath + "/")
    }
}

public struct SystemXcodeApplicationDiscoverer: XcodeApplicationDiscovering {
    public init() {}

    public func discoverXcodeApplicationURLs() -> [URL] {
        var discoveredURLs: [URL] = []

        let knownBundleIdentifiers = [
            "com.apple.dt.Xcode",
            "com.apple.dt.XcodeBeta",
        ]

        for bundleIdentifier in knownBundleIdentifiers {
            discoveredURLs.append(contentsOf: NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier))
        }

        let likelyInstallRoots = [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory).appendingPathComponent("Applications", isDirectory: true),
        ]

        for installRoot in likelyInstallRoots {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: installRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for url in urls where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                if name.hasPrefix("xcode") {
                    discoveredURLs.append(url)
                }
            }
        }

        return discoveredURLs
    }
}

public struct XcodeSelectActiveDeveloperDirectoryProvider: ActiveDeveloperDirectoryProviding {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func activeDeveloperDirectoryURL() -> URL? {
        guard let output = try? commandRunner.run(
            launchPath: "/usr/bin/xcode-select",
            arguments: ["-p"]
        ) else {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(filePath: trimmed, directoryHint: .isDirectory)
    }
}

public struct InfoPlistFileReader: InfoPlistReading {
    public init() {}

    public func readInfoPlist(at appURL: URL) -> [String: Any] {
        let infoPlistURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoPlistURL),
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = value as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}

public struct FileSystemPathSizer: PathSizing {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func allocatedSize(at url: URL) -> Int64 {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return fileSize(for: url)
        }
        return directorySize(for: url)
    }

    private func fileSize(for fileURL: URL) -> Int64 {
        if let resourceValues = try? fileURL.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .totalFileSizeKey,
            .fileSizeKey,
        ]) {
            if let value = resourceValues.totalFileAllocatedSize {
                return Int64(value)
            }
            if let value = resourceValues.fileAllocatedSize {
                return Int64(value)
            }
            if let value = resourceValues.totalFileSize {
                return Int64(value)
            }
            if let value = resourceValues.fileSize {
                return Int64(value)
            }
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let number = attributes[.size] as? NSNumber {
            return number.int64Value
        }

        return 0
    }

    private func directorySize(for directoryURL: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .totalFileSizeKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total = Int64(0)
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .totalFileSizeKey,
                .fileSizeKey,
            ]) else {
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }
            if let size = values.totalFileAllocatedSize {
                total += Int64(size)
            } else if let size = values.fileAllocatedSize {
                total += Int64(size)
            } else if let size = values.totalFileSize {
                total += Int64(size)
            } else if let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

public struct CurrentUserHomeDirectoryProvider: HomeDirectoryProviding {
    public init() {}

    public func homeDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
}

public struct SystemRunningApplicationsProvider: RunningApplicationsProviding {
    public init() {}

    public func runningApplications() -> [RunningApplicationRecord] {
        NSWorkspace.shared.runningApplications.map { app in
            RunningApplicationRecord(
                bundleIdentifier: app.bundleIdentifier,
                bundlePath: app.bundleURL?.path,
                executablePath: app.executableURL?.path,
                processIdentifier: app.processIdentifier
            )
        }
    }
}

public struct SimctlSimulatorListingProvider: SimulatorListingProviding {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func simulatorListing() -> SimulatorListing {
        let devicesJSON = try? commandRunner.run(
            launchPath: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "--json"]
        )
        let runtimesJSON = try? commandRunner.run(
            launchPath: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "runtimes", "--json"]
        )
        return SimulatorListing(
            devices: parseDevices(json: devicesJSON),
            runtimes: parseRuntimes(json: runtimesJSON)
        )
    }

    private func parseDevices(json: String?) -> [SimulatorDeviceListingRecord] {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = object["devices"] as? [String: Any] else {
            return []
        }

        var devices: [SimulatorDeviceListingRecord] = []
        for (runtimeIdentifier, rawDevices) in devicesByRuntime {
            guard let entries = rawDevices as? [[String: Any]] else {
                continue
            }
            for entry in entries {
                guard let udid = entry["udid"] as? String else {
                    continue
                }
                let name = (entry["name"] as? String) ?? "Unknown Device"
                let state = (entry["state"] as? String) ?? "Unknown"
                let isAvailable = parseAvailability(entry["isAvailable"])
                devices.append(
                    SimulatorDeviceListingRecord(
                        udid: udid,
                        name: name,
                        runtimeIdentifier: runtimeIdentifier,
                        state: state,
                        isAvailable: isAvailable
                    )
                )
            }
        }
        return devices
    }

    private func parseRuntimes(json: String?) -> [SimulatorRuntimeListingRecord] {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimesRaw = object["runtimes"] as? [[String: Any]] else {
            return []
        }

        return runtimesRaw.compactMap { entry in
            guard let identifier = entry["identifier"] as? String else {
                return nil
            }
            let name = (entry["name"] as? String) ?? identifier
            let version = entry["version"] as? String
            let bundlePath = entry["bundlePath"] as? String
            let isAvailable = parseAvailability(entry["isAvailable"])
            return SimulatorRuntimeListingRecord(
                identifier: identifier,
                name: name,
                version: version,
                isAvailable: isAvailable,
                bundlePath: bundlePath
            )
        }
    }

    private func parseAvailability(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? String {
            let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "yes" || lowered == "true" || lowered == "available"
        }
        return false
    }
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProcessError.nonZeroExit(terminationStatus: process.terminationStatus)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

public enum ProcessError: Error {
    case nonZeroExit(terminationStatus: Int32)
}

private enum InfoPlistKeys {
    static let bundleDisplayName = "CFBundleDisplayName"
    static let bundleName = "CFBundleName"
    static let bundleIdentifier = "CFBundleIdentifier"
    static let shortVersion = "CFBundleShortVersionString"
    static let bundleVersion = "CFBundleVersion"
    static let xcodeBuild = "DTXcodeBuild"
}
