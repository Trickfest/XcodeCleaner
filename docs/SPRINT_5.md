# Sprint 5 Plan and Exit Gate

## Sprint Goal
Deliver a deterministic dry-run planner that previews exact paths and reclaim estimates before any destructive action.

## Scope
- Shared dry-run planning model in core.
- Dry-run selection support for:
- Storage categories.
- One or more simulator devices by UDID.
- Deterministic dry-run item ordering and aggregate reclaim estimate.
- Exact path preview for each dry-run item.
- Overlap guardrail to prevent simulator aggregate double counting when specific simulator devices are selected.
- GUI dry-run planning UI with category/device selection and preview.
- CLI dry-run output mode and selection flags.

## Deliverables
- `DryRunSelection`, `DryRunPlanItem`, and `DryRunPlan` models in core.
- `DryRunPlanner` implementation with reclaim estimates and notes.
- `XcodeCleanerApp` dry-run planner section in the inventory UI.
- `xcodecleaner-cli --dry-run` mode:
- `--plan-category <kind>`
- `--plan-simulator-device <udid>`
- Defaults to safe categories when `--dry-run` is used without explicit selectors.
- Test coverage for:
- Exact-path preview and reclaim totals.
- Simulator overlap guardrail behavior.
- CLI option parsing for dry-run flags.

## Exit Criteria
- Dry-run output includes exact paths per planned item.
- Total reclaim estimate equals sum of plan items.
- Multi-device simulator dry-run selection is supported and deterministic.
- GUI and CLI produce equivalent dry-run semantics from the same snapshot.
- Tests pass with workspace cache overrides.

## Out of Scope
- Actual file deletion or move-to-trash execution.
- Scheduling and automation logic.

## Follow-On
Sprint 6 executes selected dry-run plans safely with guardrails and logging.
