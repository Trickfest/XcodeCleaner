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
    case mobileDeviceCrashLogs
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

public enum CountedFootprintComponentKind: String, Codable, CaseIterable, Sendable {
    case documentationCache
    case developerPackages
    case xcodeLogs
    case coreSimulatorLogs
    case dvtDownloads
    case xcpgDevices
    case xcTestDevices
    case additionalXcodeState

    public static var explicitOptInCleanupKinds: [CountedFootprintComponentKind] {
        CleanupPolicies.explicitOptInCountedFootprintComponentKinds
    }
}

public struct CountedFootprintComponentUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: CountedFootprintComponentKind { kind }

    public let kind: CountedFootprintComponentKind
    public let title: String
    public let bytes: Int64
    public let paths: [String]
    public let ownershipSummary: String

    public init(
        kind: CountedFootprintComponentKind,
        title: String,
        bytes: Int64,
        paths: [String],
        ownershipSummary: String
    ) {
        self.kind = kind
        self.title = title
        self.bytes = bytes
        self.paths = paths
        self.ownershipSummary = ownershipSummary
    }
}

public struct PhysicalDeviceSupportDirectoryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }

    public let name: String
    public let path: String
    public let sizeInBytes: Int64
    public let modifiedAt: Date?
    public let parsedOSVersion: String?
    public let parsedBuild: String?
    public let parsedDescriptor: String?

    public init(
        name: String,
        path: String,
        sizeInBytes: Int64,
        modifiedAt: Date?,
        parsedOSVersion: String?,
        parsedBuild: String?,
        parsedDescriptor: String?
    ) {
        self.name = name
        self.path = path
        self.sizeInBytes = sizeInBytes
        self.modifiedAt = modifiedAt
        self.parsedOSVersion = parsedOSVersion
        self.parsedBuild = parsedBuild
        self.parsedDescriptor = parsedDescriptor
    }
}

public struct SimulatorRuntimeRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { identifier }

    public let identifier: String
    public let deleteIdentifier: String?
    public let name: String
    public let version: String?
    public let isAvailable: Bool
    public let bundlePath: String?
    public let sizeInBytes: Int64
    public let ownershipSummary: String
    public let safetyClassification: SafetyClassification

    public init(
        identifier: String,
        deleteIdentifier: String? = nil,
        name: String,
        version: String?,
        isAvailable: Bool,
        bundlePath: String?,
        sizeInBytes: Int64,
        ownershipSummary: String,
        safetyClassification: SafetyClassification
    ) {
        self.identifier = identifier
        self.deleteIdentifier = deleteIdentifier
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
    public let countedOnlyComponents: [CountedFootprintComponentUsage]
    public let totalBytes: Int64

    public init(
        categories: [StorageCategoryUsage],
        countedOnlyComponents: [CountedFootprintComponentUsage] = [],
        totalBytes: Int64
    ) {
        self.categories = categories
        self.countedOnlyComponents = countedOnlyComponents
        self.totalBytes = totalBytes
    }

    private enum CodingKeys: String, CodingKey {
        case categories
        case countedOnlyComponents
        case totalBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            categories: try container.decode([StorageCategoryUsage].self, forKey: .categories),
            countedOnlyComponents: try container.decodeIfPresent([CountedFootprintComponentUsage].self, forKey: .countedOnlyComponents) ?? [],
            totalBytes: try container.decode(Int64.self, forKey: .totalBytes)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categories, forKey: .categories)
        try container.encode(countedOnlyComponents, forKey: .countedOnlyComponents)
        try container.encode(totalBytes, forKey: .totalBytes)
    }
}

public struct XcodeInventorySnapshot: Codable, Equatable, Sendable {
    public let scannedAt: Date
    public let activeDeveloperDirectoryPath: String?
    public let installs: [XcodeInstall]
    public let storage: XcodeStorageUsage
    public let physicalDeviceSupportDirectories: [PhysicalDeviceSupportDirectoryRecord]
    public let simulator: SimulatorInventory
    public let runtimeTelemetry: RuntimeTelemetry

