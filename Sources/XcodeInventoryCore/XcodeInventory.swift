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
    public let sizeInBytes: Int64

    public init(
        displayName: String,
        bundleIdentifier: String?,
        version: String?,
        build: String?,
        path: String,
        developerDirectoryPath: String,
        isActive: Bool,
        sizeInBytes: Int64
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.path = path
        self.developerDirectoryPath = developerDirectoryPath
        self.isActive = isActive
        self.sizeInBytes = sizeInBytes
    }
}

public enum StorageCategoryKind: String, Codable, CaseIterable, Sendable {
    case xcodeApplications
    case derivedData
    case archives
    case deviceSupport
    case simulatorData
}

public struct StorageCategoryUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: StorageCategoryKind { kind }

    public let kind: StorageCategoryKind
    public let title: String
    public let bytes: Int64
    public let paths: [String]

    public init(kind: StorageCategoryKind, title: String, bytes: Int64, paths: [String]) {
        self.kind = kind
        self.title = title
        self.bytes = bytes
        self.paths = paths
    }
}

public struct XcodeStorageUsage: Codable, Equatable, Sendable {
    public let categories: [StorageCategoryUsage]
    public let totalBytes: Int64

    public init(categories: [StorageCategoryUsage], totalBytes: Int64) {
        self.categories = categories
        self.totalBytes = totalBytes
    }
}

public struct XcodeInventorySnapshot: Codable, Equatable, Sendable {
    public let scannedAt: Date
    public let activeDeveloperDirectoryPath: String?
    public let installs: [XcodeInstall]
    public let storage: XcodeStorageUsage

    public init(
        scannedAt: Date,
        activeDeveloperDirectoryPath: String?,
        installs: [XcodeInstall],
        storage: XcodeStorageUsage
    ) {
        self.scannedAt = scannedAt
        self.activeDeveloperDirectoryPath = activeDeveloperDirectoryPath
        self.installs = installs
        self.storage = storage
    }
}
