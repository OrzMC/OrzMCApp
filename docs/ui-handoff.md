# macOS 启动器 UI 刷新：Codex 交接文档

> **状态**：已授权分支提交推送，待人工视觉验收｜**最后更新**：2026-10-22
> **交接对象**：Codex（或下一个接手的 agent）
> **工作目录**：`/Users/bot/OrzMC/swift/app`（父仓库 `/Users/bot/OrzMC` 的子模块）
> **配套文档**：
> [`app-ui-design.md`](app-ui-design.md)（完整 UI 梳理 + 设计决策）、
> [`app-launcher-architecture.md`](app-launcher-architecture.md)（模型职责）、
> [`app-platform-split.md`](app-platform-split.md)（平台分层）。

---

## 0. 一句话状态

macOS 启动器的 UI/交互刷新已经完成一轮，**macOS / iOS 构建、平台无关单测、平台分层校验全绿**；
维护者已授权将当前改动提交推送到 `feat/ui-refresh`；通过父仓库 `feat/ui-refresh-handoff` 拉取接力。下文历史快照保留，最新恢复步骤见 [Air 接力文档](air-ui-handoff-2026-10-22.md)。
`air` 上已经用最新产物启动过 app，Settings 打开/关闭已验证无崩溃。

---

## 1. 仓库与工作区状态

| 项 | 值 |
|---|---|
| 父仓库 | `/Users/bot/OrzMC` |
| 子模块 | `swift/app`（`OrzMC/OrzMCApp`） |
| 子模块分支 | `main`（**未开分支**） |
| 子模块 HEAD | `fa571e7 fix(ui): 选中行标签隐身 + 详情页实例切换 + 控制台四操作 + 优雅停止全部 (#36)` |
| 工作区 | **脏**：37 个已跟踪文件修改 + 5 个新文件（含删除 `FeedbackToAuthor.swift`） |
| 父仓库 | `M HANDOFF.md`、`m swift/app`；**未 bump 指针** |
| 远端 | **未 push**，没有 PR |

### 1.1 新文件

- `Sources/OrzMCDesignSystem/OrzMCTheme.swift`
- `Sources/OrzMCDesignSystem/StatusBadge.swift`
- `Sources/OrzMCDesignSystem/ConsoleSurface.swift`
- `docs/app-ui-design.md`
- `docs/ui-handoff.md`（本文件）

### 1.2 删除

- `OrzMC/Launcher(MacOS)/UI/Modifiers/FeedbackToAuthor.swift`
- `FeedbackToAuthor` 删除后，app 不再直接依赖 SwiftUIX；`project.pbxproj` 已移除 SwiftUIX 产品依赖。

> **禁止** `git add -A` / `git add .`（父仓库规则：会误暂存所有子模块指针）。
> 提交前只 `git add` 显式路径；多行提交信息写文件后 `git commit -F <file>`。

---

## 2. 当前 `air` 运行状态

- 构建产物：`~/orzmc-build/app-dd/Build/Products/Debug/OrzMC.app`
- 启动方式：`scripts/air/run.sh app-run`
- 最近验证：窗口 `Minecraft - 26.3`，Settings 打开（标题「通用」）后关闭，进程未崩溃。
- **限制**：SSH 会话的 `screencapture` 被 TCC 拒绝（`could not create image from display`），
  无法截图。可用 AppleScript / System Events 读窗口、菜单、UI 元素；真正的视觉验收需要
  维护者在 `air` 的登录桌面会话里看。
- `air` 的 GUI 会话用户是 `joker`（uid 501）；`launchctl print gui/501` 正常。
- **不要**动生产目录 `E:\orzmc`（Windows）或 `air` 上无关的目录。

---

## 3. 这一轮做了什么（按主题）

### 3.1 Settings 崩溃（P0，已修）

根因：`Settings` 只注入 `app.settings`，但 `SettingsView` 读 `@Environment(AppModel.self)`：

```swift
Settings {
    SettingsView().environment(app.settings)   // 旧
}
```

崩溃栈：`AppWindowsController.makeSettingsWindowController` → `EnvironmentValues.subscript.getter`
→ `_assertionFailure`（SIGTRAP）。修复：

