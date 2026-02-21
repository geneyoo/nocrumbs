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

    /// Returns set of file paths that are untracked (new files not yet staged).
    func untrackedFiles(_ filePaths: [String], at path: String) async throws -> Set<String> {
        var args = ["ls-files", "--others", "--exclude-standard", "--"]
        args.append(contentsOf: filePaths)
        let output = try await run("git", args: args, at: path)
        guard !output.isEmpty else { return [] }
        return Set(output.split(separator: "\n").map(String.init))
    }

    /// Returns set of file paths that have no uncommitted changes (clean/committed).
    func cleanFiles(_ filePaths: [String], at path: String) async throws -> Set<String> {
        var args = ["status", "--porcelain", "--"]
        args.append(contentsOf: filePaths)
        let output = try await run("git", args: args, at: path)
        // Files NOT in porcelain output are clean
        let dirtyPaths = Set(output.split(separator: "\n").compactMap { line -> String? in
            guard line.count > 3 else { return nil }
            return String(line.dropFirst(3))
        })
        return Set(filePaths.filter { !dirtyPaths.contains($0) })
    }

    private func run(_ command: String, args: [String], at directory: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command)")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: VCSError.commandFailed(command, process.terminationStatus))
                }
            }
        }
    }
}

enum VCSError: Error, LocalizedError {
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code): "\(cmd) failed with exit code \(code)"
        }
    }
}
