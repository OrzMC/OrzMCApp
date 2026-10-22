import AppKit

/// 观察**用户**对控制台滚动位置的改变（不拦截点击）。
///
/// 只监听 `NSScrollView.didLiveScrollNotification`：它只在用户拖滚动条/滚轮/键盘翻页
/// 改变位置后发布，日志追加与程序 `scrollTo` 都不会触发，因此不会和自动跟随打架。
final class ConsoleScrollProbe: NSView {
    var onLeaveBottom: (() -> Void)?
    var onReachBottom: (() -> Void)?

    /// 用户滚动时命中的容差（pt）：贴底 4pt 内视为「在底部」。
    private let bottomTolerance: CGFloat = 4

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        // SwiftUI 安装到 NSScrollView 后才查询祖先。
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.window != nil, let scroll = self.enclosingScrollView else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(userScrolled),
                name: NSScrollView.didLiveScrollNotification, object: scroll
            )
        }
    }

    @objc private func userScrolled(_ notification: Notification) {
        guard let scroll = notification.object as? NSScrollView,
              let document = scroll.documentView else { return }
        let visible = scroll.contentView.documentVisibleRect
        let atBottom = document.isFlipped
            ? visible.maxY >= document.bounds.maxY - bottomTolerance
            : visible.minY <= document.bounds.minY + bottomTolerance
        if atBottom {
            onReachBottom?()
        } else {
            onLeaveBottom?()
        }
    }
}
