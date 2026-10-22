import Foundation

/// 控制台「跟随最新日志」的状态机（纯逻辑，可单测）。
///
/// 规则（2026-10-22 交互审查 §1：上滚后不该被后续日志拽回底部）：
/// - **默认跟随**：新行到达时由视图滚到底部，不累计未读；
/// - **用户把阅读位置移离底部** → 暂停跟随；此后新行只累计未读，不再改变阅读位置；
/// - **用户自己把阅读位置滚回底部** → 恢复跟随并清零未读（终端/Xcode 里的标准行为）；
///   程序滚动（跟随）不会触发这两个回调，所以不会与自动滚动互相打架；
/// - **搜索期间暂停跟随**：搜索后可见行随日志变化，跟随会不断改动阅读位置；
/// - **结束搜索不自动恢复**：保留用户此刻的阅读位置（是否恢复由下一次明确操作决定）；
/// - **「回到最新」是明确意图**：无论当前在搜索还是已暂停，都恢复跟随并清零未读。
///
/// 视图只负责渲染与滚动，判定全部在这里，才能不依赖 GUI 做受控验证。
public struct ConsoleFollowState: Equatable, Sendable {
    /// 是否自动跟随最新行。
    public private(set) var isFollowing = true
    /// 暂停/搜索期间新增、用户还没看到的行数。
    public private(set) var unreadCount = 0
    /// 是否正在按关键词过滤日志。
    public private(set) var isSearching = false

    public init() {}

    /// 此刻到达的新行是否应该滚动到底部（搜索期间一律不滚）。
    public var shouldScrollToLatest: Bool { isFollowing && !isSearching }

    /// 界面上是否该出现「回到最新」入口（暂停或搜索中）。
    public var showsReturnToLatest: Bool { !shouldScrollToLatest }

    /// 新日志到达（`count` 为本次新增行数）。
    public mutating func appended(_ count: Int = 1) {
        guard count > 0, !shouldScrollToLatest else { return }
        unreadCount += count
    }

    /// 用户把阅读位置移离底部（只有用户操作会触发）。
    public mutating func userLeftBottom() {
        guard isFollowing else { return }
        isFollowing = false
    }

    /// 用户把阅读位置滚回底部：恢复跟随并清零未读（搜索中不恢复）。
    ///
    /// 滚动过程中会反复报“在底部”，所以状态不变时不写回，避免无意义的重绘。
    public mutating func userReachedBottom() {
        guard !isSearching, !isFollowing || unreadCount != 0 else { return }
        isFollowing = true
        unreadCount = 0
    }

    /// 搜索框内容变化（`isEmpty` 表示已清空）。
    ///
    /// 开始搜索：暂停跟随并清零未读；结束搜索：只退出搜索态，**不**自动恢复跟随。
    public mutating func searchChanged(isEmpty: Bool) {
        isSearching = !isEmpty
        if isSearching {
            isFollowing = false
            unreadCount = 0
        }
    }

    /// 用户明确要求回到最新（「回到最新」按钮或打开 Follow 开关）。
    public mutating func requestFollow() {
        // 过滤后的行集不完整；跟随最新前退出搜索（视图负责清空搜索框）。
        isSearching = false
        isFollowing = true
        unreadCount = 0
    }

    /// 用户主动关掉 Follow 开关。
    public mutating func suspendFollowing() {
        guard isFollowing || unreadCount != 0 else { return }
        isFollowing = false
        unreadCount = 0
    }
}
