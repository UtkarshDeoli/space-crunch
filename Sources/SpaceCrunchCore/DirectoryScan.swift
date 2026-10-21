import Darwin
import Foundation

/// Reads a directory tree straight from the file system, in a way that is safe
/// to point at a folder macOS has locked away.
///
/// ## Why the old scanner hung
///
/// macOS does not tell an app without Full Disk Access that a folder is
/// protected. It makes the `open` call *wait* for a permission prompt that
/// never arrives, so the call blocks forever. `FileManager.enumerator` opens
/// every directory it visits by absolute path, so the scan sat on the first
/// protected folder it met — an hour of "Scanning…" with the CPU at zero.
///
/// ## What this does instead
///
/// A *relative* `openat` — one that resolves the folder against a descriptor
/// the scanner already holds — behaves differently. It waits the same few
/// seconds for the same authorization, then gives up and returns `EINTR`.
/// That is a bounded wait, and it is paid once per protected *directory*,
/// because a folder that cannot be opened cannot hold a file the scanner could
/// read either.
///
/// The walk reads directories breadth-first and hands the next level to a small
/// pool of workers to open while it processes the current one, so those waits
/// happen alongside the work rather than in front of it.
///
/// ## Descriptors
///
/// Every open costs a descriptor and the process only has a few hundred, so a
/// directory's descriptor is shared — reference counted — by all the opens of
/// its children, and the pool stops opening ahead once enough opened folders
/// are waiting to be read. Without that, a folder with thousands of children
/// would either exhaust the descriptor table or, worse, have a descriptor
/// closed by one worker while another was still using it.
///
/// ## Sizes
///
/// A file's size is its allocated size — the space it actually takes on disk —
/// which is `st_blocks * 512`. That is the same number `totalFileAllocatedSize`
/// reported, so the totals the user sees do not change.
final class DirectoryScan {
    /// What the scan worked out about a folder, and what its children inherit.
    struct FolderFacts {
        /// The category the folder is coloured by.
        var displayCategory: SpaceCategory
        /// What the folder's *name* or *path* says it is. Stored on the node.
        var structural: SpaceCategory?
        /// What kind of standard macOS folder it is.
        var context: SpaceCategory?
        /// What children of this folder inherit when their own path says
        /// nothing.
        var effectiveOverride: SpaceCategory?
    }

    struct Result {
        let node: DirNode
        var categories: [SpaceCategory: Int64] = [:]
        var largeFiles: [LargeFile] = []
        var oldInstallers: [CleanupItem] = []
        var permissionIssues = 0
    }

    private let homePath: String
    private let configuration: ScanConfiguration
    private let reporter: ProgressReporter
    private let isCancelled: @Sendable () -> Bool
    /// Shared by every root of one scan, so the whole scan uses one pool of
    /// openers instead of one pool per top-level folder.
    private let pool: OpenPool
    private let ownsPool: Bool

    init(
        home: URL,
        configuration: ScanConfiguration,
        reporter: ProgressReporter,
        pool: OpenPool? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) {
        self.homePath = home.path
        self.configuration = configuration
        self.reporter = reporter
        self.isCancelled = isCancelled
        self.pool = pool ?? OpenPool(workerCount: 8, capacity: 32)
        self.ownsPool = pool == nil
    }

    // MARK: - Scanning a root

    /// Scans one top-level folder and returns its tree.
    func scan(root: URL) throws -> Result {
        defer { if ownsPool { pool.stop() } }
        return try walk(root: root)
    }

    private func walk(root: URL) throws -> Result {
        let resolvedRoot = PathCanonicalizer.canonical(root)

        let rootStructural = FileClassifier.structuralCategory(forPath: resolvedRoot.path, home: homePath)
        let contextCategory = FileClassifier.topLevelCategory(path: resolvedRoot.path)
        // A folder named "Developer" or "Projects" is source code by convention, even
        // though its path says nothing about it.
        let nameCategory = FileClassifier.folderNameCategory(name: resolvedRoot.lastPathComponent)

        let rootNode = DirNode(
            name: resolvedRoot.lastPathComponent,
            path: resolvedRoot.path,
            category: rootStructural ?? nameCategory ?? contextCategory ?? .other
        )
        rootNode.structuralCategory = rootStructural ?? nameCategory
        rootNode.contextCategory = contextCategory

        // The root's own name and kind are not inherited by its children —
        // only its structural kind is. `~/Developer` is a developer folder, but
        // everything inside it is classified on its own merits.
        let rootFacts = FolderFacts(
            displayCategory: rootNode.category ?? .other,
            structural: rootStructural ?? nameCategory,
            context: contextCategory,
            effectiveOverride: rootStructural
        )

        var result = Result(node: rootNode)

        // `stat`, never `open`: a metadata lookup on a protected folder returns
        // immediately, so this cannot hang.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedRoot.path, isDirectory: &isDirectory) else {
            return result
        }

