# XcodeCleaner

Native macOS tooling (Swift + SwiftUI) to inventory, understand, and clean Xcode-related disk usage.

## Sprint 1 Status

Sprint 1 deliverables implemented:
- Read-only Xcode installation inventory scanner.
- Active developer directory detection (`xcode-select -p`).
- SwiftUI app shell to view discovered installs.
- CLI output for quick verification and automation.
- Unit tests for multi-Xcode discovery and metadata behavior.

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
