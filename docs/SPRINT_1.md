# Sprint 1 Plan and Exit Gate

## Sprint Goal
Deliver a read-only, testable inventory experience that identifies installed Xcode apps and active selection.

## Scope
- App shell in SwiftUI for macOS.
- Core scanner module for installed Xcode discovery.
- Active developer directory detection.
- CLI for machine-readable inventory output.
- Unit tests for multi-install behavior.

## Deliverables
- `XcodeInventoryCore` module.
- `XcodeCleanerApp` executable target.
- `xcodecleaner-cli` executable target.
- Automated test coverage for scanner rules.

## Exit Criteria
- Scanner deduplicates installs and reports versions/builds/paths.
- Active install is correctly marked from `xcode-select -p`.
- CLI emits valid JSON snapshot.
- GUI and CLI outputs are consistent for install count, active selection, and metadata values.
- Tests pass in CI/local with workspace cache overrides.

## Out of Scope
- Disk category scanning (DerivedData, Archives, DeviceSupport, etc.).
- Cleanup execution and safety workflows.
- Scheduling/automation policies.

## Demo Script
1. Run `xcodecleaner-cli` and confirm JSON inventory.
2. Open `XcodeCleanerApp` and verify install list + active badge.
3. Run test suite and verify scanner fixture tests pass.
