//
//  LauncherServicesTests.swift
//  OrzMCTests
//

import MojangAPI
import OrzMCLauncher
import XCTest
@testable import OrzMC

/// 应用层服务（不在 SwiftPM 包里、只能 `@testable import OrzMC` 的那些）。
///
/// 注意：这个 target 以前**从没被跑过**（`scripts/swift-check.sh app-test` 只跑 SwiftPM 单测），
/// 于是它悄悄腐烂了（引用了已经不存在的 `VersionFilterService` / `runningServerPids()`）。
/// 现在 `app-test` 与 CI 都会跑它，这里保持与当前 API 一致。
final class LauncherServicesTests: XCTestCase {

    // MARK: - Java

    func testJavaRuntimeStatus() {
        let service = JavaRuntimeService()

        XCTAssertEqual(service.status(installedMajorVersions: [], requiredMajorVersion: nil), .unknown)
        XCTAssertEqual(service.status(installedMajorVersions: [17], requiredMajorVersion: 21), .missing)
        XCTAssertEqual(service.status(installedMajorVersions: [21], requiredMajorVersion: 21), .valid)
        // 策略是**精确 major**：装了 22 也不算满足 21（启动前会补装 21，见 `JavaRuntimePolicy`）。
        XCTAssertEqual(service.status(installedMajorVersions: [22], requiredMajorVersion: 21), .missing)
    }

    // MARK: - 服务端进程登记

    func testServerProcessRegistration() {
        var service = ServerProcessService()

        XCTAssertEqual(service.key(versionId: "1.21.5", software: .paper), "1.21.5#Paper")
        XCTAssertFalse(service.hasManagedRunningServers)

        service.record(LaunchedServer(versionId: "1.21.5", software: .paper, pid: "100"))
        service.record(LaunchedServer(versionId: "1.20.6", software: .vanilla, pid: "200"))

        XCTAssertTrue(service.hasManagedRunningServers)
        XCTAssertEqual(Set(service.pids()), ["100", "200"])
        XCTAssertEqual(service.pid(versionId: "1.21.5", software: .paper), "100")

        service.remove(versionId: "1.20.6", software: .vanilla)
        XCTAssertEqual(service.pids(), ["100"])

        service.removeAll()
        XCTAssertFalse(service.hasManagedRunningServers)
    }

    // MARK: - 版本过滤（`VersionListFilter` 在平台无关层，这里是接线验证）

    func testVersionFiltering() throws {
        let versions = try makeVersions()
        let filter = VersionListFilter()

        XCTAssertEqual(filter.filter(versions: versions, searchText: "", releaseOnly: true).map(\.id), ["1.21.5"])
        XCTAssertEqual(filter.filter(versions: versions, searchText: "RC", releaseOnly: false).map(\.id), ["1.21.5-rc1"])
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
