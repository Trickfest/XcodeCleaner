# Sprint 10 Plan and Exit Gate

## Sprint Goal
Reorganize the GUI so users can quickly find and execute core workflows without scanning a long feature dump.

## Problem Statement
Current UI behavior is function-rich but low in information hierarchy. Users must scroll and context-switch through unrelated sections to complete tasks.

## UX Principles
- Prioritize workflow clarity over raw data density.
- Keep destructive actions explicit and guardrailed.
- Use consistent row layouts and status badges.
- Keep current functionality; improve discoverability and flow.

## Target Information Architecture
Use a left sidebar (or segmented top nav on compact widths) with these sections:
- `Overview`
- `Cleanup`
- `Automation`
- `Tools`
- `Reports`

## Section Specs

### Overview
- Show top-level system state:
  - Total Xcode-related footprint.
  - Top reclaim opportunities.
  - Runtime telemetry snapshot (running Xcode/Simulator instances).
  - Active Xcode details.
- Provide quick links/actions into Cleanup, Automation, and Tools.

### Cleanup
- Guided flow with clear steps:
  - Select scope (categories/devices/installs).
  - Review plan (items, bytes, safety badges).
  - Execute cleanup.
- Keep persistent summary/action strip:
  - Estimated reclaim bytes.
  - Primary action (`Execute Cleanup`).
  - Current execute status.

### Automation
- Focus on policy lifecycle and operations:
  - Policy list with status and schedule.
  - Create/edit policy panel.
  - Run now / run due controls.
  - Recent runs and trend cards.
- Keep export shortcuts available but secondary.

### Tools
- Place non-cleanup operational tools only:
  - Active Xcode switching.
  - Stale runtime/device-support candidate management.

### Reports
- Centralize reporting and exports:
  - Run history list.
  - Trend summaries.
  - Export actions for JSON/CSV history and trends.
  - Last export path and status.

## Shared UI Components and Behavior
- Global status strip pinned near top:
  - Scan phase, progress percent, last scan time.
  - Run/execute busy indicator.
- Consistent badges:
  - `Regenerable`, `Conditionally Safe`, `Destructive`.
  - `Active`, `Running`, `Enabled/Disabled`.
- Consistent table/list columns where applicable:
  - Name, Version/Build, State, Size, Path.
- Utility controls where paths are shown:
  - Copy path.
  - Open in Finder.

## Non-Goals
- No new cleanup engines or policy semantics.
- No backend model rewrite beyond what is necessary for view composition.
- No distribution/packaging changes.

## Deliverables
- Refactored SwiftUI navigation and sectioned layout.
- Reorganized views for Overview/Cleanup/Automation/Tools/Reports.
- Maintained parity with existing capabilities.
- Updated GUI smoke checklist results (deferred from Sprint 9).

## Exit Criteria
- All existing GUI capabilities remain available.
- Primary user tasks are achievable without full-page scrolling:
  - Plan and execute cleanup.
  - Create/run automation policy.
  - Switch active Xcode.
  - Export reports.
- Deferred manual GUI smoke pass is completed and documented.
- Automated test suite remains green.
- No high-severity regressions introduced by UI reorganization.

## Implementation Order

### Chunk 1: Navigation Shell and Section Routing
- Implement sidebar/top-nav shell and split existing monolith into section containers.
- Keep existing controls wired; no behavior change yet.
- Value at chunk end: users can navigate major areas directly.

### Chunk 2: Cleanup Workflow Reframe
- Move planner and executor into step-oriented Cleanup section.
- Add persistent reclaim/action strip.
- Value at chunk end: cleanup flow is clearer and faster to operate.

### Chunk 3: Automation Section Consolidation
- Move policy list/create/run/history/trends into dedicated Automation section.
- Preserve current run and export behavior.
- Value at chunk end: automation operations are self-contained and scannable.

### Chunk 4: Tools Section Isolation
- Move Active Xcode switch and stale artifact tools into Tools section.
- Keep existing guardrails and statuses.
- Value at chunk end: operational tools are separated from routine cleanup.

### Chunk 5: Reports Section and Export UX
- Add dedicated Reports section for history/trends and export actions.
- Improve readability of run history rows and export status messaging.
- Value at chunk end: reporting workflows are obvious and centralized.

### Chunk 6: Polish, Consistency, and GUI Smoke
- Standardize badges/row styles/copy-open path utilities.
- Execute deferred manual GUI smoke checklist and document outcomes.
- Value at chunk end: sprint closes with validated, production-usable UI organization.

## Follow-On
Sprint 11 (V2) begins recommendation engine work after Sprint 10 UI organization is validated.
