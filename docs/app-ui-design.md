# macOS 启动器：UI 信息架构、设计系统与改进路线

> **状态**：生效中｜**最后更新**：2026-11-08
> **范围**：`OrzMC/Launcher(MacOS)/UI/**` + `OrzMC/Common/{ServersUI,SelfHosted,ExarotonUI,MCSManagerUI,RemoteHostingUI}/**` + `Sources/OrzMCDesignSystem/**`
> **交接**：[`ui-handoff.md`](ui-handoff.md)（给下一个 agent 的状态/待办/提示词）。
> **关联**：[`app-launcher-architecture.md`](app-launcher-architecture.md)（模型职责）、
> [`app-platform-split.md`](app-platform-split.md)（平台分层）、
> [`console-acceptance.md`](console-acceptance.md)（控制台验收）。
>
> 本文回答三件事：**界面现在怎么组织、哪些地方不统一、接下来按什么优先级改**。
> 设计令牌与状态组件的实现见 `Sources/OrzMCDesignSystem/`。

---

## 服务器页：一个列表、按来源分组（2026-11-08 合并）

**一个页面**（`OrzMC/Common/ServersUI/ServersContentView.swift`，macOS「服务器」窗口与 iOS 首页同一份），
分组顺序固定 **自建 → exaroton → MCSManager**；每组允许多个账号 / 面板，每个账号下完整展示实例。
**页顶只有一个带边框的「添加服务器」菜单**（先选来源：自建服务器 / Exaroton 账号 / MCSManager 面板，
再填对应表单）；分组标题旁不再放添加按钮，一条记录都没有的来源整组不渲染。
账号和实例操作菜单统一使用系统默认带边框样式。

> 2026-11-08 之前自建与远程托管是两个"面"：macOS 窗口顶部分段控件切换、iOS 两个 Tab。
> 合并后**顶部不再有切换控件**，iOS 也不再分 Tab——"服务器在哪"只是同一张列表里的分组。
> 决策与验收见下方 §11。

**共享骨架落在** `OrzMC/Common/RemoteHostingUI/`（三家来源都用，macOS 与 iPhone 同一份）：

| 骨架 | 负责 | 两家各自特化的部分 |
|---|---|---|
| `ServersContentView`（`Common/ServersUI/`） | 页面层：持有三个模型、页顶唯一添加入口、所有表单 sheet、统一空态 | 分组顺序与空态文案 |
| `AddServerMenu` | **页顶唯一**的添加入口：先选来源（自建 / Exaroton / MCSManager），再弹对应表单 | 表单内容（地址+RCON / 账号+TOKEN / 地址+API Key） |
| `RemoteProviderSection` | 分组标题行（图标 + 名称 + 实例数）；**一条记录都没有的来源整组不渲染** | 标题文案 / 图标 / 计数口径 |
| `EmptyContentView`（设计系统） | 三条来源一条都没有时的空态说明页 | 文案 |
| `RemoteAccountCard` | 账号卡（头部 + 面板底 + 内边距） | exaroton：账号凭据；MCSM：面板地址 + API Key |
| `RemoteAccountMenu` | `⋯` 菜单：刷新 → 编辑 → 删除（顺序固定） | 编辑/删除落到各自模型 |
| `RemoteInstanceRow` | 实例行：`名称 + 状态徽标` → 明细行 → 右侧动作 → 底部（停止进度 / 错误） | exaroton：id、标签、地址、MOTD、跳详情页；MCSM：地址、玩家数、动作菜单、开控制台**页** |
| `RemoteInlineLoading` / `RemoteInlineEmpty` / `RemoteInlineError` | 账号内的加载 / 空 / 失败（同一套排版，失败带「重试」） | 文案 |

排版规则（改远程托管页必须遵守）：

0. **添加入口只有一个，在页顶**：菜单里选来源 → 弹该来源的表单；不在分组标题旁边再放「添加」。
   三条来源一条都没有时不渲染任何分组，只显示空态说明页（同一页不再出现"空卡片"）。
1. **组内不再"面板套面板"**：账号卡是一张面板，实例/额度池是**平铺行**（同一套行骨架），
   行间用 `Spacing.md` 分隔。
2. **行内字段顺序固定**：名称 + 状态徽标（`RemoteInstanceHeading`，内含 `OrzMCStatusBadge`）→ 明细 → 右侧。
   右侧只放"不属于本体"的东西：跳转箭头、玩家数、`⋯` 菜单。
3. **辅助功能大字号**：右侧动作自动换到下一行（`RemoteInstanceRow` 里统一处理），不在各供应商视图里重写。
4. **状态徽章 / 停止进度 / 控制台**仍然各自唯一实现：`OrzMCStatusBadge`、`RemoteStopProgress`、
   共享控制台（见 [`console-rendering.md`](console-rendering.md)）。骨架只摆位置，不判状态。
5. **不在 SwiftUI 容器上设 `accessibilityIdentifier`**：行的按钮锚点由 `RemoteInstanceRow(tapIdentifier:)`
   交给内部那个按钮；容器的标识会下发给子元素并覆盖它们自己的 identifier。

前后对比截图：骨架重构 [`ui-remote-hosting-2026-11-05/`](ui-remote-hosting-2026-11-05/)、
统一添加入口 [`ui-remote-add-provider-2026-11-06/`](ui-remote-add-provider-2026-11-06/)。

## 字段与行布局约定（2026-10-22 视觉复审后固化）

这几条来自实际踩到的观感问题，新增/修改界面时按此执行：

1. **表单行一律用 `LabeledContent`**，并套 `.labeledContentStyle(.orzMCFieldRow)`（设计系统里固定 96pt 标签列）。
   macOS 默认标签列会撑到约半行宽，1200pt 窗口下标签与控件被拉到两端；手写 `HStack` 行则会让左边缘参差
   （详情页"启动区排布混乱"就是这两件事叠加）。
