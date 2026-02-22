import Foundation

let version = "0.4.0"
let args = CommandLine.arguments

guard args.count >= 2 else {
    print("nocrumbs \(version) — git blame for the AI era")
    print("")
    print("Usage:")
    print("  nocrumbs event               Pipe any Claude Code hook event to app")
    print("  nocrumbs capture-prompt      (legacy) Pipe from UserPromptSubmit hook")
    print("  nocrumbs capture-change      (legacy) Pipe from PostToolUse hook")
    print("  nocrumbs annotate-commit     Annotate commit message (git hook)")
    print("  nocrumbs install             Install Claude Code hooks")
    print("  nocrumbs install-git-hooks   Install prepare-commit-msg git hook")
    print("  nocrumbs describe            Pipe per-file change descriptions to app")
    print("  nocrumbs rename-session      Rename a session (pipe JSON with session_id + name)")
    print("  nocrumbs template            Manage commit annotation templates")
    print("  nocrumbs --version           Show version")
    exit(0)
}

let command = args[1]

do {
    switch command {
    case "--version":
        print("nocrumbs \(version)")
    case "event":
        try CaptureEventCommand.run()
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
    case "describe":
        try DescribeCommand.run()
    case "rename-session":
        try RenameSessionCommand.run()
    case "template":
        try TemplateCommand.run()
    default:
        fputs("Unknown command: \(command)\n", stderr)
        exit(1)
    }
} catch {
    // Fire-and-forget: log to stderr but exit 0 so we never block Claude Code
    fputs("nocrumbs: \(error)\n", stderr)
    exit(0)
}
