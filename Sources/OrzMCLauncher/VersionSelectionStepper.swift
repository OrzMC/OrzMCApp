import Foundation

/// 版本列表的键盘导航：算出「下一个选中项」。
///
/// 抽成纯函数是为了能单测（列表在 app target 里，`VersionCatalogModel` 无法单测）：
/// - 普通 ↑/↓：在**过滤后的列表**里走一格，到边界就停住（不循环）；
/// - ⌘↑/⌘↓：直接跳到首/末（列表按清单顺序，首 = 最新）；
/// - 当前没有选中项：↓ 选第一个、↑ 选最后一个。
public enum VersionSelectionStepper {
    public static func next<Item: Equatable>(
        current: Item?,
        list: [Item],
        delta: Int,
        jumpToEdge: Bool
    ) -> Item? {
        guard !list.isEmpty else { return nil }
        guard let current, let index = list.firstIndex(of: current) else {
            return delta > 0 ? list.first : list.last
        }
        let target: Int
        if jumpToEdge {
            target = delta > 0 ? list.count - 1 : 0
        } else {
            target = min(max(index + delta, 0), list.count - 1)
        }
        return list[target]
    }
}