    public init(
        scannedAt: Date,
        activeDeveloperDirectoryPath: String?,
        installs: [XcodeInstall],
        storage: XcodeStorageUsage,
        physicalDeviceSupportDirectories: [PhysicalDeviceSupportDirectoryRecord] = [],
        simulator: SimulatorInventory,
        runtimeTelemetry: RuntimeTelemetry
    ) {
        self.scannedAt = scannedAt
        self.activeDeveloperDirectoryPath = activeDeveloperDirectoryPath
        self.installs = installs
        self.storage = storage
        self.physicalDeviceSupportDirectories = physicalDeviceSupportDirectories
        self.simulator = simulator
        self.runtimeTelemetry = runtimeTelemetry
    }
}

public struct DryRunSelection: Codable, Equatable, Sendable {
    public let selectedCategoryKinds: [StorageCategoryKind]
    public let selectedCountedFootprintComponentKinds: [CountedFootprintComponentKind]
    public let selectedSimulatorDeviceUDIDs: [String]
    public let selectedSimulatorRuntimeIdentifiers: [String]
    public let selectedPhysicalDeviceSupportDirectoryPaths: [String]
    public let selectedXcodeInstallPaths: [String]

    public init(
        selectedCategoryKinds: [StorageCategoryKind],
        selectedCountedFootprintComponentKinds: [CountedFootprintComponentKind] = [],
        selectedSimulatorDeviceUDIDs: [String],
        selectedSimulatorRuntimeIdentifiers: [String] = [],
        selectedPhysicalDeviceSupportDirectoryPaths: [String] = [],
        selectedXcodeInstallPaths: [String] = []
    ) {
        self.selectedCategoryKinds = Array(Set(selectedCategoryKinds)).sorted {
            $0.rawValue < $1.rawValue
        }
        self.selectedCountedFootprintComponentKinds = Array(Set(selectedCountedFootprintComponentKinds)).sorted {
            $0.rawValue < $1.rawValue
        }
        self.selectedSimulatorDeviceUDIDs = Array(Set(selectedSimulatorDeviceUDIDs)).sorted()
        self.selectedSimulatorRuntimeIdentifiers = Array(Set(selectedSimulatorRuntimeIdentifiers)).sorted()
        self.selectedPhysicalDeviceSupportDirectoryPaths = Array(
            Set(selectedPhysicalDeviceSupportDirectoryPaths.map {
                URL(filePath: $0).standardizedFileURL.resolvingSymlinksInPath().path
            })
        )
        .sorted()
        self.selectedXcodeInstallPaths = Array(Set(selectedXcodeInstallPaths)).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case selectedCategoryKinds
        case selectedCountedFootprintComponentKinds
        case selectedSimulatorDeviceUDIDs
        case selectedSimulatorRuntimeIdentifiers
        case selectedPhysicalDeviceSupportDirectoryPaths
        case selectedXcodeInstallPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedCategoryKinds: try container.decode([StorageCategoryKind].self, forKey: .selectedCategoryKinds),
            selectedCountedFootprintComponentKinds: try container.decodeIfPresent([CountedFootprintComponentKind].self, forKey: .selectedCountedFootprintComponentKinds) ?? [],
            selectedSimulatorDeviceUDIDs: try container.decode([String].self, forKey: .selectedSimulatorDeviceUDIDs),
            selectedSimulatorRuntimeIdentifiers: try container.decodeIfPresent([String].self, forKey: .selectedSimulatorRuntimeIdentifiers) ?? [],
            selectedPhysicalDeviceSupportDirectoryPaths: try container.decodeIfPresent([String].self, forKey: .selectedPhysicalDeviceSupportDirectoryPaths) ?? [],
            selectedXcodeInstallPaths: try container.decodeIfPresent([String].self, forKey: .selectedXcodeInstallPaths) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedCategoryKinds, forKey: .selectedCategoryKinds)
        try container.encode(selectedCountedFootprintComponentKinds, forKey: .selectedCountedFootprintComponentKinds)
        try container.encode(selectedSimulatorDeviceUDIDs, forKey: .selectedSimulatorDeviceUDIDs)
        try container.encode(selectedSimulatorRuntimeIdentifiers, forKey: .selectedSimulatorRuntimeIdentifiers)
        try container.encode(selectedPhysicalDeviceSupportDirectoryPaths, forKey: .selectedPhysicalDeviceSupportDirectoryPaths)
        try container.encode(selectedXcodeInstallPaths, forKey: .selectedXcodeInstallPaths)
    }

    public static let safeCategoryDefaults = DryRunSelection(
        selectedCategoryKinds: CleanupPolicies.defaultPlanningCategoryKinds,
        selectedSimulatorDeviceUDIDs: [],
        selectedSimulatorRuntimeIdentifiers: [],
        selectedPhysicalDeviceSupportDirectoryPaths: [],
        selectedXcodeInstallPaths: []
    )
}