- `Settings` 注入 `.environment(app)`；
- `AppModel` 提升到 `OrzMCApp` 的 App 级 `@State`，主窗口 / Settings / 控制台窗口 / 远程窗口共享同一实例。

### 3.2 多窗口边界（已落地）

| 窗口 | 实现 | 说明 |
|---|---|---|
| 主启动器 | `Window("OrzMC", id: "main")` | **唯一**，单份 `AppModel` |
| 控制台 | `WindowGroup("Console", id: "console", for: ConsoleTarget.self)` | `openWindow(value:)` 按实例打开，共享 `AppModel` / `ServerConsoleModel` |
| 远程服务器 | `Window("Remote Servers", id: "remote")` | 独立 `ExarotonServerModel`，不碰本机进程 |
| Settings | `Settings` | 共享 `AppModel` |

- `CommandGroup(replacing: .newItem) {}` 移除 File > New Window 的空白入口。
- `Window > Show Main Window`（⌘0）由 `MainWindowCommands` 提供。
- 控制台 `Open in New Window` 需要 `ConsoleTarget: Codable & Hashable`；
  `SettingsModel.ServerSoftware` 已加 `Codable`。

### 3.3 信息架构（已改）

- 侧边栏 `GameView` **只做导航**：版本列表 + 搜索 + Releases 过滤 + 刷新 + Remote Servers 工具栏按钮。
- 启动配置移到详情页顶部的 `LaunchControls`（定义在 `GameView.swift`，由 `BasicInfo` 的 `Form` 使用）。
- Launch 区已压成 **3 行**：
  1. 版本号 + 版本类型标签 + Client/Server 分段选择；
  2. Java 状态（`Java 17 → 21 [就绪] ↻`）；
  3. Username 或 Server Core + Start。
- 详情页 Terminate/Delete 收进 `⋯` 菜单；日常操作仍是 Console / Plugins / Start / Restart / Stop。

### 3.4 文本输入框统一（已改）

问题：`LabeledContent("Username") { TextField("Username") }` 导致行标签和占位符重复。

统一约定：

- **单字段**：`LabeledContent("标题") { TextField("", text:, prompt: Text("示例")) ... .labelsHidden() }`
- **Form 标准字段**：也可以直接 `TextField("标题", text:)`，但不要再套一层同名的 `LabeledContent`。
- Prompt 只放示例，不放标题：`Offline player name` / `Absolute path` / `512M` / `2G`。

已处理：启动区 Username、Settings Username / Game folder / JVM memory / JVM arguments。

### 3.5 设计系统（新增）

- `OrzMCTheme`：Spacing / Radius / Typography / Palette（只用语义色）。
- `OrzMCStatusBadge`：状态徽标；支持 `LocalizedStringKey` 与 `verbatim` 两种文案。
- `OrzMCTag`：分类标签（版本类型 / local / 渠道 / 更新数 / 软件版本 / 玩家数）。
- `OrzMCBanner`：错误 / 警告 / 信息；支持 localized 与 verbatim。
- `.consoleSurface()`：控制台/日志面板统一底色与边框（浅色/深色/提高对比度）。

### 3.6 本地化（已接）

- `OrzMC/Common/Localizable.xcstrings`：**220 条 zh-Hans**（截至本次交接）。
- 覆盖：菜单、Settings、Launch、控制台、插件、Exaroton、确认/错误标题、状态文案。
- 已在 `air`（系统语言中文）实际验证菜单：`设置…` / `显示边栏` / `游戏 > 启动 服务器` /
  `全部停止服务器…` / `窗口 > 显示主窗口`。
- 仍为英文的部分：引擎返回的长错误文案、`RiskyAction.message` 长说明、部分 `.help()` 悬停提示。
  错误码（`E_*`）仍保留。

### 3.7 控制台 / 插件 / 远程服务器

