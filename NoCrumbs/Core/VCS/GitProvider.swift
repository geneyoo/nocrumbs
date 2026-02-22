import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "Git")

struct GitProvider: VCSProvider {
    let type: VCSType = .git

    func currentHead(at path: String) async throws -> String {
        try await run("git", args: ["rev-parse", "HEAD"], at: path)
    }

    func currentBranch(at path: String) async throws -> String {
        try await run("git", args: ["rev-parse", "--abbrev-ref", "HEAD"], at: path)
    }

    func isValidCommit(_ hash: String, at path: String) async throws -> Bool {
        do {
            _ = try await run("git", args: ["cat-file", "-t", hash], at: path)
            return true
        } catch {
            return false
        }
    }

    func diff(for hash: String, at path: String) async throws -> String {
        try await run("git", args: ["diff", "\(hash)~1", hash], at: path)
    }

    func uncommittedDiff(at path: String) async throws -> String {
        try await run("git", args: ["diff", "HEAD"], at: path)
    }

    func diffForFiles(_ filePaths: [String], at path: String) async throws -> String {
        var args = ["diff", "HEAD", "--"]
        args.append(contentsOf: filePaths)
        return try await run("git", args: args, at: path)
    }

    /// Diff working tree against a specific base commit (shows all changes since that commit).
    func diffFromBase(_ baseHash: String, filePaths: [String], at path: String) async throws -> String {
        var args = ["diff", baseHash, "--"]
        args.append(contentsOf: filePaths)
        return try await run("git", args: args, at: path)
    }

    /// Find the HEAD commit at or before a given timestamp.
    func headBefore(_ date: Date, at path: String) async throws -> String? {
        let iso = ISO8601DateFormatter().string(from: date)
        let result = try await run("git", args: ["log", "-1", "--format=%H", "--before=\(iso)"], at: path)
        return result.isEmpty ? nil : result
    }

    /// Returns set of file paths that are untracked (new files not yet staged).
    func untrackedFiles(_ filePaths: [String], at path: String) async throws -> Set<String> {
        var args = ["ls-files", "--others", "--exclude-standard", "--"]
        args.append(contentsOf: filePaths)
        let output = try await run("git", args: args, at: path)
        guard !output.isEmpty else { return [] }
        return Set(output.split(separator: "\n").map(String.init))
    }

    /// Returns the remote origin URL, or nil if no remote is configured.
    func remoteURL(at path: String) async throws -> String? {
        do {
            let result = try await run("git", args: ["config", "--get", "remote.origin.url"], at: path)
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    /// Returns set of file paths that have no uncommitted changes (clean/committed).
    func cleanFiles(_ filePaths: [String], at path: String) async throws -> Set<String> {
        var args = ["status", "--porcelain", "--"]
        args.append(contentsOf: filePaths)
        let output = try await run("git", args: args, at: path)
        // Files NOT in porcelain output are clean
        let dirtyPaths = Set(
            output.split(separator: "\n").compactMap { line -> String? in
                guard line.count > 3 else { return nil }
                return String(line.dropFirst(3))
            })
        return Set(filePaths.filter { !dirtyPaths.contains($0) })
    }

    private func run(_ command: String, args: [String], at directory: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command)")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: directory)

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Read stdout BEFORE waitUntilExit to prevent pipe buffer deadlock.
                // If git output exceeds ~64KB, the process blocks on write until the
                // pipe is drained. Reading in terminationHandler = classic deadlock.
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output =
                    String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let stderr =
                        String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    logger.error("\(command) \(args.joined(separator: " ")) → exit \(process.terminationStatus): \(stderr)")
                    continuation.resume(throwing: VCSError.commandFailed(command, process.terminationStatus, stderr))
                }
            }
        }
    }
}

enum VCSError: Error, LocalizedError {
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code, let stderr):
            let detail = stderr.isEmpty ? "" : " — \(stderr)"
            return "\(cmd) failed with exit code \(code)\(detail)"
        }
    }
}
