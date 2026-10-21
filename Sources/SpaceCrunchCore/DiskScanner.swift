import Foundation

public struct ScanConfiguration: Sendable {
    public var homeURL: URL
    public var extraRoots: [URL]
    public var largeFileThreshold: Int64
    public var maxLargeFiles: Int
    public var now: Date

    /// How many top-level folders to walk at once.
    ///
    /// The scan is bound by reading directories, not by CPU, so more parallelism
    /// keeps the disk busy. Measured on a home folder with ~3.2M files: 4 roots
    /// took 134s, 8 took 100s, and 16 was no faster again — the disk was already
    /// saturated at 8.
    public var maxConcurrentRoots: Int
    public var skipCloudStorage: Bool
    public var oldInstallerMinimumSize: Int64
    public var oldInstallerMinimumAge: TimeInterval

    /// Walk the boot volume from `/` instead of only the home folder and `extraRoots`.
    public var scanWholeVolume: Bool

    /// Paths the walk never descends into.
    ///
    /// `System/Volumes` holds the firmlinked Data volume, so walking both it and the
    /// firmlinked `/Users`, `/Library` and `/Applications` would count those bytes
    /// twice. `/Volumes` holds other disks plus a second mount of this one. The rest
    /// are virtual or index folders that are either unreadable or not user storage.
    public var excludedPaths: Set<String>

    public static let defaultExcludedPaths: Set<String> = [
        "/System/Volumes",
        "/Volumes",
        "/dev",
        "/cores",
        "/.vol",
        "/.Spotlight-V100",
        "/.fseventsd",
        "/.DocumentRevisions-V100",
        "/.Trashes",
    ]

    public init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraRoots: [URL] = [URL(fileURLWithPath: "/Applications", isDirectory: true)],
        largeFileThreshold: Int64 = 100 * 1_000_000,
        maxLargeFiles: Int = 400,
        now: Date = Date(),
        maxConcurrentRoots: Int = 8,
        skipCloudStorage: Bool = true,
        oldInstallerMinimumSize: Int64 = 50 * 1_000_000,
        oldInstallerMinimumAge: TimeInterval = 30 * 24 * 60 * 60,
        scanWholeVolume: Bool = false,
        excludedPaths: Set<String> = ScanConfiguration.defaultExcludedPaths
    ) {
        self.homeURL = homeURL
        self.extraRoots = extraRoots
        self.largeFileThreshold = largeFileThreshold
        self.maxLargeFiles = maxLargeFiles
        self.now = now
        self.maxConcurrentRoots = maxConcurrentRoots
        self.skipCloudStorage = skipCloudStorage
        self.oldInstallerMinimumSize = oldInstallerMinimumSize
        self.oldInstallerMinimumAge = oldInstallerMinimumAge
        self.scanWholeVolume = scanWholeVolume
        self.excludedPaths = excludedPaths
    }
}

public final class DiskScanner: @unchecked Sendable {
    public let configuration: ScanConfiguration

    public init(configuration: ScanConfiguration = ScanConfiguration()) {
        self.configuration = configuration
    }

