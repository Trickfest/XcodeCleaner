# XcodeCleaner Implementation Roadmap

## Planning Assumptions
- Sprint length: 2 weeks.
- Every sprint must ship an internal release candidate with demoable functionality.
- Every sprint must ship both artifacts:
- `XcodeCleanerApp` for interactive workflows.
- `xcodecleaner-cli` for scriptable workflows.
- No sprint closes without automated tests for new behavior and a manual smoke test script.

## Sprint Plan

| Sprint | Version Target | End-of-Sprint Deliverable | Testable Exit Criteria | Business Value |
|---|---|---|---|---|
| 1 | V1 | App shell + read-only Xcode inventory (installed apps, versions, paths, active selection) | Multi-Xcode fixture test passes; UI lists all detected installs | Immediate visibility into what Xcodes are installed and active |
| 2 | V1 | Storage scanner for major categories (Xcode apps, DerivedData, Archives, DeviceSupport, Simulator data) | Size totals verified against fixture filesystem; scan completes within perf budget on sample machine | Users see where space is going and largest offenders |
| 3 | V1 | Ownership attribution, temporary/non-temporary classification UI, itemized simulator inventory (per-device and per-runtime), and runtime telemetry (Xcode + simulator instance counts) | Classification tests pass; simulator device/runtime fixtures are listed with per-item sizes and metadata; Xcode/simulator running-instance telemetry is exposed in GUI and CLI | Users can identify exactly which simulator devices/runtimes are consuming space and what is currently running |
| 4 | V1 | Dry-run planner with exact path preview and reclaim estimate, including selective simulator-device plans | Dry-run output deterministic in tests; selecting one or more simulator devices produces exact file plan | Users can safely stage targeted simulator cleanup before executing |
| 5 | V1 | Safe execution engine (move-to-Trash first, guarded delete fallback) + selective simulator-device deletion + action log | Integration tests validate multi-device deletion, reclaimed bytes, blocked booted-device guardrails, instance-count-based guardrails, and logs | Users reclaim disk safely with precise control over simulator cleanup |
| 6 | V1 | Modification tools: switch active Xcode and manage stale runtimes/device support | `xcode-select` switch validated in integration tests; runtime guardrails enforced | Users can actively tune local Xcode environment, not just clean files |
| 7 | V1 | Automation policies (age/size/category) with "only when Xcode/simulator closed" checks | Scheduled/manual runs validated; guard conditions tested | Ongoing disk hygiene without manual effort |
| 8 | V1 GA | History/trends, JSON+CSV report export, signed/notarized release package | Release smoke suite passes; notarized artifact installs cleanly on fresh Mac | Shippable V1 with clear user value and low install friction |
| 9 | V2 | Recommendation engine with explainable ranking | Recommendation outputs stable on fixture scenarios; rationale shown in UI | Faster decision-making for cleanup opportunities |
| 10 | V2 | Policy import/export for teams + simulation mode | Round-trip policy tests pass; simulation and live results aligned | Team consistency and repeatable workstation standards |
| 11 | V2 GA | Multi-step automation workflows + threshold alerts | Workflow tests pass with fail/retry paths; alert threshold logic verified | Proactive maintenance and reduced disk incidents |
| 12 | V3 | Predictive disk growth forecasting (Xcode footprint) | Forecast evaluation suite meets agreed error target on fixtures | Users can prevent storage crises before they happen |
| 13 | V3 | Optional adjacent toolchain storage modules + recovery assistant | Opt-in boundaries tested; recovery flow validated in destructive-action simulation | Broader workspace optimization with safer operations |
| 14 | V3 GA | Enterprise policy signing/compliance reporting + hardening pass | Signature verification tests fail closed; full regression suite green | Enterprise-ready governance and trust posture |

## Quality Gates (Apply Every Sprint)
- New code paths require unit tests.
- User-visible flows require integration coverage.
- New sprint capabilities must be exposed through both GUI and CLI when technically applicable.
- GUI and CLI parity tests/fixtures must pass for shared models and computed values.
- Regression suite must pass before sprint close.
- Known high-severity defects block sprint acceptance.

## Incremental Value Rule
Each sprint must leave users with at least one new outcome they can realize immediately:
- Better visibility.
- More reliable cleanup.
- Lower risk.
- Less manual effort.
- Better predictability.

## Immediate Next Action
Sprint 1 and Sprint 2 are complete; start Sprint 3 by implementing ownership attribution plus itemized simulator device/runtime inventory in shared core models with GUI/CLI parity.