- 控制台：日志 Follow 开关、搜索、导出（`NSSavePanel`）、`Open in New Window`、独立窗口。
- 插件管理：`NavigationStack` + 系统 `.searchable` + `ContentUnavailableView`。
- Exaroton：
  - 列表：状态徽标 + 软件/玩家标签 + 地址行 + Section 数量统计。
  - 详情：服务器名称标题、状态徽标、MOTD、地址、指标标签；Actions 用 Start 主按钮 + Stop/Restart `ControlGroup`；
    Console 高度增加，Send/Clear 同一行。
  - 额度池：大额度卡 + 成员/服务器列表。
  - 加载遮罩条件渲染；Token/命令 sheet 显式 Save/Send；日志上限 2000 行；加载 RAM 不再重复 `changeRAM`。
- 外部链接走默认浏览器，删除 SwiftUIX `Web` 包装。

### 3.8 顺带修复

- 详情页 1.5s 只重算**当前选中版本**（`VersionCatalogModel.refreshInstallState(for:)`），不再全量 stat。
- 侧边栏 Start 防重复：`AppModel.isCurrentInstanceRunning`。
- 「停止全部」忙碌标记：`AppModel.isStoppingAll`。
- 全局启动中锁定详情/控制台生命周期按钮。
- ⌘C（发命令覆盖 Copy）/ ⌘S（Remote Server）冲突移除；「停止全部」改 ⇧⌘K。
- 删除未使用的 SwiftUIX / FeedbackToAuthor。

---

## 4. 关键文件地图

```
swift/app/
├── OrzMC/OrzMCApp.swift                  App 级 @State AppModel + 平台分支
├── OrzMC/Launcher(MacOS)/
│   ├── UI/MacOSScene.swift               Window / Console WindowGroup / Remote Window / Settings / 菜单
│   ├── UI/LauncherUI.swift               NavigationSplitView + 错误/停止全部 alert
│   ├── UI/SideBar/GameView.swift         侧边栏列表 + LaunchControls（启动配置在这里）
│   ├── UI/SideBar/GameList.swift         版本行 / 标签
│   ├── UI/Detail/GameInfoView.swift      详情 NavigationStack（只剩本机实例）
│   ├── UI/Detail/BasicInfo.swift         LaunchControls + 实例目录/操作 + 控制台跳转
│   ├── UI/Detail/ServerConsoleView.swift 控制台 + 搜索/导出/独立窗口 + ConsoleWindowView
│   ├── UI/Detail/PluginManagerView.swift 插件管理 sheet
│   ├── UI/Detail/LinkMenu.swift          外链菜单
│   ├── UI/Detail/RiskyAction.swift       高危操作确认（标题/按钮已本地化）
│   ├── UI/Settings/SettingsView.swift    四页 TabView：General/Server/Tools/About
│   ├── Model/AppModel.swift              组合根；isStoppingAll / isCurrentInstanceRunning
│   └── Model/VersionCatalogModel.swift   refreshInstallState(for:)
├── OrzMC/Common/Localizable.xcstrings     zh-Hans 本地化
├── OrzMC/Common/ExarotonUI/              远程托管（macOS 窗口 + iOS 共用）
├── Sources/OrzMCDesignSystem/            设计令牌 + 状态/标签/提示/控制台面板
└── docs/
    ├── app-ui-design.md                  完整 UI 梳理与决策
    └── ui-handoff.md                     本文件
```

---

## 5. 必须保留的约定

1. **父仓库只 bump 指针，代码改子模块**；提交前显式 `git add <路径>`。
2. **不要恢复 `WindowGroup` 主窗口**：复制启动器会导致 `servers.json`/探活/控制台分叉。
3. **不要恢复重复的文本框标签**：行标签 + 空 label TextField + 示例 prompt。
4. **不要在业务视图里写死颜色**：统一走 `OrzMCTheme.Palette`。
5. **控制台/日志面板用 `.consoleSurface()`**，不要用 `Color.black` / `Color.white`。
6. **外部链接用 `Link` / `openURL`**，不要恢复 SwiftUIX `Web`。
7. **静态文案走 `Localizable.xcstrings`**；运行时错误用 `verbatim:` 初始化器。
8. **`Sources/*` 不 import AppKit/UIKit**（CI 会跑 `check-platform-split.sh`）。
9. **控制台窗口共享 `AppModel`**，不要为每个窗口新建 `AppModel`。
10. **删除/终止/停止全部**必须二次确认；`⋯` 菜单里的 Terminate/Delete 不要漏确认。

---

