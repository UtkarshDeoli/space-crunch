import CoreGraphics
import Foundation

// MARK: - Categories

public enum SpaceCategory: String, CaseIterable, Identifiable, Sendable {
    case apps
    case photos
    case video
    case audio
    case documents
    case downloads
    case developer
    case caches
    case archives
    case other

    public var id: String { rawValue }

    /// A stable slot for this category, so byte tallies can be kept in a flat array
    /// rather than a dictionary. The scan touches tens of millions of files, and a
    /// hashed dictionary write per file is slow.
    public var slot: Int {
        switch self {
        case .apps: 0
        case .photos: 1
        case .video: 2
        case .audio: 3
        case .documents: 4
        case .downloads: 5
        case .developer: 6
        case .caches: 7
        case .archives: 8
        case .other: 9
        }
    }

    /// Every category, in slot order.
    public static let inSlotOrder: [SpaceCategory] = [
        .apps, .photos, .video, .audio, .documents,
        .downloads, .developer, .caches, .archives, .other,
    ]

    /// The category holding most of the bytes in a per-category tally.
    ///
    /// Returns `nil` when nothing in the tally is recognised, so callers can tell
    /// "we know what this is" apart from "we have no idea".
    public static func dominant(in totals: [Int64]) -> SpaceCategory? {
        var best: SpaceCategory?
        var bestBytes: Int64 = 0
        for category in inSlotOrder {
            let bytes = totals[category.slot]
            if bytes > bestBytes {
                bestBytes = bytes
                best = category
            }
        }
        return best
    }

    public var title: String {
        switch self {
        case .apps: "Applications"
        case .photos: "Photos"
        case .video: "Video"
        case .audio: "Audio"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .developer: "Developer"
        case .caches: "Caches & Logs"
        case .archives: "Archives"
        case .other: "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .apps: "app.dashed"
        case .photos: "photo.on.rectangle.angled"
        case .video: "film"
        case .audio: "waveform"
        case .documents: "doc.text"
        case .downloads: "arrow.down.circle"
        case .developer: "hammer"
        case .caches: "shippingbox"
        case .archives: "archivebox"
        case .other: "square.grid.2x2"
        }
    }
}

// MARK: - Safety & deletion

public enum CleanupSafety: String, Sendable, Hashable {
    /// Removed data is regenerated automatically by macOS or the app that owns it.
    case safe
    /// The data can be removed, but the user should understand the trade-off first.
    case review

    public var title: String {
        switch self {
        case .safe: "Safe to remove"
        case .review: "Review first"
        }
    }
}

public enum CleanupDeletionMode: String, Sendable, Hashable {
    case trash
    case permanent
}

// MARK: - Cleanup

public struct CleanupItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let detail: String
    public let size: Int64
    public let modified: Date?
    public let safety: CleanupSafety
    public let category: SpaceCategory
    public let isDirectory: Bool

    public init(
        url: URL,
        name: String? = nil,
        detail: String,
        size: Int64,
        modified: Date? = nil,
        safety: CleanupSafety,
        category: SpaceCategory,
        isDirectory: Bool
    ) {
        self.id = url.path
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.detail = detail
        self.size = size
        self.modified = modified
        self.safety = safety
        self.category = category
        self.isDirectory = isDirectory
    }
}

public struct CleanupGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbolName: String
    public let safety: CleanupSafety
    public let deletionMode: CleanupDeletionMode
    public let defaultSelected: Bool
    public var items: [CleanupItem]

    public init(
        id: String,
        title: String,
        subtitle: String,
        symbolName: String,
        safety: CleanupSafety,
        deletionMode: CleanupDeletionMode = .trash,
        defaultSelected: Bool,
        items: [CleanupItem]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.safety = safety
        self.deletionMode = deletionMode
        self.defaultSelected = defaultSelected
        self.items = items
    }

    public var size: Int64 { items.reduce(0) { $0 + $1.size } }
    public var itemCount: Int { items.count }
    public var isPermanent: Bool { deletionMode == .permanent }
}

public struct LargeFile: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let folder: String
    public let size: Int64
    public let modified: Date?
    public let category: SpaceCategory

    public init(url: URL, folder: String, size: Int64, modified: Date?, category: SpaceCategory) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.folder = folder
        self.size = size
        self.modified = modified
        self.category = category
    }
}

// MARK: - Directory tree

public final class DirNode: @unchecked Sendable {
    public let name: String
    public let path: String
    public var size: Int64
    public var fileCount: Int
    public var modified: Date?
    public var category: SpaceCategory?
    public var children: [String: DirNode]
    public weak var parent: DirNode?

    /// The category implied by where the folder sits — caches, app bundles, toolchain
    /// directories. Set from the path rules during the scan.
    public var structuralCategory: SpaceCategory?

    /// The category of a standard macOS folder — Downloads, Movies, Documents. Set from
    /// the path rules during the scan.
    public var contextCategory: SpaceCategory?

