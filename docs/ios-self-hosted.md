# iOS 自建服务器（最小闭环）

> 状态：已落地（2026-10-23）｜最后更新：2026-10-23

前情：iOS 端以前只有一个页面——exaroton 远程托管（`ExarotonContent`），**必须先注册第三方账号**
才能用。本文件记录新增的「我的服务器」这条路：不依赖任何账号，直接对一个自己架的
Minecraft 服务端查状态、发控制台命令。

## 1. 用户能做什么

| 功能 | 协议 | 说明 |
|---|---|---|
| 在线状态（在线/离线、版本、玩家 0/20、延迟、MOTD） | Server List Ping | 和游戏里「多人游戏」列表看到的是同一份数据 |
| 在线玩家列表 | SLP 的 `players.sample` | 服务端可能隐藏，隐藏时整块不显示 |
| 控制台命令 | RCON | 需要在服务端 `server.properties` 打开 `enable-rcon=true` |
| 常用命令 | RCON | 「列出玩家 / 保存世界 / 广播 / 踢出 / 封禁 / OP / 白名单」——**要参数的先填好开头**，不用背语法 |
| 玩家快捷动作 | RCON | 玩家列表每行有「踢出」「OP」，点一下填进输入框 |

**多台服务器**：顶部胶囊菜单切换（新增/编辑/删除在菜单里，删除要二次确认）。
早期版本只存一台，升级时自动迁移（`orzmc.selfHosted.profile` → `orzmc.selfHosted.profiles`，
密码从旧的固定 Keychain 账户搬到新档案上），用户不会看到"配置没了"。

iOS 首页变成两个并列的 Tab：**我的服务器** / **远程托管**。

macOS 上这两个面放进同一个「服务器」窗口（顶部分段控件切换，`ServersWindowContent`），
入口在主窗口工具栏的 **Servers**；窗口支持 Esc 关闭（规则见 `docs/app-ui-design.md` §3.2.1）。

## 2. 分层

```
OrzMC/Common/SelfHosted/          应用侧（跨平台，只用 Foundation/SwiftUI）
  SelfHostedCredentials.swift     RCON 密码 → Keychain（按档案 id 分开，含旧账户迁移）
  SelfHostedServersModel.swift    @MainActor @Observable：多档案 + 每台的状态/控制台/错误文案
  SelfHostedServerView.swift      服务器菜单 + 状态卡 + 玩家列表 + 控制台 + 常用命令
  SelfHostedServerSettingsView.swift  地址/端口/RCON 表单（含校验、删除这台服务器）
  ServersWindowContent.swift     macOS「服务器」窗口：自建 / 远程托管 两个面

Sources/OrzMCLauncher/            平台无关、可单测
  SelfHostedProfiles.swift        档案模型 + `upsert`/`remove`/选中规则 + 旧格式迁移

Sources/OrzMCProtocol/            协议层（可单测，无 UI）
  Transport/MCByteStream.swift    字节流协议 + Socket 实现 + 读缓冲（MCReadBuffer）
  Transport/RaceWithTimeout.swift 「跑一段工作，超时就放弃，不等它收尾」
  Status/MCStatusSummary.swift    SLP JSON → 界面要的字段（容错解析）
  Status/MCServerProbe.swift      async status() / runRCON()，阻塞 IO + 硬超时
  ServerListPing/ RCON/          老的分包编解码（保留复用）
```

## 3. 三个必须记住的坑（都踩过并已修）

1. **读缓冲**：TCP 不按包边界送。`read(count:)` 一次读回 112 字节、只要 111 字节时，
   多出来的 1 字节必须留在缓冲里，否则下一个包永远等不到数据（表现为「检查中…」永不结束）。
   → `MCReadBuffer`，有单测。
2. **阻塞 IO 不能占协作线程**：`Task.detached` 里跑阻塞 socket 会占住 Swift 并发线程池，
   连「超时计时」都调度不起来（实测 2 秒超时被拖到 8 秒）。→ 专用 `DispatchQueue`（并发）。
3. **超时不能用 `withThrowingTaskGroup` 竞速**：结构化并发要求作用域退出前所有子任务结束，
   「超时先抛」之后仍要等被卡住的子任务。→ `RaceWithTimeout`：一次性令牌 + continuation，
   超时立刻返回，并回调 `onTimeout` 关 socket 让阻塞线程退出。

## 4. 验证方式

```bash
# 协议层单测（假流，不需要网络）
swift test --package-path swift/app --filter "MCServerProbeTests|MCReadBufferTests|RaceWithTimeoutTests"

# 真机 smoke（需要一个本地/远程真实服务端）
ORZMC_LIVE_PROBE=127.0.0.1:25565 swift test --package-path swift/app --filter LiveProbeSmokeTests

# iOS 端到端
xcodebuild -project swift/app/OrzMC.xcodeproj -scheme OrzMC \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation build
xcrun simctl install booted <…>/OrzMC.app && xcrun simctl launch booted com.joker.OrzMC.iOS
```

真机结果（2026-10-23，本机 Fabric 26.3）：状态卡显示 `26.3 / 0/20 名玩家 / 2 毫秒 / 在线`，
控制台卡正常显示（RCON 未在服务端开启时不显示）。

## 5. 还没做的（明确记录，避免误以为有）

- RCON 多包响应：已支持（第一包必读，之后 120ms 内还有数据就继续读，最后按行拼接）。
- 多服务器档案：目前只有一个地址（P3 最小闭环）。
- `OrzMCProtocol` 里老的 `MCSLP` / `MCRCON`（BlueSocket 同步封装）已不被应用使用，
  但保留了分包实现；后续可整体并入 `MCServerProbe` 后删除。
- macOS 入口、玩家管理快捷命令（kick/ban）等留给后续。
