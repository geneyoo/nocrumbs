import AppKit

final class DiffScrollSync {
    private weak var leftScrollView: NSScrollView?
    private weak var rightScrollView: NSScrollView?
    private var isSyncing = false
    private var isAttached = false

    func register(scrollView: NSScrollView, side: DiffTextView.Side) {
        switch side {
        case .left: leftScrollView = scrollView
        case .right: rightScrollView = scrollView
        }
        tryAttach()
    }

    private func tryAttach() {
        guard !isAttached,
              let left = leftScrollView,
              let right = rightScrollView else { return }
        isAttached = true

        left.contentView.postsBoundsChangedNotifications = true
        right.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(leftDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: left.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rightDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: right.contentView
        )
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        leftScrollView = nil
        rightScrollView = nil
        isAttached = false
    }

    @objc private func leftDidScroll(_ notification: Notification) {
        guard !isSyncing, let left = leftScrollView, let right = rightScrollView else { return }
        isSyncing = true
        right.contentView.bounds.origin = left.contentView.bounds.origin
        isSyncing = false
    }

    @objc private func rightDidScroll(_ notification: Notification) {
        guard !isSyncing, let left = leftScrollView, let right = rightScrollView else { return }
        isSyncing = true
        left.contentView.bounds.origin = right.contentView.bounds.origin
        isSyncing = false
    }

    deinit {
        detach()
    }
}
