import AppKit
import SwiftUI

enum AppFonts {
    // File paths throughout the app
    static let filePath = Font.callout.monospaced()

    // Numeric displays (timestamps, counts, durations)
    static let numeric = Font.callout.monospacedDigit()

    // Small numeric (sidebar, inline stats)
    static let numericSmall = Font.caption.monospacedDigit()

    // Section headers in GroupBoxes
    static let sectionHeader = Font.headline

    // Status badges (A/M/D)
    static let statusBadge = Font.system(size: 11, weight: .bold, design: .monospaced)

    // Diff editor (NSFont for NSTextView)
    static let diffEditor = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let diffLineNumber = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
}
