# macOS 启动器：UI 信息架构、设计系统与改进路线

> **状态**：生效中｜**最后更新**：2026-10-21
> **范围**：`OrzMC/Launcher(MacOS)/UI/**` + `OrzMC/Common/ExarotonUI/**` + `Sources/OrzMCDesignSystem/**`
> **交接**：[`ui-handoff.md`](ui-handoff.md)（给下一个 agent 的状态/待办/提示词）。
> **关联**：[`app-launcher-architecture.md`](app-launcher-architecture.md)（模型职责）、
> [`app-platform-split.md`](app-platform-split.md)（平台分层）、
> [`console-acceptance.md`](console-acceptance.md)（控制台验收）。
>
> 本文回答三件事：**界面现在怎么组织、哪些地方不统一、接下来按什么优先级改**。
> 设计令牌与状态组件的实现见 `Sources/OrzMCDesignSystem/`。

---

## 1. 信息架构与跳转流程

### 1.1 macOS（主产品）

```
主窗口「OrzMC」（Window，单实例，⌘, 打开 Settings）
└── NavigationSplitView
    ├── Sidebar（320pt，可拉宽到 480pt）
    │   ├── 版本列表 List(selection:)
    │   ├── 工具栏：Releases 过滤 / 刷新 / Remote Servers
    │   └── .searchable(.sidebar)
    └── Detail：GameInfoView
        └── NavigationStack
            └── BasicInfo（Form）
                ├── Launch（启动配置：Java 状态 / 版本 / 模式 / 核心 / 用户名 / 内存 / Start）
                ├── 实例切换器（Client / Paper / Vanilla / Fabric / Forge）
                ├── 实例表头：状态 + Console / Plugins / Start / Restart / Stop / ⋯(Terminate/Delete)
                └── 常用目录行 → Finder
                    └── ServerConsoleView
                        ├── 日志（等宽、可选中、Follow、搜索、导出）
                        ├── 工具栏：Open in New Window / Export / Clear / Start / Restart / Stop / Terminate
                        └── 命令输入（仅服务端；↑/↓ 历史）

独立窗口「Console」（WindowGroup(for: ConsoleTarget.self)，共享同一个 AppModel）
独立窗口「Remote Servers」（Window，独立 ExarotonServerModel）
Settings（TabView：General / Server / Tools / About）
```

**菜单**：`OrzMC`（About / Check for Updates / Settings… / Quit）、`Edit`、`View`（Show Sidebar / Enter Full Screen）、`Game`（Start Client|Server ⌘B、Stop All Servers… ⇧⌘K）、`Window`（Close / Show Main Window ⌘0 / OrzMC / Remote Servers）、`Help`（Contact Author）。

> **没有 File > New Window**：主启动器使用 `Window`，控制台窗口通过 `openWindow(value:)` 按实例打开，
> 远程服务器使用独立 `Window`。不会出现“再开一个启动器”的入口（见 §3）。

### 1.2 iOS（远控 helper）

```
WindowGroup
└── ContentView
    └── ExarotonContent
        └── NavigationStack
            ├── ExarotonServerList（服务器 / 额度池 / 添加账号 Token）
            ├── ExarotonServerDetail（General / Playlist / Metrics / Actions / Console）
            └── ExarotonCreditPoolDetail（成员 / 服务器）
```

iOS 与 macOS **共用** `Common/ExarotonUI`；平台差异只在 `#if os(...)` 里（List 样式、键盘、sheet detents）。

### 1.3 关键跳转规则

| 从 | 到 | 方式 | 返回 |
|---|---|---|---|
| 版本列表 | 详情 / 启动配置 | `List(selection:)` 绑定 `catalog.selected` | 直接选另一个版本 |
| 实例表头 | 控制台 | `navigationDestination(item:)` | 系统返回 |
| 控制台工具栏 | 独立控制台窗口 | `openWindow(value: ConsoleTarget)` | 关闭窗口 |
| 实例表头 | 插件管理 | `.sheet` + `NavigationStack` | Done / 关闭 |
| 侧边栏 | 远程服务器 | 独立 `Window(id:"remote")` | 关闭窗口 |
| Links 菜单 | 外部网站 | `Link` → 默认浏览器 | 不占用应用内导航 |
| 菜单 / 详情工具栏 | 停止全部 | 同一个 `wantsStopAllConfirmation` alert | Cancel |

---

## 2. 设计系统（`Sources/OrzMCDesignSystem`）

### 2.1 令牌

