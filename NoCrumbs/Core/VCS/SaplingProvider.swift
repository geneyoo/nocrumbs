import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "Sl")

struct SaplingProvider: VCSProvider {
    let type: VCSType = .sapling

    func currentHead(at path: String) async throws -> String {
        try await run("sl", args: ["log", "-r", ".", "-T", "{node}"], at: path)
    }

    func currentBranch(at path: String) async throws -> String {
        try await run("sl", args: ["bookmark", "--active"], at: path)
    }

    func isValidCommit(_ hash: String, at path: String) async throws -> Bool {
        do {
            _ = try await run("sl", args: ["log", "-r", hash, "-T", "{node}"], at: path)
            return true
        } catch {
            return false
        }
    }

    func diff(for hash: String, at path: String) async throws -> String {
        try await run("sl", args: ["diff", "--git", "-c", hash], at: path)
    }

    func uncommittedDiff(at path: String) async throws -> String {
        try await run("sl", args: ["diff", "--git"], at: path)
    }

    func diffForFiles(_ filePaths: [String], at path: String) async throws -> String {
        var args = ["diff", "--git"]
        args.append(contentsOf: filePaths)
        return try await run("sl", args: args, at: path)
    }

    func diffFromBase(_ baseHash: String, filePaths: [String], at path: String) async throws -> String {
        var args = ["diff", "--git", "-r", baseHash]
        args.append(contentsOf: filePaths)
        return try await run("sl", args: args, at: path)
    }

    func headBefore(_ date: Date, at path: String) async throws -> String? {
        let iso = ISO8601DateFormatter().string(from: date)
        let result = try await run(
            "sl", args: ["log", "-r", "date('<\(iso)')", "-l", "1", "-T", "{node}"], at: path
        )
        return result.isEmpty ? nil : result
    }

    func untrackedFiles(_ filePaths: [String], at path: String) async throws -> Set<String> {
        let output = try await run("sl", args: ["status", "-un"], at: path)
        guard !output.isEmpty else { return [] }
        let allUntracked = Set(output.split(separator: "\n").map(String.init))
        return allUntracked.intersection(filePaths)
    }

    private func run(_ command: String, args: [String], at directory: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
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

            process.terminationHandler = { _ in
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output =
                    String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr =
                        String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    logger.error("sl \(args.joined(separator: " ")) → exit \(process.terminationStatus): \(stderr)")
                    continuation.resume(throwing: VCSError.commandFailed(command, process.terminationStatus, stderr))
                }
            }
        }
    }
}
