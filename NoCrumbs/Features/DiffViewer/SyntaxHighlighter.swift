import AppKit

enum SyntaxHighlighter {

    // MARK: - Public

    /// Apply syntax highlighting colors to an attributed string based on file extension.
    /// Overlays foreground colors on top of existing attributes (preserves background).
    static func highlight(_ attrString: NSMutableAttributedString, fileExtension: String, lineRanges: [NSRange], theme: DiffTheme) {
        guard let grammar = grammar(for: fileExtension, theme: theme) else { return }

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

    private static let grammarMap: [String: (DiffTheme) -> Grammar] = [
        "swift": { swiftGrammar($0) }, "py": { pythonGrammar($0) },
        "js": { jsGrammar($0) }, "jsx": { jsGrammar($0) }, "mjs": { jsGrammar($0) },
        "ts": { tsGrammar($0) }, "tsx": { tsGrammar($0) },
        "json": { jsonGrammar($0) }, "yml": { yamlGrammar($0) }, "yaml": { yamlGrammar($0) },
        "md": { markdownGrammar($0) }, "markdown": { markdownGrammar($0) },
        "sh": { shellGrammar($0) }, "bash": { shellGrammar($0) }, "zsh": { shellGrammar($0) },
        "rb": { rubyGrammar($0) }, "go": { goGrammar($0) }, "rs": { rustGrammar($0) },
        "c": { cGrammar($0) }, "h": { cGrammar($0) },
        "cpp": { cppGrammar($0) }, "cc": { cppGrammar($0) }, "cxx": { cppGrammar($0) }, "hpp": { cppGrammar($0) },
        "java": { javaGrammar($0) }, "css": { cssGrammar($0) },
        "html": { htmlGrammar($0) }, "htm": { htmlGrammar($0) },
        "sql": { sqlGrammar($0) }, "toml": { tomlGrammar($0) },
    ]

    private static func grammar(for ext: String, theme: DiffTheme) -> Grammar? {
        let key = ext.lowercased()
        return grammarMap[key].map { builder in
            builder(theme)
        }
    }

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

    private static func swiftGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#"#"[^"]*""#, t.stringColor),            // #"raw string"#
        (#"""".*?""""#, t.stringColor),            // multi-line string (single-line portion)
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"@\w+"#, t.preprocessorColor),           // @Observable, @State, etc.
        (#"#\w+"#, t.preprocessorColor),           // #if, #available, etc.
        (#"\b(?:import|func|var|let|class|struct|enum|protocol|extension|return|if|else|guard|switch|case|default|for|while|repeat|break|continue|throw|throws|try|catch|do|defer|where|in|as|is|self|Self|super|init|deinit|nil|true|false|static|private|fileprivate|internal|public|open|override|final|lazy|weak|unowned|mutating|nonmutating|typealias|associatedtype|some|any|async|await|actor|nonisolated|isolated|consuming|borrowing|sending|inout)\b"#, t.keywordColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, t.numberColor),
    ])) }

    private static func pythonGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"#.*$"#, t.commentColor),
        (#"\"\"\"[\s\S]*?\"\"\""#, t.stringColor),
        (#"'''[\s\S]*?'''"#, t.stringColor),
        (#"f"(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"f'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"@\w+"#, t.preprocessorColor),
        (#"\b(?:def|class|return|if|elif|else|for|while|break|continue|pass|import|from|as|try|except|finally|raise|with|yield|lambda|and|or|not|in|is|None|True|False|self|async|await|global|nonlocal|del|assert)\b"#, t.keywordColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, t.numberColor),
    ])) }