| 类别 | 位置 | 规则 |
|---|---|---|
| 间距 | `OrzMCTheme.Spacing` | 2 / 4 / 8 / 12 / 16 / 24，不再随手写 3、5、7、10 |
| 圆角 | `OrzMCTheme.Radius` | 6 / 10 / 14 三档 |
| 字体 | `OrzMCTheme.Typography` | 控制台用等宽 `.caption` / `.body`；路径与 ID 用 `code`；版本号用 `numeric`（`monospacedDigit`） |
| 颜色 | `OrzMCTheme.Palette` | 只用 SwiftUI 语义色：`accent` / `success` / `warning` / `danger` / `idle` / `subtleFill` / `consoleBackground` / `consoleBorder` |

**硬规则**：

1. 不在业务视图里写 `Color(red:green:blue:)`、`Color.black`、`Color.white`。
2. 不用颜色单独表达状态：所有状态 = 颜色 + 文字（`OrzMCStatusBadge`）。
3. `Sources/*` 不 `import AppKit` / `UIKit`（CI 的 `check-platform-split.sh` 会查），
   所以令牌只用 SwiftUI 跨平台语义色。
4. 日志/终端面板一律 `.consoleSurface()`：`Color.primary.opacity(0.06)` 底 + 边框，
   浅色/深色/提高对比度都成立。
5. 静态文案走 `Localizable.xcstrings`；运行时错误用 `verbatim:` 初始化器，避免把变量当 key。

### 2.2 组件

| 组件 | 用途 | 替代了什么 |
|---|---|---|
| `OrzMCStatusBadge` | Running / Stopped / Starting… / Ready | 详情页、控制台、Java 状态各自手写的圆点 + 胶囊 |
| `OrzMCTag` | 分类标签（版本类型 / `local` / 渠道 / 更新数） | 各处不同透明度的 Capsule |
| `OrzMCBanner` | 错误 / 警告 / 说明（localized / verbatim） | 散落的红/橙/灰 `Text` |
| `.consoleSurface()` | 控制台、日志、CLI 输出 | `Color.black.opacity(0.06)` / 黑板白字 |
| `EmptyContentView` | 无选中 / 无远端服务器 | 空白页 |

### 2.3 系统组件优先

已统一到系统组件的地方：

- 设置页：`Form` + `Section` + `.formStyle(.grouped)` + `LabeledContent` + `TabView`。
- 侧边栏：`NavigationSplitView`、`List(selection:)`、`.searchable(.sidebar)`、`ToolbarItem`。
- 详情页：`Form` + `Section` + `LabeledContent` + `Picker` + `TextField(.roundedBorder)`。
- 控制台：`ScrollView` + `ContentUnavailableView.search` + `NSSavePanel` + `.searchable`。
- 插件管理：`NavigationStack` + `.searchable` + `List` + `ContentUnavailableView`。
- 空状态：`ContentUnavailableView`（可带 actions）。
- 外部链接：`Link` / `openURL`（不再用 SwiftUIX `Web` 把网页塞进详情导航）。
- 状态动画：`.symbolEffect(.pulse, ...)`（尊重“减弱动态效果”）。
- 窗口：`Window` + `WindowGroup(for:)` + `SidebarCommands()`。
- 远程列表：`NavigationLink(value:)`（系统高亮 / 键盘导航 / 辅助功能语义）。

---

## 3. 多窗口：哪些可以存在

### 3.1 不能存在：复制启动器

启动器的状态是**进程级**的，不是文档级：

- `AppModel` 持有 `ServerRegistryModel`（`servers.json` 登记表）、`serverProcesses`（优雅停止用的句柄）、
  `ServerConsoleRegistry`（每个实例的日志缓冲）、`LaunchModel`（启动进度）。
- 两个启动器窗口如果**共享**同一个 `AppModel`：选择互相覆盖、错误弹窗两边各弹一次、
  `.task { monitor() }` 跑两份探活。
- 两个启动器窗口如果**各自**新建 `AppModel`：两份登记表写同一个 `servers.json`，
  A 窗口启动的服务端 B 窗口不知道，可能重复启动撞端口；`Stop All` 只停自己那一份。

### 3.2 现在允许的两种窗口

| 窗口 | 场景 | 状态 |
|---|---|---|
| `Window(id:"main")` | 主启动器 | **唯一**，单份 `AppModel` |
| `WindowGroup(for: ConsoleTarget.self)` | 某个实例的控制台 | 共享主窗口的 `AppModel`，同一个 `ServerConsoleModel` |
| `Window(id:"remote")` | Exaroton 远程托管 | 独立 `ExarotonServerModel`，不碰本机进程状态 |

- `GameView` 工具栏的 **Remote Servers** 打开远程窗口；
- 控制台工具栏的 **Open in New Window** 用 `openWindow(value: ConsoleTarget)` 打开独立控制台；
- `MainWindowCommands` 提供 **Window > Show Main Window（⌘0）**，关掉主窗口后能叫回来；
- 用 `CommandGroup(replacing: .newItem) {}` 移除 File > New Window 的空白窗口入口。

