import Foundation

public enum JunkRules {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]

    private static let minimumSizes: [String: Int64] = [
        "caches": 1_000_000,
        "logs": 500_000,
        "packages": 2_000_000,
        "derived": 5_000_000,
        "archives": 0,
        "device-support": 5_000_000,
        "simulators": 5_000_000,
        "node-modules": 10_000_000,
        "build-artifacts": 10_000_000,
        "trash": 0,
        "old-installers": 0,
        "docker": 100_000_000,
    ]

    // MARK: - Group construction

    public static func makeCleanupGroups(
        home: URL,
        homeRoot: DirNode,
        oldInstallers: [CleanupItem],
        now: Date
    ) -> [CleanupGroup] {
        let homePath = home.path
        var groups: [CleanupGroup] = []

        func resolve(_ components: [String]) -> DirNode? {
            homeRoot.find(relativeComponents: components.map { Substring($0) })
        }

        func childItems(
            of node: DirNode?,
            minimumSize: Int64,
            safety: CleanupSafety,
            category: SpaceCategory,
            detailPrefix: String,
            limit: Int = 250
        ) -> [CleanupItem] {
            guard let node else { return [] }
            let items = node.children.values
                .filter { $0.size >= minimumSize }
                .sorted { $0.size > $1.size }
                .prefix(limit)
                .map { child in
                    CleanupItem(
                        url: URL(fileURLWithPath: child.path, isDirectory: true),
                        detail: detailPrefix,
                        size: child.size,
                        modified: child.modified,
                        safety: safety,
                        category: category,
                        isDirectory: true
                    )
                }
            return Array(items)
        }

        // Application caches (everything in ~/Library/Caches except toolchain caches,
        // which are grouped separately because developers tend to think of them differently).
        let toolchainCacheNames: Set<String> = [
            "Homebrew", "Yarn", "CocoaPods", "pip", "pip3", "org.swift.swiftpm",
            "com.apple.dt.Xcode", "com.apple.dt.instruments",
        ]
        if let caches = resolve(["Library", "Caches"]) {
            let items = caches.children.values
                .filter { $0.size >= minimumSizes["caches"]! && !toolchainCacheNames.contains($0.name) }
                .sorted { $0.size > $1.size }
                .prefix(250)
                .map { child in
                    CleanupItem(
                        url: URL(fileURLWithPath: child.path, isDirectory: true),
                        detail: SizeText.abbreviatedPath(caches.path, home: homePath),
                        size: child.size,
                        modified: child.modified,
                        safety: .safe,
                        category: .caches,
                        isDirectory: true
                    )
                }
            if !items.isEmpty {
                groups.append(
                    CleanupGroup(
                        id: "caches",
                        title: "Application caches",
                        subtitle: "Temporary files apps recreate on demand",
                        symbolName: "shippingbox.fill",
                        safety: .safe,
                        defaultSelected: true,
                        items: Array(items)
                    )
                )
            }
        }

        // Logs
        let logs = childItems(
            of: resolve(["Library", "Logs"]),
            minimumSize: minimumSizes["logs"]!,
            safety: .safe,
            category: .caches,
            detailPrefix: "~/Library/Logs"
        )
        if !logs.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "logs",
                    title: "Logs",
                    subtitle: "Diagnostic logs and crash reports",
                    symbolName: "doc.text.magnifyingglass",
                    safety: .safe,
                    defaultSelected: true,
                    items: logs
                )
            )
        }

        // Developer package caches that live outside ~/Library/Caches (and toolchain caches
        // inside it).
        let packageCachePaths: [(components: [String], label: String)] = [
            (["Library", "Caches", "Homebrew"], "Homebrew"),
            (["Library", "Caches", "Yarn"], "Yarn"),
            (["Library", "Caches", "CocoaPods"], "CocoaPods"),
            (["Library", "Caches", "pip"], "pip"),
            (["Library", "Caches", "pip3"], "pip"),
            (["Library", "Caches", "org.swift.swiftpm"], "Swift Package Manager"),
            (["Library", "Caches", "com.apple.dt.Xcode"], "Xcode caches"),
            (["Library", "Caches", "com.apple.dt.instruments"], "Instruments caches"),
            ([".npm", "_cacache"], "npm"),
            ([".yarn", "cache"], "Yarn"),
            ([".pnpm-store"], "pnpm"),
            ([".gradle", "caches"], "Gradle"),
            ([".m2", "repository"], "Maven"),
            ([".cargo", "registry"], "Cargo"),
            ([".cache"], "User caches"),
        ]
        var packageItems: [CleanupItem] = []
        var seenPackagePaths = Set<String>()
        for entry in packageCachePaths {
            guard let node = resolve(entry.components), node.size >= minimumSizes["packages"]!,
                  seenPackagePaths.insert(node.path).inserted else { continue }
            packageItems.append(
                CleanupItem(
                    url: URL(fileURLWithPath: node.path, isDirectory: true),
                    name: entry.label,
                    detail: SizeText.abbreviatedPath(node.path, home: homePath),
                    size: node.size,
                    modified: node.modified,
                    safety: .safe,
                    category: .developer,
                    isDirectory: true
                )
            )
        }
        if !packageItems.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "package-caches",
                    title: "Package manager caches",
                    subtitle: "Downloaded dependencies and toolchain caches",
                    symbolName: "shippingbox.and.arrow.backward.fill",
                    safety: .safe,
                    defaultSelected: true,
                    items: packageItems.sorted { $0.size > $1.size }
                )
            )
        }

        // Xcode DerivedData
        let derived = childItems(
            of: resolve(["Library", "Developer", "Xcode", "DerivedData"]),
            minimumSize: minimumSizes["derived"]!,
            safety: .safe,
            category: .developer,
            detailPrefix: "~/Library/Developer/Xcode/DerivedData"
        )
        if !derived.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "xcode-derived",
                    title: "Xcode DerivedData",
                    subtitle: "Build intermediates Xcode regenerates",
                    symbolName: "hammer.fill",
                    safety: .safe,
                    defaultSelected: true,
                    items: derived
                )
            )
        }

        // Xcode Archives
        let archives = childItems(
            of: resolve(["Library", "Developer", "Xcode", "Archives"]),
            minimumSize: minimumSizes["archives"]!,
            safety: .review,
            category: .developer,
            detailPrefix: "~/Library/Developer/Xcode/Archives"
        )
        if !archives.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "xcode-archives",
                    title: "Xcode Archives",
                    subtitle: "Archived builds you may still need for App Store uploads",
                    symbolName: "archivebox.fill",
                    safety: .review,
                    defaultSelected: false,
                    items: archives
                )
            )
        }

        // iOS DeviceSupport
        let deviceSupport = childItems(
            of: resolve(["Library", "Developer", "Xcode", "iOS DeviceSupport"]),
            minimumSize: minimumSizes["device-support"]!,
            safety: .review,
            category: .developer,
            detailPrefix: "~/Library/Developer/Xcode/iOS DeviceSupport"
        )
        if !deviceSupport.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "device-support",
                    title: "iOS DeviceSupport",
                    subtitle: "Debug symbols for devices and old iOS versions",
                    symbolName: "iphone",
                    safety: .review,
                    defaultSelected: false,
                    items: deviceSupport
                )
            )
        }

        // Simulator devices
        let simulators = childItems(
            of: resolve(["Library", "Developer", "CoreSimulator", "Devices"]),
            minimumSize: minimumSizes["simulators"]!,
            safety: .review,
            category: .developer,
            detailPrefix: "~/Library/Developer/CoreSimulator/Devices"
        )
        if !simulators.isEmpty {
            let total = simulators.reduce(0) { $0 + $1.size }
            groups.append(
                CleanupGroup(
                    id: "simulators",
                    title: "Simulator devices",
                    subtitle: "Simulated iPhones and iPads, including their app data",
                    symbolName: "iphone.gen3",
                    safety: .review,
                    defaultSelected: false,
                    items: simulators.isEmpty
                        ? []
                        : [
                            CleanupItem(
                                url: URL(fileURLWithPath: resolve(["Library", "Developer", "CoreSimulator", "Devices"])!.path, isDirectory: true),
                                name: "All simulator devices",
                                detail: "\(simulators.count) devices · recreate them in Xcode",
                                size: total,
                                modified: simulators.compactMap(\.modified).max(),
                                safety: .review,
                                category: .developer,
                                isDirectory: true
                            )
                        ]
                )
            )
        }

        // Simulator caches
        let simulatorCaches = childItems(
            of: resolve(["Library", "Developer", "CoreSimulator", "Caches"]),
            minimumSize: 1_000_000,
            safety: .safe,
            category: .developer,
            detailPrefix: "~/Library/Developer/CoreSimulator/Caches"
        )
        if !simulatorCaches.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "simulator-caches",
                    title: "Simulator caches",
                    subtitle: "Temporary runtime data used by Simulator",
                    symbolName: "memorychip",
                    safety: .safe,
                    defaultSelected: true,
                    items: simulatorCaches
                )
            )
        }

        // Caches that sandboxed apps keep inside their containers.
        var containerCacheNodes: [DirNode] = []
        if let containers = resolve(["Library", "Containers"]) {
            collectArtifacts(
                containers,
                names: ["Caches"],
                minimumSize: 50_000_000,
                skippedPrefixes: [],
                into: &containerCacheNodes
            )
        }
        if let groupContainers = resolve(["Library", "Group Containers"]) {
            collectArtifacts(
                groupContainers,
                names: ["Caches"],
                minimumSize: 50_000_000,
                skippedPrefixes: [],
                into: &containerCacheNodes
            )
        }
        if !containerCacheNodes.isEmpty {
            let items = containerCacheNodes
                .sorted { $0.size > $1.size }
                .prefix(150)
                .map { node in
                    CleanupItem(
                        url: URL(fileURLWithPath: node.path, isDirectory: true),
                        name: containerName(for: node.path),
                        detail: SizeText.abbreviatedPath(node.path, home: homePath),
                        size: node.size,
                        modified: node.modified,
                        safety: .safe,
                        category: .caches,
                        isDirectory: true
                    )
                }
            groups.append(
                CleanupGroup(
                    id: "container-caches",
                    title: "App container caches",
                    subtitle: "Caches stored inside sandboxed app containers",
                    symbolName: "shippingbox.circle.fill",
                    safety: .safe,
                    defaultSelected: true,
                    items: Array(items)
                )
            )
        }

        // Local iPhone and iPad backups.
        let backups = childItems(
            of: resolve(["Library", "Application Support", "MobileSync", "Backup"]),
            minimumSize: 1_000_000,
            safety: .review,
            category: .documents,
            detailPrefix: "~/Library/Application Support/MobileSync/Backup"
        )
        if !backups.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "ios-backups",
                    title: "iPhone & iPad backups",
                    subtitle: "Local device backups you can recreate from iCloud or Finder",
                    symbolName: "iphone.and.arrow.forward",
                    safety: .review,
                    defaultSelected: false,
                    items: backups
                )
            )
        }

        // Regenerable project artifacts: node_modules and Swift .build folders.
        var artifactNodes: [DirNode] = []
        collectArtifacts(homeRoot, names: ["node_modules"], minimumSize: minimumSizes["node-modules"]!, skippedPrefixes: [homePath + "/Library", homePath + "/.Trash"], into: &artifactNodes)
        if !artifactNodes.isEmpty {
            let items = artifactNodes
                .sorted { $0.size > $1.size }
                .prefix(250)
                .map { node in
                    CleanupItem(
                        url: URL(fileURLWithPath: node.path, isDirectory: true),
                        detail: SizeText.abbreviatedPath(node.path, home: homePath),
                        size: node.size,
                        modified: node.modified,
                        safety: .review,
                        category: .developer,
                        isDirectory: true
                    )
                }
            groups.append(
                CleanupGroup(
                    id: "node-modules",
                    title: "node_modules",
                    subtitle: "Reinstall with npm, yarn or pnpm when you need them",
                    symbolName: "curlybraces",
                    safety: .review,
                    defaultSelected: false,
                    items: Array(items)
                )
            )
        }

        var buildNodes: [DirNode] = []
        collectArtifacts(homeRoot, names: [".build"], minimumSize: minimumSizes["build-artifacts"]!, skippedPrefixes: [homePath + "/Library", homePath + "/.Trash"], into: &buildNodes)
        if !buildNodes.isEmpty {
            let items = buildNodes
                .sorted { $0.size > $1.size }
                .prefix(250)
                .map { node in
                    CleanupItem(
                        url: URL(fileURLWithPath: node.path, isDirectory: true),
                        detail: SizeText.abbreviatedPath(node.path, home: homePath),
                        size: node.size,
                        modified: node.modified,
                        safety: .review,
                        category: .developer,
                        isDirectory: true
                    )
                }
            groups.append(
                CleanupGroup(
                    id: "build-artifacts",
                    title: "Build artifacts",
                    subtitle: "Swift build folders that can be rebuilt",
                    symbolName: "swift",
                    safety: .review,
                    defaultSelected: false,
                    items: Array(items)
                )
            )
        }

        // Trash
        let trash = trashItems(home: home)
        if !trash.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "trash",
                    title: "Trash",
                    subtitle: "Items already in the Trash will be deleted permanently",
                    symbolName: "trash.fill",
                    safety: .review,
                    deletionMode: .permanent,
                    defaultSelected: false,
                    items: trash
                )
            )
        }

        // Old installers in Downloads
        if !oldInstallers.isEmpty {
            groups.append(
                CleanupGroup(
                    id: "old-installers",
                    title: "Old installers",
                    subtitle: "Large downloads older than 30 days",
                    symbolName: "externaldrive.badge.xmark",
                    safety: .review,
                    defaultSelected: false,
                    items: oldInstallers
                )
            )
        }

        // Docker's virtual disk
        let dockerURL = home.appendingPathComponent(
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
        )
        if FileManager.default.fileExists(atPath: dockerURL.path) {
            let (size, modified) = allocatedSize(of: dockerURL)
            if size >= minimumSizes["docker"]! {
                groups.append(
                    CleanupGroup(
                        id: "docker",
                        title: "Docker disk image",
                        subtitle: "Container images, volumes and cache stored in one file",
                        symbolName: "shippingbox.fill",
                        safety: .review,
                        defaultSelected: false,
                        items: [
                            CleanupItem(
                                url: dockerURL,
                                detail: "~/Library/Containers/com.docker.docker",
                                size: size,
                                modified: modified,
                                safety: .review,
                                category: .developer,
                                isDirectory: false
                            )
                        ]
                    )
                )
            }
        }

        return groups
            .filter { !$0.items.isEmpty && $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    // MARK: - Trash

    public static func trashItems(home: URL) -> [CleanupItem] {
        let trashURL = home.appendingPathComponent(".Trash", isDirectory: true)
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else { return [] }

        return children.compactMap { url -> CleanupItem? in
            let (size, modified) = allocatedSize(of: url)
            guard size > 0 else { return nil }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return CleanupItem(
                url: url,
                detail: "~/.Trash",
                size: size,
                modified: modified,
                safety: .review,
                // The category has to be the one the scanner recorded for this file,
                // so that removing it takes the right bytes out of the breakdown.
                category: isDirectory
                    ? .other
                    : FileClassifier.extensionCategory(url.pathExtension) ?? .other,
                isDirectory: isDirectory
            )
        }
        .sorted { $0.size > $1.size }
    }

    // MARK: - Size helpers

    /// Recursive allocated size, used for items that are already in the Trash or exist as
    /// single files (Docker.raw).
    public static func allocatedSize(of url: URL) -> (size: Int64, modified: Date?) {
        let fileManager = FileManager.default
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return (0, nil) }
        if values.isSymbolicLink == true { return (0, nil) }

        if values.isDirectory == true {
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [],
                errorHandler: nil
            ) else { return (0, values.contentModificationDate) }

            var total: Int64 = 0
            var modified = values.contentModificationDate
            while let child = enumerator.nextObject() as? URL {
                guard let childValues = try? child.resourceValues(forKeys: resourceKeys),
                      childValues.isSymbolicLink != true,
                      childValues.isDirectory != true else { continue }
                total += Int64(
                    childValues.totalFileAllocatedSize
                        ?? childValues.fileAllocatedSize
                        ?? childValues.fileSize
                        ?? 0
                )
                if let date = childValues.contentModificationDate,
                   modified == nil || date > modified! {
                    modified = date
                }
            }
            return (total, modified)
        }

        let size = Int64(
            values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        )
        return (size, values.contentModificationDate)
    }

    // MARK: - Artifact traversal

    private static func containerName(for path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        if let index = components.firstIndex(where: { $0 == "Containers" || $0 == "Group Containers" }),
           components.indices.contains(index + 1) {
            return components[index + 1]
        }
        return "App caches"
    }

    private static func collectArtifacts(
        _ node: DirNode,
        names: Set<String>,
        minimumSize: Int64,
        skippedPrefixes: [String],
        into results: inout [DirNode]
    ) {
        if skippedPrefixes.contains(where: { node.path == $0 || node.path.hasPrefix($0 + "/") }) {
            return
        }
        guard node.size >= minimumSize else { return }

        if names.contains(node.name) {
            results.append(node)
            return
        }

        for child in node.children.values {
            collectArtifacts(
                child,
                names: names,
                minimumSize: minimumSize,
                skippedPrefixes: skippedPrefixes,
                into: &results
            )
        }
    }
}
