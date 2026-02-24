import Foundation

enum SetupRemoteCommand {
    static func run() throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("Usage: nocrumbs setup-remote <ssh-host>")
            print("")
            print("Sets up NoCrumbs on a remote dev server in one command.")
            print("Run this from your Mac — it SSHes into <ssh-host> and configures everything.")
            print("")
            print("Steps performed:")
            print("  1. Copy CLI binary to remote (~/.local/bin/nocrumbs)")
            print("  2. Set NOCRUMBS_HOST=localhost in remote shell profile")
            print("  3. Run 'nocrumbs install' on remote")
            print("  4. Add RemoteForward to local ~/.ssh/config")
            print("  5. Enable TCP listener locally (defaults write)")
            print("  6. Verify tunnel connectivity")
            exit(1)
        }

        let host = args[2]
        var succeeded: [String] = []
        var failed: [(step: String, error: String)] = []

        // Step 1: Copy CLI binary to remote
        print("→ Copying CLI binary to \(host):~/.local/bin/nocrumbs...")
        let cliPath = resolveLocalCLIPath()
        do {
            try sshRun(host, "mkdir -p ~/.local/bin")
            try scpFile(localPath: cliPath, host: host, remotePath: "~/.local/bin/nocrumbs")
            try sshRun(host, "chmod +x ~/.local/bin/nocrumbs")
            succeeded.append("CLI installed: ~/.local/bin/nocrumbs")
        } catch {
            failed.append(("Copy CLI binary", "\(error)"))
        }

        // Step 2: Detect remote shell and set NOCRUMBS_HOST
        print("→ Configuring NOCRUMBS_HOST on remote...")
        do {
            let shell = try sshOutput(host, "basename $SHELL").trimmingCharacters(in: .whitespacesAndNewlines)
            let rcFile: String
            switch shell {
            case "zsh": rcFile = "~/.zshrc"
            case "fish": rcFile = "~/.config/fish/config.fish"
            default: rcFile = "~/.bashrc"
            }

            let alreadySet = (try? sshOutput(host, "grep -q NOCRUMBS_HOST \(rcFile) && echo yes || echo no"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "no"
            if alreadySet == "yes" {
                print("  Already set in \(rcFile), skipping")
            } else {
                let exportLine: String
                if shell == "fish" {
                    exportLine = "set -gx NOCRUMBS_HOST localhost"
                } else {
                    exportLine = "export NOCRUMBS_HOST=localhost"
                }
                try sshRun(host, "echo '\\n# NoCrumbs remote connection\\n\(exportLine)' >> \(rcFile)")
            }

            // Also ensure ~/.local/bin is in PATH
            let inPath = (try? sshOutput(host, "grep -q '\\.local/bin' \(rcFile) && echo yes || echo no"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "no"
            if inPath != "yes" {
                if shell == "fish" {
                    try sshRun(host, "echo 'fish_add_path ~/.local/bin' >> \(rcFile)")
                } else {
                    try sshRun(host, "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> \(rcFile)")
                }
            }
            succeeded.append("NOCRUMBS_HOST=localhost in \(rcFile)")
        } catch {
            failed.append(("Configure NOCRUMBS_HOST", "\(error)"))
        }

        // Step 3: Run nocrumbs install on remote
        print("→ Installing Claude Code hooks on remote...")
        do {
            let output = try sshOutput(host, "~/.local/bin/nocrumbs install --remote")
            // Only print first line of install output
            if let firstLine = output.split(separator: "\n").first {
                print("  \(firstLine)")
            }
            succeeded.append("Hooks configured: ~/.claude/settings.json")
        } catch {
            failed.append(("Install hooks on remote", "\(error)"))
        }

        // Step 4: Add RemoteForward to local ~/.ssh/config
        print("→ Configuring SSH RemoteForward...")
        do {
            try configureSSHConfig(host: host)
            succeeded.append("SSH tunnel: RemoteForward 19876 in ~/.ssh/config")
        } catch {
            failed.append(("Configure SSH RemoteForward", "\(error)"))
        }

        // Step 5: Enable TCP listener locally
        print("→ Enabling TCP listener...")
        do {
            try shellRun("/usr/bin/defaults", ["write", "com.geneyoo.nocrumbs", "remoteTCPPort", "-int", "19876"])
            succeeded.append("TCP listener: enabled on localhost:19876")
        } catch {
            failed.append(("Enable TCP listener", "\(error)"))
        }

        // Step 6: Verify tunnel (best-effort — tunnel only works during active SSH session)
        print("→ Verifying tunnel connectivity...")
        let tunnelOK: Bool
        do {
            let result = try sshOutput(host, "nc -zw2 localhost 19876 && echo OK || echo FAIL")
            tunnelOK = result.trimmingCharacters(in: .whitespacesAndNewlines) == "OK"
        } catch {
            tunnelOK = false
        }

        // Summary
        print("")
        if failed.isEmpty {
            print("✅ Remote setup complete for \(host)")
        } else {
            print("⚠️  Remote setup partially complete for \(host)")
        }

        for item in succeeded {
            print("   \(item)")
        }

        if !tunnelOK {
            print("")
            print("   ⚠️  Tunnel not yet active — this is normal.")
            print("   The RemoteForward activates when you SSH into \(host).")
            print("   After connecting: nc -zw1 localhost 19876  (should succeed)")
        }

        if !failed.isEmpty {
            print("")
            print("Failed steps (fix manually):")
            for (step, error) in failed {
                print("   ✗ \(step): \(error)")
            }
        }

        print("")
        print("Next: ssh \(host) and start a Claude Code session")
    }

    // MARK: - CLI Path Resolution

    /// Resolves the local nocrumbs CLI binary path.
    /// Priority: app bundle → which nocrumbs → current executable
    private static func resolveLocalCLIPath() -> String {
        // Check app bundle first
        let bundlePath = "/Applications/NoCrumbs.app/Contents/Resources/nocrumbs"
        if FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        // Try which
        if let whichPath = try? shellOutput("/usr/bin/which", ["nocrumbs"]),
           !whichPath.isEmpty
        {
            let path = whichPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to current executable
        let execPath = CommandLine.arguments[0]
        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: execPath) {
            return resolved
        }
        return execPath
    }

    // MARK: - SSH Config

    private static func configureSSHConfig(host: String) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.ssh/config"
        let remoteForward = "RemoteForward 19876 localhost:19876"

        // Ensure .ssh directory exists
        let sshDir = "\(home)/.ssh"
        if !FileManager.default.fileExists(atPath: sshDir) {
            try FileManager.default.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sshDir)
        }

        // Read existing config or start empty
        var content: String
        if FileManager.default.fileExists(atPath: configPath) {
            content = try String(contentsOfFile: configPath, encoding: .utf8)
        } else {
            content = ""
        }

        // Check if RemoteForward already configured for this host
        if hasRemoteForward(in: content, host: host) {
            print("  RemoteForward already configured for \(host), skipping")
            return
        }

        // Find existing Host block and append RemoteForward, or create new block
        if let range = findHostBlock(in: content, host: host) {
            // Insert RemoteForward after the Host line
            let insertionPoint = content.index(range.upperBound, offsetBy: 0)
            content.insert(contentsOf: "\n    \(remoteForward)", at: insertionPoint)
        } else {
            // Append new host block
            if !content.isEmpty && !content.hasSuffix("\n") {
                content += "\n"
            }
            content += "\nHost \(host)\n    \(remoteForward)\n"
        }

        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
        // Preserve standard ssh config permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configPath)
    }

    /// Checks if RemoteForward 19876 is already configured for the given host.
    private static func hasRemoteForward(in config: String, host: String) -> Bool {
        let lines = config.components(separatedBy: "\n")
        var inHostBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.lowercased().hasPrefix("host ") {
                let hostValue = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                inHostBlock = (hostValue == host)
                continue
            }

            if inHostBlock {
                if trimmed.lowercased().contains("remoteforward") && trimmed.contains("19876") {
                    return true
                }
            }
        }
        return false
    }

    /// Finds the end of the Host line for the given host (to insert after it).
    private static func findHostBlock(in config: String, host: String) -> Range<String.Index>? {
        let lines = config.components(separatedBy: "\n")
        var offset = config.startIndex

        for line in lines {
            let nextOffset = config.index(offset, offsetBy: line.count)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.lowercased().hasPrefix("host ") {
                let hostValue = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if hostValue == host {
                    return offset..<nextOffset
                }
            }

            // Move past this line + the newline
            if nextOffset < config.endIndex {
                offset = config.index(after: nextOffset)
            } else {
                offset = nextOffset
            }
        }
        return nil
    }

    // MARK: - Shell Helpers

    @discardableResult
    private static func sshRun(_ host: String, _ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [host, command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError.sshFailed(command, process.terminationStatus)
        }
        return process.terminationStatus
    }

    private static func sshOutput(_ host: String, _ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [host, command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError.sshFailed(command, process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func scpFile(localPath: String, host: String, remotePath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = [localPath, "\(host):\(remotePath)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError.scpFailed(process.terminationStatus)
        }
    }

    @discardableResult
    private static func shellRun(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError.shellFailed(executable, process.terminationStatus)
        }
        return process.terminationStatus
    }

    private static func shellOutput(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError.shellFailed(executable, process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum SetupError: Error, CustomStringConvertible {
    case sshFailed(String, Int32)
    case scpFailed(Int32)
    case shellFailed(String, Int32)

    var description: String {
        switch self {
        case .sshFailed(let cmd, let code): "ssh command failed (exit \(code)): \(cmd)"
        case .scpFailed(let code): "scp failed (exit \(code))"
        case .shellFailed(let cmd, let code): "\(cmd) failed (exit \(code))"
        }
    }
}
