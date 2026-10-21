import Testing
@testable import OrzMCLauncher

@Suite struct InstanceLifecycleTests {

    @Test func stoppedInstanceOnlyAllowsStart() {
        let a = InstanceActionAvailability.make(
            isRunning: false, activity: .idle, canControlGracefully: false
        )
        #expect(a.canStart)
        #expect(!a.canRestart && !a.canStop && !a.canTerminate)
        #expect(a.canDelete, "没在跑就可以删")
        #expect(a.canConsole, "控制台可以先看后启动")
    }

    @Test func runningWithHandleAllowsAllLifecycleActions() {
        let a = InstanceActionAvailability.make(
            isRunning: true, activity: .idle, canControlGracefully: true
        )
        #expect(!a.canStart)
        #expect(a.canRestart && a.canStop && a.canTerminate)
        #expect(!a.canDelete, "跑着的时候不许删文件")
    }

    @Test func runningWithoutHandleCannotStopGracefully() {
        // 例：App 重启后接着管上一个自己以前开的服务端 —— stdin 句柄已丢失。
        let a = InstanceActionAvailability.make(
            isRunning: true, activity: .idle, canControlGracefully: false
        )
        #expect(!a.canStop, "没有句柄就送不进 stop，只能终止")
        #expect(a.canTerminate && a.canRestart)
    }

    @Test func busyDisablesEverything() {
        for activity in [InstanceActivity.starting, .stopping, .terminating, .restarting] {
            let a = InstanceActionAvailability.make(
                isRunning: true, activity: activity, canControlGracefully: true
            )
            #expect(!a.canStart && !a.canRestart && !a.canStop && !a.canTerminate)
            #expect(!a.canConsole && !a.canDelete, "\(activity) 期间全禁用，防连点")
        }
    }

    @Test func activityLabels() {
        #expect(InstanceActivity.idle.statusOverride == nil)
        #expect(InstanceActivity.starting.statusOverride == "Starting…")
        #expect(InstanceActivity.stopping.statusOverride == "Stopping…")
        #expect(InstanceActivity.terminating.statusOverride == "Terminating…")
        #expect(InstanceActivity.restarting.statusOverride == "Restarting…")
        #expect(InstanceActivity.restarting.isBusy)
        #expect(!InstanceActivity.idle.isBusy)
    }

    @Test func confirmationRules() {
        #expect(!ServerLifecycleAction.start.requiresConfirmation)
        #expect(ServerLifecycleAction.restart.requiresConfirmation)
        #expect(ServerLifecycleAction.stop.requiresConfirmation)
        #expect(ServerLifecycleAction.terminate.requiresConfirmation)
        #expect(!ServerLifecycleAction.start.requiresRunning)
        #expect(ServerLifecycleAction.stop.requiresRunning)
    }
}
