# Sprint 6 Plan and Exit Gate

## Sprint Goal
Execute selected cleanup plans safely with strong guardrails, including selective simulator-device deletion and selective per-install Xcode uninstall.

## Scope
- Safe execution engine shared by GUI and CLI.
- Move-to-Trash first strategy for eligible targets.
- Guarded direct-delete fallback only when trash is unavailable or explicitly requested.
- Selective simulator-device deletion:
- Delete one or more selected simulator devices in a single run.
- Enforce booted/running-device guardrails before destructive actions.
- Selective per-install Xcode uninstall:
- Let user pick exactly which installed Xcode bundles to remove while keeping others.
- Enforce active developer-directory and running-instance guardrails.
- Action logging with per-item result details and reclaimed-byte reporting.
- Deterministic execution order and deterministic outcome reporting for repeatability.

## Deliverables
- Shared execution models for planned action, execution result, and action log records.
- File-operation pipeline with:
- Allowlisted path validation.
- Move-to-Trash attempt.
- Guarded delete fallback path.
- Reclaim-byte accounting per action and total.
- Guardrail policy checks for:
- Running Xcode install instance counts.
- Active developer-directory install protection.
- Booted or running simulator device protection.
- `XcodeCleanerApp` execute flow for selected dry-run items, with per-item success/failure feedback.
- `xcodecleaner-cli` execute mode for selected dry-run items, with machine-readable action results.
- Integration tests covering:
- Multi-device simulator deletion.
- Multi-install Xcode uninstall with subset selection.
- Guardrail-blocked actions and partial-success behavior.
- Action-log integrity and reclaimed-byte totals.

## Exit Criteria
- User can execute cleanup for one or more selected simulator devices in one operation.
- User can execute uninstall for any selected subset of Xcode installs while leaving unselected installs untouched.
- Active Xcode install and running Xcode installs are blocked from uninstall with explicit reasons.
- Booted/running simulator devices are blocked from deletion with explicit reasons.
- Successful actions report reclaimed bytes and exact affected paths.
- Failed or blocked actions do not stop independent eligible actions unless configured fail-fast.
- GUI and CLI expose equivalent execution semantics over the same plan model.
- Tests pass with workspace cache overrides.

## Out of Scope
- Xcode switching workflows (`xcode-select`) and CLT retargeting.
- Scheduled automation policies.
- Historical trend visualization and report export UX polish.

## Follow-On
Sprint 7 delivers modification tools for active Xcode switching and stale runtime/device-support management.