## 6. 待办与验收标准

### P0：维护者视觉验收后可能要微调

1. **Launch 区高度/对齐**：在 960/1200 宽窗口下看 3 行是否仍然偏松；
   若要更紧凑，可把 Section header 改成普通 `Label` 行或减少 `Form` 行间距。
2. **文本框**：确认 Settings / Launch 的字段宽度、prompt 与焦点环视觉一致；
   若 Form 的 `LabeledContent` 行高仍然奇怪，改为纯 `TextField("标题", text:)` + 单独控件行。
3. **远程服务器**：在 Remote Servers 窗口打开时检查：
   - 列表状态徽标是否与名称/标签对齐；
   - 详情 General 的地址复制按钮是否可点；
   - Actions 的 `ControlGroup` 在窄窗口是否换行；
   - 额度池大额度卡是否过大/过小。
4. **中文文本**：检查长文案是否截断；必要时 `.lineLimit(2)` / `.fixedSize(horizontal:false, vertical:true)`。

### P1：收尾

1. 在 `air` 桌面会话截图（需维护者授权屏幕录制），做 3 张基线：主窗口、Settings、Remote Servers。
2. 把 `RiskyAction.message` 长说明与 `LauncherError` 引擎错误也纳入本地化（错误码 + 本地化资源）。
3. Exaroton 3s Timer 改 WebSocket 状态驱动（内部实时性，先不做以免影响流订阅）。
4. 控制台 `consoleLog` 每秒 `joined` 改增量拼接（2000 行上限已控制影响）。
5. 若维护者给品牌色，再补 `AccentColor` light/dark/高对比度三套。

### P2：可选

- 视觉回归脚本（`screencapture` 需 GUI/录屏权限）。
- 更多无障碍：控制台“朗读最新一行”、日志按级别过滤。
- 远程服务器详情增加静态/动态地址的显式标签。

---

## 7. 构建 / 运行 / 验证

```bash
cd /Users/bot/OrzMC

# macOS（增量 ~17s）
scripts/air/run.sh app

# iOS Simulator（~1m）
scripts/air/run.sh app-ios

# 平台无关单测
scripts/air/run.sh app-test

# 平台分层（Sources/ 不得 import AppKit/UIKit）
cd swift/app && ./scripts/check-platform-split.sh

# 在 air 上打开最新产物（GUI）
cd /Users/bot/OrzMC && scripts/air/run.sh app-run
```

最近一次结果：

- `app`：BUILD SUCCEEDED
- `app-ios`：BUILD SUCCEEDED
- `app-test`：通过
- `check-platform-split.sh`：通过
- `Localizable.xcstrings`：JSON 合法
- Settings 打开/关闭：`air` 上验证无崩溃

### 7.1 用 AppleScript 检查窗口/菜单（air）

```bash
ssh air 'osascript -e "tell application \"System Events\" to tell process \"OrzMC\" to get {frontmost, count of windows, name of windows}"'
```

打开 Settings：

```bash
ssh air 'osascript -e "tell application \"OrzMC\" to activate" \
  -e "delay 1" \
  -e "tell application \"System Events\" to keystroke \",\" using command down"'
```

> `air` 上 `screencapture` 被 TCC 拒绝；不要试图用 `screencapture` 做验收，改用维护者桌面会话。

---

## 8. 建议的提交 / PR 计划（待维护者确认）

1. 在 `swift/app` 开分支：`feat/ui-refresh`（从当前 `main` 工作区切）。
2. 按主题拆 commits（Conventional Commits + 中文）：
   - `fix(settings): inject AppModel and share app-level state`
   - `feat(window): single launcher window + remote/console windows`
   - `feat(ui): design tokens, compact launch, unified text fields`
   - `feat(exaroton): restyle remote server list/detail`
   - `feat(l10n): add zh-Hans string catalog`
   - `chore(deps): remove unused SwiftUIX / FeedbackToAuthor`
   - `docs(ui): add UI review and handoff docs`
3. 跑 `scripts/air/run.sh app|app-ios|app-test` + `check-platform-split.sh`。
4. 推分支 → PR（子模块自己的 CI）→ 合并。
5. 回父仓库：
   ```bash
   git add swift/app
   git commit -F /tmp/bump-app.txt   # chore(submodule): bump swift/app 指针（UI 刷新）
   ```
