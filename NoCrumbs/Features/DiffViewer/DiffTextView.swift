import AppKit
import SwiftUI

struct DiffTextView: NSViewRepresentable {
    let lines: [DiffLine?]
    let side: Side
    var scrollSync: DiffScrollSync?
    var fileExtension: String = ""
    var scale: CGFloat = 1.0
    var theme: DiffTheme

    enum Side { case left, right }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = DiffNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindPanel = true
        textView.drawsBackground = true
        textView.backgroundColor = theme.editorBgColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 44

        scrollView.documentView = textView

        scrollSync?.register(scrollView: scrollView, side: side)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? DiffNSTextView else { return }
        textView.lineData = lines
        textView.diffSide = side
        textView.lineNumberColor = theme.lineNumberFgColor
        textView.fontScale = scale
        textView.backgroundColor = theme.editorBgColor
        applyAttributedContent(to: textView)
    }

    private func applyAttributedContent(to textView: DiffNSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let font = AppFonts.diffEditor(scale)

        let fullString = NSMutableAttributedString()
        var lineRanges: [NSRange] = []

        for (index, line) in lines.enumerated() {
            let text: String
            let bgColor: NSColor
            let fgColor: NSColor

            if let line {
                text = line.text
                switch line.type {
                case .addition:
                    bgColor = theme.additionBgColor
                    fgColor = theme.editorFgColor
                case .deletion:
                    bgColor = theme.deletionBgColor
                    fgColor = theme.editorFgColor
                case .context:
                    bgColor = theme.contextBgColor
                    fgColor = theme.editorFgColor
                }
            } else {
                text = ""
                bgColor = theme.emptyLineBgColor
                fgColor = theme.lineNumberFgColor
            }

            let lineStr = text + (index < lines.count - 1 ? "\n" : "")
            let start = fullString.length
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: fgColor,
                .backgroundColor: bgColor,
            ]
            fullString.append(NSAttributedString(string: lineStr, attributes: attrs))
            // Track the text portion (exclude trailing newline) for syntax highlighting
            lineRanges.append(NSRange(location: start, length: text.utf16.count))
        }

        // Overlay syntax highlighting colors
        if !fileExtension.isEmpty {
            SyntaxHighlighter.highlight(fullString, fileExtension: fileExtension, lineRanges: lineRanges, theme: theme)
        }

        textStorage.beginEditing()
        textStorage.setAttributedString(fullString)
        textStorage.endEditing()
    }
}

// MARK: - Custom NSTextView with Line Number Gutter

final class DiffNSTextView: NSTextView {
    var lineData: [DiffLine?] = []
    var diffSide: DiffTextView.Side = .left
    var lineNumberColor: NSColor = .tertiaryLabelColor
    var fontScale: CGFloat = 1.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawLineNumbers(dirtyRect)
    }

    private func drawLineNumbers(_ dirtyRect: NSRect) {
        guard let layoutManager = layoutManager,
            let textContainer = textContainer
        else { return }

        let font = AppFonts.diffLineNumber(fontScale)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: lineNumberColor,
        ]

        let inset = textContainerInset
        var lineIndex = 0
        var glyphIndex = 0
        let totalGlyphs = layoutManager.numberOfGlyphs

        while glyphIndex < totalGlyphs, lineIndex < lineData.count {
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex, effectiveRange: &lineRange
            )

            let y = lineRect.origin.y + inset.height
            let lineHeight = lineRect.height

            if NSRect(x: 0, y: y, width: 40, height: lineHeight).intersects(dirtyRect) {
                if let line = lineData[lineIndex] {
                    let num: Int?
                    switch diffSide {
                    case .left: num = line.oldLineNumber
                    case .right: num = line.newLineNumber
                    }

                    if let num {
                        let str = "\(num)"
                        let size = str.size(withAttributes: attrs)
                        let drawPoint = NSPoint(x: 36 - size.width, y: y + (lineHeight - size.height) / 2)
                        str.draw(at: drawPoint, withAttributes: attrs)
                    }
                }
            }

            glyphIndex = NSMaxRange(lineRange)
            lineIndex += 1
        }
    }
}
