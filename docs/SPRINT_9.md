# Sprint 9 Plan and Exit Gate

## Sprint Goal
Ship V1 GA with usable historical reporting, exportable run outputs, and source-first release readiness.

## Scope
- History and trends for cleanup and automation outcomes.
- Export of run reports in JSON and CSV formats.
- Source-first release readiness (clone/build/run/test).
- Regression validation plus automated/CLI smoke for V1 GA candidate.
- Manual GUI smoke is deferred to Sprint 10 because the UI is being reorganized next sprint.

## Deliverables
- GUI history/trends surfaces for recent cleanup/automation activity.
- CLI support for report export workflows (JSON/CSV).
- Stable report schema documentation for downstream scripting (`docs/REPORT_SCHEMA.md`).
- Release build helper script for reproducible local artifact generation (`scripts/build_release_artifacts.sh`).
- Optional notarization helper scaffold for future binary distribution (`scripts/notarize_release.sh`).
- Sprint-level smoke checklist and release gate results (`docs/RELEASE_SMOKE_CHECKLIST.md`).
- Explicit Sprint 10 handoff note for manual GUI smoke verification.

## Exit Criteria
- Users can review historical cleanup outcomes in-app.
- Users can export machine-readable JSON and human-readable CSV reports.
- Exported reports are deterministic for identical inputs.
- Clone/build/run workflow succeeds on a fresh developer macOS environment.
- Automated regression suite and CLI/report smoke checks pass.
- No open high-severity defects for V1 GA scope.

## Out of Scope
- Major UI redesign and information architecture overhaul.
- New recommendation or predictive systems.
- Signed/notarized binary distribution (kept as optional future packaging work).

## Follow-On
Sprint 10 is reserved for UI cleanup and workflow organization improvements.
Sprint 10 also owns the manual GUI smoke pass after UI reorganization.
