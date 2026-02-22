import SwiftUI

enum AppColors {
    // VCS status
    static let addition = Color.green
    static let deletion = Color.red
    static let modified = Color.orange

    // Diffstat visuals (slightly muted for bars/squares)
    static let additionMuted = Color.green.opacity(0.7)
    static let deletionMuted = Color.red.opacity(0.7)
    static let additionSquare = Color.green.opacity(0.8)
    static let deletionSquare = Color.red.opacity(0.8)

    // Session state
    static let live = Color.green
    static let paused = Color.orange
    static let warning = Color.yellow
}
