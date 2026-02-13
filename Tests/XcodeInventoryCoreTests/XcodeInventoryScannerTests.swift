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
            ]),
            homeDirectoryProvider: StubHomeDirectoryProvider(url: fakeHome),
            now: { Date(timeIntervalSince1970: 42) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.installs.count == 2)
        #expect(snapshot.activeDeveloperDirectoryPath == activeDeveloperDirectory.path)
        #expect(snapshot.installs.filter(\.isActive).count == 1)
        #expect(snapshot.installs.first?.displayName == "Xcode-16.1-beta")
        #expect(snapshot.installs.first?.version == "16.1")
        #expect(snapshot.installs.first?.build == "16B500")
        #expect(snapshot.installs.first?.sizeInBytes == 2_000)
        #expect(snapshot.storage.totalBytes == 6_300)
        #expect(snapshot.storage.categories.count == 5)
        #expect(snapshot.storage.categories[0].kind == .xcodeApplications)
        #expect(snapshot.storage.categories[0].bytes == 3_000)
        #expect(snapshot.storage.categories[1].kind == .simulatorData)
        #expect(snapshot.storage.categories[1].bytes == 2_100)
        #expect(bytes(for: .deviceSupport, in: snapshot) == 500)
        #expect(bytes(for: .archives, in: snapshot) == 400)
        #expect(bytes(for: .derivedData, in: snapshot) == 300)
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
            now: { Date(timeIntervalSince1970: 99) }
        )

        let snapshot = scanner.scan()

        #expect(snapshot.installs.count == 1)
        #expect(snapshot.installs[0].build == "15F31d")
        #expect(snapshot.installs[0].version == "15.4")
        #expect(snapshot.installs[0].sizeInBytes == 512)
        #expect(bytes(for: .xcodeApplications, in: snapshot) == 512)
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
