import Foundation

enum VCSDetector {
    static func detect(at path: String) -> VCSType? {
        var current = normalizePath(path)
        let fm = FileManager.default
        while current != "/" {
            if fm.fileExists(atPath: "\(current)/.git") { return .git }
            if fm.fileExists(atPath: "\(current)/.sl") { return .sapling }
            if fm.fileExists(atPath: "\(current)/.hg") { return .mercurial }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    static func repoRoot(at path: String, for vcs: VCSType) -> String? {
        var current = normalizePath(path)
        let fm = FileManager.default
        let marker: String
        switch vcs {
        case .git: marker = ".git"
        case .sapling: marker = ".sl"
        case .mercurial: marker = ".hg"
        }
        while current != "/" {
            if fm.fileExists(atPath: "\(current)/\(marker)") { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Normalize path: resolve symlinks, remove trailing slashes.
    static func normalizePath(_ path: String) -> String {
        let resolved = (path as NSString).resolvingSymlinksInPath
        if resolved.hasSuffix("/"), resolved.count > 1 {
            return String(resolved.dropLast())
        }
        return resolved
    }
}