2. **字段标签 = `LabeledContent` 的行标签**，`TextField` 自身标题留空 + 给示例 `prompt`
   （例：`TextField("", text:, prompt: Text("Absolute path"))`）。
   **必须同时 `.labelsHidden()`**：空标题在 `Form` 里仍会占一个标签列，输入框会被推到右边
   （2026-10-22 截图确认，这就是"输入框文字对齐异常"的根因）。
   再用 `.multilineTextAlignment(.leading)` 显式左对齐——表单默认把"值"右对齐（数值字段才用 `.trailing`）。
3. **行内混排文字与控件用 `.firstTextBaseline`**（例：`0 – 2G` 内存输入）。
   纯控件行（输入框 + 按钮）保持默认 `.center`，但要给无内边距的 `.plain` 字段补 `padding(.vertical)`。
4. **等宽文字与相邻控件同字号**：路径/令牌用 `.font(.body.monospaced())`，
   不要用 `.caption` 等宽（比按钮文字小一号，看着“没对齐”）。
5. **数值输入右对齐**：`.multilineTextAlignment(.trailing)`。
6. **主操作单独成行、跨满宽度**（`.frame(maxWidth: .infinity)` + `.borderedProminent`），
   不塞进带输入控件的 `LabeledContent`——否则文案一变宽窄就挤压输入框。
7. **侧边栏行**：图标与两行文字整体居中对齐（不要 `.firstTextBaseline` 装 SF Symbol，会低半格）；
   第二行固定最小高度（空内容也占位），行高不随“是否安装”跳动；
   侧边栏里不用胶囊标签，已装内容用次要文本。
8. **作用于列表的过滤/刷新放在列表自己的顶部**，与搜索框同一行、用单图标按钮（2026-10-22 起）：
   `SidebarSearchBar`（放大镜搜索 + 只看正式版 + 刷新）。不要挂到窗口工具栏，
   也不用 `.searchable`（系统搜索框右侧插不进自定义按钮）。
   开关用 `.switch`（有明确开/关语义），加载中不要替换图标（宽度会跳）。
11. **窗口级入口放窗口工具栏**（顶部一排，与系统侧边栏开关同排）：外部链接菜单、远程服务器窗口。
   它们与"当前版本"无关，**不要挂在版本详情页的工具栏上**——详情页只放启动配置、实例目录与控制台。
   工具栏菜单按钮用 `.menuIndicator(.hidden)`，与相邻图标按钮保持同样的圆形/胶囊轮廓。
9. **工具栏只留当前主动作**；低频/破坏性动作进 `Menu`（控制台：生命周期常驻，
   打开新窗口/导出/清空进溢出菜单）。
10. **焦点成组**：每个表单/面板加 `.focusSection()`，避免 Tab 在侧边栏、表单、工具栏之间乱跳。


## 1. 信息架构与跳转流程

### 1.1 macOS（主产品）

```
主窗口「OrzMC」（Window，单实例，⌘, 打开 Settings）
└── NavigationSplitView
    ├── 窗口工具栏（顶部一排）：外部链接 · 远程服务器 · 系统侧边栏开关
    ├── Sidebar（260–520pt，可拖拽）
    │   ├── 顶部一行：搜索 + 只看正式版 + 刷新
    │   ├── 清单更新时间（今天 HH:mm）
    │   └── 版本列表 List(selection:)：版本号 + [最新] + 「发布日期 · 已装内容」，↑/↓ 与 ⌘↑/⌘↓
    └── Detail：GameInfoView（标题栏 = 启动区；正文只放实例内容）
        └── NavigationStack
            ├── 窗口工具栏：仅「停止全部服务器」（运行中时出现）
            ├── 详情页顶部「启动卡」（LaunchBar，品牌色薄渐变 + 强调描边 + 14pt 圆角，
            │   刻意区别于下面的实例列表卡）：
            │   启动目标菜单 | 玩家名（仅客户端）| Java 需求状态（点击重扫）| ▶ 启动
            └── BasicInfo（ScrollView + 玻璃面板，**按类型分组列出全部实例**）
                ├── 客户端组标题行右侧：展示模式 = 两个**图标动作按钮**（compress / expand，默认折叠，
                │   `@AppStorage` 记住选择；点击总是作用于全部卡片，不依赖当前选中态）
                │   单栏还能点标题（或标题左侧的 ⌄/›）单独折叠/展开；改全局模式会清掉单栏覆盖
                ├── 客户端组：客户端（Vanilla）/ 客户端（Fabric），共用 `<version>/client`
                └── 服务端组：服务器（Paper / Vanilla / Fabric / Forge），各自独立目录与生命周期
                    └── 实例面板：折叠 = 只留表头一行；展开 = 表头 + 目录行
                        └── 表头动作按 `HeaderActionPlan` 尽量全部内联：
                            控制台/插件 ｜ 启动/重启/停止 ｜ 终止/删除（放不下才收进 `⋯`）
                    └── ServerConsoleView
                        ├── 日志（等宽、可选中、Follow、搜索、导出）
                        ├── 工具栏：生命周期常驻 + ⋯(Open in New Window / Export / Clear)
                        └── 命令输入（仅服务端；↑/↓ 历史）

独立窗口「Console」（WindowGroup(for: ConsoleTarget.self)，共享同一个 AppModel）
独立窗口「Remote Servers」（Window，独立 ExarotonServerModel）
Settings（TabView：General / Server / Tools / About）
```

**菜单**（2026-10-22 修订）：
- `OrzMC`：**关于**（替换系统默认的「关于 OrzMC」，仍弹系统标准关于面板）/ **检查更新…** ⌘U / 设置… ⌘, / 服务 / 隐藏 / 退出。
  菜单文案一律走 `Localizable.xcstrings`；「检查更新」的标题由应用传入（依赖默认值是硬编码英文）。