### 3.3 结论

- **“再开一个启动器”不允许**（会造成进程管理分叉）。
- **“多视图看同一份状态”允许**：控制台窗口、远程管理窗口。
- 如果将来要做“多实例并行管理”，正确方向是 `WindowGroup(for: InstanceID.self)` + 共享 `AppModel`，
  而不是复制 `AppModel`。

---

## 4. Settings 崩溃：根因与修复

### 4.1 根因

`Settings` 场景只注入了 `SettingsModel`：

```swift
Settings {
    SettingsView()
        .environment(app.settings)   // ← 只注入 settings
}
```

但 `SettingsView` 读的是 `AppModel`：

```swift
@Environment(AppModel.self) private var app
```

`@Environment(Type.self)` 是非可选的，找不到就触发断言。2026-10-21 的崩溃报告
（`OrzMC-2026-10-21-195204.ips` / `-200151.ips`）栈顶正是：

```
AppWindowsController.makeSettingsWindowController
→ EnvironmentValues.subscript.getter
→ _assertionFailure
```

### 4.2 修复

```swift
Settings {
    SettingsView()
        .environment(app)   // ← AppModel：设置只是它的一部分
}
```

同时：

- `AppModel` 提升到 `OrzMCApp` 的 App 级 `@State`，主窗口 / Settings / 控制台窗口 / 远程窗口共享同一实例；
- `SettingsView` 拆成 General / Server / Tools / About 四页；
- 根目录写入统一走 `AppModel.rootDir`（会刷新版本目录、JRE、进程视图）。

### 4.3 回归验证

- `scripts/air/run.sh app`：macOS 构建通过。
- `scripts/air/run.sh app-ios`：iOS 模拟器构建通过（共享 Exaroton UI 也一起编）。
- `scripts/air/run.sh app-test`：平台无关单测通过。
- AppleScript 检查菜单（air 系统语言为中文，验证了本地化）：
  - `设置…` / `显示边栏` / `全部停止服务器…` / `显示主窗口` 均存在；
  - 没有 File 菜单 / New Window；
  - Window 菜单列出 `OrzMC` 与 `远程服务器`。

> `air` 的 SSH 会话没有 WindowServer（`!cgsConnection`），无法截图；真实窗口的视觉验收
> 仍需在登录后的桌面会话里点一遍（四页设置、启动配置、控制台搜索/导出/独立窗口、Remote Servers）。

---

## 5. 已修问题

| # | 问题 | 修复 |
|---|---|---|
| 1 | Settings 崩溃 | 注入 `AppModel`（§4） |
| 2 | File > New Window 可复制启动器 | 主窗口 `Window` + `CommandGroup(replacing: .newItem) {}`；控制台/远程用独立窗口 |
| 3 | 「停止全部」注册了两个 ⌘K / 两个 alert | 只保留 `LauncherUI` 一个 alert；快捷键改 ⇧⌘K |
| 4 | 深色模式控制台“黑板 + 8pt 白字” | `.consoleSurface()` + 语义色 + 等宽 `.caption` |
| 5 | 加载指示器 `.opacity(0)` 仍拦截点击 | 条件渲染 |
| 6 | Exaroton Token / 命令 sheet 在 `body` 里发请求 | 显式 Save / Send + `onSave` |
| 7 | Exaroton 行 `onTapGesture` | `NavigationLink(value:)` |
| 8 | 网页塞进 `NavigationStack`（SwiftUIX `Web`） | `Link` 默认浏览器；移除 SwiftUIX 依赖 |
| 9 | Stopped/Offline 用红色 | 中性色；红色只给 error/destructive |
| 10 | 详情页 1.5s 全量 stat 所有版本 | 只重算当前选中版本 |
| 11 | Exaroton 控制台日志无上限 | 最近 2000 行 |
| 12 | Exaroton 加载 RAM 后又 changeRAM | `confirmedRAM` 区分加载与拖动 |
| 13 | ⌘C 发命令覆盖 Copy、⌘S Remote Server | 移除两个快捷键 |
| 14 | 设置固定 600×620 长滚动 | 四页 `TabView` + 系统 Form |
| 15 | 侧边栏可重复启动 | `isCurrentInstanceRunning` |
| 16 | 停止全部无忙碌标记 | `isStoppingAll` |
| 17 | 侧边栏同时承担导航 + 启动配置 | 启动配置移到详情页 `LaunchControls` |
| 18 | 详情页 7 个图标平铺 | Terminate/Delete 收进 `⋯` 菜单 |
| 19 | 本地实例与 Exaroton 混在同一导航栈 | Remote Servers 独立窗口 |
| 20 | 无独立控制台窗口 | `WindowGroup(for: ConsoleTarget.self)` + Open in New Window |
| 21 | 控制台无搜索/导出 | `.searchable` + `ContentUnavailableView.search` + `NSSavePanel` |
| 22 | 插件管理自定义搜索框 | `NavigationStack` + `.searchable` |
| 23 | 界面英文 / 中文混排 | `Localizable.xcstrings`（200+ zh-Hans 条目）+ 状态/确认文案本地化 |
| 24 | 辅助功能标签缺失 | 图标按钮补 label/help；装饰性图标 `accessibilityHidden` |
| 25 | 未使用的 SwiftUIX / FeedbackToAuthor | 删除文件与依赖 |
| 26 | Launch 区域过高（版本/Java/模式/用户名各占整行） | 压成 3 行：版本+模式 / Java / 用户名或核心 + Start |
| 27 | 文本框出现“行标签 + 相同占位符” | 统一为 `LabeledContent` + 空 label TextField + 示例 prompt（如 `Offline player name` / `512M`） |
| 28 | 远程服务器列表/详情观感旧 | 状态徽标 + 软件/玩家标签 + 地址行 + 指标标签；Actions 改为 Start 主按钮 + Stop/Restart `ControlGroup`；额度池大额度卡 |

