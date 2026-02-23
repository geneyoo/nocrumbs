import SwiftUI

/// NSSplitView wrapper for file list / diff panes — native AppKit resize, no SwiftUI relayout jank.
struct DiffSplitView<FileList: View, Detail: View>: NSViewRepresentable {
    var fileListVisible: Bool
    var fileListWidth: CGFloat
    @ViewBuilder var fileList: () -> FileList
    @ViewBuilder var detail: () -> Detail

    func makeNSView(context: Context) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = context.coordinator

        let fileListHost = NSHostingView(rootView: fileList())
        let detailHost = NSHostingView(rootView: detail())

        split.addArrangedSubview(fileListHost)
        split.addArrangedSubview(detailHost)

        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        // Set initial width
        fileListHost.frame.size.width = fileListWidth
        split.adjustSubviews()

        context.coordinator.split = split

        return split
    }

    func updateNSView(_ split: NSSplitView, context: Context) {
        guard split.subviews.count == 2 else { return }

        let fileListHost = split.subviews[0] as! NSHostingView<FileList>
        let detailHost = split.subviews[1] as! NSHostingView<Detail>

        fileListHost.rootView = fileList()
        detailHost.rootView = detail()

        if fileListVisible {
            if split.isSubviewCollapsed(fileListHost) {
                split.setPosition(fileListWidth, ofDividerAt: 0)
            }
        } else {
            split.setPosition(0, ofDividerAt: 0)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        weak var split: NSSplitView?

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            120
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            400
        }

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            subview == splitView.subviews.first
        }
    }
}
