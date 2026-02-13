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

        let scanner = XcodeInventoryScanner(
            applicationDiscoverer: StubDiscoverer(urls: [xcode16, xcode16, xcodeBeta]),
            activeDeveloperDirectoryProvider: StubActiveDeveloperProvider(url: activeDeveloperDirectory),
            now: { Date(timeIntervalSince1970: 42) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.installs.count == 2)
        #expect(snapshot.activeDeveloperDirectoryPath == activeDeveloperDirectory.path)
        #expect(snapshot.installs.filter(\.isActive).count == 1)
        #expect(snapshot.installs.first?.displayName == "Xcode-16.1-beta")
        #expect(snapshot.installs.first?.version == "16.1")
        #expect(snapshot.installs.first?.build == "16B500")
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
            now: { Date(timeIntervalSince1970: 99) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.installs.count == 1)
        #expect(snapshot.installs[0].build == "15F31d")
        #expect(snapshot.installs[0].version == "15.4")
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
