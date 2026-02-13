# XcodeCleaner Implementation Roadmap

## Planning Assumptions
- Sprint length: 2 weeks.
- Every sprint must ship an internal release candidate with demoable functionality.
- No sprint closes without automated tests for new behavior and a manual smoke test script.

## Sprint Plan

| Sprint | Version Target | End-of-Sprint Deliverable | Testable Exit Criteria | Business Value |
|---|---|---|---|---|
| 1 | V1 | App shell + read-only Xcode inventory (installed apps, versions, paths, active selection) | Multi-Xcode fixture test passes; UI lists all detected installs | Immediate visibility into what Xcodes are installed and active |
| 2 | V1 | Storage scanner for major categories (Xcode apps, DerivedData, Archives, DeviceSupport, Simulator data) | Size totals verified against fixture filesystem; scan completes within perf budget on sample machine | Users see where space is going and largest offenders |
| 3 | V1 | Ownership attribution and temporary/non-temporary classification UI | Classification rule tests pass; unknown items are explicitly labeled | Users can distinguish safe cleanup vs risky cleanup |
| 4 | V1 | Dry-run planner with exact path preview and reclaim estimate | Dry-run output deterministic in tests; preview matches selected items | Users can plan cleanup confidently before taking action |
| 5 | V1 | Safe execution engine (move-to-Trash first, guarded delete fallback) + action log | Integration tests validate reclaimed bytes, partial-failure handling, and logs | Users reclaim disk safely with traceability |
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
Start Sprint 1 by implementing a read-only scanner and fixture-based test harness; this de-risks the rest of the roadmap and provides first business value quickly.
