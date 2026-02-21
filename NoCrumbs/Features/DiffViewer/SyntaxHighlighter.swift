import AppKit

enum SyntaxHighlighter {

    // MARK: - Public

    /// Apply syntax highlighting colors to an attributed string based on file extension.
    /// Overlays foreground colors on top of existing attributes (preserves background).
    static func highlight(_ attrString: NSMutableAttributedString, fileExtension: String, lineRanges: [NSRange]) {
        guard let grammar = grammar(for: fileExtension) else { return }

        for lineRange in lineRanges where lineRange.length > 0 {
            let lineText = (attrString.string as NSString).substring(with: lineRange)
            applyGrammar(grammar, to: attrString, text: lineText, baseOffset: lineRange.location)
        }
    }

    // MARK: - Grammar

    private struct Grammar {
        let rules: [(pattern: NSRegularExpression, color: NSColor)]
    }

    private static func applyGrammar(_ grammar: Grammar, to attrString: NSMutableAttributedString, text: String, baseOffset: Int) {
        // Track which character positions have been colored (earlier rules win)
        var colored = IndexSet()

        for rule in grammar.rules {
            let matches = rule.pattern.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                // Use capture group 1 if it exists, otherwise full match
                let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1)
                    : match.range

                // Skip if any part of this range is already colored
                let indexRange = range.location..<(range.location + range.length)
                if colored.intersects(integersIn: indexRange) { continue }

                colored.insert(integersIn: indexRange)
                let targetRange = NSRange(location: baseOffset + range.location, length: range.length)
                attrString.addAttribute(.foregroundColor, value: rule.color, range: targetRange)
            }
        }
    }

    // MARK: - Language Detection

    private static let grammarMap: [String: () -> Grammar] = [
        "swift": { swiftGrammar }, "py": { pythonGrammar },
        "js": { jsGrammar }, "jsx": { jsGrammar }, "mjs": { jsGrammar },
        "ts": { tsGrammar }, "tsx": { tsGrammar },
        "json": { jsonGrammar }, "yml": { yamlGrammar }, "yaml": { yamlGrammar },
        "md": { markdownGrammar }, "markdown": { markdownGrammar },
        "sh": { shellGrammar }, "bash": { shellGrammar }, "zsh": { shellGrammar },
        "rb": { rubyGrammar }, "go": { goGrammar }, "rs": { rustGrammar },
        "c": { cGrammar }, "h": { cGrammar },
        "cpp": { cppGrammar }, "cc": { cppGrammar }, "cxx": { cppGrammar }, "hpp": { cppGrammar },
        "java": { javaGrammar }, "css": { cssGrammar },
        "html": { htmlGrammar }, "htm": { htmlGrammar },
        "sql": { sqlGrammar }, "toml": { tomlGrammar },
    ]

    private static func grammar(for ext: String) -> Grammar? {
        grammarMap[ext.lowercased()]?()
    }

    // MARK: - Colors (Xcode-inspired, adapts to dark/light)

    private static let keyword = NSColor.systemPink          // pink keywords like Xcode
    private static let string = NSColor.systemRed            // red strings
    private static let comment = NSColor.systemGreen         // green comments
    private static let number = NSColor.systemBlue           // blue numbers
    private static let type = NSColor.systemCyan             // cyan types
    private static let preprocessor = NSColor.systemOrange   // orange preprocessor/decorators
    private static let property = NSColor.systemPurple       // purple properties

    // MARK: - Regex Helpers

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static func rules(_ pairs: [(String, NSColor)]) -> [(pattern: NSRegularExpression, color: NSColor)] {
        pairs.map { (regex($0.0), $0.1) }
    }

    // MARK: - Grammars

    // Rules are ordered by priority — first match wins per character position.
    // Comments and strings first so keywords inside them don't get colored.
    // swiftlint:disable line_length

    private static let swiftGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#"#"[^"]*""#, string),            // #"raw string"#
        (#"""".*?""""#, string),            // multi-line string (single-line portion)
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"@\w+"#, preprocessor),           // @Observable, @State, etc.
        (#"#\w+"#, preprocessor),           // #if, #available, etc.
        (#"\b(?:import|func|var|let|class|struct|enum|protocol|extension|return|if|else|guard|switch|case|default|for|while|repeat|break|continue|throw|throws|try|catch|do|defer|where|in|as|is|self|Self|super|init|deinit|nil|true|false|static|private|fileprivate|internal|public|open|override|final|lazy|weak|unowned|mutating|nonmutating|typealias|associatedtype|some|any|async|await|actor|nonisolated|isolated|consuming|borrowing|sending|inout)\b"#, keyword),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, number),
    ]))

    private static let pythonGrammar = Grammar(rules: rules([
        (#"#.*$"#, comment),
        (#"\"\"\"[\s\S]*?\"\"\""#, string),
        (#"'''[\s\S]*?'''"#, string),
        (#"f"(?:[^"\\]|\\.)*""#, string),
        (#"f'(?:[^'\\]|\\.)*'"#, string),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"@\w+"#, preprocessor),
        (#"\b(?:def|class|return|if|elif|else|for|while|break|continue|pass|import|from|as|try|except|finally|raise|with|yield|lambda|and|or|not|in|is|None|True|False|self|async|await|global|nonlocal|del|assert)\b"#, keyword),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, number),
    ]))

    private static let jsGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#"`(?:[^`\\]|\\.)*`"#, string),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"\b(?:function|const|let|var|return|if|else|for|while|do|switch|case|default|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|null|undefined|true|false|void)\b"#, keyword),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, number),
    ]))

    private static let tsGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#"`(?:[^`\\]|\\.)*`"#, string),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"@\w+"#, preprocessor),
        (#"\b(?:function|const|let|var|return|if|else|for|while|do|switch|case|default|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|null|undefined|true|false|void|type|interface|enum|implements|abstract|declare|namespace|module|readonly|keyof|infer|never|unknown|any|number|string|boolean|symbol|bigint)\b"#, keyword),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, number),
    ]))

    private static let jsonGrammar = Grammar(rules: rules([
        (#""(?:[^"\\]|\\.)*"\s*:"#, property),   // keys
        (#""(?:[^"\\]|\\.)*""#, string),           // string values
        (#"\b(?:true|false|null)\b"#, keyword),
        (#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, number),
    ]))

    private static let yamlGrammar = Grammar(rules: rules([
        (#"#.*$"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"^[\w./-]+(?=\s*:)"#, property),
        (#"\b(?:true|false|null|yes|no)\b"#, keyword),
        (#"\b\d+(?:\.\d+)?\b"#, number),
    ]))

    private static let markdownGrammar = Grammar(rules: rules([
        (#"^#{1,6}\s+.*$"#, keyword),             // headers
        (#"`[^`]+`"#, string),                     // inline code
        (#"\[([^\]]+)\]\([^)]+\)"#, property),     // links
        (#"\*\*[^*]+\*\*"#, type),                 // bold
    ]))

    private static let shellGrammar = Grammar(rules: rules([
        (#"#.*$"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'[^']*'"#, string),
        (#"\$\{?[\w@#?$!*-]+\}?"#, preprocessor), // variables
        (#"\b(?:if|then|elif|else|fi|for|while|do|done|case|esac|in|function|return|local|export|source|alias|unalias|set|unset|readonly|shift|exit|exec|eval|trap|wait|cd|echo|printf|read|test)\b"#, keyword),
    ]))

    private static let rubyGrammar = Grammar(rules: rules([
        (#"#.*$"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#":\w+"#, property),                      // symbols
        (#"\b(?:def|end|class|module|if|elsif|else|unless|for|while|until|do|begin|rescue|ensure|raise|return|yield|self|super|nil|true|false|require|include|extend|attr_accessor|attr_reader|attr_writer|puts|print)\b"#, keyword),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b\d+(?:\.\d+)?\b"#, number),
    ]))

    private static let goGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#"`[^`]*`"#, string),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"\b(?:func|var|const|type|struct|interface|map|chan|go|select|switch|case|default|if|else|for|range|return|break|continue|goto|fallthrough|defer|package|import|nil|true|false|iota|make|new|len|cap|append|copy|delete|close|panic|recover)\b"#, keyword),
        (#"\b(?:int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|string|bool|byte|rune|error|any)\b"#, type),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, number),
    ]))

    private static let rustGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"#\[[\w(,= )]*\]"#, preprocessor),       // attributes
        (#"\b(?:fn|let|mut|const|static|struct|enum|impl|trait|type|pub|crate|mod|use|as|self|Self|super|return|if|else|match|for|while|loop|break|continue|move|ref|where|async|await|unsafe|extern|dyn|true|false)\b"#, keyword),
        (#"\b(?:i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc)\b"#, type),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, number),
    ]))

    private static let cGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"#\s*\w+"#, preprocessor),
        (#"\b(?:auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|NULL)\b"#, keyword),
        (#"\b[A-Z][A-Za-z0-9_]*(?:_t)?\b"#, type),
        (#"\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)[UuLlFf]*\b"#, number),
    ]))

    private static let cppGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"#\s*\w+"#, preprocessor),
        (#"\b(?:auto|break|case|catch|class|const|constexpr|continue|default|delete|do|dynamic_cast|else|enum|explicit|export|extern|false|for|friend|goto|if|inline|mutable|namespace|new|noexcept|nullptr|operator|override|private|protected|public|register|reinterpret_cast|return|short|signed|sizeof|static|static_cast|struct|switch|template|this|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|while)\b"#, keyword),
        (#"\b(?:bool|char|char8_t|char16_t|char32_t|wchar_t|int|long|float|double|size_t|string|vector|map|set|unique_ptr|shared_ptr)\b"#, type),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)[UuLlFf]*\b"#, number),
    ]))

    private static let javaGrammar = Grammar(rules: rules([
        (#"//.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"@\w+"#, preprocessor),
        (#"\b(?:abstract|assert|break|case|catch|class|continue|default|do|else|enum|extends|final|finally|for|if|implements|import|instanceof|interface|native|new|package|private|protected|public|return|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|void|volatile|while|true|false|null)\b"#, keyword),
        (#"\b(?:boolean|byte|char|double|float|int|long|short|String|Integer|Long|Double|Float|Boolean|Object|List|Map|Set|Optional)\b"#, type),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, type),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?[LlFfDd]?\b"#, number),
    ]))

    private static let cssGrammar = Grammar(rules: rules([
        (#"/\*.*?\*/"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"#[0-9a-fA-F]{3,8}\b"#, number),         // hex colors
        (#"[\w-]+(?=\s*:)"#, property),              // property names
        (#"\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|pt|cm|mm|in|s|ms|deg|rad|fr)?\b"#, number),
    ]))

    private static let htmlGrammar = Grammar(rules: rules([
        (#"<!--.*?-->"#, comment),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"</?[\w-]+"#, keyword),                    // tag names
        (#"\b[\w-]+(?=\s*=)"#, property),            // attribute names
    ]))

    private static let sqlGrammar = Grammar(rules: rules([
        (#"--.*$"#, comment),
        (#"/\*.*?\*/"#, comment),
        (#"'(?:[^'\\]|\\.)*'"#, string),
        (#"\b(?i:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|IN|EXISTS|BETWEEN|LIKE|IS|NULL|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|AS|DISTINCT|COUNT|SUM|AVG|MIN|MAX|CASE|WHEN|THEN|ELSE|END|UNION|PRIMARY|KEY|FOREIGN|REFERENCES|CASCADE|CONSTRAINT|IF|BEGIN|COMMIT|ROLLBACK|TRANSACTION|PRAGMA|INTEGER|TEXT|REAL|BLOB)\b"#, keyword),
        (#"\b\d+(?:\.\d+)?\b"#, number),
    ]))

    private static let tomlGrammar = Grammar(rules: rules([
        (#"#.*$"#, comment),
        (#""""[\s\S]*?""""#, string),
        (#"'''[\s\S]*?'''"#, string),
        (#""(?:[^"\\]|\\.)*""#, string),
        (#"'[^']*'"#, string),
        (#"^\s*\[[\w.]+\]"#, preprocessor),          // section headers
        (#"^[\w.-]+(?=\s*=)"#, property),
        (#"\b(?:true|false)\b"#, keyword),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?\b"#, number),
    ]))
    // swiftlint:enable line_length
}
