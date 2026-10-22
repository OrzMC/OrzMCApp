import XCTest
@testable import OrzMCLauncher

/// 控制台 Follow：上滚暂停、未读计数、滚回底部恢复、搜索期间不跟随。
final class ConsoleFollowStateTests: XCTestCase {
    func testFollowsByDefaultWithoutUnread() {
        var follow = ConsoleFollowState()
        XCTAssertTrue(follow.shouldScrollToLatest)

        follow.appended(3)
        XCTAssertTrue(follow.shouldScrollToLatest)
        XCTAssertEqual(follow.unreadCount, 0)
        XCTAssertFalse(follow.showsReturnToLatest)
    }

    func testLeavingBottomPausesAndCountsNewLines() {
        var follow = ConsoleFollowState()
        follow.userLeftBottom()
        XCTAssertFalse(follow.shouldScrollToLatest)
        XCTAssertTrue(follow.showsReturnToLatest)

        follow.appended()
        follow.appended(2)
        XCTAssertEqual(follow.unreadCount, 3, "暂停后每条新行都要计未读")
    }

    func testReachingBottomAgainResumesAndClearsUnread() {
        var follow = ConsoleFollowState()
        follow.userLeftBottom()
        follow.appended(5)

        follow.userReachedBottom()
        XCTAssertTrue(follow.shouldScrollToLatest)
        XCTAssertEqual(follow.unreadCount, 0)
        XCTAssertFalse(follow.showsReturnToLatest)
    }

    func testSearchPausesFollowAndKeepsReadingPosition() {
        var follow = ConsoleFollowState()
        follow.searchChanged(isEmpty: false)
        XCTAssertTrue(follow.isSearching)
        XCTAssertFalse(follow.shouldScrollToLatest)

        follow.appended(2)
        XCTAssertEqual(follow.unreadCount, 2)
        XCTAssertFalse(follow.shouldScrollToLatest, "搜索期间不跟随")

        // 搜索中用户滚回底部也不恢复跟随：过滤集不完整。
        follow.userReachedBottom()
        XCTAssertFalse(follow.shouldScrollToLatest)
    }

    func testEndingSearchDoesNotResumeAutomatically() {
        var follow = ConsoleFollowState()
        follow.searchChanged(isEmpty: false)
        follow.appended(2)
        follow.searchChanged(isEmpty: true)

        XCTAssertFalse(follow.isSearching)
        XCTAssertFalse(follow.shouldScrollToLatest, "清空搜索后保留阅读位置")
        XCTAssertEqual(follow.unreadCount, 2)
        XCTAssertTrue(follow.showsReturnToLatest)
    }

    func testRequestFollowClearsSearchAndUnread() {
        var follow = ConsoleFollowState()
        follow.searchChanged(isEmpty: false)
        follow.appended(4)

        follow.requestFollow()
        XCTAssertTrue(follow.shouldScrollToLatest)
        XCTAssertFalse(follow.isSearching)
        XCTAssertEqual(follow.unreadCount, 0)
    }

    func testSuspendFollowingFromToggleCountsLaterLines() {
        var follow = ConsoleFollowState()
        follow.suspendFollowing()
        XCTAssertFalse(follow.shouldScrollToLatest)

        follow.appended(2)
        XCTAssertEqual(follow.unreadCount, 2)

        // 开关重新打开等价于「回到最新」。
        follow.requestFollow()
        XCTAssertTrue(follow.shouldScrollToLatest)
        XCTAssertEqual(follow.unreadCount, 0)
    }

    func testReachingBottomWhilePausedWithoutUnreadResumesFollow() {
        var follow = ConsoleFollowState()
        follow.suspendFollowing()
        follow.userReachedBottom()
        XCTAssertTrue(follow.shouldScrollToLatest, "滚回底部即恢复跟随，与未读数无关")
    }

    func testZeroOrNegativeAppendsAreIgnored() {
        var follow = ConsoleFollowState()
        follow.userLeftBottom()
        follow.appended(0)
        follow.appended(-3)
        XCTAssertEqual(follow.unreadCount, 0)
    }
}
