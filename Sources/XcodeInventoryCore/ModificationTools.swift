import Foundation

public protocol DirectoryListing {
    func childDirectoryURLs(at directoryURL: URL) -> [URL]
}

public struct FileManagerDirectoryLister: DirectoryListing {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func childDirectoryURLs(at directoryURL: URL) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
                return false
            }
            return values.isDirectory == true
        }
    }
}

public struct StaleArtifactDetector: @unchecked Sendable {
    private let directoryLister: DirectoryListing
    private let pathSizer: PathSizing
    private let now: () -> Date

    public init(
        directoryLister: DirectoryListing = FileManagerDirectoryLister(),
        pathSizer: PathSizing = FileSystemPathSizer(),
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryLister = directoryLister
        self.pathSizer = pathSizer
        self.now = now
    }

    public func detect(snapshot: XcodeInventorySnapshot) -> StaleArtifactReport {
        var notes: [String] = []
        var candidates: [StaleArtifactCandidate] = []

        for runtime in snapshot.simulator.runtimes {
            guard let bundlePath = runtime.bundlePath else {
                continue
            }
            let staleReasons = SimulatorStaleness.runtimeStaleReasons(
                for: runtime,
                devices: snapshot.simulator.devices
            )
            guard !staleReasons.isEmpty else {
                continue
            }
            let normalizedPath = normalize(path: bundlePath)
            candidates.append(
                StaleArtifactCandidate(
                    id: "\(StaleArtifactKind.simulatorRuntime.rawValue):\(normalizedPath)",
                    kind: .simulatorRuntime,
                    title: "Stale Simulator Runtime: \(runtime.name)",
                    path: normalizedPath,
                    reclaimableBytes: runtime.sizeInBytes,
                    reason: staleReasons.contains(.unavailable)
                        ? "Runtime is unavailable and can usually be removed safely."
                        : "Runtime is not referenced by any current simulator device.",
                    safetyClassification: .conditionallySafe
                )
            )
        }

        let deviceSupportRoots = snapshot.storage.categories
            .first(where: { $0.kind == .deviceSupport })?
            .paths ?? []
        for rootPath in deviceSupportRoots {
            let rootURL = URL(filePath: rootPath, directoryHint: .isDirectory)
            let childDirectories = directoryLister.childDirectoryURLs(at: rootURL)
            let parsed = childDirectories.compactMap { url -> (url: URL, version: SemanticVersion)? in
                guard let version = parseLeadingVersion(from: url.lastPathComponent) else {
                    return nil
                }
                return (url, version)
            }
            let sorted = parsed.sorted { lhs, rhs in lhs.version > rhs.version }

            // Keep the two newest parsed versions; older version folders are stale candidates.
            let stale = Array(sorted.dropFirst(2))
            if sorted.count > 2 {
                notes.append("Detected stale Device Support directories by keeping the two newest parsed versions under \(normalize(path: rootPath)).")
            }

            for entry in stale {
                let path = normalize(path: entry.url.path)
                let bytes = pathSizer.fileExists(at: entry.url) ? pathSizer.allocatedSize(at: entry.url) : 0
                candidates.append(
                    StaleArtifactCandidate(
                        id: "\(StaleArtifactKind.deviceSupportDirectory.rawValue):\(path)",
                        kind: .deviceSupportDirectory,
                        title: "Stale Device Support: \(entry.url.lastPathComponent)",
                        path: path,
                        reclaimableBytes: bytes,
                        reason: "Older Device Support directory; newest two parsed versions are retained.",
                        safetyClassification: .regenerable
                    )
                )
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.reclaimableBytes != rhs.reclaimableBytes {
                return lhs.reclaimableBytes > rhs.reclaimableBytes
            }
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        if candidates.isEmpty {
            notes.append("No stale runtime or Device Support candidates were detected.")
        }

        let total = candidates.reduce(Int64(0)) { partial, candidate in
            partial + candidate.reclaimableBytes
        }
        return StaleArtifactReport(
            generatedAt: now(),
            candidates: candidates,
            totalReclaimableBytes: total,
            notes: notes
        )
    }

    private func parseLeadingVersion(from name: String) -> SemanticVersion? {
        let prefix = name.prefix { character in
            character.isNumber || character == "."
        }
        guard !prefix.isEmpty else {
            return nil
        }
        let parts = prefix.split(separator: ".", omittingEmptySubsequences: true)
        guard let major = parts.first.flatMap({ Int($0) }) else {
            return nil
        }
        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }

    private func normalize(path: String) -> String {
        URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

public enum StaleArtifactPlanner {
    public static func makePlan(
        snapshot: XcodeInventorySnapshot,
        report: StaleArtifactReport,
        selectedCandidateIDs: [String],
        now: Date = Date()
    ) -> DryRunPlan {
        let selected = Set(selectedCandidateIDs)
        let selectedCandidates: [StaleArtifactCandidate]
        if selected.isEmpty {
            selectedCandidates = report.candidates
        } else {
            selectedCandidates = report.candidates.filter { selected.contains($0.id) }
        }

        let items = selectedCandidates.map { candidate in
            DryRunPlanItem(
                kind: candidate.kind == .simulatorRuntime ? .staleSimulatorRuntime : .staleDeviceSupport,
                staleArtifactID: candidate.id,
                staleArtifactKind: candidate.kind,
                title: candidate.title,
                reclaimableBytes: candidate.reclaimableBytes,
                paths: [candidate.path],
                ownershipSummary: candidate.reason,
                safetyClassification: candidate.safetyClassification
            )
        }
        .sorted { lhs, rhs in
            if lhs.reclaimableBytes != rhs.reclaimableBytes {
                return lhs.reclaimableBytes > rhs.reclaimableBytes
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let total = items.reduce(Int64(0)) { partial, item in
            partial + item.reclaimableBytes
        }
        var notes: [String] = []
        if items.isEmpty {
            notes.append("No stale artifact plan items selected.")
        }

        return DryRunPlan(
            generatedAt: now,
            selection: DryRunSelection(
                selectedCategoryKinds: [],
                selectedSimulatorDeviceUDIDs: [],
                selectedXcodeInstallPaths: []
            ),
            items: items,
            totalReclaimableBytes: total,
            notes: notes
        )
    }
}

public struct ActiveXcodeSwitcher: @unchecked Sendable {
    private let commandRunner: CommandRunning
    private let now: () -> Date

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        now: @escaping () -> Date = Date.init
    ) {
        self.commandRunner = commandRunner
        self.now = now
    }

    public func switchActiveXcode(
        snapshot: XcodeInventorySnapshot,
        targetInstallPath: String
    ) -> ActiveXcodeSwitchResult {
        let normalizedTarget = normalize(path: targetInstallPath)
        let previousActive = snapshot.activeDeveloperDirectoryPath.map(normalize(path:))

        guard let install = snapshot.installs.first(where: { normalize(path: $0.path) == normalizedTarget }) else {
            return ActiveXcodeSwitchResult(
                requestedInstallPath: normalizedTarget,
                requestedDeveloperDirectoryPath: nil,
                previousActiveDeveloperDirectoryPath: previousActive,
                newActiveDeveloperDirectoryPath: previousActive,
                status: .blocked,
                message: "Target Xcode install is not present in the latest scan snapshot.",
                recordedAt: now()
            )
        }

        if install.isActive {
            return ActiveXcodeSwitchResult(
                requestedInstallPath: normalizedTarget,
                requestedDeveloperDirectoryPath: install.developerDirectoryPath,
                previousActiveDeveloperDirectoryPath: previousActive,
                newActiveDeveloperDirectoryPath: previousActive,
                status: .blocked,
                message: "Target Xcode install is already active.",
                recordedAt: now()
            )
        }

        if install.runningInstanceCount > 0 {
            return ActiveXcodeSwitchResult(
                requestedInstallPath: normalizedTarget,
                requestedDeveloperDirectoryPath: install.developerDirectoryPath,
                previousActiveDeveloperDirectoryPath: previousActive,
                newActiveDeveloperDirectoryPath: previousActive,
                status: .blocked,
                message: "Target Xcode install has running instances. Close Xcode before switching.",
                recordedAt: now()
            )
        }

        do {
            _ = try commandRunner.run(
                launchPath: "/usr/bin/xcode-select",
                arguments: ["--switch", install.developerDirectoryPath]
            )
        } catch {
            return ActiveXcodeSwitchResult(
                requestedInstallPath: normalizedTarget,
                requestedDeveloperDirectoryPath: install.developerDirectoryPath,
                previousActiveDeveloperDirectoryPath: previousActive,
                newActiveDeveloperDirectoryPath: previousActive,
                status: .failed,
                message: "Failed to run xcode-select switch. \(error.localizedDescription)",
                recordedAt: now()
            )
        }

        let provider = XcodeSelectActiveDeveloperDirectoryProvider(commandRunner: commandRunner)
        let current = provider.activeDeveloperDirectoryURL()
            .map { normalize(path: $0.path) }
        let expected = normalize(path: install.developerDirectoryPath)
        if current == expected {
            return ActiveXcodeSwitchResult(
                requestedInstallPath: normalizedTarget,
                requestedDeveloperDirectoryPath: expected,
                previousActiveDeveloperDirectoryPath: previousActive,
                newActiveDeveloperDirectoryPath: current,
                status: .succeeded,
                message: "Active Xcode switched successfully.",
                recordedAt: now()
            )
        }

        return ActiveXcodeSwitchResult(
            requestedInstallPath: normalizedTarget,
            requestedDeveloperDirectoryPath: expected,
            previousActiveDeveloperDirectoryPath: previousActive,
            newActiveDeveloperDirectoryPath: current,
            status: .failed,
            message: "xcode-select completed but active developer directory did not match the requested install.",
            recordedAt: now()
        )
    }

    private func normalize(path: String) -> String {
        URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}