public enum DryRunItemKind: String, Codable, Sendable {
    case storageCategory
    case countedFootprintComponent
    case simulatorDevice
    case simulatorRuntime
    case deviceSupportDirectory
    case xcodeInstall
    case staleSimulatorDevice
    case staleSimulatorRuntime
}

public struct DryRunPlanItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(kind.rawValue):\(title)" }

    public let kind: DryRunItemKind
    public let storageCategoryKind: StorageCategoryKind?
    public let countedFootprintComponentKind: CountedFootprintComponentKind?
    public let staleArtifactID: String?
    public let staleArtifactKind: StaleArtifactKind?
    public let title: String
    public let reclaimableBytes: Int64
    public let paths: [String]
    public let ownershipSummary: String
    public let safetyClassification: SafetyClassification

    public init(
        kind: DryRunItemKind,
        storageCategoryKind: StorageCategoryKind? = nil,
        countedFootprintComponentKind: CountedFootprintComponentKind? = nil,
        staleArtifactID: String? = nil,
        staleArtifactKind: StaleArtifactKind? = nil,
        title: String,
        reclaimableBytes: Int64,
        paths: [String],
        ownershipSummary: String,
        safetyClassification: SafetyClassification
    ) {
        self.kind = kind
        self.storageCategoryKind = storageCategoryKind
        self.countedFootprintComponentKind = countedFootprintComponentKind
        self.staleArtifactID = staleArtifactID
        self.staleArtifactKind = staleArtifactKind
        self.title = title
        self.reclaimableBytes = reclaimableBytes
        self.paths = paths
        self.ownershipSummary = ownershipSummary
        self.safetyClassification = safetyClassification
    }
}

public struct DryRunPlan: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let selection: DryRunSelection
    public let items: [DryRunPlanItem]
    public let totalReclaimableBytes: Int64
    public let notes: [String]

    public init(
        generatedAt: Date,
        selection: DryRunSelection,
        items: [DryRunPlanItem],
        totalReclaimableBytes: Int64,
        notes: [String]
    ) {
        self.generatedAt = generatedAt
        self.selection = selection
        self.items = items
        self.totalReclaimableBytes = totalReclaimableBytes
        self.notes = notes
    }
}

public enum CleanupActionStatus: String, Codable, Sendable {
    case succeeded
    case partiallySucceeded
    case blocked
    case failed
}

public enum CleanupOperation: String, Codable, Sendable {
    case moveToTrash
    case directDelete
    case simctlDelete
    case mixed
    case none
}

public enum CleanupPathStatus: String, Codable, Sendable {
    case succeeded
    case blocked
    case failed
    case skippedMissing
    case skippedNoReclaim
}

public struct CleanupPathResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }

    public let path: String
    public let status: CleanupPathStatus
    public let operation: CleanupOperation
    public let reclaimedBytes: Int64
    public let message: String

    public init(
        path: String,
        status: CleanupPathStatus,
        operation: CleanupOperation,
        reclaimedBytes: Int64,
        message: String
    ) {
        self.path = path
        self.status = status
        self.operation = operation
        self.reclaimedBytes = reclaimedBytes
        self.message = message
    }
}

