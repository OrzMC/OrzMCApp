//
//  ProtocolPacketTests.swift
//  OrzMCTests
//
//  Created by Codex on 2026/5/3.
//

import XCTest
@testable import OrzMC

final class ProtocolPacketTests: XCTestCase {
    func testSLPPacketReadsStringLengthSafely() throws {
        let packet = MCSLPPacket()
        packet.writeString(value: "hello")

        XCTAssertEqual(try packet.readString(), "hello")
    }

    func testSLPPacketRejectsShortVarInt() {
        let packet = MCSLPPacket(data: Data([0x80]))

        XCTAssertThrowsError(try packet.readVarInt())
    }

    func testRCONPacketRejectsShortData() {
        XCTAssertNil(RCONPacket(data: Data([0x01, 0x02, 0x03])))
    }

    func testRCONPacketRoundTripsBody() {
        let packet = RCONPacket(id: 7, type: .command, body: "list")
        let decoded = RCONPacket(data: packet.data)

        XCTAssertEqual(decoded?.id, 7)
        XCTAssertEqual(decoded?.type, .command)
        XCTAssertEqual(decoded?.body, "list")
    }

}