        // A top-level file in the home folder is unusual but should still count.
        if !isDirectory.boolValue {
            var fileStat = stat()
            guard lstat(resolvedRoot.path, &fileStat) == 0 else { return result }
            let size = allocatedBytes(fileStat)
            let modified = modificationDate(fileStat)
            rootNode.size = size
            rootNode.fileCount = 1
            rootNode.modified = modified
            let category = FileClassifier.fileCategory(
                pathExtension: resolvedRoot.pathExtension,
                structuralOverride: rootFacts.effectiveOverride,
                context: rootFacts.displayCategory
            )
            rootNode.category = category
            rootNode.ownContentTotals[category.slot] = size
            rootNode.subtreeTotals[category.slot] = size
            rootNode.dominantCategory = category
            result.categories[category] = size
            if size >= configuration.largeFileThreshold {
                result.largeFiles.append(
                    LargeFile(
                        url: resolvedRoot,
                        folder: resolvedRoot.deletingLastPathComponent().path,
                        size: size,
                        modified: modified,
                        category: category
                    )
                )
            }
            return result
        }

        // Open the root's *parent* — never the root itself by absolute path.
        // An absolute open of a protected folder waits forever; a relative one
        // gives up after a few seconds. The parent is the home folder or the
        // disk root, neither of which is ever protected.
        let (parentPath, leafName) = resolvedRoot.path.splitLastComponent()
        let parentDescriptor = Darwin.open(parentPath, O_RDONLY | O_DIRECTORY)
        guard parentDescriptor >= 0 else {
            result.permissionIssues = 1
            return result
        }

        let rootHandle = DirHandle(fd: parentDescriptor)
        let rootJob = OpenJob(parent: rootHandle, name: leafName)
        rootHandle.release()  // the job holds its own reference now
        pool.submit(rootJob)

        // Breadth-first: the queue holds the directories still to read. Jobs are
        // submitted as children are discovered, so a protected folder is already
        // being authorized while this thread reads the folder before it.
        var queue: [PendingDirectory?] = [
            PendingDirectory(path: resolvedRoot.path, node: rootNode, facts: rootFacts, job: rootJob)
        ]
        var nextIndex = 0

        let downloadsPrefix = homePath + "/Downloads/"
        let trashPrefix = homePath + "/.Trash/"
        let cloudStoragePath = homePath + "/Library/CloudStorage"

        var pendingFiles = 0
        var pendingBytes: Int64 = 0
        var currentPath = resolvedRoot.path

