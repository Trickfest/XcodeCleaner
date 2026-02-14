# XcodeCleaner

Native macOS tooling (Swift + SwiftUI) to inventory, understand, and clean Xcode-related disk usage.

## Sprint Status

Implemented through Sprint 6:
- Read-only Xcode installation inventory scanner.
- Active developer directory detection (`xcode-select -p`).
- Read-only storage accounting for:
- Xcode application bundles.
- DerivedData.
- Archives.
- iOS DeviceSupport.
- Simulator data (devices, caches, runtimes path).
- Ownership attribution and safety classification for storage categories and simulator artifacts.
- Runtime telemetry:
- Per-Xcode running instance count.
- Per-simulator-device running/booted state and instance count.
- Itemized simulator inventory:
- Per runtime metadata and size.
- Per device metadata and size.
- Scan progress instrumentation:
- Shared scan phases and monotonic progress events from core scanner.
- GUI progress bar with percentage and current phase/status message.
- CLI progress/status output on stderr while keeping final JSON on stdout.
- CLI `--no-progress` switch to suppress progress output when desired.
- Dry-run planning:
- Shared dry-run planner with deterministic item ordering and reclaim estimates.
- Exact path previews for each dry-run item.
- Selective simulator-device planning by UDID.
- Selective per-install Xcode planning by install path.
- GUI dry-run section with category/device/Xcode-install selection and live plan preview.
- CLI dry-run output mode via `--dry-run`, with `--plan-category`, `--plan-simulator-device`, and `--plan-xcode-install`.
- Safe execution:
- Shared cleanup execution engine with per-item action log records.
- Move-to-trash first with optional direct-delete fallback.
- Guardrails for active/running Xcode installs and booted/running simulator devices.
- GUI execute flow with per-item success/blocked/failed feedback.
- CLI execute mode via `--execute` with machine-readable execution report JSON.
- SwiftUI app shell showing inventory and storage totals.
- CLI JSON output with inventory and storage models.
- Unit tests for multi-Xcode discovery, storage categorization, telemetry, simulator itemization, progress phase ordering, dry-run planning, and cleanup execution guardrails.

## Quick Start

Run tests:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift test --disable-sandbox
```

Run CLI inventory output:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli
```

Run SwiftUI app shell:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox XcodeCleanerApp
```
