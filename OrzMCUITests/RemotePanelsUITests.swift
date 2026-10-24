import XCTest

/// iOS 端**自动化验收**：真正驱动点击，断言界面结果。
///
/// 跑之前需要本机的假 SLP / RCON 服务端（`scripts/test-servers/`），
/// 用 `scripts/dev/run-ios-ui-tests.sh` 会一并启动。
///
/// 用到的 DEBUG 钩子（发布构建里不存在）：
/// * `ORZMC_DEMO_SEED_PROFILE="名称|host|port|rconPort|rconEnabled"`
/// * `ORZMC_DEMO_RCON_PASSWORD`、`ORZMC_DEMO_TAB`、`ORZMC_DEMO_FAKE_SERVER`
final class RemotePanelsUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func makeApp(_ environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        // 固定中文，断言文案才稳定。
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["ORZMC_DEMO_SEED_PROFILE"] = "演示服|127.0.0.1|25566|25575|1"
        app.launchEnvironment["ORZMC_DEMO_RCON_PASSWORD"] = "testpass"
        app.launchEnvironment["ORZMC_DEMO_TAB"] = "selfHosted"
        for (key, value) in environment { app.launchEnvironment[key] = value }
        return app
    }

    /// 自建服务器页：状态卡、玩家卡、控制台是否都出来（假服务端在线）。
    func testSelfHostedPageShowsLiveStatus() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["演示服"].waitForExistence(timeout: 20), "服务器名应显示")
        XCTAssertTrue(app.staticTexts["在线"].waitForExistence(timeout: 20), "假 SLP 服务端在线，状态应为「在线」")
        XCTAssertTrue(app.staticTexts["26.3"].exists, "版本标签来自 SLP")
        XCTAssertTrue(app.staticTexts["玩家"].exists, "玩家卡应始终显示")

        // 三个名单页签都能切（数据来自假 RCON：list / whitelist list / banlist list）
        XCTAssertTrue(app.staticTexts["alice"].waitForExistence(timeout: 10), "在线名单应来自 RCON list")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '白名单'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["carol"].waitForExistence(timeout: 5), "白名单应来自 whitelist list")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '封禁'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'dave'")).firstMatch
            .waitForExistence(timeout: 5), "封禁列表应来自 banlist list（带原因）")

        XCTAssertTrue(app.staticTexts["控制台（RCON）"].exists, "开了 RCON 应有控制台卡")
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    /// 设置 sheet：点「设置」应立即出现（这是真机反馈过的"偶现加载很久/空白"）。
    func testServerSettingsSheetAppearsImmediately() {
        let app = makeApp()
        app.launch()

        let settings = app.buttons["selfHosted.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()

        // 2 秒内出现标题，且「测试连接」按钮就在首屏——不需要滚动。
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 2), "设置 sheet 必须立刻出现")
        XCTAssertTrue(app.buttons["测试连接"].exists, "连通性区块应在首屏")
        add(XCTAttachment(screenshot: app.screenshot()))

        app.buttons["取消"].tap()
    }

    /// 添加服务器：`＋` 打开"添加服务器"（标题是「添加服务器」）。
    func testAddServerOpensEmptySheet() {
        let app = makeApp()
        app.launch()

        let add = app.buttons["selfHosted.addServer"]
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()

        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 2), "新建档案的 sheet 应立刻出现")
        app.buttons["取消"].tap()
    }

    /// 远程托管：用假服务器进详情页，确认动作区三个按钮都在（不需要 exaroton Token）。
    func testRemoteDetailShowsActionButtons() {
        let app = makeApp(["ORZMC_DEMO_FAKE_SERVER": "1", "ORZMC_DEMO_TAB": "managed"])
        app.launchArguments += ["--remote-detail"]
        app.launch()

        XCTAssertTrue(app.buttons["启动服务器"].waitForExistence(timeout: 20), "详情页应能进（假服务器）")
        XCTAssertTrue(app.buttons["停止"].exists)
        XCTAssertTrue(app.buttons["重启"].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
