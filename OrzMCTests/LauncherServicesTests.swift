//
//  LauncherServicesTests.swift
//  OrzMCTests
//
//  Created by Codex on 2026/5/3.
//

import MojangAPI
import XCTest
@testable import OrzMC

final class LauncherServicesTests: XCTestCase {
    func testJavaRuntimeStatus() {
        let service = JavaRuntimeService()

        XCTAssertEqual(service.status(currentMajorVersion: nil, requiredMajorVersion: 21), .unknown)
        XCTAssertEqual(service.status(currentMajorVersion: 17, requiredMajorVersion: 21), .invalid)
        XCTAssertEqual(service.status(currentMajorVersion: 21, requiredMajorVersion: 21), .valid)
        XCTAssertEqual(service.status(currentMajorVersion: 22, requiredMajorVersion: 21), .valid)
    }

    func testServerProcessKeyAndPIDFiltering() {
        let service = ServerProcessService()

        XCTAssertEqual(service.key(versionId: "1.21.5", software: .paper), "1.21.5#Paper")
        XCTAssertEqual(
            service.filteredPIDMap(["paper": "100", "vanilla": "200"], runningPids: ["200"]),
            ["vanilla": "200"]
        )
    }

    func testVersionFiltering() throws {
        let versions = try makeVersions()
        let service = VersionFilterService()

        XCTAssertEqual(service.filter(versions: versions, searchText: "", releaseOnly: true).map(\.id), ["1.21.5"])
        XCTAssertEqual(service.filter(versions: versions, searchText: "RC", releaseOnly: false).map(\.id), ["1.21.5-rc1"])
    }

    private func makeVersions() throws -> [Version] {
        let jsonData = """
        [
          {
            "id" : "1.21.5",
            "releaseTime" : "2025-03-25T12:14:58+00:00",
            "time" : "2025-03-25T12:24:50+00:00",
            "type" : "release",
            "url" : "https://example.com/1.21.5.json"
          },
          {
            "id" : "1.21.5-rc1",
            "releaseTime" : "2025-03-20T13:45:48+00:00",
            "time" : "2025-03-25T11:02:08+00:00",
            "type" : "snapshot",
            "url" : "https://example.com/1.21.5-rc1.json"
          }
        ]
        """.data(using: .utf8)!

        return try JSONDecoder().decode([Version].self, from: jsonData)
    }
}
