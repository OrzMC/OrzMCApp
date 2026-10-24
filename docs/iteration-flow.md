# OrzMCApp 迭代流程（标准化）

> 状态：生效中（2026-10-23）｜最后更新：2026-10-23
> 面向：人 + AI agent。目标只有一个——**改动到合入之间的反馈环尽量短、失败尽量早暴露**。

## 1. 一条命令的本地门禁

```bash
./scripts/dev/check.sh          # 静态检查 + 包单测 + 应用测试 + macOS 构建   （2~4 min）
./scripts/dev/check.sh --fast   # 只跑静态检查                                （< 5 s）
./scripts/dev/check.sh --full   # 上面全部 + iOS 构建 + 真 socket 协议联调     （6~10 min）
./scripts/dev/check.sh --build  # 只构建 macOS
./scripts/dev/check.sh --ios    # 只构建 iOS
```

**一次装好 git 钩子**（每个 clone 一次，钩子不入库）：

```bash
./scripts/dev/install-hooks.sh          # 安装
./scripts/dev/install-hooks.sh --check   # 核查是否过期
```

`pre-push` 行为：纯文档/资源改动放行；源码改动跑 `--fast`；
`PREPUSH_FULL=1 git push` 跑完整门禁；`SKIP_PREPUSH=1 git push` 直接放行（CI 仍会查）。

### 静态检查现在查什么

| 检查 | 脚本 | 防的是哪个坑 |
|---|---|---|
| 平台分层 | `scripts/check-platform-split.sh` | `Sources/*` 里混进 AppKit/UIKit（iOS 直接编不过） |
| 工程文件登记 | `scripts/dev/check-pbxproj.py` | 新增 `.swift` 没进 `project.pbxproj` —— **本地增量构建不报错、干净构建才炸**（踩过两次） |
| 中文翻译 | `scripts/dev/check-localization.py` | 新增文案漏了 `zh-Hans` —— 编译不报错，切中文才看到英文 |

## 2. 改动 → 合入 的标准动作

```bash
git switch -c feat/<主题>            # 或 fix/ perf/ docs/ release/
# …改代码…
./scripts/dev/check.sh               # 本地门禁（钩子也会跑 --fast）
git add -A && git commit -F /tmp/msg.txt     # 多行提交信息**写文件**再 -F（反引号会被 shell 吃掉）
git push -u origin HEAD
gh pr create -R OrzMC/OrzMCApp --base main --fill     # 或用模板：--body-file
# 等 CI 绿（split → protocol-live → build(macos) / build(ios)）
gh pr merge <PR> -R OrzMC/OrzMCApp --squash --delete-branch
git switch main && git pull --ff-only
```

规则：

- **一个 PR 一件事**：主题混了就拆。squash 合并，分支随合并删除，不留 `merged-but-alive` 的分支。
- **PR 描述写"为什么 + 怎么验证"**，不要只写"改了什么"（模板见 `.github/pull_request_template.md`）。
- **不要 `git push --force` 到 `main`**；`main` 只接受 PR。
- 提交信息：Conventional Commits + 中文描述。
- **跨仓库改动**（OrzMCKit / OrzMojangAPI …）：先在该仓库 PR 合并，再回本仓库 bump `Package.resolved` 并在同一个 PR 里说明。

## 3. CI 有哪些 job（`.github/workflows/ci.yml`）

| job | 内容 | 什么时候会红 |
|---|---|---|
| `split` | 平台分层 + 工程文件登记 + 本地化（秒级） | 忘了登记文件 / 漏中文 |
| `protocol-live` | 起本地假 SLP / RCON 服务端，跑 `LiveProbeSmokeTests` | 协议实现回归（TCP 分段、VarInt、超时） |
| `build (macOS)` | `swift test` + `xcodebuild test -only-testing:OrzMCTests` + macOS 构建 | 编译错误 / 单测 / 应用层测试 |
| `build (iOS)` | iOS 模拟器构建 | 平台分层漏网、iOS 专属 API 误用 |

