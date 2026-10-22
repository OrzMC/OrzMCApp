//
//  HeaderActionPlanTests.swift
//  OrzMCLauncherTests
//

import CoreGraphics
import Testing
@testable import OrzMCLauncher

struct HeaderActionPlanTests {

    private let serverPresence: [HeaderActionPlan.Group: Int] = [
        .inspect: 2,     // 控制台 + 插件
        .lifecycle: 3,   // 启动 + 重启 + 停止
        .danger: 2,      // 终止 + 删除
    ]

    @Test("宽度足够时全部内联")
    func allInlineWhenWide() {
        let plan = HeaderActionPlan.plan(availableWidth: 600, present: serverPresence)
        #expect(plan.inline == [.inspect, .lifecycle, .danger])
        #expect(plan.overflow.isEmpty)
    }

    @Test("放不下时只把高危组收进菜单")
    func overflowDangerFirst() {
        // 全内联需要 7*28 + 5*8 + 2*9 = 254；只去掉 danger 后需要 5*28+3*8+9 + 9+8+28 = 226
        let plan = HeaderActionPlan.plan(availableWidth: 240, present: serverPresence)
        #expect(plan.inline == [.inspect, .lifecycle])
        #expect(plan.overflow == [.danger])
    }

    @Test("更窄时连生命周期也收进菜单")
    func overflowLifecycle() {
        let plan = HeaderActionPlan.plan(availableWidth: 150, present: serverPresence)
        #expect(plan.inline == [.inspect])
        #expect(plan.overflow == [.lifecycle, .danger])
    }

    @Test("极窄时全部收进菜单")
    func everythingOverflows() {
        let plan = HeaderActionPlan.plan(availableWidth: 20, present: serverPresence)
        #expect(plan.inline.isEmpty)
        #expect(plan.overflow == [.inspect, .lifecycle, .danger])
    }

    @Test("没有动作时不产生菜单")
    func emptyPresence() {
        let plan = HeaderActionPlan.plan(availableWidth: 200, present: [:])
        #expect(plan.inline.isEmpty)
        #expect(plan.overflow.isEmpty)
    }

    @Test("客户端只有看与高危两组，顺序不变")
    func clientGroups() {
        let plan = HeaderActionPlan.plan(availableWidth: 400, present: [.inspect: 1, .danger: 1])
        #expect(plan.inline == [.inspect, .danger])
    }
}
