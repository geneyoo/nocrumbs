import Foundation

let version = "0.1.0"

if CommandLine.arguments.contains("--version") {
    print("nocrumbs \(version)")
} else {
    print("nocrumbs \(version) — git blame for the AI era")
    print("Usage: nocrumbs event --project <path> --files <files>")
}
