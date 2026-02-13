# XcodeCleaner V2 Specification

## 1) Goal
Expand beyond core cleanup into optimization guidance, deeper diagnostics, and team-friendly policy sharing while preserving V1 safety principles.

## 2) Scope

### 2.1 Smart Recommendations
- Heuristics that rank cleanup opportunities by reclaim size and risk.
- "Why recommended" explanations for each suggestion.
- Confidence labels to reduce false positives.

### 2.2 Advanced Diagnostics
- Build artifact lineage view (which jobs/projects produced large artifacts).
- Runtime duplication analysis across Xcode versions.
- Detection of misconfigurations causing repeated cache bloat.

### 2.3 Team/Org Policy Packs
- Import/export cleanup policy bundles.
- Shared policy templates (local file import/export, no backend required).
- Enforcement mode for managed Macs (optional local profile support).

### 2.4 Extended Automation
- Multi-step workflows (scan, notify, cleanup, verify reclaim).
- Automation conditions (battery, network state, disk pressure threshold).
- Preflight and post-run validation reports.

### 2.5 Observability
- Weekly digest view of growth trends and cleanup impact.
- Drift alerts when disk usage exceeds user-defined thresholds.

### 2.6 Dual-Artifact Delivery
- Every V2 feature must ship in both `XcodeCleanerApp` and `xcodecleaner-cli` when technically applicable.
- CLI output schema must include all V2 data needed for non-interactive workflows.
- GUI and CLI must share the same core evaluation logic to avoid drift.

## 3) UX Requirements
- Recommendation center with one-click drill-down to exact affected paths.
- Policy editor with simulation mode before save.
- Comparative "before vs after" views for each automation run.

## 4) Acceptance Criteria
- Recommendations must be auditable with exact rule traces.
- Policy import/export round-trips with no semantic changes.
- Automation workflows produce deterministic logs and summary outcomes.
- GUI and CLI return consistent recommendation and policy evaluation results on the same fixture inputs.
- No regression in V1 scan and cleanup performance/safety gates.

## 5) Test Strategy
- Unit tests for recommendation scoring and policy evaluation.
- Integration tests for policy import/export compatibility.
- End-to-end automation tests with failure injection and rollback checks.
