import Foundation

let version = "0.2.0"
let args = CommandLine.arguments

guard args.count >= 2 else {
    print("nocrumbs \(version) — git blame for the AI era")
    print("")
    print("Usage:")
    print("  nocrumbs capture-prompt      Pipe from UserPromptSubmit hook stdin")
    print("  nocrumbs capture-change      Pipe from PostToolUse hook stdin")
    print("  nocrumbs annotate-commit     Annotate commit message (git hook)")
    print("  nocrumbs install             Install Claude Code hooks")
    print("  nocrumbs install-git-hooks   Install prepare-commit-msg git hook")
    print("  nocrumbs --version           Show version")
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
    case "annotate-commit":
        try AnnotateCommitCommand.run()
    case "install":
        try InstallCommand.run()
    case "install-git-hooks":
        try InstallGitHooksCommand.run()
    default:
        fputs("Unknown command: \(command)\n", stderr)
        exit(1)
    }
} catch {
    // Fire-and-forget: log to stderr but exit 0 so we never block Claude Code
    fputs("nocrumbs: \(error)\n", stderr)
    exit(0)
}
