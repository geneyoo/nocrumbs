import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "ShellEnv")

/// Captures the user's login shell environment once at app launch.
/// GUI apps get a minimal environment with no PATH or custom variables.
/// VCS tools (especially hg/sl on FB machines) need the full shell env.
enum ShellEnvironment {
    /// The captured environment dictionary. Falls back to ProcessInfo if capture fails.
    static let variables: [String: String] = {
        let captured = captureFromShell()
        if captured.isEmpty {
            logger.warning("Shell env capture failed — using ProcessInfo environment")
            return ProcessInfo.processInfo.environment
        }
        logger.info("Captured \(captured.count, privacy: .public) shell environment variables")
        return captured
    }()

    private static func captureFromShell() -> [String: String] {
        // Determine user's login shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -ilc: interactive login shell, run command
        process.arguments = ["-ilc", "env"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch shell for env capture: \(error.localizedDescription, privacy: .public)")
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
            let output = String(data: data, encoding: .utf8)
        else {
            logger.warning("Shell env capture exited with \(process.terminationStatus)")
            return [:]
        }

        var env: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eqIdx])
            let value = String(line[line.index(after: eqIdx)...])
            env[key] = value
        }

        return env
    }
}
