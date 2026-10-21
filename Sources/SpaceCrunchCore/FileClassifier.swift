import Foundation

public enum FileClassifier {
    public static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp",
        "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "svg", "webp",
        "psd", "ai", "sketch", "fig",
    ]

    public static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg",
        "3gp", "ts", "mts", "m2ts", "vob", "ogv", "prproj", "fcpbundle",
    ]

    public static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "wma",
        "alac", "caf", "mid", "midi", "aup3", "band", "logicx",
    ]

    public static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "pages", "txt", "rtf", "rtfd", "md", "markdown",
        "xls", "xlsx", "numbers", "ppt", "pptx", "key", "epub", "csv", "tsv",
        "odt", "ods", "odp", "tex", "bib", "html", "htm", "xml", "json", "yaml", "yml",
    ]

    public static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst", "tgz", "tbz2",
        "dmg", "pkg", "iso", "img", "sparsebundle", "xip", "cab", "lz", "lzma",
        // Virtual machine disks and snapshots.
        "vmdk", "vmem", "vdi", "qcow2", "vhd", "vhdx", "ova", "ovf",
    ]

    public static let installerExtensions: Set<String> = [
        "dmg", "pkg", "iso", "xip", "zip", "tar", "gz", "rar", "7z",
    ]

    public static let developerExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "rs", "go", "js", "jsx",
        "ts", "tsx", "py", "rb", "java", "kt", "kts", "cs", "php", "scala", "dart",
        "vue", "svelte", "wasm", "o", "a", "dylib", "framework", "xcarchive",
        "xcworkspace", "xcodeproj", "swiftmodule", "swiftdoc", "swiftinterface",
    ]

    /// Folder names that mean "developer work" wherever they appear. People name
    /// their project folders all sorts of things, so this matches on the name rather
    /// than on a fixed path.
    public static let developerFolderNames: Set<String> = [
        "developer", "development", "projects", "project", "repos", "repositories",
        "source", "sources", "src", "code", "workspace", "workspaces",
        "github", "gitlab", "gitea", "bitbucket",
    ]

    /// Dependency trees, which are always developer data whatever they contain.
    public static let dependencyFolderNames: Set<String> = [
        "node_modules", "vendor", "pods", ".build", "carthage", "bower_components",
    ]

    public static func extensionCategory(_ rawExtension: String) -> SpaceCategory? {
        let ext = rawExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        if photoExtensions.contains(ext) { return .photos }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if documentExtensions.contains(ext) { return .documents }
        if archiveExtensions.contains(ext) { return .archives }
        if developerExtensions.contains(ext) { return .developer }
        return nil
    }

    /// Categories implied by where a file or folder lives. These override extension guesses
    /// because a file cached inside `Library/Caches` is cache data no matter its extension.
    public static func structuralCategory(forPath path: String, home: String) -> SpaceCategory? {
        let cachePaths = [
            home + "/Library/Caches",
            home + "/Library/Logs",
            home + "/.cache",
        ]
        if cachePaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .caches
        }

        // Sandboxed apps keep their caches inside their containers.
        if path.hasSuffix("/Library/Caches") || path.contains("/Library/Caches/") {
            return .caches
        }

        let developerPaths = [
            home + "/Library/Developer",
            home + "/.npm",
            home + "/.gradle",
            home + "/.m2",
            home + "/.cargo",
            home + "/.pnpm-store",
            home + "/.yarn",
        ]
        if developerPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .developer
        }

        let components = path.split(separator: "/")
        if components.contains(where: { $0 == "node_modules" || $0 == ".build" }) {
            return .developer
        }
        if path.hasSuffix(".app") || path.contains(".app/") {
            return .apps
        }
        return nil
    }

    /// A folder's own name, used to recognise the kind of work a folder holds.
    ///
    /// Unlike `structuralCategory` this looks at the name wherever it sits, so
    /// `~/Developer` and `~/work/Projects` are both recognised as source code without
    /// having to be in a fixed location.
    ///
    /// Takes the name directly rather than a path: this runs once per directory, and
    /// a home folder can hold hundreds of thousands of them.
    public static func folderNameCategory(name: String) -> SpaceCategory? {
        guard !name.isEmpty else { return nil }
        let lowercased = name.lowercased()
        if dependencyFolderNames.contains(lowercased) { return .developer }
        if developerFolderNames.contains(lowercased) { return .developer }
        return nil
    }

    /// Used for the root of a scanned top-level folder.
    ///
    /// Only names that mean something on their own are returned. `~/Library` and
    /// `~/.Trash` deliberately return `nil`: they are not a kind of content, they are
    /// just places other content happens to live, so they get coloured by what they
    /// actually contain.
    public static func topLevelCategory(path: String) -> SpaceCategory? {
        if path.hasSuffix(".app") || path.contains(".app/") { return .apps }
        if path.hasSuffix("/Applications") { return .apps }
        if path.hasSuffix("/Downloads") { return .downloads }
        if path.hasSuffix("/Movies") { return .video }
        if path.hasSuffix("/Music") { return .audio }
        if path.hasSuffix("/Pictures") { return .photos }
        if path.hasSuffix("/Documents") || path.hasSuffix("/Desktop") { return .documents }
        return nil
    }

    /// File category using the structural override first, then the extension, then the
    /// containing folder's category.
    public static func fileCategory(
        pathExtension: String,
        structuralOverride: SpaceCategory?,
        context: SpaceCategory?
    ) -> SpaceCategory {
        if let structuralOverride { return structuralOverride }
        if let extCategory = extensionCategory(pathExtension) { return extCategory }
        if let context { return context }
        return .other
    }

    /// The category a file gets when its own extension says nothing useful.
    public static func directoryCategory(
        path: String,
        inherited: SpaceCategory?,
        structural: SpaceCategory?
    ) -> SpaceCategory {
        if let structural { return structural }
        if let topLevel = topLevelCategory(path: path) { return topLevel }
        if let inherited { return inherited }
        return .other
    }

    public static func isInstaller(name: String) -> Bool {
        installerExtensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased())
    }
}