    public func scan(progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async throws -> ScanSnapshot {
        let startedAt = Date()
        let home = PathCanonicalizer.canonical(configuration.homeURL)
        let extras = configuration.extraRoots
            .map(PathCanonicalizer.canonical)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let reporter = ProgressReporter(progress)

        // Any volume mounted below `/` is backed by storage that the boot volume walk
        // already sees (simulator runtimes under `/Library/Developer`, for example),
        // so walking through the mount would count the same bytes twice.
        let effectiveConfiguration: ScanConfiguration = {
            var config = configuration
            guard config.scanWholeVolume else { return config }
            let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
            config.excludedPaths.formUnion(mounted.map(\.path).filter { $0 != "/" })
            return config
        }()

        let fileManager = FileManager.default
        var homeChildren: [URL] = []
        if let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) {
            homeChildren = children.filter { child in
                let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey])
                return values?.isSymbolicLink != true
            }
        }

        let extraPaths = Set(extras.map(\.path))
        let roots: [URL]
        if configuration.scanWholeVolume {
            // Every real folder at the root of the boot volume. Firmlinked and
            // virtual folders are excluded, so each byte is counted once.
            let volumeChildren = (try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: "/", isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )) ?? []
            roots = volumeChildren.filter { child in
                guard !effectiveConfiguration.excludedPaths.contains(child.path) else { return false }
                // Dot-named entries at the root are system bookkeeping (`/.vol`,
                // `/.Spotlight-V100`, `/.nofollow`), not user storage.
                guard !child.lastPathComponent.hasPrefix(".") else { return false }
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isSymbolicLink != true && values?.isDirectory == true
            }
        } else {
            roots = homeChildren.filter { !extraPaths.contains($0.path) } + extras
        }

        // One pool of directory-openers for the whole scan. The workers spend
        // most of their time waiting on macOS to authorize a protected folder,
        // so a single pool lets those waits overlap across roots instead of
        // multiplying threads per root.
        let openPool = OpenPool(workerCount: 24, capacity: 64)
        defer { openPool.stop() }

        var results: [RootResult] = []
        try await withThrowingTaskGroup(of: RootResult.self) { group in
            var queue = ArraySlice(roots)
            let initialCount = min(max(1, configuration.maxConcurrentRoots), roots.count)
            for _ in 0..<initialCount {
                guard let root = queue.popFirst() else { break }
                group.addTask { try self.scanRoot(root, home: home, reporter: reporter, pool: openPool, configuration: effectiveConfiguration) }
            }

            while let result = try await group.next() {
                results.append(result)
                if let next = queue.popFirst() {
                    group.addTask { try self.scanRoot(next, home: home, reporter: reporter, pool: openPool, configuration: effectiveConfiguration) }
                }
            }
        }

        try Task.checkCancellation()

        var categories: [SpaceCategory: Int64] = [:]
        var largeFiles: [LargeFile] = []
        var oldInstallers: [CleanupItem] = []
        var fileCount = 0
        var permissionIssues = 0

        let homeRoot: DirNode
        let browseRoot: DirNode

        if configuration.scanWholeVolume {
            // The roots are the volume's own top-level folders, so the tree is the
            // disk. `homeRoot` is whichever node the home folder landed on, which
            // is what the cleanup rules and the Home section expect.
            let diskRoot = DirNode(name: "Macintosh HD", path: "/", category: .other)
            for result in results {
                // Empty synthetic roots (`/pkg`) add nothing to a storage map.
                guard result.node.size > 0 || result.node.fileCount > 0 else { continue }
                diskRoot.children[result.node.name] = result.node
                result.node.parent = diskRoot

                for (category, size) in result.categories {
                    categories[category, default: 0] += size
                }
                largeFiles.append(contentsOf: result.largeFiles)
                oldInstallers.append(contentsOf: result.oldInstallers)
                fileCount += result.node.fileCount
                permissionIssues += result.permissionIssues
            }
            diskRoot.size = results.reduce(0) { $0 + $1.node.size }
            diskRoot.fileCount = fileCount
            diskRoot.modified = results.compactMap(\.node.modified).max()
            rollUpTotals(diskRoot)
            browseRoot = diskRoot
            homeRoot = diskRoot.find(relativeComponents: home.path.split(separator: "/"))
                ?? DirNode(name: "Home", path: home.path, category: .other)
        } else {
            let synthesizedHome = DirNode(name: "Home", path: home.path, category: .other)
            var extraRootNodes: [DirNode] = []
            var homeBytes: Int64 = 0
            var extraBytes: Int64 = 0

            for result in results {
                let isExtra = extraPaths.contains(result.rootURL.path)
                if isExtra {
                    extraRootNodes.append(result.node)
                    extraBytes += result.node.size
                } else {
                    synthesizedHome.children[result.node.name] = result.node
                    result.node.parent = synthesizedHome
                    homeBytes += result.node.size
                }

                for (category, size) in result.categories {
                    categories[category, default: 0] += size
                }
                largeFiles.append(contentsOf: result.largeFiles)
                oldInstallers.append(contentsOf: result.oldInstallers)
                fileCount += result.node.fileCount
                permissionIssues += result.permissionIssues
            }

            synthesizedHome.size = homeBytes
            synthesizedHome.fileCount = results
                .filter { !extraPaths.contains($0.rootURL.path) }
                .reduce(0) { $0 + $1.node.fileCount }
            synthesizedHome.modified = results
                .filter { !extraPaths.contains($0.rootURL.path) }
                .compactMap(\.node.modified)
                .max()
            rollUpTotals(synthesizedHome)

            let synthesizedBrowse = DirNode(name: "Macintosh HD", path: "/", category: .other)
            synthesizedBrowse.children["Home"] = synthesizedHome
            synthesizedHome.parent = synthesizedBrowse
            for node in extraRootNodes {
                synthesizedBrowse.children[node.name] = node
                node.parent = synthesizedBrowse
            }
            synthesizedBrowse.size = homeBytes + extraBytes
            synthesizedBrowse.fileCount = fileCount
            synthesizedBrowse.modified = max(synthesizedHome.modified ?? .distantPast, extraRootNodes.compactMap(\.modified).max() ?? .distantPast)
            rollUpTotals(synthesizedBrowse)

            homeRoot = synthesizedHome
            browseRoot = synthesizedBrowse
        }

        largeFiles.sort {
            if $0.size == $1.size { return $0.name < $1.name }
            return $0.size > $1.size
        }
        if largeFiles.count > configuration.maxLargeFiles {
            largeFiles = Array(largeFiles.prefix(configuration.maxLargeFiles))
        }

        oldInstallers.sort { $0.size > $1.size }
        if oldInstallers.count > 100 {
            oldInstallers = Array(oldInstallers.prefix(100))
        }

        let cleanupGroups = JunkRules.makeCleanupGroups(
            home: home,
            homeRoot: homeRoot,
            oldInstallers: oldInstallers,
            now: configuration.now
        )

        let volume = readVolumeInfo(for: home)
        reporter.finish()

        return ScanSnapshot(
            scannedAt: Date(),
            homeURL: home,
            browseRoot: browseRoot,
            volume: volume,
            categories: categories.filter { $0.value > 0 },
            cleanupGroups: cleanupGroups,
            largeFiles: largeFiles,
            totalScanned: browseRoot.size,
            fileCount: fileCount,
            duration: Date().timeIntervalSince(startedAt),
            permissionIssueCount: permissionIssues
        )
    }

    // MARK: - Root scanning

    private struct RootResult {
        let rootURL: URL
        let node: DirNode
        var categories: [SpaceCategory: Int64]
        var largeFiles: [LargeFile]
        var oldInstallers: [CleanupItem]
        var permissionIssues: Int
    }

    private func scanRoot(
        _ root: URL,
        home: URL,
        reporter: ProgressReporter,
        pool: OpenPool,
        configuration: ScanConfiguration
    ) throws -> RootResult {
        let scan = DirectoryScan(
            home: home,
            configuration: configuration,
            reporter: reporter,
            pool: pool
        )
        let result = try scan.scan(root: root)
        return RootResult(
            rootURL: PathCanonicalizer.canonical(root),
            node: result.node,
            categories: result.categories,
            largeFiles: result.largeFiles,
            oldInstallers: result.oldInstallers,
            permissionIssues: result.permissionIssues
        )
    }

    /// Recomputes subtree totals for a node whose children were assembled by hand
    /// (the `Home` and `Macintosh HD` roots), rather than by the enumerator walk.
    private func rollUpTotals(_ node: DirNode) {
        var totals = node.ownContentTotals
        for child in node.children.values {
            for slot in totals.indices {
                totals[slot] += child.subtreeTotals[slot]
            }
        }
        node.subtreeTotals = totals
        node.dominantCategory = SpaceCategory.dominant(in: totals)
    }

    private func allocatedBytes(_ values: URLResourceValues?) -> Int64 {
        guard let values else { return 0 }
        if let allocated = values.totalFileAllocatedSize, allocated > 0 { return Int64(allocated) }
        if let allocated = values.fileAllocatedSize, allocated > 0 { return Int64(allocated) }
        return Int64(values.fileSize ?? 0)
    }

    private func readVolumeInfo(for url: URL) -> VolumeInfo {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return VolumeInfo(total: 0, free: 0)
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeInfo(total: total, free: max(0, free))
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let emit: @Sendable (ScanProgress) -> Void
    private var files = 0
    private var bytes: Int64 = 0
    private var lastEmit = Date.distantPast
    private var lastPath = ""

    init(_ emit: @escaping @Sendable (ScanProgress) -> Void) {
        self.emit = emit
    }

    func advance(files newFiles: Int, bytes newBytes: Int64, path: String) {
        lock.lock()
        files += newFiles
        bytes += newBytes
        lastPath = path
        let now = Date()
        let shouldEmit = now.timeIntervalSince(lastEmit) > 0.09
        if shouldEmit { lastEmit = now }
        let snapshot = shouldEmit ? ScanProgress(files: files, bytes: bytes, currentPath: path) : nil
        lock.unlock()

        if let snapshot { emit(snapshot) }
    }

    func finish() {
        lock.lock()
        let snapshot = ScanProgress(files: files, bytes: bytes, currentPath: lastPath)
        lock.unlock()
        emit(snapshot)
    }
}
