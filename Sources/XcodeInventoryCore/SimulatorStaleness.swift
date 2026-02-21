import Foundation

public enum SimulatorRuntimeStaleReason: String, Codable, CaseIterable, Sendable {
    case unavailable
    case unreferencedByAnyDevice
}

public enum SimulatorDeviceStaleReason: String, Codable, CaseIterable, Sendable {
    case unavailable
    case runtimeMissing
    case runtimeUnavailable
}

public enum SimulatorStaleness {
    public static func runtimeStaleReasons(
        for runtime: SimulatorRuntimeRecord,
        devices: [SimulatorDeviceRecord]
    ) -> [SimulatorRuntimeStaleReason] {
        var reasons: [SimulatorRuntimeStaleReason] = []
        let runtimeIDsInUse = Set(devices.map(\.runtimeIdentifier))

        if !runtime.isAvailable {
            reasons.append(.unavailable)
        }
        if !runtimeIDsInUse.contains(runtime.identifier) {
            reasons.append(.unreferencedByAnyDevice)
        }

        return reasons
    }

    public static func deviceStaleReasons(
        for device: SimulatorDeviceRecord,
        runtimes: [SimulatorRuntimeRecord]
    ) -> [SimulatorDeviceStaleReason] {
        let runtimeByIdentifier = Dictionary(
            uniqueKeysWithValues: runtimes.map { ($0.identifier, $0) }
        )
        return deviceStaleReasons(
            for: device,
            runtimeByIdentifier: runtimeByIdentifier
        )
    }

    public static func deviceStaleReasons(
        for device: SimulatorDeviceRecord,
        runtimeByIdentifier: [String: SimulatorRuntimeRecord]
    ) -> [SimulatorDeviceStaleReason] {
        var reasons: [SimulatorDeviceStaleReason] = []

        if !device.isAvailable {
            reasons.append(.unavailable)
        }

        guard let runtime = runtimeByIdentifier[device.runtimeIdentifier] else {
            reasons.append(.runtimeMissing)
            return reasons
        }

        if !runtime.isAvailable {
            reasons.append(.runtimeUnavailable)
        }

        return reasons
    }
}