---

## 6. 剩余优化（P2，按需）

1. **引擎错误文案本地化**：`LauncherError` / `RiskyAction.message` 的长文案仍来自引擎/英文常量；
   要彻底本地化，需要把引擎错误改为错误码 + 本地化资源（错误码已经保留）。
2. **Exaroton 实时性**：`ExarotonServerDetail` 仍是 3s Timer 轮询；可改为 WebSocket 状态驱动，
   减少空闲请求。
3. **控制台增量渲染**：`consoleLines.joined` 每秒重建字符串；日志上限 2000 行后影响可控，
   后续可改为增量追加。
4. **品牌色**：`AccentColor` 仍是系统默认（跟随用户在系统设置中的强调色）。若要品牌色，
   在 Asset Catalog 加 light/dark/高对比度三套，并只改 `OrzMCTheme.Palette.accent`。
5. **视觉回归**：在 `air` 的登录桌面会话里跑 `screencapture` + 关键页面基线图（SSH 会话不可用）。
6. **更多无障碍**：控制台“朗读最新一行”、日志按级别过滤、动态类型/提高对比度的逐页走查。

---

## 7. 多平台适配清单

| 能力 | macOS 14 | iOS 18 | 做法 |
|---|---|---|---|
| 语义色/字体 | ✅ | ✅ | `OrzMCTheme` 只用 SwiftUI 跨平台 API |
| 状态徽标 / 标签 / 提示条 | ✅ | ✅ | `OrzMCDesignSystem` 共用 |
| Exaroton 面板 | ✅ | ✅ | `Common/ExarotonUI` 共用；平台差异 `#if os` |
| 远程列表行 | `NavigationLink` + `.listStyle(.inset)` | `NavigationLink` + 默认 insetGrouped | 同一份代码 |
| 控制台 | 等宽日志 + 命令输入 + 独立窗口 | 日志 + 命令 sheet | `ServerConsoleView` 仅 macOS；Exaroton 控制台共用 |
| 设置页 | `Settings` + TabView | — | macOS 专属 |
| 空状态 | `ContentUnavailableView` | `ContentUnavailableView` | 系统组件 |
| 符号动画 | `.symbolEffect(.pulse)` | `.symbolEffect(.pulse)` | 尊重“减弱动态效果” |
| 窗口 | `Window` / `WindowGroup(for:)` | `WindowGroup` | `OrzMCApp` 按平台分支 |
| 本地化 | `Localizable.xcstrings` | 同 | zh-Hans 已接；其余语言可增量补 |

**不要**为了“统一”把 macOS 的 `NavigationSplitView` 强推到 iOS，或把 iOS 的
`NavigationStack` 强推到 macOS；共用的应该是**令牌、组件、语义和 Exaroton 面板**，
导航容器按平台各用各的。

---

## 8. 验收命令

```bash
# macOS app（增量 ~17s）
scripts/air/run.sh app

# iOS 模拟器（~1m）
scripts/air/run.sh app-ios

# 平台无关单测
scripts/air/run.sh app-test

# 平台分层（Sources/ 不得 import AppKit/UIKit）
./scripts/check-platform-split.sh

# 在 air 上打开（需要登录桌面会话；SSH 会话可能没有 WindowServer）
scripts/air/run.sh app-run
```
