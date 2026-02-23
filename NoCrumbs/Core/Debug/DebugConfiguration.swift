import Foundation

enum DebugConfiguration {
    static let isMockDataEnabled = ProcessInfo.processInfo.arguments.contains("-debugMockData")
}