⚠️ CI 里**不要**调父仓库的 `scripts/swift-check.sh`（那是 OrzMC 父仓库的脚本，本仓库没有）。
本地等价命令就是 `./scripts/dev/check.sh`。

## 4. 界面改动的验证方式

不要"用眼睛看"，用**应用内快照**（DEBUG 构建，不需要屏幕录制权限）：

```bash
APP="$HOME/Library/Developer/Xcode/DerivedData/OrzMC-local/Build/Products/Debug/OrzMC.app"
"$APP/Contents/MacOS/OrzMC" -ApplePersistenceIgnoreState YES --snapshot-watch /tmp/shots &
# 写请求 → 出图 + done 标记
printf '%s' '{"prefix":"/tmp/shots/dark","size":"960x740","appearance":"dark"}' > /tmp/shots/request.json
```

请求里可用的键：`prefix` / `size` / `appearance`（dark|light）/ `settings` / `settingsTab` /
`remote`（打开「服务器」窗口）/ `clickRemote`（在该窗口里点一下 x,y）/ `esc`（投递 Esc 验证关闭）。

其他调试开关：`--test-click "x,y;x,y"`、`--dump-menus`、`--remote-detail`。

自建服务器（RCON）的验收：Keychain 在无 GUI 的会话里写不进去，所以 **DEBUG 构建**允许用
`ORZMC_DEMO_RCON_PASSWORD=<密码>` 临时代替钥匙串里的密码（发布构建里这段代码不存在）。
配合 `scripts/test-servers/` 的两个假服务端即可跑通「状态 + 名单 + 控制台」全流程：

```bash
python3 scripts/test-servers/slp_server.py 25566 &
python3 scripts/test-servers/rcon_server.py 25575 &
ORZMC_DEMO_RCON_PASSWORD=testpass "$APP/Contents/MacOS/OrzMC" -ApplePersistenceIgnoreState YES --snapshot-watch /tmp/shots &
```
**必须**带 `-ApplePersistenceIgnoreState YES`，否则上次异常退出会让窗口不出现。

iOS 用模拟器：

```bash
xcrun simctl boot 2>/dev/null || true
xcodebuild build -project OrzMC.xcodeproj -scheme OrzMC \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted <…>/OrzMC.app && xcrun simctl launch booted com.joker.OrzMC.iOS
xcrun simctl io booted screenshot /tmp/ios.png
```

## 4.0 本地调试要验 Keychain / 通知时，用**签名**构建

`check.sh` / `swift-check.sh app` 都是 `CODE_SIGNING_ALLOWED=NO`（CI 也一样，快、不需要证书）。
但**钥匙串条目是按代码签名做 ACL 的**：

- 未签名（或 cdhash 每次变化的 ad-hoc）构建，读不到之前由签名构建写入的条目 →
  「远程托管列表空着」「RCON 密码读不到」；
- 还可能弹「OrzMC 想使用钥匙串中的机密信息」（`SecurityAgent`）等待点「始终允许」。

所以验证这类功能用：

```bash
./scripts/dev/run-macos-signed.sh       # 开发证书签名构建 + 启动（首次点「始终允许」）
```

要在 **Terminal.app** 里跑（ssh/agent 会话拿不到 GUI 钥匙串，会报 `errSecInternalComponent`）。
iOS 真机安装脚本本身就走开发签名，所以手机上不受影响。

## 4.1 真机验收（真实 Minecraft 服务端）

两件工具，配合起来能在**不改 App 代码**的情况下完成端到端验收：

```bash
# 1) 给本机服务端打开 RCON（自动备份 server.properties，生成/沿用密码并打印）
./scripts/dev/accept-real-server.sh --patch

# 2) 重启服务端（在 App 里选中该版本 → 重启服务器），再自动检查
./scripts/dev/accept-real-server.sh --version 26.3 --wait 240
```

