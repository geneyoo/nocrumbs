import AppKit
import SwiftUI

struct DiffTextView: NSViewRepresentable {
    let lines: [DiffLine?]
    let side: Side
    var scrollSync: DiffScrollSync?
    var fileExtension: String = ""

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
        textView.backgroundColor = .textBackgroundColor
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
        applyAttributedContent(to: textView)
    }

    private func applyAttributedContent(to textView: DiffNSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

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
                    bgColor = NSColor.systemGreen.withAlphaComponent(0.12)
                    fgColor = .textColor
                case .deletion:
                    bgColor = NSColor.systemRed.withAlphaComponent(0.12)
                    fgColor = .textColor
                case .context:
                    bgColor = .clear
                    fgColor = .textColor
                }
            } else {
                text = ""
                bgColor = NSColor.separatorColor.withAlphaComponent(0.05)
                fgColor = .tertiaryLabelColor
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
            SyntaxHighlighter.highlight(fullString, fileExtension: fileExtension, lineRanges: lineRanges)
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawLineNumbers(dirtyRect)
    }

    private func drawLineNumbers(_ dirtyRect: NSRect) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor,
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