    private static func jsGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#"`(?:[^`\\]|\\.)*`"#, t.stringColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"\b(?:function|const|let|var|return|if|else|for|while|do|switch|case|default|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|null|undefined|true|false|void)\b"#, t.keywordColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, t.numberColor),
    ])) }

    private static func tsGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#"`(?:[^`\\]|\\.)*`"#, t.stringColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"@\w+"#, t.preprocessorColor),
        (#"\b(?:function|const|let|var|return|if|else|for|while|do|switch|case|default|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|null|undefined|true|false|void|type|interface|enum|implements|abstract|declare|namespace|module|readonly|keyof|infer|never|unknown|any|number|string|boolean|symbol|bigint)\b"#, t.keywordColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, t.numberColor),
    ])) }

    private static func jsonGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#""(?:[^"\\]|\\.)*"\s*:"#, t.propertyColor),   // keys
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),           // string values
        (#"\b(?:true|false|null)\b"#, t.keywordColor),
        (#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, t.numberColor),
    ])) }

    private static func yamlGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"#.*$"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"^[\w./-]+(?=\s*:)"#, t.propertyColor),
        (#"\b(?:true|false|null|yes|no)\b"#, t.keywordColor),
        (#"\b\d+(?:\.\d+)?\b"#, t.numberColor),
    ])) }

    private static func markdownGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"^#{1,6}\s+.*$"#, t.keywordColor),             // headers
        (#"`[^`]+`"#, t.stringColor),                     // inline code
        (#"\[([^\]]+)\]\([^)]+\)"#, t.propertyColor),     // links
        (#"\*\*[^*]+\*\*"#, t.typeColor),                 // bold
    ])) }

    private static func shellGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"#.*$"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'[^']*'"#, t.stringColor),
        (#"\$\{?[\w@#?$!*-]+\}?"#, t.preprocessorColor), // variables
        (#"\b(?:if|then|elif|else|fi|for|while|do|done|case|esac|in|function|return|local|export|source|alias|unalias|set|unset|readonly|shift|exit|exec|eval|trap|wait|cd|echo|printf|read|test)\b"#, t.keywordColor),
    ])) }

    private static func rubyGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"#.*$"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#":\w+"#, t.propertyColor),                      // symbols
        (#"\b(?:def|end|class|module|if|elsif|else|unless|for|while|until|do|begin|rescue|ensure|raise|return|yield|self|super|nil|true|false|require|include|extend|attr_accessor|attr_reader|attr_writer|puts|print)\b"#, t.keywordColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b\d+(?:\.\d+)?\b"#, t.numberColor),
    ])) }

    private static func goGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#"`[^`]*`"#, t.stringColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"\b(?:func|var|const|type|struct|interface|map|chan|go|select|switch|case|default|if|else|for|range|return|break|continue|goto|fallthrough|defer|package|import|nil|true|false|iota|make|new|len|cap|append|copy|delete|close|panic|recover)\b"#, t.keywordColor),
        (#"\b(?:int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|string|bool|byte|rune|error|any)\b"#, t.typeColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, t.numberColor),
    ])) }

    private static func rustGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"#\[[\w(,= )]*\]"#, t.preprocessorColor),       // attributes
        (#"\b(?:fn|let|mut|const|static|struct|enum|impl|trait|type|pub|crate|mod|use|as|self|Self|super|return|if|else|match|for|while|loop|break|continue|move|ref|where|async|await|unsafe|extern|dyn|true|false)\b"#, t.keywordColor),
        (#"\b(?:i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc)\b"#, t.typeColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?\b"#, t.numberColor),
    ])) }

    private static func cGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"#\s*\w+"#, t.preprocessorColor),
        (#"\b(?:auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|NULL)\b"#, t.keywordColor),
        (#"\b[A-Z][A-Za-z0-9_]*(?:_t)?\b"#, t.typeColor),
        (#"\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)[UuLlFf]*\b"#, t.numberColor),
    ])) }

    private static func cppGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"#\s*\w+"#, t.preprocessorColor),
        (#"\b(?:auto|break|case|catch|class|const|constexpr|continue|default|delete|do|dynamic_cast|else|enum|explicit|export|extern|false|for|friend|goto|if|inline|mutable|namespace|new|noexcept|nullptr|operator|override|private|protected|public|register|reinterpret_cast|return|short|signed|sizeof|static|static_cast|struct|switch|template|this|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|while)\b"#, t.keywordColor),
        (#"\b(?:bool|char|char8_t|char16_t|char32_t|wchar_t|int|long|float|double|size_t|string|vector|map|set|unique_ptr|shared_ptr)\b"#, t.typeColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)[UuLlFf]*\b"#, t.numberColor),
    ])) }

    private static func javaGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"//.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"@\w+"#, t.preprocessorColor),
        (#"\b(?:abstract|assert|break|case|catch|class|continue|default|do|else|enum|extends|final|finally|for|if|implements|import|instanceof|interface|native|new|package|private|protected|public|return|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|void|volatile|while|true|false|null)\b"#, t.keywordColor),
        (#"\b(?:boolean|byte|char|double|float|int|long|short|String|Integer|Long|Double|Float|Boolean|Object|List|Map|Set|Optional)\b"#, t.typeColor),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, t.typeColor),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?[LlFfDd]?\b"#, t.numberColor),
    ])) }

    private static func cssGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"/\*.*?\*/"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"#[0-9a-fA-F]{3,8}\b"#, t.numberColor),         // hex colors
        (#"[\w-]+(?=\s*:)"#, t.propertyColor),              // property names
        (#"\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|pt|cm|mm|in|s|ms|deg|rad|fr)?\b"#, t.numberColor),
    ])) }

    private static func htmlGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"<!--.*?-->"#, t.commentColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"</?[\w-]+"#, t.keywordColor),                    // tag names
        (#"\b[\w-]+(?=\s*=)"#, t.propertyColor),            // attribute names
    ])) }

    private static func sqlGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"--.*$"#, t.commentColor),
        (#"/\*.*?\*/"#, t.commentColor),
        (#"'(?:[^'\\]|\\.)*'"#, t.stringColor),
        (#"\b(?i:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|IN|EXISTS|BETWEEN|LIKE|IS|NULL|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|AS|DISTINCT|COUNT|SUM|AVG|MIN|MAX|CASE|WHEN|THEN|ELSE|END|UNION|PRIMARY|KEY|FOREIGN|REFERENCES|CASCADE|CONSTRAINT|IF|BEGIN|COMMIT|ROLLBACK|TRANSACTION|PRAGMA|INTEGER|TEXT|REAL|BLOB)\b"#, t.keywordColor),
        (#"\b\d+(?:\.\d+)?\b"#, t.numberColor),
    ])) }

    private static func tomlGrammar(_ t: DiffTheme) -> Grammar { Grammar(rules: rules([
        (#"#.*$"#, t.commentColor),
        (#""""[\s\S]*?""""#, t.stringColor),
        (#"'''[\s\S]*?'''"#, t.stringColor),
        (#""(?:[^"\\]|\\.)*""#, t.stringColor),
        (#"'[^']*'"#, t.stringColor),
        (#"^\s*\[[\w.]+\]"#, t.preprocessorColor),          // section headers
        (#"^[\w.-]+(?=\s*=)"#, t.propertyColor),
        (#"\b(?:true|false)\b"#, t.keywordColor),
        (#"\b\d[\d_]*(?:\.\d[\d_]*)?\b"#, t.numberColor),
    ])) }
    // swiftlint:enable line_length
}
