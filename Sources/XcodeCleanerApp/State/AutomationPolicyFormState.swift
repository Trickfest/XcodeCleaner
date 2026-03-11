import Foundation
import XcodeInventoryCore

struct AutomationPolicyFormState {
    var name = ""
    var everyHours = ""
    var minAgeDays = ""
    var minTotalBytes = ""
    var categoryKinds = Set(guiDefaultCleanupCategoryKinds)
    var skipIfToolsRunning = true
    var allowDirectDelete = false
    var validationError: String?

    mutating func makeCreationRequest() -> AutomationPolicyCreationRequest? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Policy name is required."
            return nil
        }

        let everyHoursResult = parsePositiveInt(from: everyHours)
        switch everyHoursResult {
        case .invalid:
            validationError = "Every hours must be a positive whole number."
            return nil
        case .none, .value:
            break
        }

        let minAgeDaysResult = parsePositiveInt(from: minAgeDays)
        switch minAgeDaysResult {
        case .invalid:
            validationError = "Minimum age days must be a positive whole number."
            return nil
        case .none, .value:
            break
        }

        let minBytesResult = parseNonNegativeInt64(from: minTotalBytes)
        switch minBytesResult {
        case .invalid:
            validationError = "Minimum reclaim bytes must be a non-negative whole number."
            return nil
        case .none, .value:
            break
        }

        validationError = nil
        let allowedCategoryKinds = categoryKinds
            .filter { $0 != .xcodeApplications && $0 != .deviceSupport }
            .sorted { $0.rawValue < $1.rawValue }

        return AutomationPolicyCreationRequest(
            name: trimmedName,
            categoryKinds: allowedCategoryKinds,
            everyHours: everyHoursResult.value,
            minAgeDays: minAgeDaysResult.value,
            minTotalReclaimBytes: minBytesResult.value,
            skipIfToolsRunning: skipIfToolsRunning,
            allowDirectDelete: allowDirectDelete
        )
    }

    mutating func resetAfterSubmit() {
        name = ""
        everyHours = ""
        minAgeDays = ""
        minTotalBytes = ""
    }
}

struct AutomationPolicyCreationRequest {
    let name: String
    let categoryKinds: [StorageCategoryKind]
    let everyHours: Int?
    let minAgeDays: Int?
    let minTotalReclaimBytes: Int64?
    let skipIfToolsRunning: Bool
    let allowDirectDelete: Bool
}

private enum ParsedIntResult<T> {
    case none
    case value(T)
    case invalid

    var value: T? {
        switch self {
        case .value(let value):
            return value
        case .none, .invalid:
            return nil
        }
    }
}

private func parsePositiveInt(from text: String) -> ParsedIntResult<Int> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return .none
    }
    guard let value = Int(trimmed), value > 0 else {
        return .invalid
    }
    return .value(value)
}

private func parseNonNegativeInt64(from text: String) -> ParsedIntResult<Int64> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return .none
    }
    guard let value = Int64(trimmed), value >= 0 else {
        return .invalid
    }
    return .value(value)
}
