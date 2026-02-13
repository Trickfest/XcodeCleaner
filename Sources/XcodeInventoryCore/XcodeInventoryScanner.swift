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

public struct XcodeInventoryScanner {
    private let applicationDiscoverer: XcodeApplicationDiscovering
    private let activeDeveloperDirectoryProvider: ActiveDeveloperDirectoryProviding
    private let infoPlistReader: InfoPlistReading
    private let pathSizer: PathSizing
    private let homeDirectoryProvider: HomeDirectoryProviding
    private let now: () -> Date

    public init(
        applicationDiscoverer: XcodeApplicationDiscovering = SystemXcodeApplicationDiscoverer(),
        activeDeveloperDirectoryProvider: ActiveDeveloperDirectoryProviding = XcodeSelectActiveDeveloperDirectoryProvider(),
        infoPlistReader: InfoPlistReading = InfoPlistFileReader(),
        pathSizer: PathSizing = FileSystemPathSizer(),
        homeDirectoryProvider: HomeDirectoryProviding = CurrentUserHomeDirectoryProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.applicationDiscoverer = applicationDiscoverer
        self.activeDeveloperDirectoryProvider = activeDeveloperDirectoryProvider
        self.infoPlistReader = infoPlistReader
        self.pathSizer = pathSizer
        self.homeDirectoryProvider = homeDirectoryProvider
        self.now = now
    }

    public func scan() -> XcodeInventorySnapshot {
        let activeDeveloperDirectoryURL = activeDeveloperDirectoryProvider.activeDeveloperDirectoryURL()
        let activeDeveloperDirectoryPath = normalizedPath(for: activeDeveloperDirectoryURL)

        let installs = deduplicatedApplicationURLs(from: applicationDiscoverer.discoverXcodeApplicationURLs())
            .map { appURL -> XcodeInstall in
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
                    sizeInBytes: pathSizer.allocatedSize(at: appURL)
                )
            }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive
                }
                if lhs.displayName != rhs.displayName {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }

        let storage = buildStorageUsage(installs: installs)

        return XcodeInventorySnapshot(
            scannedAt: now(),
            activeDeveloperDirectoryPath: activeDeveloperDirectoryPath,
            installs: installs,
            storage: storage
        )
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
                paths: installs.map { URL(filePath: $0.path, directoryHint: .isDirectory) }
            ),
            makeCategory(
                kind: .derivedData,
                title: "Derived Data",
                paths: [homeDirectoryURL.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)]
            ),
            makeCategory(
                kind: .archives,
                title: "Archives",
                paths: [homeDirectoryURL.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)]
            ),
            makeCategory(
                kind: .deviceSupport,
                title: "Device Support",
                paths: [homeDirectoryURL.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)]
            ),
            makeCategory(
                kind: .simulatorData,
                title: "Simulator Data",
                paths: simulatorPaths
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

    private func makeCategory(kind: StorageCategoryKind, title: String, paths: [URL]) -> StorageCategoryUsage {
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

        return StorageCategoryUsage(kind: kind, title: title, bytes: bytes, paths: existingPaths)
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