- `编辑` / `显示`（显示边栏 ⌃⌘S）/ `窗口`（最小化 / 缩放 / OrzMC / 远程服务器 / 显示主窗口 ⌘0）。
- `游戏`：跳到最新版本 ⌘↑ / 跳到最旧版本 ⌘↓ / 启动客户端·服务器 ⌘B / 全部停止服务器… ⇧⌘K。
  中文里不写空格（`"Start %@"` 的 zh-Hans 用「启动%@」，否则会出现「启动 客户端」）。
- `帮助`：**使用文档** / 联系作者。**不再保留系统自动插入的「OrzMC 帮助」**——本项目没有 Help Book，
  那一项点开只会让帮助浏览器搜不到结果，等同于不可用（`CommandGroup(replacing: .help)`）。

> **没有 File > New Window**：主启动器使用 `Window`，控制台窗口通过 `openWindow(value:)` 按实例打开，
> 远程服务器使用独立 `Window`。不会出现“再开一个启动器”的入口（见 §3）。

### 1.2 iOS（远控 helper）

```
WindowGroup
└── ContentView
    └── ServersContentView（与 macOS「服务器」窗口同一份）
        └── NavigationStack（标题：服务器）
            ├── SelfHostedServersSection（自建：卡片列表，点卡片进详情）
            │   └── SelfHostedServerDetailView（状态 / 玩家 / RCON 控制台）
            ├── ExarotonAccountsSection（账号卡 → 实例卡片 / 额度池）
            │   ├── ExarotonServerDetail（概览 / 玩家 / 性能 / 内存 / 操作 / 控制台）
            │   └── ExarotonCreditPoolDetail（成员 / 服务器）
            └── MCSManagerSection（面板卡 → 实例卡片 → 控制台页，push）
```

iOS 与 macOS **共用** `Common/ServersUI`、`Common/SelfHosted`、`Common/ExarotonUI`、`Common/MCSManagerUI`；
平台差异只在 `#if os(...)` 里（List 样式、键盘、sheet detents、是否需要 Esc）。

macOS 的「服务器」窗口与 iOS 首页是**同一个页面**：一个列表、页顶一个「添加服务器」菜单，
不再有分段控件 / Tab 切换（见 §3.2、§11）。

### 1.3 关键跳转规则

| 从 | 到 | 方式 | 返回 |
|---|---|---|---|
| 版本列表 | 详情 / 启动配置 | `List(selection:)` 绑定 `catalog.selected` | 直接选另一个版本 |
| 实例表头 | 控制台 | `navigationDestination(item:)` | 系统返回 |
| 控制台工具栏 | 独立控制台窗口 | `openWindow(value: ConsoleTarget)` | 关闭窗口 |
| 实例表头 | 插件管理 | `.sheet` + `NavigationStack` | Done / 关闭 |
| 侧边栏 | 远程服务器 | 独立 `Window(id:"remote")` | 关闭窗口 |
| 工具栏「链接」菜单 | 外部网站 | `Link` → 默认浏览器 | 不占用应用内导航 |
| 菜单 / 实例面板 ⋯ | 停止全部 | 同一个 `wantsStopAllConfirmation` alert | Cancel |

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

- 设置页：`Form` + `Section` + `.formStyle(.grouped)` + `LabeledContent` + `TabView`
  （5 页：通用 / 客户端 / 服务器 / 命令行 / 关于；**section 标题与行标签不重复**，
  CLI 参数说明放 `.help()`，低频项渐进披露）。
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
| `Window(id:"remote")` | 「服务器」：一个列表（自建 SLP/RCON + exaroton + MCSManager 面板按来源分组） | 自建用 `SelfHostedServersModel`；托管用独立的 `ExarotonServerModel` / `MCSManagerModel`。都不碰本机进程状态 |

- `GameView` 工具栏的 **Servers** 打开「服务器」窗口；
- 控制台工具栏的 **Open in New Window** 用 `openWindow(value: ConsoleTarget)` 打开独立控制台；
- `MainWindowCommands` 提供 **Window > Show Main Window（⌘0）**，关掉主窗口后能叫回来；
- 用 `CommandGroup(replacing: .newItem) {}` 移除 File > New Window 的空白窗口入口。

### 3.2.1 窗口关闭语义（2026-10-23 定稿）

| 类别 | 例子 | Esc | ⌘W / 红点 |
|---|---|---|---|
| **主窗口** | 启动器主页 | ❌ 不关（Esc 留给"取消搜索 / 退出编辑") | ✅ |
| **辅助窗口** | 设置、控制台、服务器 | ✅ 关 | ✅ |
| **弹层** | sheet / 确认框 / alert | ✅ 关（先关这一层） | — |

理由：辅助窗口是"看一眼就走"的覆盖层，Esc 是 macOS 里撤掉一层覆盖层的通用手势；
主窗口关掉等于退出应用，不该被一次误按 Esc 触发。

统一实现：`OrzMC/Launcher(MacOS)/UI/Settings/EscapeClosesWindow.swift`（`.escapeClosesWindow()`）：

- 只响应**聚焦窗口**（`NSApp.keyWindow === window`），不会在 A 窗口按 Esc 把 B 窗口关掉；
  控制台窗口例外（`allowWhenNotKey: true`），因为 `openWindow(value:)` 之后 key 可能仍在主窗口；
- 放行条件：输入法正在拼写、窗口上有 sheet、正在文本编辑（`closeWhileEditingText: false` 时）；
- 不用 `.onExitCommand`（辅助窗口第一响应者常为空，命令链收不到），也不用零尺寸
  `keyboardShortcut(.escape)` 按钮（独立 `Window` 里不参与键盘分发）。

### 3.3 结论

- **“再开一个启动器”不允许**（会造成进程管理分叉）。
- **“多视图看同一份状态”允许**：控制台窗口、远程管理窗口。
- 如果将来要做“多实例并行管理”，正确方向是 `WindowGroup(for: InstanceID.self)` + 共享 `AppModel`，
  而不是复制 `AppModel`。

### 3.x 状态徽章里的旋转图标：时间驱动