6. 更新父仓库 `HANDOFF.md` 的当前焦点/会话日志（已有本次记录，可补充 PR 链接）。

---

## 9. 给 Codex 的交接提示词（复制下面整段）

```text
你在 OrzMC 父仓库（/Users/bot/OrzMC）的 macOS 启动器子模块 swift/app 继续工作。
先读这三个文件，再动手：
1) swift/app/docs/ui-handoff.md（本交接文档）
2) swift/app/docs/app-ui-design.md（UI 信息架构/设计系统/决策）
3) 父仓库 AGENTS.md + HANDOFF.md

当前状态：
- swift/app 在 main 分支，有约 42 个文件的未提交改动（37 个已跟踪修改 + 5 个新文件，删除 FeedbackToAuthor.swift）。
- 主线已完成：Settings 崩溃修复、单启动器 Window + 控制台 WindowGroup + 远程 Window、侧边栏/详情信息架构、启动区压缩、文本输入框统一、设计系统、本地化（zh-Hans 220 条）、控制台搜索/导出/独立窗口、插件 searchable、Exaroton 列表/详情/额度池美化。
- 最近验证：scripts/air/run.sh app / app-ios / app-test / check-platform-split.sh 全绿；air 上 Settings 打开/关闭无崩溃。
- 改动尚未提交/推送，父仓库未 bump 指针。

硬约束：
- 代码改子模块，父仓库只 bump 指针；禁止 git add -A。
- 不要恢复 WindowGroup 作为主启动器（会复制 AppModel，破坏进程登记/探活/控制台）。
- 文本框统一：LabeledContent 行标签 + 空 label TextField + 示例 prompt；不要出现“行标签 + 同名占位符”。
- 颜色只用 OrzMCTheme 语义色；控制台用 .consoleSurface()；外部链接用 Link。
- 静态文案走 Localizable.xcstrings；Sources/* 不得 import AppKit/UIKit。
- 不要替维护者决定提交/发版；先做视觉/交互修正，等确认后再开分支提交。

你的任务：
1. 先通读未提交 diff，确认没有破坏上述约束；列出你发现的回归或风险。
2. 在 air 上用最新产物启动 app，按以下清单验收并记录问题：
   - 详情页顶部 Launch 区是否仍然偏高/对齐不齐；
   - Settings 与 Launch 的文本框 label/prompt/宽度/焦点环是否一致；
   - Remote Servers 窗口的列表、详情、Actions、Console、额度池在 960/1200 宽下是否美观；
   - 中文长文案是否截断；
   - 控制台搜索/导出/Follow/独立窗口是否可用；
   - Settings 四页、停止全部、Console 生命周期是否仍正常。
3. 只修视觉/交互问题；每改一处说明“改了什么、为什么、如何验证”。不要顺手重构无关代码。
4. 每次修改后跑：
   scripts/air/run.sh app
   scripts/air/run.sh app-ios
   scripts/air/run.sh app-test
   cd swift/app && ./scripts/check-platform-split.sh
5. 把新发现与验证结果追加到 swift/app/docs/ui-handoff.md 的“待办/验收”或“会话记录”，不要覆盖历史。
6. 维护者确认后再开 feat/ui-refresh 分支、按主题提交、推 PR；提交信息用 Conventional Commits + 中文，多行信息写文件后 git commit -F。

如果 air 的 GUI 看不到窗口：
- 用 ssh air 'osascript -e "tell application \"OrzMC\" to activate"'；
- 用 System Events 读 {frontmost, count of windows, name of windows}；
- 不要用 screencapture（TCC 拒绝），需要截图时请维护者在桌面会话操作。
```

---

## 10. 交接检查清单

- [x] 最新 macOS / iOS 构建通过
- [x] 平台无关单测通过
- [x] 平台分层校验通过
- [x] Settings 打开/关闭无崩溃
- [x] 中文菜单/本地化生效
- [ ] 维护者视觉验收（主窗口 / Settings / Remote Servers）
- [ ] 根据验收微调 Launch / 文本框 / Exaroton 布局
- [ ] 开分支、提交、PR
- [ ] 父仓库 bump `swift/app` 指针

