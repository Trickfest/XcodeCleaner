# Sprint 4 Plan and Exit Gate

## Sprint Goal
Make long scans transparent by showing progress and active scan phase in both GUI and CLI.

## Scope
- Add scan-progress instrumentation in shared core scanning pipeline.
- Define stable scan phases (for example: install discovery, storage category sizing, simulator parsing, final aggregation).
- Emit progress updates as scan advances through phases.
- GUI progress experience:
- Progress bar with percentage.
- Current phase text.
- Smooth updates without blocking the interface.
- CLI progress experience:
- Human-readable progress/status updates while scanning.
- Preserve final JSON output compatibility.
- Add CLI switch to suppress progress output for automation use cases.
- Parity checks to ensure GUI and CLI report the same phase model.

## Deliverables
- Shared progress model in core scanner.
- `XcodeCleanerApp` progress bar and current-phase UI.
- `xcodecleaner-cli` progress/status output during scan.
- `xcodecleaner-cli --no-progress` mode with progress suppressed.
- Tests for phase ordering, monotonic progress movement, and parity between outputs.

## Exit Criteria
- On slow/large scans, GUI shows progress and current phase until completion.
- On slow/large scans, CLI shows progress and current phase until completion.
- Progress reaches completion state only when scan snapshot is complete.
- Existing JSON schema remains backward compatible for downstream tooling.
- Tests pass with workspace cache overrides.

## Out of Scope
- New cleanup execution behavior.
- New deletion policy rules.

## Follow-On
Dry-run planner moves to Sprint 5; selective simulator-device deletion moves to Sprint 6.
