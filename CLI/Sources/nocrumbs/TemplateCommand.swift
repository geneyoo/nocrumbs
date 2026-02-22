import Foundation

enum TemplateCommand {
    static func run() throws {
        let args = CommandLine.arguments

        // nocrumbs template <action> [--name X] [--body Y]
        guard args.count >= 3 else {
            printUsage()
            return
        }

        switch args[2] {
        case "add": try handleAdd()
        case "list": try handleList()
        case "set": try handleSet()
        case "remove": try handleRemove()
        case "preview": try handlePreview()
        default:
            fputs("Unknown template action: \(args[2])\n", stderr)
            printUsage()
        }
    }

    private static func handleAdd() throws {
        guard let name = flagValue("--name"), let body = flagValue("--body") else {
            fputs("nocrumbs template add: requires --name and --body\n", stderr)
            return
        }
        let response = try sendTemplateRequest([
            "type": "template", "action": "add", "name": name, "body": body,
        ])
        if let error = response["error"] as? String {
            fputs("error: \(error)\n", stderr)
        } else {
            print("Template '\(name)' saved.")
        }
    }

    private static func handleList() throws {
        let response = try sendTemplateRequest(["type": "template", "action": "list"])
        guard let templates = response["templates"] as? [[String: Any]] else { return }
        if templates.isEmpty {
            print("No templates configured.")
            return
        }
        for t in templates {
            let name = t["name"] as? String ?? ""
            let active = t["is_active"] as? Bool ?? false
            let body = t["body"] as? String ?? ""
            let marker = active ? " (active)" : ""
            print("\(name)\(marker)")
            let preview = body.prefix(80).replacingOccurrences(of: "\n", with: "\\n")
            print("  \(preview)")
        }
    }

    private static func handleSet() throws {
        guard let name = flagValue("--name") else {
            fputs("nocrumbs template set: requires --name\n", stderr)
            return
        }
        let response = try sendTemplateRequest([
            "type": "template", "action": "set", "name": name,
        ])
        if let error = response["error"] as? String {
            fputs("error: \(error)\n", stderr)
        } else {
            print("Active template set to '\(name)'.")
        }
    }

    private static func handleRemove() throws {
        guard let name = flagValue("--name") else {
            fputs("nocrumbs template remove: requires --name\n", stderr)
            return
        }
        let response = try sendTemplateRequest([
            "type": "template", "action": "remove", "name": name,
        ])
        if let error = response["error"] as? String {
            fputs("error: \(error)\n", stderr)
        } else {
            print("Template '\(name)' removed.")
        }
    }

    private static func handlePreview() throws {
        let response = try sendTemplateRequest([
            "type": "template",
            "action": "preview",
            "cwd": FileManager.default.currentDirectoryPath,
        ])
        if let preview = response["preview"] as? String {
            print(preview)
        } else if let error = response["error"] as? String {
            fputs("error: \(error)\n", stderr)
        }
    }

    private static func sendTemplateRequest(_ request: [String: Any]) throws -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            throw CLIError.invalidInput("failed to encode request")
        }
        let responseData = try SocketClient.sendAndReceive(data)
        guard !responseData.isEmpty,
            let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            return [:]
        }
        return json
    }

    private static func flagValue(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func printUsage() {
        print("Usage: nocrumbs template <action> [options]")
        print("")
        print("Actions:")
        print("  add      --name <name> --body <template>   Add or update a template")
        print("  list                                        List all templates")
        print("  set      --name <name>                      Set active template")
        print("  remove   --name <name>                      Remove a template")
        print("  preview                                     Preview rendered annotation")
    }
}