        while nextIndex < queue.count {
            if isCancelled() {
                for entry in queue { entry?.job.abandon() }
                throw CancellationError()
            }

            // Prefer the oldest folder, but never sit behind one that is still
            // waiting to be authorized when a folder behind it is already open.
            // A protected folder can take seconds; blocking on it while opened
            // folders wait unread also holds their descriptors against the
            // pool's budget, which then stops opening anything else. Reading
            // out of order keeps every walk moving.
            var index: Int
            var handle: DirHandle?
            var ready: Int?
            var cursor = nextIndex
            let scanLimit = min(queue.count, nextIndex + 4096)
            while cursor < scanLimit {
                if let entry = queue[cursor], entry.job.isReady {
                    ready = cursor
                    break
                }
                cursor += 1
            }

            if let ready {
                index = ready
                handle = queue[index]!.job.wait()
            } else {
                // Nothing here is ready yet. Waiting on the oldest entry is safe:
                // if opens are being held back, the opened folders belong to
                // other walks, and those walks drain them and free the slots.
                while nextIndex < queue.count, queue[nextIndex] == nil { nextIndex += 1 }
                guard nextIndex < queue.count else { break }
                index = nextIndex
                handle = queue[index]!.job.wait()
            }

            let pending = queue[index]!
            queue[index] = nil
            if index == nextIndex {
                nextIndex += 1
                while nextIndex < queue.count, queue[nextIndex] == nil { nextIndex += 1 }
            }

            if let failure = pending.job.failure,
               failure == EINTR || failure == EACCES || failure == EPERM {
                result.permissionIssues += 1
            }
            guard let handle else {
                continue
            }
            // The folder's descriptor is now this thread's to read. Telling the
            // pool frees it to open another one.
            pool.consumed()

            // `fdopendir` takes ownership of its descriptor, so it reads from a
            // duplicate and leaves the shared handle alone.
            let readDescriptor = dup(handle.fd)
            guard readDescriptor >= 0, let directory = fdopendir(readDescriptor) else {
                if readDescriptor >= 0 { close(readDescriptor) }
                handle.release()
                result.permissionIssues += 1
                continue
            }
            let directoryFD = dirfd(directory)

            // The tally for this folder's own files, indexed by `SpaceCategory.slot`.
            // Kept local and flushed once per folder rather than taking a lock per file.
            var ownTotals = [Int64](repeating: 0, count: SpaceCategory.inSlotOrder.count)
            var childNames: [String] = []

            while let entry = readdir(directory) {
                let name = entry.pointee.name
                if name == "." || name == ".." { continue }

                var fileStat = stat()
                guard fstatat(directoryFD, name, &fileStat, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
                let kind = fileStat.st_mode & S_IFMT
                // Symlinks are never followed: a link out of the tree would
                // double-count, and a link back into it would loop.
                if kind == S_IFLNK { continue }

                if kind == S_IFDIR {
                    childNames.append(name)
                    continue
                }
                guard kind == S_IFREG else { continue }

                let size = allocatedBytes(fileStat)
                let modified = modificationDate(fileStat)
                let childPath = pending.node.path + "/" + name

                pending.node.size += size
                pending.node.fileCount += 1
                if pending.node.modified == nil || modified > pending.node.modified! {
                    pending.node.modified = modified
                }

                let category = FileClassifier.fileCategory(
                    pathExtension: (name as NSString).pathExtension,
                    structuralOverride: pending.facts.effectiveOverride,
                    context: pending.facts.displayCategory
                )
                result.categories[category, default: 0] += size
                ownTotals[category.slot] += size

                if size >= configuration.largeFileThreshold, !childPath.hasPrefix(trashPrefix) {
                    result.largeFiles.append(
                        LargeFile(
                            url: URL(fileURLWithPath: childPath),
                            folder: pending.node.path,
                            size: size,
                            modified: modified,
                            category: category
                        )
                    )
                }

                if childPath.hasPrefix(downloadsPrefix),
                   FileClassifier.isInstaller(name: name),
                   size >= configuration.oldInstallerMinimumSize,
                   configuration.now.timeIntervalSince(modified) > configuration.oldInstallerMinimumAge {
                    result.oldInstallers.append(
                        CleanupItem(
                            url: URL(fileURLWithPath: childPath),
                            detail: SizeText.abbreviatedPath(pending.node.path, home: homePath),
                            size: size,
                            modified: modified,
                            safety: .review,
                            category: .archives,
                            isDirectory: false
                        )
                    )
                }

                pendingFiles += 1
                pendingBytes += size
                currentPath = childPath
                if pendingFiles >= 128 {
                    reporter.advance(files: pendingFiles, bytes: pendingBytes, path: currentPath)
                    pendingFiles = 0
                    pendingBytes = 0
                }
            }
            closedir(directory)

            for slot in ownTotals.indices {
                pending.node.ownContentTotals[slot] += ownTotals[slot]
            }

            // Every child's open holds this folder's descriptor open until it
            // has run, so the folder can be released here without pulling the
            // descriptor out from under a worker.
            for name in childNames {
                let childPath = pending.node.path + "/" + name
                if configuration.skipCloudStorage, childPath == cloudStoragePath { continue }
                // Firmlinked or synthetic mount points would count the same bytes
                // twice, and some virtual folders cannot be walked at all.
                if configuration.excludedPaths.contains(childPath) { continue }

                let childFacts = facts(
                    forPath: childPath,
                    name: name,
                    parentNode: pending.node,
                    parentOverride: pending.facts.effectiveOverride
                )
                let childNode = DirNode(
                    name: name,
                    path: childPath,
                    category: childFacts.displayCategory,
                    parent: pending.node
                )
                childNode.structuralCategory = childFacts.structural
                childNode.contextCategory = childFacts.context
                pending.node.children[name] = childNode

                let job = OpenJob(parent: handle, name: name)
                pool.submit(job)
                queue.append(
                    PendingDirectory(path: childPath, node: childNode, facts: childFacts, job: job)
                )
            }

            handle.release()
        }

        if pendingFiles > 0 {
            reporter.advance(files: pendingFiles, bytes: pendingBytes, path: currentPath)
        }

        DirectoryScan.finalize(rootNode)
        return result
    }

