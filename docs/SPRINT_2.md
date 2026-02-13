# Sprint 2 Plan and Exit Gate

## Sprint Goal
Deliver read-only storage accounting so users can see where Xcode-related disk usage is concentrated.

## Scope
- Storage categories in shared core model and scanner.
- Category totals for:
- Xcode applications.
- DerivedData.
- Archives.
- iOS DeviceSupport.
- Simulator data.
- GUI updates to show totals and category details.
- CLI updates to expose the same storage model in JSON.
- Fixture-based tests for category bytes and total aggregation.

## Deliverables
- Extended `XcodeInventorySnapshot` with storage usage model.
- Shared scanner logic for category-level byte accounting.
- `XcodeCleanerApp` storage overview section.
- `xcodecleaner-cli` parity output for storage usage.
- Automated tests validating category totals and ordering.

## Exit Criteria
- Scanner remains read-only and does not modify filesystem state.
- Category totals are deterministic in fixtures.
- Grand total matches sum of categories.
- GUI and CLI show consistent values for inventory and storage.
- Tests pass with workspace cache overrides.

## Out of Scope
- Ownership attribution and safety classification.
- Cleanup execution, trashing, or deletion.
- Automation and scheduling.

## Demo Script
1. Run `xcodecleaner-cli` and inspect storage category bytes and total.
2. Open `XcodeCleanerApp` and verify category ordering by largest usage first.
3. Run the test suite and validate scanner storage tests pass.