> 最后提醒：当前工作区是**未提交**状态。Codex 接手时不要 `git checkout .` / `git reset --hard`，
> 也不要直接 `git add -A`；先 `git status` + `git diff` 看清约 42 个文件再动。


## 11. 会话记录（追加）

### 2026-10-21 — Codex：diff 审查与 air 交互复核

**范围与工作区**
- 阅读 UI 交接、设计文档、父仓库规则与 HANDOFF；检查现有未提交代码/项目配置差异、新设计系统文件和字符串目录。
- 保持 `main` 未提交工作树；未创建分支、暂存、提交、推送或 bump 父仓库指针。
- 单主窗口 `Window`、App 级唯一 `AppModel`、控制台共享模型、二次确认与平台分层均保留。

**本轮修正（改什么 / 为什么 / 如何验证）**
1. `GameView.swift`：Launch 用户名行改为 `LabeledContent`，空 label TextField + `.labelsHidden()` + 原示例 prompt，启动按钮仍同行。原手写 HStack 不符合字段约定；macOS 构建及最新产物启动通过，焦点环/宽度的视觉一致性待桌面复核。
2. `ServerConsoleView.swift`：Follow 监听 `console.lines.last?.id`，替代 `lines.count`。缓冲达到 2000 行后 count 不再变化、最新 ID 继续递增；已核对缓冲实现，构建/现有单测通过，最新 GUI 开关 `1 → 0 → 1` 成功；满缓冲持续滚动尚待动态验收。
3. `ServerConsoleView.swift` + `Localizable.xcstrings`：行数三元 String 改为两个 Text 分支，新增 `%lld lines` / `%lld / %lld lines` 中文资源。原 String 丢失本地化语义；最新 GUI 读到 `0 行`、搜索提交后 `0 / 0 行`，目录 222 条，格式占位符一致。
4. `MacOSScene.swift`：Help 的联系作者从 NSWorkspace Button 改为 Link，符合外链约定；macOS 构建通过，未实际打开浏览器。
5. `ExarotonContent.swift`：接回错误/操作结果 alert。旧 GameInfoView 被移除时这两类消息无人展示；现在放到共用远程入口，运行时消息用 verbatim。macOS/iOS 构建通过；未故意触发线上失败或远程动作。

**本轮验证（全部修正后的工作树）**
- `scripts/air/run.sh app`：BUILD SUCCEEDED；日志 `/tmp/orzmc-ui-verified-macos.log`。
- `scripts/air/run.sh app-ios`：BUILD SUCCEEDED；日志 `/tmp/orzmc-ui-verified-ios.log`。
- `scripts/air/run.sh app-test`：13 tests / 2 suites 全通过；日志 `/tmp/orzmc-ui-verified-tests.log`。
- `cd swift/app && ./scripts/check-platform-split.sh`：通过。
- `git diff --check`、字符串 JSON/占位符校验：通过。
- 构建脚本同步时有 `.build/checkouts/BlueSocket: not empty, cannot delete` 警告，未影响本轮成功结果；未改父仓库构建脚本。
- 最新产物通过 `app-run` 启动，System Events 返回 `{true, 1, Minecraft - 26.3}`。
- 最新产物 Settings「服务器 / 工具 / 关于 / 通用」逐页打开后关闭成功，进程未崩溃。
- 最新独立 Paper 控制台可打开；Follow 开关可切换；搜索 `test` 后按回车显示中文无结果与 `0 / 0 行`。
- 修正前产物的 Forge 控制台保留 55 行已停止日志；独立窗口创建成功、原控制台仍保留；导出按钮打开系统「保存」独立窗口（不是 sheet）。未验实际文件写入。重启最新产物后旧保存窗口已关闭。
- 修正前产物 Remote 窗口：1 台服务器 + 1 个额度池；列表 → 详情、列表 → 额度池导航成功，详情地址复制按钮与 Actions 可访问。服务器离线，未启动/停止/重启或更改 RAM，也未读取或修改 Token。
- Remote 实际尺寸：960 宽可设置；请求 1200 宽被桌面裁至 1129 宽（高度请求 700，实际 694）。不能将此记为 1200 宽验收通过。

