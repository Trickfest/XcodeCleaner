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

public struct XcodeInventoryScanner {
    private let applicationDiscoverer: XcodeApplicationDiscovering
    private let activeDeveloperDirectoryProvider: ActiveDeveloperDirectoryProviding
    private let infoPlistReader: InfoPlistReading
    private let now: () -> Date

    public init(
        applicationDiscoverer: XcodeApplicationDiscovering = SystemXcodeApplicationDiscoverer(),
        activeDeveloperDirectoryProvider: ActiveDeveloperDirectoryProviding = XcodeSelectActiveDeveloperDirectoryProvider(),
        infoPlistReader: InfoPlistReading = InfoPlistFileReader(),
        now: @escaping () -> Date = Date.init
    ) {
        self.applicationDiscoverer = applicationDiscoverer
        self.activeDeveloperDirectoryProvider = activeDeveloperDirectoryProvider
        self.infoPlistReader = infoPlistReader
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
                    )
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

        return XcodeInventorySnapshot(
            scannedAt: now(),
            activeDeveloperDirectoryPath: activeDeveloperDirectoryPath,
            installs: installs
        )
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
