import Foundation

public enum ScanPhase: String, Codable, CaseIterable, Sendable {
    case discoveringXcodeInstalls
    case sizingXcodeInstalls
    case sizingStorageCategories
    case loadingSimulatorListing
    case buildingSimulatorInventory
    case computingRuntimeTelemetry
    case finalizingSnapshot

    public var title: String {
        switch self {
        case .discoveringXcodeInstalls:
            return "Discovering Xcode Installs"
        case .sizingXcodeInstalls:
            return "Sizing Xcode Installs"
        case .sizingStorageCategories:
            return "Sizing Storage Categories"
        case .loadingSimulatorListing:
            return "Loading Simulator Listing"
        case .buildingSimulatorInventory:
            return "Building Simulator Inventory"
        case .computingRuntimeTelemetry:
            return "Computing Runtime Telemetry"
        case .finalizingSnapshot:
            return "Finalizing Snapshot"
        }
    }
}

public struct ScanProgress: Equatable, Sendable {
    public let phase: ScanPhase
    public let fractionCompleted: Double
    public let message: String

    public init(phase: ScanPhase, fractionCompleted: Double, message: String) {
        self.phase = phase
        self.fractionCompleted = min(1, max(0, fractionCompleted))
        self.message = message
    }
}

public enum SafetyClassification: String, Codable, Sendable {
    case regenerable
    case conditionallySafe
    case destructive
}

public struct XcodeInstall: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }

    public let displayName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let build: String?
    public let path: String
    public let developerDirectoryPath: String
    public let isActive: Bool
    public let runningInstanceCount: Int
    public let sizeInBytes: Int64
    public let ownershipSummary: String
    public let safetyClassification: SafetyClassification

    public init(
        displayName: String,
        bundleIdentifier: String?,
        version: String?,
        build: String?,
        path: String,
        developerDirectoryPath: String,
        isActive: Bool,
        runningInstanceCount: Int,
        sizeInBytes: Int64,
        ownershipSummary: String,
        safetyClassification: SafetyClassification
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.path = path
        self.developerDirectoryPath = developerDirectoryPath
        self.isActive = isActive
        self.runningInstanceCount = runningInstanceCount
        self.sizeInBytes = sizeInBytes
        self.ownershipSummary = ownershipSummary
        self.safetyClassification = safetyClassification
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
    public let ownershipSummary: String
    public let safetyClassification: SafetyClassification

    public init(
        kind: StorageCategoryKind,
        title: String,
        bytes: Int64,
        paths: [String],
        ownershipSummary: String,
        safetyClassification: SafetyClassification
    ) {
        self.kind = kind
        self.title = title
        self.bytes = bytes
        self.paths = paths
        self.ownershipSummary = ownershipSummary
        self.safetyClassification = safetyClassification
    }
}

public struct SimulatorRuntimeRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { identifier }

    public let identifier: String
    public let name: String
    public let version: String?
    public let isAvailable: Bool
    public let bundlePath: String?
    public let sizeInBytes: Int64
    public let ownershipSummary: String
    public let safetyClassification: SafetyClassification

    public init(
        identifier: String,
        name: String,
        version: String?,
        isAvailable: Bool,
        bundlePath: String?,
        sizeInBytes: Int64,
        ownershipSummary: String,
        safetyClassification: SafetyClassification
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.isAvailable = isAvailable
        self.bundlePath = bundlePath
        self.sizeInBytes = sizeInBytes
        self.ownershipSummary = ownershipSummary
        self.safetyClassification = safetyClassification
    }
}

public struct SimulatorDeviceRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { udid }

    public let udid: String
    public let name: String
    public let runtimeIdentifier: String
    public let runtimeName: String?
    public let state: String
    public let isAvailable: Bool
    public let dataPath: String
    public let sizeInBytes: Int64
    public let runningInstanceCount: Int
    public let ownershipSummary: String
    public let safetyClassification: SafetyClassification

    public init(
        udid: String,
        name: String,
        runtimeIdentifier: String,
        runtimeName: String?,
        state: String,
        isAvailable: Bool,
        dataPath: String,
        sizeInBytes: Int64,
        runningInstanceCount: Int,
        ownershipSummary: String,
        safetyClassification: SafetyClassification
    ) {
        self.udid = udid
        self.name = name
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeName = runtimeName
        self.state = state
        self.isAvailable = isAvailable
        self.dataPath = dataPath
        self.sizeInBytes = sizeInBytes
        self.runningInstanceCount = runningInstanceCount
        self.ownershipSummary = ownershipSummary
        self.safetyClassification = safetyClassification
    }
}

public struct SimulatorInventory: Codable, Equatable, Sendable {
    public let devices: [SimulatorDeviceRecord]
    public let runtimes: [SimulatorRuntimeRecord]

    public init(devices: [SimulatorDeviceRecord], runtimes: [SimulatorRuntimeRecord]) {
        self.devices = devices
        self.runtimes = runtimes
    }
}

public struct RuntimeTelemetry: Codable, Equatable, Sendable {
    public let totalXcodeRunningInstances: Int
    public let totalSimulatorAppRunningInstances: Int

    public init(totalXcodeRunningInstances: Int, totalSimulatorAppRunningInstances: Int) {
        self.totalXcodeRunningInstances = totalXcodeRunningInstances
        self.totalSimulatorAppRunningInstances = totalSimulatorAppRunningInstances
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
    public let simulator: SimulatorInventory
    public let runtimeTelemetry: RuntimeTelemetry

    public init(
        scannedAt: Date,
        activeDeveloperDirectoryPath: String?,
        installs: [XcodeInstall],
        storage: XcodeStorageUsage,
        simulator: SimulatorInventory,
        runtimeTelemetry: RuntimeTelemetry
    ) {
        self.scannedAt = scannedAt
        self.activeDeveloperDirectoryPath = activeDeveloperDirectoryPath
        self.installs = installs
        self.storage = storage
        self.simulator = simulator
        self.runtimeTelemetry = runtimeTelemetry
    }
}
