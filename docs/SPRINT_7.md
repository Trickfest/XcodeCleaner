# Sprint 7 Plan and Exit Gate

## Sprint Goal
Deliver modification tools so users can actively tune their Xcode environment: switch active Xcode and clean stale runtime/device-support artifacts safely.

## Scope
- Active Xcode switching workflow shared by GUI and CLI.
- Enumerate switch targets from discovered installs and validate selected target path.
- Execute active-developer switch using `xcode-select` with explicit status feedback.
- Stale artifact management:
- Identify stale simulator runtimes and stale Xcode device-support content.
- Show candidate size and paths before execution.
- Support selective cleanup of stale runtime/device-support items.
- Guardrails for modification actions:
- Block risky runtime/device-support actions while simulator is running.
- Block invalid/missing switch targets and failed privilege-bound operations with clear reasons.
- Action logging for switch and cleanup operations with timestamps and outcomes.

## Deliverables
- Shared core services/models for:
- Active Xcode switch intent/result records.
- Stale runtime/device-support candidate records.
- Guardrail evaluation and action log events.
- `XcodeCleanerApp` modifications UI:
- Select active Xcode target and apply switch.
- List stale runtime/device-support candidates and execute selected cleanup.
- `xcodecleaner-cli` modifications support:
- Active-Xcode switch command/flag with machine-readable result.
- Stale runtime/device-support listing and selective cleanup execution.
- Integration tests covering:
- Successful `xcode-select` switch path and verification.
- Guardrail-blocked modification scenarios.
- Stale candidate detection and selective cleanup behavior.

## Exit Criteria
- User can switch active Xcode from both GUI and CLI.
- After switch, `xcode-select -p` resolves to the selected install’s developer directory.
- Invalid or unavailable switch targets fail safely with explicit error messages.
- User can identify stale runtimes/device-support items with size/path transparency.
- User can clean selected stale runtime/device-support items with guardrails enforced.
- Action log records switch and cleanup outcomes consistently for GUI and CLI flows.
- Tests pass with workspace cache overrides.

## Out of Scope
- Scheduled cleanup automation and policy execution.
- History/trend visualization and JSON/CSV export packaging.
- Signing/notarization release pipeline work.

## Follow-On
Sprint 8 delivers automation policies (age/size/category) with scheduled/manual run modes and “only when Xcode/simulator closed” checks.
