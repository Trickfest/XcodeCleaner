import Foundation
import Testing
@testable import XcodeInventoryCore

struct SimulatorStalenessTests {
    @Test("Runtime stale reasons include unreferenced when runtime is not used by devices")
    func runtimeStaleWhenUnreferenced() {
        let runtime = makeRuntime(identifier: "runtime-18", isAvailable: true)
        let devices = [
            makeDevice(udid: "SIM-1", runtimeIdentifier: "runtime-17", isAvailable: true)
        ]

        let reasons = SimulatorStaleness.runtimeStaleReasons(for: runtime, devices: devices)

        #expect(reasons == [.unreferencedByAnyDevice])
    }

    @Test("Runtime stale reasons include unavailable and unreferenced when both apply")
    func runtimeStaleWhenUnavailableAndUnreferenced() {
        let runtime = makeRuntime(identifier: "runtime-18", isAvailable: false)
        let devices = [
            makeDevice(udid: "SIM-1", runtimeIdentifier: "runtime-17", isAvailable: true)
        ]

        let reasons = SimulatorStaleness.runtimeStaleReasons(for: runtime, devices: devices)

        #expect(reasons == [.unavailable, .unreferencedByAnyDevice])
    }

    @Test("Runtime has no stale reasons when available and referenced by a device")
    func runtimeNotStaleWhenAvailableAndReferenced() {
        let runtime = makeRuntime(identifier: "runtime-18", isAvailable: true)
        let devices = [
            makeDevice(udid: "SIM-1", runtimeIdentifier: "runtime-18", isAvailable: true)
        ]

        let reasons = SimulatorStaleness.runtimeStaleReasons(for: runtime, devices: devices)

        #expect(reasons.isEmpty)
    }

    @Test("Device stale reasons include unavailable and runtime missing when both apply")
    func deviceStaleWhenUnavailableAndRuntimeMissing() {
        let device = makeDevice(udid: "SIM-1", runtimeIdentifier: "runtime-18", isAvailable: false)

        let reasons = SimulatorStaleness.deviceStaleReasons(for: device, runtimes: [])

        #expect(reasons == [.unavailable, .runtimeMissing])
    }

    @Test("Device stale reasons include runtime unavailable when runtime exists but unavailable")
    func deviceStaleWhenRuntimeUnavailable() {
        let device = makeDevice(udid: "SIM-1", runtimeIdentifier: "runtime-18", isAvailable: true)
        let runtimes = [
            makeRuntime(identifier: "runtime-18", isAvailable: false)
        ]

        let reasons = SimulatorStaleness.deviceStaleReasons(for: device, runtimes: runtimes)

        #expect(reasons == [.runtimeUnavailable])
    }

    @Test("Device has no stale reasons when available and runtime is available")
    func deviceNotStaleWhenAvailableAndRuntimeAvailable() {
        let device = makeDevice(udid: "SIM-1", runtimeIdentifier: "runtime-18", isAvailable: true)
        let runtimes = [
            makeRuntime(identifier: "runtime-18", isAvailable: true)
        ]

        let reasons = SimulatorStaleness.deviceStaleReasons(for: device, runtimes: runtimes)

        #expect(reasons.isEmpty)
    }
}

private func makeRuntime(identifier: String, isAvailable: Bool) -> SimulatorRuntimeRecord {
    SimulatorRuntimeRecord(
        identifier: identifier,
        name: identifier,
        version: "1.0",
        isAvailable: isAvailable,
        bundlePath: "/tmp/\(identifier).simruntime",
        sizeInBytes: 100,
        ownershipSummary: "Owned by runtime files",
        safetyClassification: .conditionallySafe
    )
}

private func makeDevice(udid: String, runtimeIdentifier: String, isAvailable: Bool) -> SimulatorDeviceRecord {
    SimulatorDeviceRecord(
        udid: udid,
        name: "Test Device",
        runtimeIdentifier: runtimeIdentifier,
        runtimeName: nil,
        state: "Shutdown",
        isAvailable: isAvailable,
        dataPath: "/tmp/Devices/\(udid)",
        sizeInBytes: 10,
        runningInstanceCount: 0,
        ownershipSummary: "Owned by device data",
        safetyClassification: .conditionallySafe
    )
}