- `scripts/dev/accept-real-server.sh`：定位 `<游戏目录>/versions/<版本>/server/server.properties`，
  按需写入 `enable-rcon=true` / `rcon.port` / `rcon.password`（**先备份**），
  `--wait N` 等服务端起来后自动跑检查。**不会启动/停止服务端**。
- `scripts/dev/verify-real-server.py`：只用 SLP + RCON 两个协议连真实服务端，
  打印**原始回复**与解析结果（`list` / `whitelist list` / `banlist list`）。
  看到新措辞就说明解析器要加兼容——这是 App 里看不到的信息。

## 4.1.1 iOS UI 自动化验收（XCUITest）

`devicectl` 没有触摸注入，人（和 AI）都不能"点一下看看"。**XCUITest** 能真正驱动点击/滑动，
既能跑模拟器也能跑真机，把"手工点 + 截图 + 肉眼判断"变成可重复断言 + 截图附件：

```bash
./scripts/dev/run-ios-ui-tests.sh                 # 默认 iPhone SE3 尺寸模拟器，约 1~2 分钟
./scripts/dev/run-ios-ui-tests.sh --device <UDID> # 真机（需在 Terminal.app 里跑，开发签名）
./scripts/dev/check.sh --ui                       # 等价入口
```

脚本会：起假 SLP/RCON 服务端 → 构建 App → `build-for-testing` → 修 xctestrun →（真机额外装 App）→
`test-without-building`。

**真机前置条件**

1. iPhone **解锁**（锁屏时 Xcode 会卡 600 秒然后报一个误导性的错误）；
2. 设置 → 开发者 → 打开 **「Enable UI Automation」**；
3. 在 Terminal.app 里跑（要钥匙串里的开发签名）；
4. 数据线插上更稳（无线隧道也能跑，但诊断信息少）。

**真机调试时踩过的三个坑（都已修，别再踩一遍）**

| 现象 | 真正原因 | 处理 |
|---|---|---|
| `runner exited with code 74 before establishing connection` + `peer refused channel request for dtxproxy:XCTestDriverInterface` | xctestrun 里 `UITargetAppPath` 少了 `.app`（本项目 pbxproj 手工维护，Xcode 27 会写错），runner 找不到目标 App | `scripts/dev/patch-xctestrun.py` 补 `UITargetAppPath` + `UITargetAppBundleIdentifier` |
| 界面点不动、断言全红 | 首次联网弹「允许 OrzMC 查找本地网络中的设备?」，不点掉整个 UI 都不响应 | 用例里 `allowSystemPrompts()` 去 SpringBoard 点「允许」 |
| 假服务端在真机上"连不上" | 真机访问的是 Mac 的局域网地址：iOS 本地网络权限 + macOS 防火墙 + python 未签名都会被拦 | 默认走应用内假数据 `ORZMC_DEMO_FAKE_SELFHOSTED=1`；要测真链路才用 `ORZMC_UITEST_USE_NETWORK=1` |

### 日常迭代跑模拟器，发版前跑真机

| 时机 | 命令 | 耗时 | 覆盖 |
|---|---|---|---|
| 每次改动 | `./scripts/dev/run-ios-ui-tests.sh`（默认模拟器） | 约 1–1.5 分钟 | 假数据：自建页、设置、添加、远程详情 |
| 每次改动 | `./scripts/dev/check.sh --ui` | 同上 | 同上（等价入口） |
| **发版前** | `./scripts/dev/run-ios-ui-tests.sh --device <UDID>` | 约 2–3 分钟 | 上述 + 真实账号控制台 |
| **发版前（更狠）** | 再加 `POWER_CYCLE=1` 环境 | 约 90 秒/次 | 真实启停 + 控制台日志流 |

**模拟器够用**：它跑在 Mac 上，能直接走真实网络（真实自建服务器、真实 exaroton 账号都能连），
所以"真实服务器 + 真实账号"这两类**不必上真机**——真机只在发版前验证签名/安装/权限/手感差异。

### 真实凭据怎么放（敏感信息）

