import AppKit
import SwiftUI

enum AppFonts {
    // File paths throughout the app
    static func filePath(_ s: CGFloat = 1) -> Font {
        .system(size: round(13 * s)).monospaced()
    }

    // Numeric displays (timestamps, counts, durations)
    static func numeric(_ s: CGFloat = 1) -> Font {
        .system(size: round(13 * s)).monospacedDigit()
    }

    // Small numeric (sidebar, inline stats)
    static func numericSmall(_ s: CGFloat = 1) -> Font {
        .system(size: round(11 * s)).monospacedDigit()
    }

    // Section headers in GroupBoxes
    static func sectionHeader(_ s: CGFloat = 1) -> Font {
        .system(size: round(14 * s), weight: .bold)
    }

    // Status badges (A/M/D)
    static func statusBadge(_ s: CGFloat = 1) -> Font {
        .system(size: round(11 * s), weight: .bold, design: .monospaced)
    }

    // Diff editor (NSFont for NSTextView)
    static func diffEditor(_ s: CGFloat = 1) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: round(12 * s), weight: .regular)
    }

    static func diffLineNumber(_ s: CGFloat = 1) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: round(10 * s), weight: .regular)
    }
}
