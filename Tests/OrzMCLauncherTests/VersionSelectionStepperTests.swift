import XCTest
@testable import OrzMCLauncher

/// 键盘上下键切换版本：走一格 / 边界停住 / ⌘ 跳首末。
final class VersionSelectionStepperTests: XCTestCase {
    private let list = ["1.21.5", "1.21.4", "1.21.3", "1.21.2"]

    func testDownAndUpMoveOneStep() {
        XCTAssertEqual(VersionSelectionStepper.next(current: "1.21.4", list: list, delta: 1, jumpToEdge: false), "1.21.3")
        XCTAssertEqual(VersionSelectionStepper.next(current: "1.21.4", list: list, delta: -1, jumpToEdge: false), "1.21.5")
    }

    func testEdgesClampInsteadOfWrapping() {
        XCTAssertEqual(VersionSelectionStepper.next(current: "1.21.5", list: list, delta: -1, jumpToEdge: false), "1.21.5")
        XCTAssertEqual(VersionSelectionStepper.next(current: "1.21.2", list: list, delta: 1, jumpToEdge: false), "1.21.2")
    }

    func testCommandJumpsToEdges() {
        XCTAssertEqual(VersionSelectionStepper.next(current: "1.21.3", list: list, delta: -1, jumpToEdge: true), "1.21.5")
        XCTAssertEqual(VersionSelectionStepper.next(current: "1.21.3", list: list, delta: 1, jumpToEdge: true), "1.21.2")
    }

    func testNoSelectionStartsAtEdge() {
        XCTAssertEqual(VersionSelectionStepper.next(current: String?.none, list: list, delta: 1, jumpToEdge: false), "1.21.5")
        XCTAssertEqual(VersionSelectionStepper.next(current: String?.none, list: list, delta: -1, jumpToEdge: false), "1.21.2")
    }

    func testEmptyListKeepsSelectionEmpty() {
        XCTAssertNil(VersionSelectionStepper.next(current: String?.none, list: [String](), delta: 1, jumpToEdge: false))
        XCTAssertNil(VersionSelectionStepper.next(current: "1.21.5", list: [String](), delta: 1, jumpToEdge: true))
    }

    func testUnrelatedCurrentFallsBackToEdge() {
        XCTAssertEqual(VersionSelectionStepper.next(current: "0.0.1", list: list, delta: 1, jumpToEdge: false), "1.21.5")
    }
}
