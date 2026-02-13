# Sprint 3 Plan and Exit Gate

## Sprint Goal
Add itemized simulator visibility and ownership/safety context so users can decide exactly what to clean.

## Scope
- Ownership attribution for scanned artifacts.
- Temporary/non-temporary safety classification.
- Runtime telemetry:
- Per Xcode install running indicator and instance count.
- Per simulator device running/booted indicator and instance count.
- Itemized simulator inventory:
- Per simulator device listing.
- Per simulator runtime listing.
- Per-item size and identifying metadata in GUI and CLI outputs.
- Deterministic sorting and filtering for simulator inventory views.

## Deliverables
- Extended shared core models for simulator runtime/device records.
- Extended shared core models for runtime telemetry records and instance counts.
- Scanner support for per-item simulator inventory.
- Scanner support for running-state telemetry for Xcode installs and simulator devices.
- `XcodeCleanerApp` views for simulator device/runtime lists.
- `XcodeCleanerApp` indicators for runtime status and instance counts.
- `xcodecleaner-cli` parity output for simulator itemization and runtime telemetry.
- Fixture tests for itemization, size attribution, and classification.

## Exit Criteria
- Simulator data is visible as itemized rows, not aggregate only.
- Device and runtime sizes are deterministic in fixture tests.
- Xcode install rows include running status and instance counts.
- Simulator device rows include running/booted status and instance counts.
- Ownership and safety labels appear consistently in GUI and CLI.
- Tests pass with workspace cache overrides.

## Out of Scope
- Destructive deletion execution.
- Automation and scheduling behavior.

## Follow-On
Selective deletion of one or more simulator devices lands in Sprint 5 after dry-run planning support in Sprint 4.
