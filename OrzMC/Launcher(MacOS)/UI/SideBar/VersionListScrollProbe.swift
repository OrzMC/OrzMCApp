//
//  VersionListScrollProbe.swift
//  OrzMC
//

import AppKit
import SwiftUI

/// 版本列表的底层滚动控制。
///
/// 为什么需要它：`ScrollViewReader.scrollTo(id, anchor:)` 对**懒加载**的 `List` 只按估算位置滚，
/// 跳到很远的一行时会稳定地差上几行（实测 ⌘↓ 后最后一行仍被裁掉），也滚不到"真正的底"
/// （末尾留白看不到）。这里直接拿到 `List` 背后的 `NSScrollView`，滚到 `documentView` 的首/末端。
@MainActor
final class VersionListScrollController {
    weak var scrollView: NSScrollView?

    func scrollToTop() {
        scroll(toRow: 0, edge: .top)
    }

    func scrollToBottom() {
        guard let table = scrollView?.documentView as? NSTableView else { return }
        scroll(toRow: table.numberOfRows - 1, edge: .bottom)
    }

    /// 懒加载的 `NSTableView` 文档高度是**边滚边长**的，一次算不准：
    /// 先让表格把目标行滚进视野，再按"当前文档高度 − 视口高度"贴边，重复几轮直到收敛。
    private func scroll(toRow row: Int, edge: Edge) {
        guard let scrollView, let table = scrollView.documentView as? NSTableView, row >= 0 else { return }
        for _ in 0..<5 {
            table.scrollRowToVisible(row)
            scrollView.layoutSubtreeIfNeeded()
            let clip = scrollView.contentView
            let maxY = max(0, table.bounds.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: edge == .top ? 0 : maxY))
            scrollView.reflectScrolledClipView(clip)
            log("row=\(row) doc=\(Int(table.bounds.height)) clip=\(Int(clip.bounds.height)) y=\(Int(clip.bounds.origin.y))")
        }
    }

    private func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["ORZMC_KEY_DEBUG"] != nil else { return }
        FileHandle.standardError.write(Data("scroll: \(message)\n".utf8))
    }
}

/// 把 `List` 的 `NSScrollView` 交给控制器（不拦截点击）。
///
/// 注意：SwiftUI 的 `List` **不是**探针的祖先（背景层不在 clip view 里），
/// 所以不能只用 `enclosingScrollView`；这里按窗口坐标在视图树里找"包住探针的那个 NSTableView 滚动视图"。
struct VersionListScrollProbe: NSViewRepresentable {
    let controller: VersionListScrollController

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.controller = controller
    }

    final class ProbeView: NSView {
        weak var controller: VersionListScrollController?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, let window = self.window else { return }
                let probeFrame = self.convert(self.bounds, to: nil)
                if let scroll = Self.findListScrollView(in: window.contentView, intersecting: probeFrame) {
                    self.controller?.scrollView = scroll
                }
            }
        }

        private static func findListScrollView(in view: NSView?, intersecting rect: NSRect) -> NSScrollView? {
            guard let view else { return nil }
            if let scroll = view as? NSScrollView, scroll.documentView is NSTableView {
                let frame = scroll.convert(scroll.bounds, to: nil)
                if frame.intersects(rect) { return scroll }
            }
            for subview in view.subviews {
                if let found = findListScrollView(in: subview, intersecting: rect) { return found }
            }
            return nil
        }
    }
}
