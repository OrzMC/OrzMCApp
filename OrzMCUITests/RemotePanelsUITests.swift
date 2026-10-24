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

    /// 关掉系统弹窗：真机首次联网会弹「允许 OrzMC 查找本地网络中的设备?」，
    /// 不点掉它整个界面都不响应（XCUITest 会一直点空）。这类弹窗属于 SpringBoard。
    private func allowSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["允许", "Allow", "好", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    private func makeApp(_ environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        // 固定中文，断言文案才稳定。
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        // 真机上 127.0.0.1 是手机自己，假服务端在 Mac 上 —— runner 会通过
        // `TEST_RUNNER_UITEST_HOST` 把 Mac 的局域网地址传进来。
        let host = ProcessInfo.processInfo.environment["UITEST_HOST"] ?? "127.0.0.1"
        app.launchEnvironment["ORZMC_DEMO_SEED_PROFILE"] = "演示服|\(host)|25566|25575|1"
        // 默认用**应用内假数据**：真机连不到 Mac 的假服务端（本地网络权限 / 防火墙不可控）。
        // 想验证真实的 SLP/RCON 链路时，把 ORZMC_UITEST_REAL_FAKE_SERVERS=0 传进来。
        if ProcessInfo.processInfo.environment["ORZMC_UITEST_USE_NETWORK"] != "1" {
            app.launchEnvironment["ORZMC_DEMO_FAKE_SELFHOSTED"] = "1"
        }
        app.launchEnvironment["ORZMC_DEMO_RCON_PASSWORD"] = "testpass"
        app.launchEnvironment["ORZMC_DEMO_TAB"] = "selfHosted"
        for (key, value) in environment { app.launchEnvironment[key] = value }
        // 测试进程拿到的凭据（runner 用 TEST_RUNNER_ 前缀传进来的）要显式转给 **App 进程** ——
        // 两个进程环境互不相通，不转发的话 App 里没有 Token / RCON 密码，真实用例会直接失败。
        for key in ["ORZMC_DEMO_TOKEN", "ORZMC_DEMO_RCON_PASSWORD"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                app.launchEnvironment[key] = value
            }
        }
        return app
    }

    /// 自建服务器页：状态卡、玩家卡、控制台是否都出来（假服务端在线）。
    func testSelfHostedPageShowsLiveStatus() {
        let app = makeApp()
        app.launch()
        allowSystemPrompts()

        XCTAssertTrue(app.staticTexts["演示服"].waitForExistence(timeout: 20), "服务器名应显示")
        XCTAssertTrue(app.staticTexts["在线"].waitForExistence(timeout: 20), "假服务器在线，状态应为「在线」")
        XCTAssertTrue(app.staticTexts["26.3"].exists, "版本标签来自 SLP")
        XCTAssertTrue(app.staticTexts["玩家"].exists, "玩家卡应始终显示")

        // 三个名单页签都能切（数据来自假 RCON：list / whitelist list / banlist list）
        XCTAssertTrue(app.staticTexts["alice"].waitForExistence(timeout: 10), "在线名单应来自 RCON list")

        selectPlayerTab(app, matching: "白名单")
        XCTAssertTrue(app.staticTexts["carol"].waitForExistence(timeout: 10), "白名单应来自 whitelist list")

        selectPlayerTab(app, matching: "封禁")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'dave'")).firstMatch
            .waitForExistence(timeout: 10), "封禁列表应来自 banlist list（带原因）")

        XCTAssertTrue(app.staticTexts["控制台（RCON）"].exists, "开了 RCON 应有控制台卡")
        keep(XCTAttachment(screenshot: app.screenshot()))
    }

    /// 设置 sheet：点「设置」应立即出现（这是真机反馈过的"偶现加载很久/空白"）。
    func testServerSettingsSheetAppearsImmediately() {
        let app = makeApp()
        app.launch()
        allowSystemPrompts()

        let settings = app.buttons["selfHosted.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()

        // 2 秒内出现标题，且「测试连接」按钮就在首屏——不需要滚动。
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 5), "设置 sheet 必须立刻出现")
        XCTAssertTrue(app.buttons["测试连接"].exists, "连通性区块应在首屏")
        keep(XCTAttachment(screenshot: app.screenshot()))

        app.buttons["取消"].tap()
    }

    /// 添加服务器：`＋` 打开"添加服务器"（标题是「添加服务器」）。
    func testAddServerOpensEmptySheet() {
        let app = makeApp()
        app.launch()
        allowSystemPrompts()

        let add = app.buttons["selfHosted.addServer"]
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()

        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 5), "新建档案的 sheet 应立刻出现")
        app.buttons["取消"].tap()
    }

    /// **真机专属**：用真实 exaroton 账号进第一台服务器的详情页，验证控制台是否连上。
    ///
    /// 需要设备上已有 Token（跑之前先手动登录过一次）。用 `ORZMC_UITEST_REAL_ACCOUNT=1` 开启，
    /// 模拟器上默认跳过。
    func testRealAccountConsoleAppears() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORZMC_UITEST_REAL_ACCOUNT"] == "1",
                          "需要真机 + 真实 exaroton Token，设置 ORZMC_UITEST_REAL_ACCOUNT=1 才跑")

        let app = makeApp(["ORZMC_DEMO_TAB": "managed"])
        app.launchEnvironment.removeValue(forKey: "ORZMC_DEMO_SEED_PROFILE")
        app.launch()
        allowSystemPrompts()

        // 列表第一行（真实账号里的服务器）
        // 只认"服务器卡"，不要点成额度池卡（真实账号里额度池也叫 PaperMC …）。
        let firstServer = app.buttons.matching(identifier: "remote.serverCard").firstMatch
        XCTAssertTrue(firstServer.waitForExistence(timeout: 20), "应能看到真实账号下的服务器卡片")
        firstServer.tap()
        keep(XCTAttachment(screenshot: app.screenshot(), quality: .original))

        // 控制台区块必须存在（未连接时应显示占位 + 重连，而不是整块消失）
        // 控制台在页面下方（懒加载），需要滚动才会进入可访问性树。
        let consoleTitle = app.staticTexts["控制台"]
        for _ in 0..<6 where !consoleTitle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(consoleTitle.waitForExistence(timeout: 10), "详情页应有控制台区块")
        keep(XCTAttachment(screenshot: app.screenshot()))

        // 等 15 秒，看是否出现 WS 诊断行（connected / disconnected）
        let diagnostic = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'WS:'")).firstMatch
        if diagnostic.waitForExistence(timeout: 15) {
            XCTContext.runActivity(named: "WS 诊断") { activity in
                activity.add(XCTAttachment(string: diagnostic.label))
            }
            XCTFail("控制台未连接，诊断：\(diagnostic.label)")
        }
    }

    /// 远程托管：用假服务器进详情页，确认动作区三个按钮都在（不需要 exaroton Token）。
    func testRemoteDetailShowsActionButtons() {
        let app = makeApp(["ORZMC_DEMO_FAKE_SERVER": "1", "ORZMC_DEMO_TAB": "managed"])
        app.launchArguments += ["--remote-detail"]
        app.launch()
        allowSystemPrompts()

        XCTAssertTrue(app.buttons["启动服务器"].waitForExistence(timeout: 20), "详情页应能进（假服务器）")
        XCTAssertTrue(app.buttons["停止"].exists)
        XCTAssertTrue(app.buttons["重启"].exists)
        keep(XCTAttachment(screenshot: app.screenshot()))
    }

    /// **真机专属 · 端到端**：启动服务器 → 状态变在线 → 控制台出现启动日志 →（收尾）停止。
    ///
    /// 会真的消耗 exaroton 额度（大约 1–3 分钟），默认跳过；用
    /// `TEST_RUNNER_ORZMC_UITEST_REAL_ACCOUNT=1 TEST_RUNNER_ORZMC_UITEST_POWER_CYCLE=1` 打开。
    func testStartServerThenConsoleStreams() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORZMC_UITEST_REAL_ACCOUNT"] == "1",
                          "需要真机 + 真实 exaroton Token")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORZMC_UITEST_POWER_CYCLE"] == "1",
                          "会真的启停服务器（消耗额度），设置 ORZMC_UITEST_POWER_CYCLE=1 才跑")

        let app = makeApp(["ORZMC_DEMO_TAB": "managed"])
        app.launchEnvironment.removeValue(forKey: "ORZMC_DEMO_SEED_PROFILE")
        app.launch()
        allowSystemPrompts()

        let card = app.buttons.matching(identifier: "remote.serverCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "应能看到真实账号下的服务器卡片")
        card.tap()

        let stop = app.buttons["停止"]
        let start = app.buttons["启动服务器"]
        XCTAssertTrue(stop.waitForExistence(timeout: 20) || start.waitForExistence(timeout: 20),
                      "详情页应有操作按钮")

        // 已经是在线就不要再点启动（省额度、也避免真在跑的服务被干扰）。
        var weStarted = false
        if !stop.isEnabled, start.isEnabled {
            start.tap()
            weStarted = true
            keep(XCTAttachment(string: "已点击「启动服务器」"))
        }

        // 等在线：`停止` 变可点即代表 ONLINE（过渡态是全部禁用的）。
        XCTAssertTrue(waitUntil(timeout: 240) { stop.isEnabled },
                      "启动后 240 秒内应变成在线（按钮可点）")

        // 滚到控制台，等真正的启动日志（Paper 启动完成会打印 "Done (…)"）。
        let console = app.staticTexts["控制台"]
        for _ in 0..<6 where !console.exists { app.swipeUp() }
        XCTAssertTrue(console.waitForExistence(timeout: 10), "在线后应出现控制台区块")

        XCTAssertTrue(waitUntil(timeout: 240) {
            app.swipeUp()
            return app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Done ('")).firstMatch.exists
        }, "在线后控制台应流出启动日志（等待 Paper 的 Done 行）")

        keep(XCTAttachment(screenshot: app.screenshot(), quality: .original))

        // 收尾：自己启动的就停掉，恢复原状，避免白白烧额度。
        if weStarted {
            app.swipeDown()
            app.swipeDown()
            if app.buttons["停止"].waitForExistence(timeout: 10), app.buttons["停止"].isEnabled {
                app.buttons["停止"].tap()
                // 确认弹窗（alert）
                let confirm = app.alerts.buttons["停止"]
                if confirm.waitForExistence(timeout: 5) { confirm.tap() }
            }
        }
    }

    /// 截图附件默认 `deleteOnSuccess`（测试过了就丢），真机验收需要留证据，所以统一提到 `keepAlways`。
    private func keep(_ attachment: XCTAttachment) {
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// iOS 26 的浮动 TabBar 会盖住滚动内容底部。这条用**几何断言**守它：
    /// 滚到底后，控制台输入框（页面最后一行）不能和 TabBar 相交。
    func testConsoleInputNotCoveredByTabBar() {
        let app = makeApp()
        app.launch()
        allowSystemPrompts()

        let input = app.textFields["selfHosted.consoleInput"]
        for _ in 0..<8 where !input.exists { app.swipeUp() }
        XCTAssertTrue(input.waitForExistence(timeout: 15), "应能看到控制台输入框")

        // 继续滚到页面最底部（到底后 swipeUp 不再改变位置）
        for _ in 0..<6 { app.swipeUp() }

        let tabBar = app.tabBars.firstMatch
        guard tabBar.exists else { return }   // 没有 TabBar（iPad 分栏等）时无需检查
        XCTAssertFalse(
            input.frame.intersects(tabBar.frame),
            "控制台输入框被浮动 TabBar 盖住了：input=\(input.frame) tabBar=\(tabBar.frame)"
        )
    }

    // MARK: - 视觉巡检（截图）

    /// 走一遍主要界面，把每个状态截成附件，用于人工/模型一起看视觉问题。
    ///
    /// `ORZMC_UITEST_SNAPSHOTS=1` 才跑（不参与日常回归）。截图用 `keep()` 保留。
    func testSnapshotTour() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORZMC_UITEST_SNAPSHOTS"] == "1",
                          "视觉巡检用 ORZMC_UITEST_SNAPSHOTS=1 开启")

        let app = makeApp()
        app.launch()
        allowSystemPrompts()
        _ = app.staticTexts["演示服"].waitForExistence(timeout: 20)
        snap(app, "01-selfhosted-top")

        // 玩家卡三个页签
        for (index, name) in ["白名单", "封禁"].enumerated() {
            let tab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            if tab.exists {
                tab.tap()
                snap(app, "02-players-\(index)")
            }
        }

        // 控制台：发一条命令，看命令行/回复行的排版
        let input = app.textFields["selfHosted.consoleInput"]
        for _ in 0..<6 where !input.exists { app.swipeUp() }
        if input.waitForExistence(timeout: 10) {
            snap(app, "03-console-empty")
            input.tap()
            if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { input.tap() }
            input.typeText("list")
            app.buttons["selfHosted.consoleSend"].tap()
            _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'players online'")).firstMatch
                .waitForExistence(timeout: 10)
            snap(app, "04-console-reply")
            app.swipeDown()
        }

        // 设置 sheet（首屏 + 底部）
        app.buttons["selfHosted.settings"].tap()
        _ = app.buttons["保存"].waitForExistence(timeout: 10)
        snap(app, "05-settings-top")
        app.swipeUp()
        snap(app, "06-settings-bottom")
        app.buttons["取消"].tap()

        // 添加服务器
        app.buttons["selfHosted.addServer"].tap()
        _ = app.buttons["保存"].waitForExistence(timeout: 10)
        snap(app, "07-add-server")
        app.buttons["取消"].tap()
    }

    /// 远程托管（假服务器）：列表 + 详情各区块。
    func testSnapshotTourRemote() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORZMC_UITEST_SNAPSHOTS"] == "1",
                          "视觉巡检用 ORZMC_UITEST_SNAPSHOTS=1 开启")

        let app = makeApp(["ORZMC_DEMO_FAKE_SERVER": "1", "ORZMC_DEMO_TAB": "managed"])
        app.launch()
        allowSystemPrompts()
        _ = app.buttons.matching(identifier: "remote.serverCard").firstMatch.waitForExistence(timeout: 20)
        snap(app, "10-remote-list")

        app.buttons.matching(identifier: "remote.serverCard").firstMatch.tap()
        _ = app.buttons["启动服务器"].waitForExistence(timeout: 20)
        snap(app, "11-remote-detail-top")
        app.swipeUp()
        snap(app, "12-remote-detail-mid")
        app.swipeUp()
        snap(app, "13-remote-detail-bottom")
    }

    /// 点玩家卡的名单页签。分段控件的 tap 偶尔会落在控件本身而不是分段上，
    /// 所以重试到 `isSelected` 为真再继续（否则后续断言会在"没切过去"的旧列表上失败）。
    private func selectPlayerTab(_ app: XCUIApplication, matching prefix: String) {
        // 必须限定在**分段控件内部**找：玩家行的操作按钮里也有「封禁」「踢出」这种同名文字，
        // 全局 firstMatch 会点到一个完全不同的按钮上（实测「封禁」页签永远选不中）。
        let segments = app.segmentedControls.firstMatch
        let container: XCUIElement = segments.exists ? segments : app
        let tab = container.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "应能看到「\(prefix)」页签")
        for _ in 0..<3 {
            tab.tap()
            if tab.isSelected { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(tab.isSelected, "「\(prefix)」页签应被选中")
    }

    /// 远程详情 · 控制台（假"已连接"）：专门看控制台日志区 + 下方按钮的排版。
    func testSnapshotRemoteConsole() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORZMC_UITEST_SNAPSHOTS"] == "1",
                          "视觉巡检用 ORZMC_UITEST_SNAPSHOTS=1 开启")
        let app = makeApp(["ORZMC_DEMO_FAKE_SERVER": "1",
                           "ORZMC_DEMO_TAB": "managed",
                           "ORZMC_DEMO_FAKE_LIVE": "1"])
        app.launch()
        allowSystemPrompts()
        let card = app.buttons.matching(identifier: "remote.serverCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        _ = app.buttons["启动服务器"].waitForExistence(timeout: 20)
        for _ in 0..<4 { app.swipeUp() }
        snap(app, "20-remote-console")
        app.swipeUp()
        snap(app, "21-remote-console-2")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        keep(attachment)
    }

    /// 轮询直到条件成立（UI 测试里没有原生的 "wait until"）。
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 1)
        }
        return condition()
    }

    /// **真实自建服务器 · SLP**（模拟器 / 真机都能跑）：真实主机名 + 真实状态查询。
    ///
    /// 凭据来自**未入库**的 `scripts/dev/uitest-secrets.env`（模板见 `.example.env`），没有就跳过。
    func testRealSelfHostedServerShowsOnline() throws {
        let config = try selfHostedConfig()
        let app = makeApp()
        app.launchEnvironment["ORZMC_DEMO_SEED_PROFILE"] =
            "\(config.name)|\(config.host)|\(config.port)|\(config.rconPort)|\(config.password.isEmpty ? "0" : "1")"
        if !config.password.isEmpty { app.launchEnvironment["ORZMC_DEMO_RCON_PASSWORD"] = config.password }
        app.launch()
        allowSystemPrompts()

        XCTAssertTrue(app.staticTexts[config.name].waitForExistence(timeout: 20), "服务器名应显示")
        XCTAssertTrue(waitUntil(timeout: 40) { app.staticTexts["在线"].exists }, "真实服务器应探测为在线")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '连不上'")).firstMatch.exists,
            "不应出现连接失败提示"
        )
        keep(XCTAttachment(screenshot: app.screenshot(), quality: .original))
    }

    /// **真实自建服务器 · RCON**：发一条 `list`，等真实回复。
    ///
    /// 单独一条并且要显式开启（`UI_TEST_RCON=1` 或 `TEST_RUNNER_ORZMC_UITEST_RCON=1`）：
    /// RCON 是**服务端配置**的事（enable-rcon / rcon.port / rcon.password / 防火墙），
    /// 配错了不该把日常迭代染红，但需要能一键查。
    func testRealSelfHostedRCONExecutesCommand() throws {
        let config = try selfHostedConfig()
        try XCTSkipIf(config.password.isEmpty, "没有 RCON 密码")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ORZMC_UITEST_RCON"] == "1",
                          "RCON 用例需要显式开启（UI_TEST_RCON=1）")

        let app = makeApp()
        app.launchEnvironment["ORZMC_DEMO_SEED_PROFILE"] = "\(config.name)|\(config.host)|\(config.port)|\(config.rconPort)|1"
        app.launchEnvironment["ORZMC_DEMO_RCON_PASSWORD"] = config.password
        app.launch()
        allowSystemPrompts()

        let input = app.textFields["selfHosted.consoleInput"]
        for _ in 0..<6 where !input.exists { app.swipeUp() }
        guard input.waitForExistence(timeout: 15) else {
            XCTFail("应能看到控制台输入框（滚到底部）")
            return
        }
        allowSystemPrompts()   // 首次联网可能在这时才弹权限框
        input.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { input.tap() }
        input.typeText("list")
        app.buttons["selfHosted.consoleSend"].tap()

        let replied = waitUntil(timeout: 30) {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'players online'")).firstMatch.exists
        }
        if !replied {
            // 把界面上的错误文案一起报出来，省得再跑一趟去猜。
            let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '连接'")).firstMatch
            let detail = error.exists ? error.label : "（界面上没有错误文案）"
            XCTFail("RCON 没执行成功。界面提示：\(detail)")
        }
        keep(XCTAttachment(screenshot: app.screenshot(), quality: .original))
    }

    private struct SelfHostedConfig {
        let name, host, port, rconPort, password: String
    }

    private func selfHostedConfig() throws -> SelfHostedConfig {
        let environment = ProcessInfo.processInfo.environment
        let host = environment["ORZMC_UITEST_SELFHOSTED_HOST"] ?? ""
        try XCTSkipIf(host.isEmpty, "没有本地凭据（scripts/dev/uitest-secrets.env）")
        return SelfHostedConfig(
            name: environment["ORZMC_UITEST_SELFHOSTED_NAME"] ?? "真实服务器",
            host: host,
            port: environment["ORZMC_UITEST_SELFHOSTED_PORT"] ?? "25565",
            rconPort: environment["ORZMC_UITEST_SELFHOSTED_RCON_PORT"] ?? "25575",
            password: environment["ORZMC_UITEST_SELFHOSTED_RCON_PASSWORD"] ?? ""
        )
    }

}
