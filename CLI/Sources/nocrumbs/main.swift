import Foundation

let version = "0.1.0"
let args = CommandLine.arguments

guard args.count >= 2 else {
    print("nocrumbs \(version) — git blame for the AI era")
    print("")
    print("Usage:")
    print("  nocrumbs capture-prompt    Pipe from UserPromptSubmit hook stdin")
    print("  nocrumbs capture-change    Pipe from PostToolUse hook stdin")
    print("  nocrumbs install           Install Claude Code hooks")
    print("  nocrumbs --version         Show version")
    exit(0)
}

let command = args[1]

do {
    switch command {
    case "--version":
        print("nocrumbs \(version)")
    case "capture-prompt":
        try CapturePromptCommand.run()
    case "capture-change":
        try CaptureChangeCommand.run()
    case "install":
        try InstallCommand.run()
    default:
        fputs("Unknown command: \(command)\n", stderr)
        exit(1)
    }
} catch {
    // Fire-and-forget: log to stderr but exit 0 so we never block Claude Code
    fputs("nocrumbs: \(error)\n", stderr)
    exit(0)
}
