import SwiftUI

/// Loads and manages diff color themes from bundled JSON files.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var currentTheme: DiffTheme?
    private(set) var availableThemes: [DiffTheme] = []

    private init() {}

    func loadBundledThemes() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else { return }
        availableThemes = urls.compactMap { url in
            try? JSONDecoder().decode(DiffTheme.self, from: Data(contentsOf: url))
        }
        currentTheme = availableThemes.first
    }

    func selectTheme(named name: String) {
        currentTheme = availableThemes.first { $0.name == name }
    }
}
