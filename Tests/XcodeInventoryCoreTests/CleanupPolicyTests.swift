import Testing
@testable import XcodeInventoryCore

struct CleanupPolicyTests {
    @Test("Cleanup policies preserve current GUI and planning defaults")
    func defaultSelections() {
        #expect(Set(CleanupPolicies.defaultGUICategoryKinds) == Set([.derivedData, .archives]))
        #expect(Set(CleanupPolicies.defaultPlanningCategoryKinds) == Set([.derivedData, .archives, .deviceSupport]))
        #expect(Set(DryRunSelection.safeCategoryDefaults.selectedCategoryKinds) == Set([.derivedData, .archives, .deviceSupport]))
    }

    @Test("Cleanup policies preserve explicit opt-in counted cleanup components")
    func explicitOptInCountedComponents() {
        let expected: [CountedFootprintComponentKind] = [.documentationCache, .xcodeLogs, .coreSimulatorLogs]
        #expect(CleanupPolicies.explicitOptInCountedFootprintComponentKinds == expected)
        #expect(CountedFootprintComponentKind.explicitOptInCleanupKinds == expected)
    }

    @Test("Simulator Data policy describes mixed cleanup across CoreSimulator roots")
    func simulatorDataPolicy() {
        let policy = CleanupPolicies.policy(for: .simulatorData)

        #expect(policy.surface == .optional)
        #expect(policy.guardrail == .simulatorStopped)
        #expect(policy.deletionMechanism == .mixed)
        #expect(policy.cleanupDescription.contains("simulator devices"))
        #expect(policy.cleanupDescription.contains("temp"))
        #expect(policy.affectedRootsSummary.contains("~/Library/Developer/CoreSimulator"))
        #expect(policy.affectedRootsSummary.contains("/Library/Developer/CoreSimulator"))
        #expect(policy.affectedRootsSummary.contains("~/Library/Developer/CoreSimulator/Temp"))
    }

    @Test("Documentation Cache policy is explicit opt-in and Xcode-guarded")
    func documentationCachePolicy() {
        let policy = CleanupPolicies.policy(for: .documentationCache)

        #expect(policy.surface == .explicitOptIn)
        #expect(policy.guardrail == .xcodeStopped)
        #expect(policy.deletionMechanism == .filesystem)
        #expect(policy.affectedRootsSummary == "~/Library/Developer/Xcode/DocumentationCache")
    }

    @Test("Orphaned simulator runtimes remain report-only and manual cleanup")
    func orphanedRuntimePolicy() {
        let policy = CleanupPolicies.policy(for: .orphanedSimulatorRuntime)

        #expect(policy.surface == .reportOnly)
        #expect(policy.deletionMechanism == .manualOnly)
        #expect(policy.cleanupDescription.contains("manual cleanup"))
    }
}
