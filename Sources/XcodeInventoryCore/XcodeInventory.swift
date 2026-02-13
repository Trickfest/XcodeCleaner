import Foundation

public struct XcodeInstall: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }

    public let displayName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let build: String?
    public let path: String
    public let developerDirectoryPath: String
    public let isActive: Bool

    public init(
        displayName: String,
        bundleIdentifier: String?,
        version: String?,
        build: String?,
        path: String,
        developerDirectoryPath: String,
        isActive: Bool
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.path = path
        self.developerDirectoryPath = developerDirectoryPath
        self.isActive = isActive
    }
}

public struct XcodeInventorySnapshot: Codable, Equatable, Sendable {
    public let scannedAt: Date
    public let activeDeveloperDirectoryPath: String?
    public let installs: [XcodeInstall]

    public init(scannedAt: Date, activeDeveloperDirectoryPath: String?, installs: [XcodeInstall]) {
        self.scannedAt = scannedAt
        self.activeDeveloperDirectoryPath = activeDeveloperDirectoryPath
        self.installs = installs
    }
}