进行态（开始中/停止中/加载中…）的图标**必须一直转**。踩过两次坑：

1. `symbolEffect(.rotate)`：依赖符号重新插入，文案更新引起局部重绘就停；
2. `rotationEffect` + `@State` 角度 + `repeatForever`：`onAppear` 里直接赋 360° 没有动画事务 →
   首次出现不转；从详情页返回再进入时视图重建、`@State` 已是 360° 且不再触发 `onChange` → 永远不动。

现在的实现：角度由 `TimelineView` 的时间算出（`Sources/OrzMCDesignSystem/StatusBadge.swift`），
没有状态、不依赖动画事务，重建多少次都继续转。所有徽章（列表卡片、详情概览、额度池里的服务器、
自建服务器、macOS 侧栏/控制台）都从这里出，改一次全生效。

回归测试：`testStatusBadgeKeepsSpinningAfterReentering` —— 截两次徽章区域比像素，
覆盖"首次出现 / 进详情 / 返回 / 再进"四种时刻。

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

- `scripts/swift-check.sh app`：macOS 构建通过。
- `scripts/swift-check.sh app-ios`：iOS 模拟器构建通过（共享 Exaroton UI 也一起编）。
- `scripts/swift-check.sh app-test`：平台无关单测通过。
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
| 14 | 设置固定 600×620 长滚动 | 五页 `TabView` + 系统 Form（每页不滚动） |
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
| 状态徽标 / 标签 / 提示条 | ✅ | ✅ | `OrzMCDesignSystem` 共用（**唯一**状态徽章实现：`OrzMCStatusBadge`） |
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
scripts/swift-check.sh app

# iOS 模拟器（~1m）
scripts/swift-check.sh app-ios

# 平台无关单测
scripts/swift-check.sh app-test

# 平台分层（Sources/ 不得 import AppKit/UIKit）
./scripts/check-platform-split.sh

# 在 air 上打开（需要登录桌面会话；SSH 会话可能没有 WindowServer）
scripts/swift-check.sh app-run
```


## 8.0 面板与列表行（2026-10-22 第八轮）

- **详情页 = 滚动视图 + 玻璃面板**：`.orzMCPanel()`（macOS/iOS 26+ 为 `glassEffect`，更老系统为等效填充 + 细描边）。
  不再用 `Form(.grouped)` 承载启动/实例面板——`Form` 的标签列会让控件左右飘。
- **版本列表行（方案 B）**：`版本号 + [最新]` / `发布日期（今天·昨天·N 天前）· 已装内容`；
  日期判定在 `VersionDateText`（`Sources/OrzMCLauncher`，可单测），文案在视图层本地化。
- **清单刷新时间**：侧边栏底部小字（`VersionCatalogModel.lastRefreshedAt`，持久化）。
- **筛选行**：搜索框 `minHeight 30` + 图标按钮 30–34pt；侧边栏可拖拽 260–520pt。

## 8.1 本机 UI 快照（不依赖屏幕录制权限）

调试构建内置了窗口快照，用来对照 960/1200pt 与亮暗外观（应用渲染自己的窗口，无需 TCC 授权）：

```bash
# 一次性：截完自动退出
open -n <OrzMC.app> --args --snapshot /tmp/ui --snapshot-size 1200x742

