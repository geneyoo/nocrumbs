import SwiftUI

/// Loads and manages diff color themes from bundled JSON files.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private static let selectedThemeKey = "selectedDiffTheme"

    private(set) var currentTheme: DiffTheme?
    private(set) var availableThemes: [DiffTheme] = []

    private init() {}

    func loadBundledThemes() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else { return }
        availableThemes = urls.compactMap { url in
            try? JSONDecoder().decode(DiffTheme.self, from: Data(contentsOf: url))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let savedName = UserDefaults.standard.string(forKey: Self.selectedThemeKey)
        currentTheme = availableThemes.first { $0.name == savedName } ?? availableThemes.first
    }

    func selectTheme(named name: String) {
        currentTheme = availableThemes.first { $0.name == name }
        UserDefaults.standard.set(name, forKey: Self.selectedThemeKey)
    }
}