    /// Bytes per category for the files sitting *directly* in this folder, indexed by
    /// `SpaceCategory.slot`. The scanner fills this in as it walks the tree.
    public var ownContentTotals: [Int64]

    /// Bytes per category for everything in this folder's subtree, including the
    /// folder's own files, indexed by `SpaceCategory.slot`.
    public var subtreeTotals: [Int64]

    /// The category holding most of this folder's bytes. Filled in by the roll-up pass.
    public var dominantCategory: SpaceCategory?

    public init(
        name: String,
        path: String,
        size: Int64 = 0,
        fileCount: Int = 0,
        modified: Date? = nil,
        category: SpaceCategory? = nil,
        parent: DirNode? = nil
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.fileCount = fileCount
        self.modified = modified
        self.category = category
        self.children = [:]
        self.parent = parent
        self.ownContentTotals = [Int64](repeating: 0, count: SpaceCategory.inSlotOrder.count)
        self.subtreeTotals = [Int64](repeating: 0, count: SpaceCategory.inSlotOrder.count)
    }

    public var displayName: String {
        if !name.isEmpty { return name }
        if path == "/" { return "Macintosh HD" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    public var sortedChildren: [DirNode] {
        children.values.sorted {
            if $0.size == $1.size { return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            return $0.size > $1.size
        }
    }

    /// The category to show for this folder.
    ///
    /// A folder's path usually says nothing useful about what fills it — `~/Developer`
    /// is source code by convention, but `~/Library` is whatever 200 apps have left
    /// behind. So the path rules only win when they are specific (caches, app bundles,
    /// standard macOS folders); otherwise the folder is coloured by what is actually
    /// inside it.
    ///
    /// The colour always has to agree with the category breakdown, which is why a
    /// folder's own contents win over the category its *location* implies. `~/Downloads`
    /// is a downloads folder, but if it is full of video then the video is what the
    /// user is looking at.
    public var displayCategory: SpaceCategory {
        if let structuralCategory { return structuralCategory }
        if let dominantCategory { return dominantCategory }
        if let contextCategory { return contextCategory }
        return category ?? .other
    }

    /// Walks up the tree to produce a breadcrumb path, starting at the topmost node.
    public func ancestry() -> [DirNode] {
        var chain: [DirNode] = []
        var cursor: DirNode? = self
        while let node = cursor {
            chain.append(node)
            cursor = node.parent
        }
        return chain.reversed()
    }

    public func find(relativeComponents components: [Substring]) -> DirNode? {
        var node: DirNode = self
        for component in components {
            guard let next = node.children[String(component)] else { return nil }
            node = next
        }
        return node
    }
}

// MARK: - Volume

public struct VolumeInfo: Sendable, Hashable {
    public var total: Int64
    public var free: Int64

    public init(total: Int64, free: Int64) {
        self.total = total
        self.free = free
    }

    public var used: Int64 { max(0, total - free) }
    public var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }
}

// MARK: - Snapshot

public struct ScanSnapshot: Sendable {
    public var scannedAt: Date
    public var homeURL: URL
    public var browseRoot: DirNode
    public var volume: VolumeInfo
    public var categories: [SpaceCategory: Int64]
    public var cleanupGroups: [CleanupGroup]
    public var largeFiles: [LargeFile]
    public var totalScanned: Int64
    public var fileCount: Int
    public var duration: TimeInterval
    public var permissionIssueCount: Int

    public init(
        scannedAt: Date,
        homeURL: URL,
        browseRoot: DirNode,
        volume: VolumeInfo,
        categories: [SpaceCategory: Int64],
        cleanupGroups: [CleanupGroup],
        largeFiles: [LargeFile],
        totalScanned: Int64,
        fileCount: Int,
        duration: TimeInterval,
        permissionIssueCount: Int
    ) {
        self.scannedAt = scannedAt
        self.homeURL = homeURL
        self.browseRoot = browseRoot
        self.volume = volume
        self.categories = categories
        self.cleanupGroups = cleanupGroups
        self.largeFiles = largeFiles
        self.totalScanned = totalScanned
        self.fileCount = fileCount
        self.duration = duration
        self.permissionIssueCount = permissionIssueCount
    }

    /// The home folder's node.
    ///
    /// A home-only scan synthesizes a "Home" child on the browse root. A whole-volume
    /// scan leaves the real tree in place, so the node is found by its path under
    /// `/Users` instead.
    public var homeRoot: DirNode? {
        browseRoot.children["Home"] ?? browseRoot.find(relativeComponents: homeURL.path.split(separator: "/"))
    }
    public var applicationsRoot: DirNode? { browseRoot.children["Applications"] }

    /// Everything the app considers removable, both safe and review-worthy.
    public var reclaimableTotal: Int64 {
        cleanupGroups.reduce(0) { $0 + $1.size }
    }

    public var reclaimableSafe: Int64 {
        cleanupGroups.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size }
    }

    public var reclaimableReview: Int64 {
        cleanupGroups.filter { $0.safety == .review }.reduce(0) { $0 + $1.size }
    }

    public var categoryRows: [(category: SpaceCategory, size: Int64)] {
        categories
            .filter { $0.value > 0 }
            .map { (category: $0.key, size: $0.value) }
            .sorted { $0.size > $1.size }
    }

    /// Applies the effect of moving/deleting items so the UI stays accurate without a rescan.
    public mutating func applyDeletion(of items: [CleanupItem]) {
        let removedIDs = Set(items.map(\.id))

        for index in cleanupGroups.indices {
            cleanupGroups[index].items.removeAll { removedIDs.contains($0.id) }
        }
        cleanupGroups.removeAll { $0.items.isEmpty }
        largeFiles.removeAll { removedIDs.contains($0.id) }

        for item in items {
            totalScanned = max(0, totalScanned - item.size)
            // Take the bytes out of the tree first, so the category breakdown can be
            // reduced by what actually left rather than by the item's own label. A
            // "caches" item can hold a mix of file types, and the breakdown has to
            // keep matching the treemap.
            let removed = subtract(item, from: browseRoot)
            if let removed {
                for (category, bytes) in removed {
                    let current = categories[category] ?? 0
                    categories[category] = max(0, current - bytes)
                }
            } else {
                // Not in the tree — fall back to the item's own category.
                let current = categories[item.category] ?? 0
                categories[item.category] = max(0, current - item.size)
            }
        }
    }

    /// Removes an item from the tree and reports the bytes that left, per category.
    ///
    /// Returns `nil` when the item is not in the tree.
    private func subtract(_ item: CleanupItem, from root: DirNode) -> [SpaceCategory: Int64]? {
        // Use the raw URL path: `standardizedFileURL` rewrites `/private/var` to `/var`,
        // which would not match the enumerator-derived tree paths.
        let target = item.url.path
        guard let top = root.children.values.first(where: {
            target == $0.path || target.hasPrefix($0.path + "/")
        }) else { return nil }

        // Every folder that used to contain the removed item. Their sizes and their
        // category totals both shrink by the same amount, so the treemap colours and
        // the category breakdown stay in step with the sizes.
        var ancestors: [DirNode] = [root]

        // Bytes per category that leave the tree with the item. A folder takes its
        // whole breakdown with it; a single file only takes its own bytes.
        var removed = [Int64](repeating: 0, count: SpaceCategory.inSlotOrder.count)
        var found = false

        if top.path == target {
            for slot in removed.indices { removed[slot] = top.subtreeTotals[slot] }
            root.children.removeValue(forKey: top.name)
            found = true
        } else {
            ancestors.append(top)
            var node = top
            let remainder = String(target.dropFirst(top.path.count))
            let components = remainder.split(separator: "/")

            for component in components {
                let key = String(component)
                guard let child = node.children[key] else {
                    // Not a folder, so it is a file sitting directly in `node`.
                    let slot = item.category.slot
                    removed[slot] = item.size
                    node.ownContentTotals[slot] = max(0, node.ownContentTotals[slot] - item.size)
                    found = true
                    break
                }
                if child.path == target {
                    // A whole folder goes, and with it every category it held.
                    for slot in removed.indices { removed[slot] = child.subtreeTotals[slot] }
                    node.children.removeValue(forKey: key)
                    found = true
                    break
                }
                ancestors.append(child)
                node = child
            }
        }

        guard found else { return nil }

        for ancestor in ancestors {
            ancestor.size = max(0, ancestor.size - item.size)
            for slot in removed.indices {
                ancestor.subtreeTotals[slot] = max(0, ancestor.subtreeTotals[slot] - removed[slot])
            }
            ancestor.dominantCategory = SpaceCategory.dominant(in: ancestor.subtreeTotals)
        }

        var result: [SpaceCategory: Int64] = [:]
        for category in SpaceCategory.inSlotOrder where removed[category.slot] > 0 {
            result[category] = removed[category.slot]
        }
        return result
    }
}

// MARK: - Progress

public struct ScanProgress: Sendable {
    public var files: Int
    public var bytes: Int64
    public var currentPath: String

    public init(files: Int = 0, bytes: Int64 = 0, currentPath: String = "") {
        self.files = files
        self.bytes = bytes
        self.currentPath = currentPath
    }

    public static let zero = ScanProgress()
}

// MARK: - Deletion

public struct DeletionFailure: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let message: String
}

public struct DeletionReport: Sendable {
    public var removed: [CleanupItem]
    public var failed: [DeletionFailure]
    public var bytesFreed: Int64

    public var removedCount: Int { removed.count }
    public var everythingSucceeded: Bool { failed.isEmpty }

    public init(removed: [CleanupItem] = [], failed: [DeletionFailure] = [], bytesFreed: Int64 = 0) {
        self.removed = removed
        self.failed = failed
        self.bytesFreed = bytesFreed
    }
}
