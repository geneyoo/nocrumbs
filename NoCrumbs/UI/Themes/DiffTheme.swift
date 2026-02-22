import AppKit

/// Defines the color palette for diff rendering and syntax highlighting.
struct DiffTheme: Codable, Equatable {
    let name: String
    let background: String
    let foreground: String
    let addedLine: String
    let removedLine: String
    let addedBackground: String
    let removedBackground: String
    let lineNumber: String
    let hunkHeader: String
    let contextBackground: String
    let emptyLineBackground: String

    // Syntax highlighting colors
    let comment: String
    let string: String
    let keyword: String
    let type: String
    let number: String
    let preprocessor: String
    let property: String

    // MARK: - Diff rendering colors

    var editorBgColor: NSColor { NSColor(hex: background) }
    var editorFgColor: NSColor { NSColor(hex: foreground) }
    var additionBgColor: NSColor { NSColor(hex: addedBackground) }
    var deletionBgColor: NSColor { NSColor(hex: removedBackground) }
    var contextBgColor: NSColor { NSColor(hex: contextBackground) }
    var emptyLineBgColor: NSColor { NSColor(hex: emptyLineBackground) }
    var lineNumberFgColor: NSColor { NSColor(hex: lineNumber) }

    // MARK: - Syntax highlighting colors

    var commentColor: NSColor { NSColor(hex: comment) }
    var stringColor: NSColor { NSColor(hex: string) }
    var keywordColor: NSColor { NSColor(hex: keyword) }
    var typeColor: NSColor { NSColor(hex: type) }
    var numberColor: NSColor { NSColor(hex: number) }
    var preprocessorColor: NSColor { NSColor(hex: preprocessor) }
    var propertyColor: NSColor { NSColor(hex: property) }
}

private extension NSColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