# 常驻监听（推荐）：应用保持运行，写请求文件即可反复出图
open -n <OrzMC.app> --args --snapshot-watch /tmp/shots
echo '{"prefix":"/tmp/shots/dark-1200","size":"1200x742","appearance":"dark"}' > /tmp/shots/request.json
echo '{"prefix":"/tmp/shots/light-set","size":"960x593","appearance":"light","settings":true,"settingsTab":"general"}' > /tmp/shots/request.json
```

输出 `<prefix>-<序号>.png`（窗口合成图）与 `<prefix>-<序号>-cached.png`（视图自绘）：
SwiftUI 的 `List`（侧边栏）只在合成图里出现，而窗口被遮挡时合成图可能是空白 —— 两份对照看。
仅 `DEBUG` 编译，Release 不含该代码。

## 9. 2026-10-22 交互与桌面复核补充

- Follow 仅在用户滚动时离开底部暂停；展示未读数与“回到最新”入口，日志追加无动画。macOS 14 通过 `NSScrollView.didLiveScrollNotification` 识别用户滚动；回到底部使用短动画，系统减少动态效果时即时定位。
- 远程服务器动作以 MainActor 模型按服务器 ID 互斥；进行中显示请求状态，接受后显示非模态“请求已提交”，服务器最终状态仍由远端数据确认。内存步进器编辑草稿，显式保存或还原；请求期间禁用冲突操作。
- 游戏目录输入先保存在草稿中；Return/应用执行绝对路径和文件类型校验后才更新 `AppModel.rootDir`。选择目录与恢复默认仍直接提交，Escape 恢复已提交值。
- Exaroton 日志改为稳定 ID 的有界缓冲，清空只清当前显示缓冲，新输出不会带回旧行。连接等待显示中性进度，断线显示重连入口。
- 切换版本会退出旧实例的内嵌控制台，独立控制台仍由固定 `ConsoleTarget` 窗口展示。Settings 最小窗口保持可滚动，并允许增大。
- 当前工作树 macOS / iOS 构建与测试待本轮最终验证；父仓库组合校验通过。真实服务器动作与有日志控制台 Follow 尚未通过受控测试验证；960/1200pt 布局、深浅色与焦点环仍需要维护者桌面视觉检查，本轮未生成或要求截图。

## 10. 2026-11-07 「我的服务器」改为卡片列表 + 详情页

维护者要求：**「我的服务器」的结构要和「远程托管」一致** —— 服务器信息卡片列表、统一的添加按钮、
点卡片进详情页后才显示 RCON 相关内容，并统一卡片样式。

**改前**（`docs/ui-selfhosted-list-2026-11-07/before-inline-rcon.png`）：页顶是「服务器选择胶囊 +
刷新/添加/设置」四个控件，下面依次平铺 状态卡 → 玩家卡 → 控制台卡。换服务器靠胶囊，整页内容重排；
RCON 相关内容与"有哪些服务器"混在一屏。

**改后**（同目录 `after-*.png`）：

| 位置 | 结构 |
|---|---|
| 页顶 | 只有**唯一**添加入口（`添加服务器`，`plus.circle` + `.bordered`，右上）——与远程托管页的「添加账号」同一个位置与样式 |
| 分组 | `RemoteProviderSection(name: "自建", systemImage: "server.rack", count: n)` ——与 `exaroton` / `MCSManager` 分组同一套标题行 |
| 卡片 | `SelfHostedServerCard`：里面就是远程实例卡的 `RemoteInstanceRow`（名称 + `OrzMCStatusBadge` → 地址 → 版本/玩家/延迟标签 → MOTD → 更新时间），外面包一层 `orzMCPanel()`，右侧 `chevron` 表示"可进下一页" |
| 空态 | 一台都没有时：`EmptyContentView` 整页居中 + 页顶浮动的添加入口（与远程托管空态完全同一套） |
| 详情页 | 点卡片进入：状态卡 / 玩家（在线·白名单·封禁）/ 控制台（RCON）；工具栏是刷新 + 设置；返回按钮回到列表 |

**模型**：新增 `refreshAllStatuses()`（列表页把所有已配置服务器**并发**探一遍，每张卡片各有状态）
与按 id 的访问器（`status(for:)` / `statusErrorText(for:)` / `lastUpdated(for:)` / `playersText(for:)`）。
以前只有"当前选中"那台会探测，列表里其它服务器永远是空白。

**移除**：服务器选择胶囊（`selfHosted.serverPicker`）—— 卡片列表本身就是选择器；
页顶的刷新/添加/设置三连按钮（刷新与设置移到详情页工具栏，添加留在页顶）。

**验证**：新增 `testSelfHostedListShowsCardsAndOpensDetail`、`testSelfHostedEmptyStateShowsAddHint`；
原有 6 条自建用例改为"先点卡片进详情"。顺带修了 `check-localization.py` 的盲区：
跨行写的 `String(\n localized: "…"\n)` 匹配不到，导致一句空态说明漏了中文（中文界面里冒英文）。

## 11. 2026-11-07 服务器卡片统一 + 品牌名与按钮风格

维护者三点要求：**①「exaroton」改成「Exaroton」；②服务器相关按钮用主窗口实例卡头的图标按钮风格；
③MCSManager 的服务器信息也对齐同一套卡片，别为三处各维护一套 UI。**

**改前**（`docs/ui-server-cards-2026-11-07/before-lowercase-and-menus.png`）：品牌名是小写 `exaroton`；
账号卡与实例卡右侧是 `⋯ ⌄` 下拉胶囊；MCSM 实例行是"名称 + 状态 + 地址 + 裸 `0/0`"，展平在账号卡里，
和自建/exaroton 的卡片不是一回事。

**改后**（`after-remote-macos.jpg`、`after-remote-iphone-*.png`）：

| 项 | 现在 |
|---|---|
| 品牌名 | 界面上一律 `Exaroton`（域名 `exaroton.me`、Token key、`exaroton.*` 标识符**不动**；账号名与 `label` 比较改成大小写无关） |
| 卡片 | 新增 `Common/RemoteHostingUI/ServerCard.swift`：**自建 / exaroton / MCSManager 三处同一个组件** ——
`名称 + 状态徽标` → `地址` → `版本/玩家/延迟` 标签 → 备注（MOTD）→ `footer`（更新时间/停止进度/错误） |
| 动作 | `ServerIconButton` + `ServerActionDivider`：**图标 + 组间细分隔线**（与主窗口实例卡头 `FormSectionHeader`
同一套观感）。账号卡：`刷新 │ 编辑 │ 删除`；MCSM 实例卡：`控制台 │ 启动 重启 停止 │ 强杀`
（删除/强杀用 `danger` 着色）。放不下时 `ServerCard` 用 `ViewThatFits` 把动作折到第二行（iPhone SE 实测会折） |
| MCSM 信息 | 玩家数从裸 `0/0` 变成统一标签 `0/0 名玩家`；地址、状态、动作位置与另两处一致 |

**为什么这么做**：同一套卡片语言写三遍，改一处就要改三处（本轮之前自建卡片是渐变面板、
exaroton 是账号卡里的平铺行、MCSM 是"玩家数 + 菜单"）。现在信息槽和动作样式各只有一份实现。

**验证**：`testMCSManagerInstanceActionsAreInline`（内联按钮在、旧 `⋯` 菜单不再出现）、
`testPanelMenuEditOpensEditor`、`testMCSManagerSectionShowsInstancesAndStatus`（`3/20 名玩家` 标签）、
`testMultipleRemoteAccountsShowInstances`（账号名 `Exaroton 1/2`）。

## 12. 2026-11-07 侧边栏「收起后再展开」卡顿：真因是 `.prominentDetail`

维护者反馈：主窗口左侧边栏点按钮关掉、再打开时有明显卡顿。

**量出来的结果**（`--test-sidebar measure`，Debug 构建，三轮往返；探针每 8ms 打点，报主线程最长停顿）：

| | `.prominentDetail`（原来） | `.balanced`（现在） |
|---|---|---|
| **展开**（收起 → 显示） | **92–192 ms**（每轮 3–5 次 >33ms） | **11–12 ms**（0 次 >16ms） |
| 收起（显示 → 隐藏） | 19–34 ms | 15–17 ms |

**真因**：`.prominentDetail` 是"侧边栏浮在详情上"的 overlay 样式，每次展开都要重排 overlay 那一层，
主线程一次性阻塞上百毫秒；`.balanced` 是常规分栏（详情让位），展开只是宽度动画，开销降到个位数毫秒。
功能与观感没有可见差异（`docs/ui-sidebar-perf-2026-11-07/after-sidebar-*.png` 对照）。

**排查过程中被证伪的猜想**（都实测过，别再走一遍）：

| 猜想 | 实测 |
|---|---|
| `catalog.filtered` 每次 body 重算 | 全生命周期只调用 8–13 次、合计 2–4 ms |
| 行内 `.help()` 提示 | 去掉后无变化 |
| `VersionListScrollProbe` 的背景视图树遍历 | 去掉后无变化 |
| 行高不统一导致反复测量 | 固定行高无变化 |
| 行数太多（上千个版本） | 只剩 1 行时仍有 ~85 ms 固定开销 |
| 侧边栏内容被销毁重建 | `GameView.onAppear` 全程只 1 次（不重建） |
| 折叠动画本身 | 关掉动画无变化 |

**复测方法**（任何改动后都能重跑）：

```bash
# 构建 Debug 后：三轮"收起 → 展开 → 收起"，打印每轮主线程最长停顿
open -n <OrzMC.app> --args --test-sidebar measure,8      # 日志在 stderr
```

⚠️ 踩过的坑：早先用 `NSApp.postEvent` 投递 ⌃⌘S 再做测量，**根本没生效**（应用不是前台时按键进不了菜单），
量到的全是噪音。现在探针用 `NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)))`，
并打印 `handled=` 与侧边栏的 `isHidden`，确认真的切了才算数。

### 11.1 补充：窄屏下实例卡的动作改成"固定底栏"（2026-11-07 维护者截图反馈）

问题（`docs/ui-server-cards-2026-11-07/before-actions-wrapped-iphone.png`）：同一屏两张 MCSM 实例卡里，
一张把动作挤在名称行、另一张被 `ViewThatFits` 折到第二行，看起来像"按钮掉到卡片底部"，观感不一致。

现在（`after-actions-bar-iphone.png`）：

| 宽度 | 动作区 |
|---|---|
| **紧凑**（iPhone 竖屏：`horizontalSizeClass == .compact`） | **固定**成卡片底部操作栏：一条细分隔线 + 右对齐的动作组，所有卡片一致 |
| 常规（iPad 横屏 / macOS） | 与名称同一行；真放不下才退化成底栏（`ViewThatFits`） |

顺带：`Actions == EmptyView` 的卡片（例如「我的服务器」）不再预留操作栏，避免多出一条空白分隔线。

## 11. 2026-11-08 自建 + 远程托管合并成一个列表

维护者要求：**「我的服务器」与「远程托管」合并成一个列表**，不再来回切换、省掉顶部切换控件，
用统一的「添加服务器」按钮（点开后选服务器类型），统一添加流程与展示 UI。

| 位置 | 改前 | 改后 |
|---|---|---|
| 页面 | macOS 顶部分段控件切两个面；iOS 两个 Tab | **一个** `ServersContentView`（macOS 窗口 + iOS 首页同一份），顶部无切换控件 |
| 添加 | 自建页「添加服务器」直接弹表单；远程页「添加账号」先选供应商 | 页顶**一个**「添加服务器」菜单：自建服务器 / Exaroton / MCSManager → 各自表单 |
| 列表 | 两个面各自的空态与页顶按钮 | 一个 ScrollView，分组固定 **自建 → exaroton → MCSManager**；没有内容的来源整组不渲染 |
| 空态 | 两套文案（还没有服务器 / 没有远程服务器） | 一套统一空态（`还没有服务器` + 一句话说明三种来源） |
| 模型 | 各页面各持一份 | 页面层持有 `SelfHostedServersModel` + `ExarotonAccountsModel` + `MCSManagerPanelsModel`，一个 `EditorSheet` 枚举管三种表单 |

**移除**：`ServersWindowContent`（分段控件 + `orzmc.serversWindow.mode` 记忆）、`ExarotonContent`
（远程专用页）、`RemoteAddProviderMenu`（被 `AddServerMenu` 取代）、iOS 的两个 Tab。

**验证**：`check.sh --fast/--build/--ios` + iOS UI 套件；UI 用例的 `ORZMC_DEMO_TAB` 钩子随 Tab 一起移除，
"空态"用例改为**同时**清掉自建档案与远程凭据（否则合并后永远不空）。

## 12. 2026-11-08 服务器卡片动作统一 + 分组折叠

维护者反馈：① 自建服务器的「刷新 / 配置 / 删除」没有和 exaroton / MCSManager 统一；
② 各来源分组要能单独折叠/展开，也要「全部折叠 / 全部展开」，跟主窗口实例栏一个用法。

**① 卡片动作统一**（`OrzMC/Common/SelfHosted/SelfHostedServerView.swift`）

| 项 | 改前 | 改后 |
|---|---|---|
| 动作位置 | 只在详情页工具栏（刷新 / 设置），删除藏在设置表单里 | 卡片右上就是**同一套** `ServerActionGroup`：刷新 ｜ 配置 ｜ 删除（危险动作单独成组并着色） |
| 自动化锚点 | `selfHosted.refresh` / `selfHosted.settings`（详情页） | 卡片上是 `selfHosted.action.refresh|edit|remove`；详情页工具栏保留 |
| 删除 | 无确认（只能从设置表单删） | `confirmationDialog` 二次确认（删本机档案 + 密码，服务器本身不动） |
| 单台刷新 | 只能"全部探一遍" | `SelfHostedServersModel.refreshStatus(for:)`：只探这一台、同台不重入 |

卡片的导航也从 `NavigationLink` 包整卡改成 `ServerCard(onTap:)` + `NavigationStack(path:)`
（`SelfHostedServerRoute`）——包在链接里的按钮点不到（MCSM 实例行早就这么做了，这里对齐）。

**② 分组折叠**（`RemoteProviderSection` / `RemoteProviderHeader` + `ServersContentView`）

- 每组标题左侧有 `chevron`，**点箭头或标题**都能折叠；折叠时只留标题（数量仍在），内容整段不渲染。
- 页顶左侧两个图标按钮：**全部折叠 / 全部展开**（与主窗口 `BasicInfo.displayModeControls` 同一套观感：
  `subtleFill` 底 + 选中档 `selectionFill`）；全局值存 `orzmc.servers.allExpanded`（默认**展开**），
  单组点击写入 `expansionOverrides`，切全局档位时清空覆盖。
- 规则与主窗口一致：**不用 `Picker` 绑全局值**（单组覆盖后全局值没变，再点同一档不触发 `onChange`）。
- 自动化锚点：`servers.collapseAll` / `servers.expandAll` / `<分组>.section.toggle`
  （`selfHosted.section.toggle`、`exaroton.section.toggle`、`mcsm.section.toggle`）；
  分组标题仍是 `staticTexts[selfHosted.section]` 这类锚点（identifier 留在 `Text` 上）。

**用例**：`testSelfHostedCardHasUnifiedActions`、`testServerGroupsCollapseAndExpand`。

## 13. 2026-11-08 视觉评审：把"层级 / 字阶 / 色彩 / 可点感"落到令牌

按 Apple HIG（2026-11-08 用 DocC JSON 核验 `Layout` / `Lists and tables` / `Typography` / `Color` /
`Materials` / `Buttons` / `Toolbars`）对合并后的服务器页做了一次带量测的评审，然后按结论改了实现。

**量测（暗色、macOS 27.2、绿色强调色、780pt 内容宽）**

| 项目 | 改前 | 结论 |
|---|---|---|
| 表面层级 | 窗口 28 / 账号卡 45 / 实例卡 59（sRGB 8bit） | 三个层级，且 45 与 59 **都是 `orzMCPanel()`**（macOS 26+ 为 Liquid Glass） |
| 次级信息对比 | 3.21:1（地址 / 标签 / MOTD / 图标） | 11pt 正文低于 4.5:1 |
| 三级信息对比 | 2.19:1（更新时间 / `chevron`） | 箭头是功能元素，低于 3:1 |
| 字号 | 分组 / 账号 / 实例**都是 `.headline`** | 层级只靠缩进 |
| 每行动作 | MCSM 行 5 个图标 + 3 条分隔线 | 密度偏高 |
| 面板圆角 | 默认 16pt（令牌 `Radius.lg` 是 14） | 令牌漂移；嵌套时内外同半径、不同心 |

**改了什么**

1. **两层表面**：`ServerCard(surface: .panel | .plain)`。顶层卡片（自建 / 详情页）仍是面板；
   账号卡 / 面板卡**内部的行一律 `.plain`**，由外层卡片提供唯一表面 + `RemoteRowDivider` 分隔。
   账号卡标题下再加一条分隔线，标题与内容的关系不再"浮着"。
   规则来源：HIG `Materials`（内容层别用 Liquid Glass、效果要克制）+ `Layout`（用对齐/缩进/分隔线表达层级）。
2. **字阶三档**：分组 `.subheadline.weight(.semibold)` + `.secondary`（计数 `.caption` tertiary）→
   账号/面板 `.callout.weight(.semibold)`（host/caption 用 `Palette.metadata`）→ 服务器名保持 `.headline`。
3. **标签不再像按钮**：`OrzMCTag`（描边胶囊）只留给"分类标签"；服务器卡片、额度池、自建详情页的
   版本/玩家/延迟改成 `RemoteMetadataLine`（`caption` + `·` 分隔，可换行）。实心胶囊只留给状态徽章。
4. **图标动作**：`Palette.control`（primary 0.72，≈6:1）替代 `.secondary`；命中区 macOS 22×22 / iOS 32×32；
   指针 hover 画 `subtleFill` 圆角底；`disabled` 自己补 `opacity 0.35`（`.foregroundStyle` 会盖掉系统调暗）。
   **危险色不常驻**：卡片上的删除/强杀图标改中性（与主窗口一致），红色只出现在确认框与就地提示。
5. **折叠控件**：底色 `Palette.controlFill`、选中档 `Palette.selectionNeutral`（不再借用强调色，
   同一屏里绿色只表达状态）；未选中图标 `secondary` 而不是"像禁用"；组头箭头 18×18 命中区 + `.tint(.secondary)`
   （iOS borderless 默认把箭头染成蓝色）；iOS 上模式按钮 34×30。
6. **卡片可点感**：`ServerCard` 在有 `onTap` 时 hover 给一层很轻的底；iOS 紧凑宽度下
   footer（更新时间/停止进度/错误）移到**底部操作栏之前**，不再像在解释那排按钮。
7. **令牌对齐**：`orzMCPanel()` 默认圆角 16 → `OrzMCTheme.Radius.lg`（14）；
   新增 `Palette.control` / `Palette.metadata` / `Palette.selectionNeutral`。

**没做 / 待定**

- **A 方案**（账号/面板降级成子标题行、所有服务器卡片同一层）仍是后续选项：本轮用 B 方案（只去掉内层面板），
  改动小、可回滚。若之后要 A，`RemoteAccountCard` 与两个 `*Section` 是落点。
- 亮色 / 提高对比 / 减弱透明 / VoiceOver 在 **macOS** 上还没人工复核（应用外观是用户设置，本轮没有改成浅色）。
  iOS 浅色已在模拟器上截图检查（分组箭头不再是强调色、卡片操作栏顺序正确）。

**验证**：`check.sh --fast/--build/--ios` 绿；iOS UI 套件 45 通过 / 15 按需跳过。

## 14. 2026-11-08 两个窗口的按钮/图标统一（维护者反馈）

**① 主窗口的实例动作按钮"全是灰的"**

原因：`FormSectionHeader` 自己写了一套图标按钮，把 `.foregroundStyle(Palette.idle)` 写在按钮上；
`.disabled` 只会写进环境，被显式前景色盖掉 → 启动/重启/停止/终止/删除全是一个灰，看不出能不能点。
服务器窗口后来补了 hover / 大命中区 / disabled 透明度，于是两边**同一件事两种观感**。

现在收进设计系统（`Sources/OrzMCDesignSystem/ActionButton.swift`）：

| 规则 | 值 |
|---|---|
| 可用 | `Palette.control`（primary 0.72，深色面板上约 6:1） |
| 不可用 | `opacity 0.35`（`.foregroundStyle` 会盖掉系统调暗，必须自己补） |
| 悬停 | `Palette.subtleFill` 圆角底；按下由 `.borderless` 提供 |
| 命中区 | macOS 22×22 / iOS 32×32（卡片里一排 5 个图标也不能把名字挤没） |
| 对外 | `OrzMCActionButton`（主窗口 + `ServerIconButton` 都走它） |

`FormSectionHeader.iconButton` 改成调用它，并把可用性**作为参数**传进去（不再依赖外部 `.disabled`）；
`Console` 在运行中仍用 `success` 绿色（表达"有实时流"，不是"可用"）。

**② 主窗口目录行的"打开"图标**

`arrow.up.forward.app` 是"在别的 App 里打开"，看起来像"打开链接"；改成 **`folder`**（Finder 语义）。
文案与 `help("Open … in Finder")` 不变。

**③ 服务器窗口页顶：添加在左、折叠/展开在右**

- `topBar`：`添加服务器`（创建类主操作，阅读起点）在左，`全部折叠/展开`（视图模式）在右。
- 空态页的添加入口也改到左上（`.overlay(alignment: .topLeading)`），与列表页同一位置。
- 「全部折叠/展开」控件抽成 `OrzMCDisplayModeControls`（设计系统），**主窗口与服务器窗口共用同一份**：
  容器 `controlFill`、选中档 `selectionNeutral`（不再借用强调色）、未选中图标 `secondary`，
  macOS 30×22 / iOS 34×30；服务器页仍保留 `servers.collapseAll|expandAll` 锚点。

### 14.1 追加（同日二次反馈：图标"还是灰的"、卡片只点文字能跳、刷新转圈没对齐）

1. **图标强度**：`Palette.control` 从 `primary 0.72` 提到 **0.85**（深色面板上实测 180/255 → 216/255），
   disabled 仍是 0.35 —— 启用/禁用一眼能分开。
   另外 `RemoteAccountMenu`（账号/面板卡的刷新·配置·删除）之前把默认 tint 写成了 `Palette.idle`（`secondary`），
   比自建卡片暗一档，正是维护者看到"一直灰色"的那三颗；统一改走 `Palette.control`。
2. **整卡可点**：`ServerCard` 改为 `ZStack`，底下垫一层铺满卡片（含内边距）的透明 `Button`，
   文本与动作按钮在它上面：
   - 点文字 → 内容里的主按钮（保留 `tapIdentifier`，UI 用例照旧）；
   - 点右侧/下方空白 → 垫层按钮（2026-11-08 反馈的"点无内容区域没反应"）；
   - 点动作图标 → 各自的按钮；
   - 垫层对无障碍隐藏（`accessibilityHidden`），避免出现两个同名按钮。
   新增用例 `testSelfHostedCardClickAnywhereOpensDetail`（在名称按钮右边缘 +80pt 处点击应进详情页）。
3. **刷新转圈对齐**：`ProgressView` 之前是 `.controlSize(.mini)` 直接塞在动作组最左边，会把整排图标推歪。
   现在**换成与图标按钮同尺寸的槽位**（`OrzMCActionButton.hitSize`：macOS 22 / iOS 32），
   并且是"替换刷新按钮"而不是加在它左边 —— 刷新中不会产生位移。
   MCSM 实例行的 busy 转圈同样处理。

## 15. 2026-11-08 控制台改成导航页 + 三类卡片交互对齐

维护者反馈三条：

**① exaroton 实例卡不是整卡可点（额度池可以）**

原因：exaroton 行是 `NavigationLink { ... } label: { ServerCard(...) }`，`ServerCard` 根部没有
`contentShape`，命中区只有文字/图标的实际绘制范围；额度池用的是 `RemoteInstanceRow`，它根部有
`.contentShape(Rectangle())`，所以整行可点。
→ `ServerCard` 根上加 `.contentShape(Rectangle())`：`NavigationLink` 包整卡时也覆盖整卡
（自建/MCSM 走 `onTap` 的透明垫层不受影响）。新增 `testExarotonCardClickAnywhereOpensDetail`。

**② 服务器卡片的「控制台」改用导航页（与主窗口一致）**

以前 MCSM 实例点开控制台是 **sheet**，主窗口是 **push**（`ServerConsoleView`）——
同一个产品里"打开控制台"两种形态。
→ 删除 `MCSManagerSection` 的 sheet 枚举与 `.sheet`，新增页面路由
`MCSManagerConsoleRoute(panelID:instanceID:)`；`ServersContentView` 用
`.navigationDestination(for:)` 推到 `MCSManagerConsoleView`（原 `MCSManagerConsoleSheet`，
文件名/类型一起改）。标题统一为已有的 **`Console — %@`** 键，iOS `.inline`；
返回按钮/⌘← 回服务器列表（与主窗口一致）。

**③ 账号卡/面板卡的刷新也要"转圈顶替图标"**

自建卡片的刷新是"刷新时图标换成同尺寸转圈"；exaroton 账号卡与 MCSM 面板卡原来是"标题旁边多一个小转圈"。
→ `RemoteAccountMenu` 增加 `isRefreshing`：刷新中在**同一槽位**（`OrzMCActionButton.hitSize`）
换成转圈，不产生位移；移除 `RemoteAccountHeader` 里旧的 `isLoading` 小转圈（避免两个指示重复）。

> 全应用的刷新入口、进行中/禁用状态与自动刷新节律，见
> [`ui-refresh-inventory-2026-11-08.md`](ui-refresh-inventory-2026-11-08.md)（含 5 种交互模式与不一致清单）。
