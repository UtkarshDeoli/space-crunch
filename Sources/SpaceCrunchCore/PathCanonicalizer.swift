import Darwin
import Foundation

enum PathCanonicalizer {
    /// `URL.resolvingSymlinksInPath()` leaves firmlinks such as `/var` alone, while
    /// `FileManager.enumerator` reports `/private/var/...`. `realpath` matches the
    /// enumerator, so all scanned paths are compared consistently.
    static func canonical(_ url: URL) -> URL {
        var resolved: URL?
        url.withUnsafeFileSystemRepresentation { representation in
            guard let representation else { return }
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            guard realpath(representation, &buffer) != nil else { return }
            resolved = URL(
                fileURLWithPath: String(cString: buffer),
                isDirectory: url.hasDirectoryPath
            )
        }
        return resolved ?? url.standardizedFileURL
    }
}