    // MARK: - Per-folder facts

    private func facts(
        forPath path: String,
        name: String,
        parentNode: DirNode,
        parentOverride: SpaceCategory?
    ) -> FolderFacts {
        let structuralRule = FileClassifier.structuralCategory(forPath: path, home: homePath)
        // A folder named "Projects" or "node_modules" is developer data by
        // convention, wherever it sits.
        let nameCategory = FileClassifier.folderNameCategory(name: name)
        let effectiveOverride = structuralRule ?? nameCategory ?? parentOverride
        let displayCategory = FileClassifier.directoryCategory(
            path: path,
            inherited: parentNode.category,
            structural: effectiveOverride
        )
        return FolderFacts(
            displayCategory: displayCategory,
            structural: structuralRule ?? nameCategory,
            context: FileClassifier.topLevelCategory(path: path),
            effectiveOverride: effectiveOverride
        )
    }

    // MARK: - Stat helpers

    /// The space a file takes on disk, in bytes.
    ///
    /// `st_blocks` counts 512-byte units, so this is the allocated size —
    /// the same number `totalFileAllocatedSize` reports, and larger than the
    /// logical size for a sparse or compressed file.
    private func allocatedBytes(_ fileStat: stat) -> Int64 {
        Int64(fileStat.st_blocks) * 512
    }

    private func modificationDate(_ fileStat: stat) -> Date {
        let seconds = Double(fileStat.st_mtimespec.tv_sec)
        let nanoseconds = Double(fileStat.st_mtimespec.tv_nsec) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds + nanoseconds)
    }

    // MARK: - Roll-up

    /// Sums child sizes into their parents and folds modification dates upward.
    @discardableResult
    static func finalize(_ node: DirNode) -> Int64 {
        var total = node.size
        var count = node.fileCount
        // The folder's own files, plus everything its subfolders contain.
        var totals = node.ownContentTotals
        for child in node.children.values {
            finalize(child)
            total += child.size
            count += child.fileCount
            for slot in totals.indices {
                totals[slot] += child.subtreeTotals[slot]
            }
            if let modified = child.modified {
                if node.modified == nil || modified > node.modified! {
                    node.modified = modified
                }
            }
        }
        node.size = total
        node.fileCount = count
        node.subtreeTotals = totals
        node.dominantCategory = SpaceCategory.dominant(in: totals)
        return total
    }
}

// MARK: - Queue entry

/// A directory waiting to be read.
private struct PendingDirectory {
    var path: String
    var node: DirNode
    var facts: DirectoryScan.FolderFacts
    /// The pool job that will produce the descriptor.
    var job: OpenJob
}

// MARK: - Reading directory entry names