模板：`scripts/dev/uitest-secrets.example.env`；真值放 `scripts/dev/uitest-secrets.env`（**已 gitignore**）。

```bash
cp scripts/dev/uitest-secrets.example.env scripts/dev/uitest-secrets.env
# 填 HOST / PORT / RCON_PORT / RCON_PASSWORD / EXAROTON_TOKEN
./scripts/dev/run-ios-ui-tests.sh      # 自动加载，日志里只说"已提供/未提供"，不回显值
```

安全网（三道）：

1. `scripts/dev/check-secrets.py` 把凭据值当"敏感字面量"扫描**所有已跟踪文件 + 暂存区**，
   命中就失败 —— 已接进 `check.sh --fast` 与 **pre-push 钩子（文档改动也扫）**。
   报"文件:行号 + 长度 + 哈希前缀"，不回显原值。
2. `.gitignore` 忽略 `scripts/dev/uitest-secrets.env`，模板文件里只有空值。
3. runner 只通过 `TEST_RUNNER_*` 环境变量传给测试进程，**不写日志、不写文件**；
   截图附件留在本机 `-resultBundlePath`，不进仓库、不进 CI。

> 万一已经推上去：**先在服务端轮换**（改 `rcon.password` / 重置 exaroton Token），再清理历史。
> 换密码比改历史快得多，也彻底。

覆盖的用例（`OrzMCUITests/RemotePanelsUITests.swift`）：

| 用例 | 断言 |
|---|---|
| 自建服务器页 | 状态卡「在线」、SLP 版本标签、玩家卡、**三个名单页签**（在线/白名单/封禁，数据来自假 RCON）、控制台卡 |
| 设置 sheet | 点 `设置` 后 **2 秒内**出现（回归"偶现加载很久/空白"） |
| 添加服务器 | 点 `＋` 立刻出现新建 sheet |
| 远程详情（假服务器） | 三个动作按钮存在（`启动服务器`/`停止`/`重启`） |
| 真实账号（真机，`TEST_RUNNER_ORZMC_UITEST_REAL_ACCOUNT=1`） | 点真服务器卡进详情 → 滚到「控制台」→ 若出现 `WS:` 诊断行则判失败并附上诊断 |
| **端到端启停**（`TEST_RUNNER_ORZMC_UITEST_POWER_CYCLE=1`） | 点「启动服务器」→ 240 秒内 `停止` 变可点（= 在线）→ 控制台流出 Paper 的 `Done (…)` 行 → 收尾自动停止 |

端到端那条**会真的消耗 exaroton 额度**（实测约 82 秒），所以默认跳过：

```bash
TEST_RUNNER_ORZMC_UITEST_REAL_ACCOUNT=1 TEST_RUNNER_ORZMC_UITEST_POWER_CYCLE=1 \
  xcodebuild test-without-building -xctestrun <已修的 xctestrun> \
  -destination 'platform=iOS,id=<UDID>' \
  -only-testing:OrzMCUITests/RemotePanelsUITests/testStartServerThenConsoleStreams
```

截图/诊断附件统一用 `keep()`（`lifetime = .keepAlways`），否则测试通过后附件会被丢掉；
`-resultBundlePath /tmp/rb.xcresult` + `xcrun xcresulttool export attachments` 就能取回。

写用例时注意：
- 用 `accessibilityIdentifier`（如 `selfHosted.settings`），不要依赖本地化文案——文案一改测试就红；
- 测试专用的数据注入走 DEBUG 环境变量（`ORZMC_DEMO_SEED_PROFILE` / `ORZMC_DEMO_RCON_PASSWORD` /
  `ORZMC_DEMO_TAB` / `ORZMC_DEMO_FAKE_SERVER`），**发布构建里不存在**；
- 模拟器首次跑 UI 测试若不预装 App，Xcode 会报
  `bundle identifier for OrzMC couldn't be read` —— 脚本已用 `simctl install` 规避。

## 4.2 真机安装 debug 包（iPhone）