**新增发现 / 待办（未确认通过的项目）**
- [ ] **视觉证据缺失**：未调用 screencapture。Launch 高度/对齐、Settings/Launch 字段宽度与焦点环、中文是否截断、Remote Actions/Console/额度池观感仍须维护者在桌面会话截图或目视确认；真正 1200 宽需更宽桌面。
- [ ] **中文遗漏实测**：Remote 玩家标签读到 `0/20 players`（资源登记 `%lld/%lld players`，需核对 API 整数插值格式）；本地目录标题与说明（Server Folder / World / Logs / Mods 等）仍英文，来自运行时目录数据；额度 accessibility 文案仍 `280.52 credits`。不可宣称 222 条资源等于 UI 全中文。
- [ ] **MOTD**：可访问性内容直接含 Minecraft `§` 格式码，待桌面核对显示并做独立显示层处理。
- [ ] **控制台深验**：带实际日志的搜索命中/清除、实际导出写入与失败反馈、满 2000 行后的 Follow、运行中关闭/重开主窗口和控制台的探活/生命周期。
- [ ] **停止全部**：本轮仅审查确认入口和忙碌状态；未启动受控服务端进行实际 Stop All/Terminate All 验证。
- [ ] **窗口关闭风险（代码审查）**：monitor task 仍绑定主 LauncherUI 生命周期；仅保留控制台时是否继续探活应做真机验证，本轮未改架构。
- [ ] **远程动作**：新增 alert 的真实错误/结果展示、在线 Console 与 RAM 失败恢复尚未操作验证。

维护者确认视觉与剩余验收后，再按第 8 节开分支和提交；本轮不代表发布验收完成。


## 会话记录：2026-10-22 三技能设计与交互审查

- 使用 apple-native-product-design、swiftui-pro、swift-concurrency-pro 审查当前工作树；完整建议见 [ui-review-2026-10-22.md](ui-review-2026-10-22.md)。
- 优先项：本地控制台 Follow 抢滚动、远程生命周期请求缺少忙碌互斥、设置目录逐字提交、远程日志清空后旧内容重新出现。另记录内嵌控制台选中关系、远程空/错状态、Launch 自适应与 RAM 提交顺序。
- Air AppleScript 确认 OrzMC 前台且存在一个主窗口；未取得截图，未声称最新工作树构建完成或完成 960/1200 宽视觉验收。未使用 screencapture。
- 本轮只交付审查文档，未修改产品代码、未提交/推送；无需重跑产品构建。文档相对链接与 git diff --check 已核验。


## 会话记录：2026-10-22 切换 Air 接力

- 新增 [Air 接力文档](air-ui-handoff-2026-10-22.md)，说明未提交工作树恢复、技能、审查优先级和验收边界。
- 完整 tracked patch 与 untracked 文件包放在 Air `/Users/joker/orzmc-handoff/2026-10-22-ui-review/`；正式修改前校验基准与现有工作区，勿把构建镜像当开发仓库。
- 本轮未修改产品代码、未提交/推送或 bump 指针。


## 会话记录：2026-10-22 授权提交与 Git 接力

维护者改为要求先提交推送，再在 Air 重新拉取。app 使用 feat/ui-refresh；父仓库使用 feat/ui-refresh-handoff 记录 app 指针与父交接。以 [Air Git 接力步骤](air-ui-handoff-2026-10-22.md) 为准，历史“未提交/patch 恢复”描述仅为当时记录。审查建议仍未实施，视觉验收未完成。构建镜像、两平台 DerivedData 与旧临时交接包在推送验证后清理。

### 提交前最终验证（2026-10-22）

- Air macOS：BUILD SUCCEEDED；iOS Simulator：BUILD SUCCEEDED。
- app-test：13 tests / 2 suites 通过；check-platform-split.sh 通过。
- 父仓库组合校验通过；git diff --check 通过。
- 仅复验现有实现；三技能审查建议仍待后续实施，视觉验收边界不变。
- 清理保留仍在运行的 macOS app-dd/Build/Products；其余本次 app 构建缓存与旧交接包已授权在推送核验后移除。
