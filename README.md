# XcodeCleaner

Native macOS tooling (Swift + SwiftUI) to inventory, understand, and clean Xcode-related disk usage.

## Sprint Status

Implemented through Sprint 2:
- Read-only Xcode installation inventory scanner.
- Active developer directory detection (`xcode-select -p`).
- Read-only storage accounting for:
- Xcode application bundles.
- DerivedData.
- Archives.
- iOS DeviceSupport.
- Simulator data (devices, caches, runtimes path).
- SwiftUI app shell showing inventory and storage totals.
- CLI JSON output with inventory and storage models.
- Unit tests for multi-Xcode discovery and storage categorization.

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