```bash
./scripts/dev/install-ios-device.sh              # 自动挑已连接的真机，装完并启动
./scripts/dev/install-ios-device.sh --device iPhoneSE3
```

- **必须在有图形会话的 Terminal.app 里跑**：`codesign` 要访问登录钥匙串里的私钥，
  锁着的钥匙串会报 `errSecInternalComponent`（ssh / agent 会话就是这种情况）。
  钥匙串锁了就 `security unlock-keychain ~/Library/Keychains/login.keychain-db`。
- **后台会话（AI agent）想跑真正的签名构建**：`launchctl managername` 会是 `Background`，
  拿不到 GUI 会话的钥匙串，`launchctl asuser` 也会被拒（Operation not permitted）。
  可行做法是用 `open -a Terminal xxx.command` 把命令**投递到图形会话**里执行，
  再把输出重定向到日志文件轮询——AI agent 就是这样完成真机安装的。
- 首次装开发包，iPhone 上要「设置 → 通用 → VPN与设备管理」信任开发者证书。
- 脚本用的是开发签名（自动 provision，team `2N62934Y28`），和 TestFlight/App Store 无关。

## 5. 发版

1. 改版本：`OrzMC/Configuration/Config.xcconfig` 里 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
   （**build 号必须严格递增**，Sparkle 靠它判断新旧）。
2. 写**用户视角**的发版说明：`docs/release-notes/<MARKETING_VERSION>.md`
   （改了什么、要不要手动做什么、已知问题）。`release-macos.sh` 会按版本号自动找它。
3. 本地核验：`./scripts/dev/check.sh --full`。
4. 触发流水线：`gh workflow run release-app.yml -R OrzMC/OrzMCApp`，等它绿。
   它会：签名 → 公证 → 打包 zip/dmg → 生成 appcast → 发 GitHub Release → 把 `products/appcast.xml` 提交回 main。
5. 核验产物（别只看"绿了"）：

```bash
gh release view <版本> -R OrzMC/OrzMCApp --json assets --jq '.assets[].name'
gh release download <版本> -R OrzMC/OrzMCApp -p '*.zip' -D /tmp/rel && cd /tmp/rel && unzip -q -o '*.zip'
codesign -dv --verbose=2 OrzMC.app 2>&1 | grep Authority
lipo -archs OrzMC.app/Contents/MacOS/OrzMC      # 期望 x86_64 arm64
spctl -a -vv --type execute OrzMC.app           # 期望 accepted / Notarized Developer ID
```

6. 父仓库 bump `swift/app` 指针 + 记 `HANDOFF.md` / `RELEASES.md`。

## 6. 已知坑（都是真踩过的）

| 坑 | 表现 | 现在怎么防 |
|---|---|---|
| 新增 `.swift` 没登记进工程 | 本地不报错，干净构建/CI 失败或代码静默不参与编译 | `check-pbxproj.py`（本地 + CI） |
| 用 `withThrowingTaskGroup` 做超时 | 超时后仍要等被卡住的子任务 | 用 `RaceWithTimeout`（见 `docs/ios-self-hosted.md`） |
| 阻塞 IO 放在 `Task.detached` | 占满协作线程池，连超时都调度不起来 | 专用 `DispatchQueue` |
| 只写假字节流单测 | 抓不到 TCP 分段 / 多字节 VarInt / 超时 | `protocol-live` job（真 socket） |
| 应用测试 target 没人跑 | 代码引用了已删除的服务，早就编不过 | `check.sh` 默认档 + CI macOS 格都跑 `OrzMCTests` |
| `Int` 插值进本地化字符串 | 端口显示成 `25,565`（千位分隔） | 先拼成字符串再插值 |
| 提交信息写在 `-m "..."` 里 | 反引号被 shell 当命令替换，消息变空 | 写文件 + `git commit -F` |
| `github.com:443` 偶发被阻断 | `git push` 超时，但 `api.github.com` 正常 | 直接等网络恢复，别改 git 配置 |
