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
