import Foundation

@Observable
final class AppScale {
    static let shared = AppScale()

    private static let defaultsKey = "appScale"
    private static let minScale: CGFloat = 0.6
    private static let maxScale: CGFloat = 2.0
    private static let step: CGFloat = 0.1

    var level: CGFloat {
        didSet { UserDefaults.standard.set(level, forKey: Self.defaultsKey) }
    }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.defaultsKey)
        self.level = stored > 0 ? CGFloat(stored) : 1.0
    }

    func zoomIn() {
        level = min(level + Self.step, Self.maxScale)
    }

    func zoomOut() {
        level = max(level - Self.step, Self.minScale)
    }

    func resetZoom() {
        level = 1.0
    }
}
