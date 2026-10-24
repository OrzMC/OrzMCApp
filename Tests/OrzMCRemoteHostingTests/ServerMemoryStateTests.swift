import XCTest
@testable import OrzMCRemoteHosting

/// 远程内存编辑：草稿、保存中防重入、失败后仍能解释「未保存」。
final class ServerMemoryStateTests: XCTestCase {
    func testLoadedValueIsClean() {
        var memory = ServerMemoryState()
        XCTAssertFalse(memory.isLoaded)
        XCTAssertFalse(memory.isDirty)

        memory.loaded(4)
        XCTAssertTrue(memory.isLoaded)
        XCTAssertEqual(memory.draft, 4)
        XCTAssertEqual(memory.confirmed, 4)
        XCTAssertFalse(memory.isDirty)
        XCTAssertFalse(memory.canSave)
    }

    func testEditingDraftDoesNotTouchConfirmedValue() {
        var memory = ServerMemoryState()
        memory.loaded(4)
        memory.edit(6)
        XCTAssertEqual(memory.draft, 6)
        XCTAssertEqual(memory.confirmed, 4, "拖动 Stepper 不等于已保存")
        XCTAssertTrue(memory.isDirty)
        XCTAssertTrue(memory.canSave)
    }

    func testSecondSaveWhileSavingIsRejected() {
        var memory = ServerMemoryState()
        memory.loaded(4)
        memory.edit(8)
        XCTAssertEqual(memory.beginSave(), 8)
        XCTAssertTrue(memory.isSaving)
        XCTAssertNil(memory.beginSave(), "在途时不得重复提交")
        XCTAssertFalse(memory.canSave)
    }

    /// 乐观更新：一开始保存就停在新值（界面不再"先跳回旧值再跳到新值"）。
    func testBeginSaveOptimisticallyAdoptsDraft() {
        var memory = ServerMemoryState()
        memory.loaded(2)
        memory.edit(4)
        _ = memory.beginSave()

        XCTAssertEqual(memory.draft, 4)
        XCTAssertEqual(memory.confirmed, 4, "保存中界面立刻显示新值")
        XCTAssertFalse(memory.isDirty)
    }

    /// 失败要能回滚到提交前的确认值。
    func testBeginSaveRollsBackOnFailure() {
        var memory = ServerMemoryState()
        memory.loaded(2)
        memory.edit(4)
        _ = memory.beginSave()
        memory.saveFailed()

        XCTAssertEqual(memory.confirmed, 2)
        XCTAssertEqual(memory.draft, 4)
        XCTAssertTrue(memory.isDirty)
    }

    func testSaveSuccessMovesConfirmedToDraft() {
        var memory = ServerMemoryState()
        memory.loaded(4)
        memory.edit(8)
        _ = memory.beginSave()

        memory.saveSucceeded(8)
        XCTAssertFalse(memory.isSaving)
        XCTAssertEqual(memory.draft, 8)
        XCTAssertEqual(memory.confirmed, 8)
        XCTAssertFalse(memory.isDirty)
        XCTAssertFalse(memory.lastSaveFailed)
    }

    func testSaveFailureKeepsDraftAndConfirmed() {
        var memory = ServerMemoryState()
        memory.loaded(4)
        memory.edit(8)
        _ = memory.beginSave()

        memory.saveFailed()
        XCTAssertFalse(memory.isSaving)
        XCTAssertTrue(memory.lastSaveFailed)
        XCTAssertEqual(memory.confirmed, 4, "服务端仍是 4 GB")
        XCTAssertEqual(memory.draft, 8, "用户的草稿不能被失败吞掉")
        XCTAssertTrue(memory.isDirty, "界面必须继续显示未保存")
        XCTAssertTrue(memory.canSave, "失败后必须能直接重试")
    }

    func testRevertAfterFailureReturnsToConfirmedValue() {
        var memory = ServerMemoryState()
        memory.loaded(4)
        memory.edit(8)
        _ = memory.beginSave()
        memory.saveFailed()

        memory.revert()
        XCTAssertEqual(memory.draft, 4)
        XCTAssertFalse(memory.isDirty)
        XCTAssertFalse(memory.lastSaveFailed)
    }

    func testReloadFromServerWhileDirtyResetsBothValues() {
        var memory = ServerMemoryState()
        memory.loaded(4)
        memory.edit(8)
        // 重新进入详情：以服务端值为准。
        memory.loaded(4)
        XCTAssertFalse(memory.isDirty)
        XCTAssertEqual(memory.draft, 4)
    }
}