private extension dirent {
    /// The entry's file name as a Swift string.
    var name: String {
        var entry = self
        let capacity = MemoryLayout.size(ofValue: entry.d_name)
        return withUnsafePointer(to: &entry.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - Splitting a path

private extension String {
    /// Splits a path into its parent and its last component.
    func splitLastComponent() -> (parent: String, leaf: String) {
        guard let slash = lastIndex(of: "/") else { return (".", self) }
        let parent = String(self[..<slash])
        let leaf = String(self[index(after: slash)...])
        return (parent.isEmpty ? "/" : parent, leaf)
    }
}

// MARK: - Descriptors

/// An open directory, shared by everything that still needs it.
///
/// A folder's descriptor has to stay open while the pool opens its children,
/// but it also has to be closed as soon as the last of those opens is done —
/// the process only has a few hundred descriptors to spend.
final class DirHandle: @unchecked Sendable {
    let fd: Int32
    private let lock = NSLock()
    private var references = 1

    init(fd: Int32) {
        self.fd = fd
    }

    // No `deinit` close: `release()` already closes the descriptor when the
    // last reference goes, and a second close here would land on whatever file
    // happened to be given that number next.
    func retain() {
        lock.lock()
        references += 1
        lock.unlock()
    }

    func release() {
        lock.lock()
        references -= 1
        let finished = references == 0
        lock.unlock()
        if finished { close(fd) }
    }
}

// MARK: - Opening directories in the background

/// One background directory open.
final class OpenJob: @unchecked Sendable {
    let parent: DirHandle
    let name: String
    /// Why the open failed, once it has. `nil` while pending or on success.
    private(set) var failure: Int32?

    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var handle: DirHandle?
    private var isResolved = false
    private var isAbandoned = false

    init(parent: DirHandle, name: String) {
        self.parent = parent
        self.name = name
        parent.retain()
    }

    /// Whether the open has finished, without waiting for it.
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isResolved
    }

    /// Waits for the open to finish and takes the opened directory, or `nil`
    /// if it could not be opened.
    func wait() -> DirHandle? {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return handle
    }

    /// Settles a job that was never handed to a worker, so a walk waiting for
    /// it during shutdown does not block forever.
    func cancelUnsubmitted() {
        lock.lock()
        isAbandoned = true
        isResolved = true
        handle = nil
        lock.unlock()
        semaphore.signal()
    }

    /// Gives up on the job without waiting. If it has already opened the
    /// folder, the descriptor is closed now; if it has not, the worker closes
    /// it when it finishes.
    func abandon() {
        lock.lock()
        if isResolved {
            let stale = handle
            handle = nil
            lock.unlock()
            stale?.release()
        } else {
            isAbandoned = true
            lock.unlock()
        }
    }

    fileprivate func resolve(_ opened: DirHandle?, failure: Int32?) {
        self.failure = failure
        lock.lock()
        if isAbandoned {
            isResolved = true
            lock.unlock()
            opened?.release()
            semaphore.signal()
            return
        }
        handle = opened
        isResolved = true
        lock.unlock()
        semaphore.signal()
    }
}

/// A pool of workers that open directories.
///
/// The opens are the slow part: a protected folder costs several seconds while
/// the kernel waits for an authorization that will not arrive. Running several
/// at once means those waits overlap instead of adding up.
///
/// The pool stops opening ahead once `capacity` opened folders are waiting to
/// be read. Each of those holds a descriptor, and without that ceiling a fast
/// walk over a deep tree would run the process out of them.
final class OpenPool: @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs: [OpenJob] = []
    /// First live index in `jobs`. `removeFirst()` shifts the whole array, and
    /// the queue can hold a hundred thousand pending opens, so the head is
    /// consumed by index instead and the storage is compacted in batches.
    private var jobsHead = 0
    private var running = true
    private var awaitingRead = 0
    private let capacity: Int

    init(workerCount: Int, capacity: Int = 64) {
        self.capacity = max(1, capacity)
        for index in 0..<max(1, workerCount) {
            let thread = Thread { [weak self] in self?.work() }
            thread.stackSize = 512 * 1024
            thread.name = "spacecrunch.open.\(index)"
            thread.start()
        }
    }

    func submit(_ job: OpenJob) {
        // Submitting never blocks: a walk waiting here could not read the
        // folders it has already opened, and those are what free the read
        // budget, so blocking would deadlock every walk at once.
        condition.lock()
        if running {
            jobs.append(job)
            condition.signal()
        }
        condition.unlock()
        if !running { job.cancelUnsubmitted() }
    }

    /// Called once the walk has taken an opened folder off the pool's hands.
    func consumed() {
        condition.lock()
        if awaitingRead > 0 { awaitingRead -= 1 }
        condition.broadcast()
        condition.unlock()
    }

    func stop() {
        condition.lock()
        running = false
        let abandoned = Array(jobs[jobsHead...])
        jobs.removeAll()
        jobsHead = 0
        condition.broadcast()
        condition.unlock()

        for job in abandoned { job.abandon() }
    }

    private func work() {
        while true {
            condition.lock()
            // The read budget is a hard ceiling. Opened-but-unread folders
            // are what consumes descriptors, so workers stop here until the
            // walk reads something and calls `consumed()`.
            while running && (jobsHead >= jobs.count || awaitingRead >= capacity) {
                condition.wait()
            }
            guard running else {
                condition.unlock()
                return
            }
            let job = jobs[jobsHead]
            jobsHead += 1
            // Compact once the consumed prefix dominates, so the array does
            // not grow without bound behind the head.
            if jobsHead >= 1_024 && jobsHead * 2 >= jobs.count {
                jobs.removeFirst(jobsHead)
                jobsHead = 0
            }
            condition.broadcast()
            condition.unlock()

            // A relative open of a protected folder gives up after a few
            // seconds and returns EINTR; a protected folder is reported as a
            // permission problem rather than an empty folder.
            errno = 0
            let descriptor = openat(job.parent.fd, job.name, O_RDONLY | O_DIRECTORY)
            let failure = errno
            job.parent.release()

            if descriptor >= 0 {
                let opened = DirHandle(fd: descriptor)
                condition.lock()
                awaitingRead += 1
                condition.unlock()
                job.resolve(opened, failure: nil)
            } else {
                job.resolve(nil, failure: failure)
            }
        }
    }
}
