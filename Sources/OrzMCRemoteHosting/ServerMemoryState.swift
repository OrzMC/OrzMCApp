import Foundation

/// 远程服务器内存的「草稿 / 已确认 / 保存中」状态（纯逻辑，可单测）。
///
/// 规则（2026-10-22 交互审查 §8：Stepper 不该每动一格就发请求，失败也不能装作已保存）：
/// - `draft` 是界面上可编辑的值，`confirmed` 是服务端确认过的值；
/// - `isDirty`（两者不同）才允许保存，界面据此显示「未保存的更改」；
/// - 保存失败时**确认值不变、草稿保留** → 界面继续解释“还没保存”，用户可直接重试或放弃；
/// - 保存中不接受新的保存（按钮禁用即可，逻辑上也拒绝）。
public struct ServerMemoryState: Equatable, Sendable {
    public private(set) var draft: Int32?
    public private(set) var confirmed: Int32?
    public private(set) var isSaving = false
    public private(set) var lastSaveFailed = false
    /// 保存中记住"提交前的确认值"，失败时回滚到它。
    private var confirmedBeforeSave: Int32?

    public init() {}

    /// 是否已经读到服务端的值（没读到就不该显示可编辑的 Stepper）。
    public var isLoaded: Bool { confirmed != nil }

    /// 草稿与确认值不同 = 有未保存修改。
    public var isDirty: Bool {
        guard let draft, let confirmed else { return false }
        return draft != confirmed
    }

    public var canSave: Bool { isDirty && !isSaving }

    /// 读取成功（进入详情、刷新、保存成功后回读）。
    public mutating func loaded(_ ram: Int32) {
        confirmed = ram
        draft = ram
        lastSaveFailed = false
    }

    /// 用户拖动 Stepper：只改草稿，不发请求。
    public mutating func edit(_ ram: Int32) {
        draft = ram
        lastSaveFailed = false
    }

    /// 「Revert」：回到已确认值。
    public mutating func revert() {
        guard let confirmed else { return }
        draft = confirmed
        lastSaveFailed = false
    }

    /// 开始保存：返回要提交的值；不可保存或在途时返回 `nil`（防重复提交）。
    public mutating func beginSave() -> Int32? {
        guard canSave, let draft else { return nil }
        isSaving = true
        lastSaveFailed = false
        // **乐观更新**：界面立刻停在"用户设置的值"，不等服务端回传。
        // 否则保存成功后服务端还会回一条旧值，界面就会"先跳回改前、再跳到改后"（真机多次反馈）。
        confirmedBeforeSave = confirmed
        confirmed = draft
        return draft
    }

    public mutating func saveSucceeded(_ ram: Int32) {
        isSaving = false
        confirmed = ram
        draft = ram
        lastSaveFailed = false
        confirmedBeforeSave = nil
    }

    /// 失败：确认值不变、草稿保留，界面仍显示未保存。
    public mutating func saveFailed() {
        isSaving = false
        lastSaveFailed = true
        // 回滚到提交前的确认值，草稿保留（界面继续显示"未保存"）。
        if let previous = confirmedBeforeSave { confirmed = previous }
        confirmedBeforeSave = nil
    }
}
