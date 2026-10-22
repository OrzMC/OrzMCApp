import AppKit
import SwiftUI

/// 只在**用户自己**滚动时才报告位置：日志追加和程序滚动不触发。
///
/// `onLeaveBottom` → 暂停跟随；`onReachBottom` → 恢复跟随并清零未读。
struct ConsoleScrollObserver: NSViewRepresentable {
    var onLeaveBottom: () -> Void
    var onReachBottom: () -> Void

    func makeNSView(context: Context) -> ConsoleScrollProbe {
        let view = ConsoleScrollProbe()
        view.onLeaveBottom = onLeaveBottom
        view.onReachBottom = onReachBottom
        return view
    }

    func updateNSView(_ nsView: ConsoleScrollProbe, context: Context) {
        nsView.onLeaveBottom = onLeaveBottom
        nsView.onReachBottom = onReachBottom
    }

    static func dismantleNSView(_ nsView: ConsoleScrollProbe, coordinator: ()) {
        NotificationCenter.default.removeObserver(nsView)
    }
}
