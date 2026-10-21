import AppKit
import Foundation
import Observation
import SpaceCrunchCore
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable {
        case overview
        case cleanup
        case largeFiles
        case browse

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .cleanup: "Smart Cleanup"
            case .largeFiles: "Large Files"
            case .browse: "Browse"
            }
        }

        var symbolName: String {
            switch self {
            case .overview: "gauge.with.dots.needle.67percent"
            case .cleanup: "sparkles"
            case .largeFiles: "doc.badge.ellipsis"
            case .browse: "square.grid.2x2"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case failed(String)
    }

    enum ToastTint {
        case success
        case warning
        case error
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let symbolName: String
        let tint: ToastTint
    }

    // Navigation & scan state
    var section: Section = .overview
    var phase: Phase = .idle
    var progress = ScanProgress.zero
    var snapshot: ScanSnapshot?
    var lastScanError: String?

    // Cleanup selection
    var selectedItemIDs: Set<String> = []
    var selectedLargeFileIDs: Set<String> = []

    // Browsing
    var browsePath: [DirNode] = []
    var searchText = ""

    // Feedback
    var isCleaning = false
    var toast: Toast?

    private var scanTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let scanConfiguration: ScanConfiguration?

    init() {
        if let home = SnapshotMode.homeOverride {
            scanConfiguration = ScanConfiguration(
                homeURL: URL(fileURLWithPath: home, isDirectory: true),
                extraRoots: [],
                skipCloudStorage: true
            )
        } else {
            scanConfiguration = nil
        }
    }

    // MARK: - Scanning

    func startScanIfNeeded() {
        guard phase == .idle, snapshot == nil else { return }
        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        phase = .scanning
        progress = .zero
        lastScanError = nil

        let scanner = DiskScanner(configuration: scanConfiguration ?? ScanConfiguration(scanWholeVolume: true))
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await scanner.scan { progress in
                    Task { @MainActor in
                        guard self.phase == .scanning else { return }
                        self.progress = progress
                    }
                }
                guard !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.phase = .ready
                self.browsePath = []
                self.selectDefaults()
            } catch is CancellationError {
                self.phase = self.snapshot == nil ? .idle : .ready
            } catch {
                self.lastScanError = error.localizedDescription
                self.phase = self.snapshot == nil ? .failed(error.localizedDescription) : .ready
                self.showToast(
                    "Scan couldn't finish: \(error.localizedDescription)",
                    symbolName: "exclamationmark.triangle.fill",
                    tint: .error
                )
            }
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    var isScanning: Bool { phase == .scanning }

    // MARK: - Selection

    enum SelectionState {
        case none
        case some
        case all
    }

    func selectDefaults() {
        guard let snapshot else {
            selectedItemIDs = []
            return
        }
        var ids = Set<String>()
        for group in snapshot.cleanupGroups where group.safety == .safe && group.defaultSelected {
            for item in group.items { ids.insert(item.id) }
        }
        selectedItemIDs = ids
        selectedLargeFileIDs = []
    }

    func selectAllSafe() {
        guard let snapshot else { return }
        var ids = Set<String>()
        for group in snapshot.cleanupGroups where group.safety == .safe {
            for item in group.items { ids.insert(item.id) }
        }
        selectedItemIDs = ids
    }

    func clearSelection() {
        selectedItemIDs = []
        selectedLargeFileIDs = []
    }

    func toggle(_ item: CleanupItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func toggle(_ file: LargeFile) {
        if selectedLargeFileIDs.contains(file.id) {
            selectedLargeFileIDs.remove(file.id)
        } else {
            selectedLargeFileIDs.insert(file.id)
        }
    }

    func selectionState(for group: CleanupGroup) -> SelectionState {
        let selected = group.items.filter { selectedItemIDs.contains($0.id) }.count
        if selected == 0 { return .none }
        if selected == group.items.count { return .all }
        return .some
    }

    func toggleGroup(_ group: CleanupGroup) {
        switch selectionState(for: group) {
        case .all:
            for item in group.items { selectedItemIDs.remove(item.id) }
        case .none, .some:
            for item in group.items { selectedItemIDs.insert(item.id) }
        }
    }

    var selectedCleanupItems: [CleanupItem] {
        guard let snapshot else { return [] }
        var result: [CleanupItem] = []
        for group in snapshot.cleanupGroups {
            for item in group.items where selectedItemIDs.contains(item.id) {
                result.append(item)
            }
        }
        return result
    }

    var selectedCleanupSize: Int64 {
        selectedCleanupItems.reduce(0) { $0 + $1.size }
    }

    var selectedLargeFiles: [LargeFile] {
        guard let snapshot else { return [] }
        return snapshot.largeFiles.filter { selectedLargeFileIDs.contains($0.id) }
    }

    var selectedLargeFilesSize: Int64 {
        selectedLargeFiles.reduce(0) { $0 + $1.size }
    }

    var selectionIsPermanent: Bool {
        guard let snapshot else { return false }
        let items = selectedCleanupItems
        return !items.isEmpty && items.allSatisfy { isInTrash($0.url, home: snapshot.homeURL) }
    }

    /// True when the selection mixes items already in the Trash with items that will be trashed.
    var selectionIsMixed: Bool {
        guard let snapshot else { return false }
        let items = selectedCleanupItems
        let trashCount = items.filter { isInTrash($0.url, home: snapshot.homeURL) }.count
        return trashCount > 0 && trashCount < items.count
    }

    // MARK: - Cleaning

    func cleanSelectedItems() async {
        await clean(items: selectedCleanupItems)
    }

    func cleanSelectedLargeFiles() async {
        let items = selectedLargeFiles.map { file in
            CleanupItem(
                url: file.url,
                detail: SizeText.abbreviatedPath(file.folder, home: snapshot?.homeURL.path ?? ""),
                size: file.size,
                modified: file.modified,
                safety: .review,
                category: file.category,
                isDirectory: false
            )
        }
        await clean(items: items)
    }

    func clean(items: [CleanupItem]) async {
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }

        let home = snapshot?.homeURL ?? FileManager.default.homeDirectoryForCurrentUser
        let report = await DeletionService.delete(items: items, home: home)

        if !report.removed.isEmpty {
            snapshot?.applyDeletion(of: report.removed)
            for item in report.removed {
                selectedItemIDs.remove(item.id)
                selectedLargeFileIDs.remove(item.id)
            }
        }

        // Drop IDs that no longer exist after the snapshot was updated.
        if let snapshot {
            let existing = Set(snapshot.cleanupGroups.flatMap { $0.items.map(\.id) })
            selectedItemIDs.formIntersection(existing)
            let fileIDs = Set(snapshot.largeFiles.map(\.id))
            selectedLargeFileIDs.formIntersection(fileIDs)
        }

        if report.failed.isEmpty {
            let trashCount = report.removed.filter { isInTrash($0.url, home: home) }.count
            let verb: String
            if trashCount == report.removed.count {
                verb = "Permanently deleted"
            } else if trashCount > 0 {
                verb = "Removed"
            } else {
                verb = "Moved to Trash"
            }
            showToast(
                "\(verb) \(report.removedCount) item\(report.removedCount == 1 ? "" : "s") · \(SizeText.string(report.bytesFreed))",
                symbolName: "checkmark.circle.fill",
                tint: .success
            )
        } else if report.removed.isEmpty {
            showToast(
                "Couldn't remove \(report.failed.count) item\(report.failed.count == 1 ? "" : "s")",
                symbolName: "exclamationmark.triangle.fill",
                tint: .error
            )
        } else {
            showToast(
                "Freed \(SizeText.string(report.bytesFreed)) · \(report.failed.count) item\(report.failed.count == 1 ? "" : "s") skipped",
                symbolName: "exclamationmark.triangle.fill",
                tint: .warning
            )
        }
    }

    func isInTrash(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let trash = home.standardizedFileURL.path + "/.Trash"
        return path == trash || path.hasPrefix(trash + "/")
    }

    // MARK: - Browsing

    var browseNode: DirNode? {
        browsePath.last ?? snapshot?.browseRoot
    }

    func focusBrowse(_ node: DirNode) {
        browsePath = node.ancestry()
        section = .browse
    }

    func drill(into node: DirNode) {
        browsePath = node.ancestry()
    }

    // MARK: - Helpers

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func showToast(_ text: String, symbolName: String, tint: ToastTint) {
        toastTask?.cancel()
        let toast = Toast(text: text, symbolName: symbolName, tint: tint)
        self.toast = toast
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == toast.id {
                self?.toast = nil
            }
        }
    }

    var reclaimableSelectionSummary: String {
        let items = selectedCleanupItems
        if items.isEmpty { return "Nothing selected" }
        return "\(items.count) item\(items.count == 1 ? "" : "s") · \(SizeText.string(selectedCleanupSize))"
    }
}
