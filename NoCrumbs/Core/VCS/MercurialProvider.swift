import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "Hg")

struct MercurialProvider: VCSProvider {
    let type: VCSType = .mercurial

    private static let resolvedPath: String = {
        VCSBinaryResolver.resolve("hg", knownPaths: [
            "/usr/local/bin/hg",
            "/opt/homebrew/bin/hg",
            "/opt/facebook/hg/bin/hg",
        ])
    }()

    func currentHead(at path: String) async throws -> String {
        try await run(args: ["log", "-r", ".", "-T", "{node}"], at: path)
    }

    func currentBranch(at path: String) async throws -> String {
        try await run(args: ["branch"], at: path)
    }

    func isValidCommit(_ hash: String, at path: String) async throws -> Bool {
        do {
            _ = try await run(args: ["log", "-r", hash, "-T", "{node}"], at: path)
            return true
        } catch {
            return false
        }
    }

    func diff(for hash: String, at path: String) async throws -> String {
        try await run(args: ["diff", "--git", "-c", hash], at: path)
    }

    func uncommittedDiff(at path: String) async throws -> String {
        try await run(args: ["diff", "--git"], at: path)
    }

    func diffForFiles(_ filePaths: [String], at path: String) async throws -> String {
        var args = ["diff", "--git"]
        args.append(contentsOf: filePaths)
        return try await run(args: args, at: path)
    }

    func diffFromBase(_ baseHash: String, filePaths: [String], at path: String) async throws -> String {
        var args = ["diff", "--git", "-r", baseHash]
        args.append(contentsOf: filePaths)
        return try await run(args: args, at: path)
    }

    func headBefore(_ date: Date, at path: String) async throws -> String? {
        let iso = ISO8601DateFormatter().string(from: date)
        let result = try await run(
            args: ["log", "-r", "date('<\(iso)')", "-l", "1", "-T", "{node}"], at: path
        )
        return result.isEmpty ? nil : result
    }

    func untrackedFiles(_ filePaths: [String], at path: String) async throws -> Set<String> {
        let output = try await run(args: ["status", "-un"], at: path)
        guard !output.isEmpty else { return [] }
        let allUntracked = Set(output.split(separator: "\n").map(String.init))
        return allUntracked.intersection(filePaths)
    }

    private func run(args: [String], at directory: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: Self.resolvedPath)
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
                process.environment = ShellEnvironment.variables

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
                    logger.error("hg \(args.joined(separator: " "), privacy: .public) → exit \(process.terminationStatus): \(stderr, privacy: .public)")
                    continuation.resume(throwing: VCSError.commandFailed("hg", process.terminationStatus, stderr))
                }
            }
        }
    }
}
