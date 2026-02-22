import SwiftUI

// MARK: - Session State Indicator

struct SessionStateIndicator: View {
    let state: SessionState

    var body: some View {
        switch state {
        case .live:
            LiveDot()
            Text("Live")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
        case .interrupted:
            Image(systemName: "pause.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Paused")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
        case .ended:
            Image(systemName: "stop.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Ended")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Live Indicator

struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 6, height: 6)
            .scaleEffect(pulse ? 1.4 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