public struct CleanupActionResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String { item.id }

    public let item: DryRunPlanItem
    public let status: CleanupActionStatus
    public let operation: CleanupOperation
    public let reclaimedBytes: Int64
    public let message: String
    public let pathResults: [CleanupPathResult]
    public let recordedAt: Date

    public init(
        item: DryRunPlanItem,
        status: CleanupActionStatus,
        operation: CleanupOperation,
        reclaimedBytes: Int64,
        message: String,
        pathResults: [CleanupPathResult],
        recordedAt: Date
    ) {
        self.item = item
        self.status = status
        self.operation = operation
        self.reclaimedBytes = reclaimedBytes
        self.message = message
        self.pathResults = pathResults
        self.recordedAt = recordedAt
    }
}

public struct CleanupExecutionReport: Codable, Equatable, Sendable {
    public let executedAt: Date
    public let allowDirectDelete: Bool
    public let skippedReason: String?
    public let selection: DryRunSelection
    public let plan: DryRunPlan
    public let results: [CleanupActionResult]
    public let totalReclaimedBytes: Int64
    public let succeededCount: Int
    public let partiallySucceededCount: Int
    public let blockedCount: Int
    public let failedCount: Int

    public init(
        executedAt: Date,
        allowDirectDelete: Bool,
        skippedReason: String? = nil,
        selection: DryRunSelection,
        plan: DryRunPlan,
        results: [CleanupActionResult],
        totalReclaimedBytes: Int64,
        succeededCount: Int,
        partiallySucceededCount: Int,
        blockedCount: Int,
        failedCount: Int
    ) {
        self.executedAt = executedAt
        self.allowDirectDelete = allowDirectDelete
        self.skippedReason = skippedReason
        self.selection = selection
        self.plan = plan
        self.results = results
        self.totalReclaimedBytes = totalReclaimedBytes
        self.succeededCount = succeededCount
        self.partiallySucceededCount = partiallySucceededCount
        self.blockedCount = blockedCount
        self.failedCount = failedCount
    }
}

public enum StaleArtifactKind: String, Codable, Sendable {
    case simulatorRuntime
    case orphanedSimulatorRuntime
    case orphanedSimulatorDevice
}

public struct StaleArtifactCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public let kind: StaleArtifactKind
    public let title: String
    public let path: String
    public let reclaimableBytes: Int64
    public let reason: String
    public let safetyClassification: SafetyClassification

    public init(
        id: String,
        kind: StaleArtifactKind,
        title: String,
        path: String,
        reclaimableBytes: Int64,
        reason: String,
        safetyClassification: SafetyClassification
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.path = path
        self.reclaimableBytes = reclaimableBytes
        self.reason = reason
        self.safetyClassification = safetyClassification
    }
}

public struct StaleArtifactReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let candidates: [StaleArtifactCandidate]
    public let totalReclaimableBytes: Int64
    public let notes: [String]

    public init(
        generatedAt: Date,
        candidates: [StaleArtifactCandidate],
        totalReclaimableBytes: Int64,
        notes: [String]
    ) {
        self.generatedAt = generatedAt
        self.candidates = candidates
        self.totalReclaimableBytes = totalReclaimableBytes
        self.notes = notes
    }
}

public enum ActiveXcodeSwitchStatus: String, Codable, Sendable {
    case succeeded
    case blocked
    case failed
}

public struct ActiveXcodeSwitchResult: Codable, Equatable, Sendable {
    public let requestedInstallPath: String
    public let requestedDeveloperDirectoryPath: String?
    public let previousActiveDeveloperDirectoryPath: String?
    public let newActiveDeveloperDirectoryPath: String?
    public let status: ActiveXcodeSwitchStatus
    public let message: String
    public let recordedAt: Date

    public init(
        requestedInstallPath: String,
        requestedDeveloperDirectoryPath: String?,
        previousActiveDeveloperDirectoryPath: String?,
        newActiveDeveloperDirectoryPath: String?,
        status: ActiveXcodeSwitchStatus,
        message: String,
        recordedAt: Date
    ) {
        self.requestedInstallPath = requestedInstallPath
        self.requestedDeveloperDirectoryPath = requestedDeveloperDirectoryPath
        self.previousActiveDeveloperDirectoryPath = previousActiveDeveloperDirectoryPath
        self.newActiveDeveloperDirectoryPath = newActiveDeveloperDirectoryPath
        self.status = status
        self.message = message
        self.recordedAt = recordedAt
    }
}
