import XCTest
@testable import OrzMCRemoteHosting

final class RemoteConsoleBufferTests: XCTestCase {
    func testClearThenReceiveDoesNotRestoreOldOutput() {
        var buffer = RemoteConsoleBuffer()
        buffer.append("old output\n")
        let oldID = buffer.lines.last!.id
        buffer.clear()
        buffer.append("new output\n")
        XCTAssertEqual(buffer.lines.map(\.text), ["new output\n"])
        XCTAssertGreaterThan(buffer.lines[0].id, oldID)
    }

    func testFullBufferKeepsStableIDsAsOutputArrives() {
        var buffer = RemoteConsoleBuffer(capacity: 2000)
        for index in 0..<2001 { buffer.append("\(index)") }
        XCTAssertEqual(buffer.lines.count, 2000)
        XCTAssertEqual(buffer.lines.first?.text, "1")
        XCTAssertEqual(buffer.lines.last?.text, "2000")
        XCTAssertEqual(Set(buffer.lines.map(\.id)).count, 2000)
        let retainedID = buffer.lines[1].id
        buffer.append("2001")
        XCTAssertEqual(buffer.lines.first?.id, retainedID)
        XCTAssertEqual(buffer.lines.last?.id, 2001)
    }
}
