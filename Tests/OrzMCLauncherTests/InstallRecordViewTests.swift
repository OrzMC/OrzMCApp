import XCTest
@testable import OrzMCLauncher

/// `install.conf` 的 `surface` / `source` 语义（规范 `install-update.md` §3.1）。
final class InstallRecordViewTests: XCTestCase {
    private func record(
        surface: String? = "gui",
        source: String? = "github:OrzMC/OrzPythonMC",
        binaryExists: Bool = true
    ) -> InstallRecordView {
        InstallRecordView(
            version: "2.18.0",
            binaryPath: "/Users/x/.local/bin/orzmc",
            surface: surface,
            source: source,
            completionFile: "/Users/x/.zsh/completions/_orzmc",
            recordPath: "/Users/x/.local/state/orzmc/install.conf",
            binaryExists: binaryExists
        )
    }

    func testSurfaceDisplay() {
        XCTAssertEqual(record(surface: "cli").surfaceText, "installed from a terminal")
        XCTAssertEqual(record(surface: "gui").surfaceText, "installed from this app")
        // 旧记录缺 surface：如实说未知，不能猜成 cli（§3.1「缺失容忍」）。
        XCTAssertEqual(record(surface: nil).surfaceText, "origin unknown (legacy record)")
        XCTAssertNil(record(surface: nil).installSurface)
        // 非法值也按未知处理，不崩。
        XCTAssertNil(record(surface: "something").installSurface)
    }

    func testChannelInferenceFromSource() {
        XCTAssertEqual(record(source: "github:OrzMC/OrzPythonMC").channel, .python)
        XCTAssertEqual(record(source: "github:OrzMC/OrzMCKit").channel, .swift)
        XCTAssertNil(record(source: "custom").channel)
        XCTAssertNil(record(source: nil).channel)
        XCTAssertNil(record(source: "").channel)
    }

    func testUpdateInPlaceRequiresBinary() {
        XCTAssertTrue(record(binaryExists: true).canUpdateInPlace)
        // 记录在、真身不在 → 只能重装，不能 `orzmc update`。
        XCTAssertFalse(record(binaryExists: false).canUpdateInPlace)
        XCTAssertTrue(record(binaryExists: false).isBroken)
    }

    func testInstallerEnvironmentIsGui() {
        let env = InstallSurfacePolicy.installerEnvironment(base: ["PATH": "/usr/bin"], surface: .gui)
        XCTAssertEqual(env["ORZMC_SURFACE"], "gui")
        XCTAssertEqual(env["PATH"], "/usr/bin", "不要丢掉继承的环境")
        XCTAssertEqual(InstallSurfacePolicy.installerEnvironment(base: [:])["ORZMC_SURFACE"], "gui")
    }
}
