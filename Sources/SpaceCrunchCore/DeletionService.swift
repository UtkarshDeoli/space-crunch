import Foundation

public enum DeletionService {
    /// Moves items to the Trash, except items that already live in the Trash, which are
    /// removed permanently. The operation runs off the main thread and reports failures
    /// individually so one stubborn file cannot block the rest.
    public static func delete(items: [CleanupItem], home: URL) async -> DeletionReport {
        guard !items.isEmpty else { return DeletionReport() }

        return await withCheckedContinuation { (continuation: CheckedContinuation<DeletionReport, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                let trashPath = home.standardizedFileURL.path + "/.Trash"
                var removed: [CleanupItem] = []
                var failures: [DeletionFailure] = []
                var bytes: Int64 = 0

                for item in items {
                    autoreleasepool {
                        let path = item.url.standardizedFileURL.path
                        let isAlreadyInTrash = path == trashPath || path.hasPrefix(trashPath + "/")

                        if !fileManager.fileExists(atPath: path) {
                            removed.append(item)
                            bytes += item.size
                            return
                        }

                        do {
                            if isAlreadyInTrash {
                                try fileManager.removeItem(at: item.url)
                            } else {
                                var resultingURL: NSURL?
                                try fileManager.trashItem(at: item.url, resultingItemURL: &resultingURL)
                            }
                            removed.append(item)
                            bytes += item.size
                        } catch {
                            failures.append(
                                DeletionFailure(
                                    name: item.name,
                                    message: error.localizedDescription
                                )
                            )
                        }
                    }
                }

                continuation.resume(
                    returning: DeletionReport(removed: removed, failed: failures, bytesFreed: bytes)
                )
            }
        }
    }
}
