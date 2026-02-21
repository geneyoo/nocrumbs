import Foundation

enum VCSDetector {
    static func detect(at path: String) -> VCSType? {
        var current = path
        let fm = FileManager.default
        while current != "/" {
            if fm.fileExists(atPath: "\(current)/.git") { return .git }
            if fm.fileExists(atPath: "\(current)/.hg") { return .mercurial }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    static func repoRoot(at path: String, for vcs: VCSType) -> String? {
        var current = path
        let fm = FileManager.default
        let marker = vcs == .git ? ".git" : ".hg"
        while current != "/" {
            if fm.fileExists(atPath: "\(current)/\(marker)") { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}
