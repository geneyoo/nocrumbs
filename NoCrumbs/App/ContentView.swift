import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("Timeline")
                    .font(.headline)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        } detail: {
            Text("NoCrumbs")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}
