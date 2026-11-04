# 控制台文本渲染（ANSI / Minecraft 颜色）

> **状态**：生效中（2026-10-25，P2-6）｜**实现**：`Sources/OrzMCFoundation/ConsoleText.swift`
> + `Sources/OrzMCDesignSystem/ConsoleText.swift`｜**验收**：`Tests/OrzMCFoundationTests/ConsoleTextTests.swift`
> + UI 用例 `testConsoleRendersANSIColorsWithoutEscapeResidue`

## 问题

三处控制台原来各写一套：

| 位置 | 以前的做法 |
|---|---|
| macOS 本地服务端（`ServerConsoleView`） | `ServerConsoleBuffer` 里正则式地**剥掉** ANSI，颜色全丢 |
| 自建服务器 RCON（`SelfHostedServerView`） | 不处理：`\u{1B}[32m`、`§`、`\r` 原样显示（"很脏"） |
| exaroton（`ExarotonServerDetail`） | 不处理，`Text(verbatim:)` 直接显示原始输出 |

结果就是：要么看到 `\u{1B}[32m` 这类控制字符，要么本来有颜色的 INFO/WARN/ERROR 全灰。

## 分层

```
┌───────────────────────────────┐
│ OrzMCFoundation               │  纯逻辑：文本 → 分段 + 样式（无 UI、可 CLI 复用、可单测）
│ ConsoleTextParser             │  ANSI SGR / § 解析、行内重绘（退格 + 光标移动）、\r 覆盖、多行拆分
│ ConsoleTextSegment/ConsoleColor│
└───────────────┬───────────────┘
                │
┌───────────────▼───────────────┐
│ OrzMCDesignSystem             │  颜色映射 + SwiftUI 渲染（不引入 WebView）
│ ConsolePalette / ConsoleLineText│
└───────────────┬───────────────┘
                │
   ┌────────────┴─────────────┬──────────────────────┐
   ▼                          ▼                      ▼
macOS 本地服务端            自建服务器 RCON          exaroton
ServerConsoleBuffer         SelfHostedServersModel  RemoteConsoleBuffer
（ConsoleLine.segments）    （ConsoleLine.segments） （Line.segments）
```

* **解析在底层**：不依赖 SwiftUI，`swift test` 就能覆盖；将来 CLI / 别的端要显示日志可以直接用。
* **渲染只有一份**：`ConsoleLineText`，本地、自建、exaroton 和 MCSManager 控制台都指向它。
* **惰性行布局共用**：四处均经 `OrzMCConsoleRows` 使用 `OrzSwiftKit` 的 `ConsoleUI.ConsoleRows`；
  滚动容器、空态、间距和业务操作仍由各场景配置。
* **缓冲区只做分块**：`ServerConsoleBuffer` 负责"半行/多行/上限"，`RemoteConsoleBuffer` 负责
  "一条 WS 消息可能是多行"，颜色不再在缓冲区里被剥掉。

## 解析规则（`ConsoleTextParser`）

| 输入 | 处理 |
|---|---|
| `ESC [ 0 m` / `ESC [ m` | 重置颜色与加粗 |
| `ESC [ 1 m` / `ESC [ 22 m` | 加粗 / 取消加粗 |
| `ESC [ 30–37 m`、`ESC [ 90–97 m` | 前景色（16 色） |
| `ESC [ 39 m` | 恢复默认前景色 |
| `ESC [ 38;5;n m` | 256 色（16 基础 + 6×6×6 立方 + 24 灰阶） |
| `ESC [ 38;2;r;g;b m` | 真彩色 |
| `ESC [ 48… m` | **背景色**：吃掉参数、不渲染（控制台底色由主题统一） |
| `\b` | 光标回退一个标量，后写字符覆盖对应位置；行首退格不产生负位置 |
| `ESC [ n D`（CUB）/ `ESC [ n C`（CUF）/ `ESC [ n G`（CHA） | 光标左移 / 右移 / 移到第 n 列；右移越过行尾的位置用空格补齐。缺省或 `0` 按 1 算 |
| `ESC [ K` / `ESC [ 0 K` / `ESC [ 1 K` / `ESC [ 2 K` | 清除光标之后、之前或整行，保留光标位置 |
| 其它 CSI、OSC（标题/超链接）、两字节 ESC | **丢弃**（未实现完整终端光标定位） |
| `§0–§f` | Minecraft 颜色（映射到标准 RGB） |
| `§l` / `§r` | 加粗 / 重置；`§k §m §n §o`（随机/删除线/下划线/斜体）只吃掉码 |
| `\r`（单行内） | 后写覆盖前面的：`10%\r50%\r100%` → `100%` |
| `\r\n` | 一个换行 |
| 其余 C0 控制字符 | 丢弃（**保留 `\t`**：缩进有意义） |
| 被截断的序列（`ESC` 结尾、`ESC [` 结尾、行尾 `§`） | 丢掉控制符，保留可见文本 |

实现细节：全部按 **Unicode 标量**遍历。Swift 把 `"\r\n"` 当作**一个** `Character`，
按字符比较会漏掉这个换行（第一版就是这么错的，被 `testCRLFIsOneLineBreak` 挡住）。
这不是完整终端模拟器：退格与水平光标移动按标量处理，复杂字形和双宽字符的光标列宽仍有局限；
上下移（`ESC [ A/B`）、绝对定位（`ESC [ H`）与擦除显示区（`ESC [ J`）仍直接丢弃（单行渲染器没有行模型）。

### 2026-11-05：`> versioversion` / `> pluginplugins`（CSI 光标左移被丢掉）

面板的 `outputlog` 是 **PTY 原文字节**，JLine 的逐字回显会夹杂两种重绘：

```text
> \u{1B}[31ml\u{1B}[0m\u{1B}[31mi\u{1B}[0m\u{1B}[31ms\u{1B}[0m\b\b\blist\u{1B}[K          ← 只用退格
> v\b\u{1B}[31mve\u{1B}[0m\u{1B}[K…\u{1B}[31mo\u{1B}[0m\u{1B}[6Dversion\u{1B}[K   ← 退格 + CSI 左移 6 列
```

早期只实现了 `\b`，把 `ESC [ 6 D` 当"未知 CSI"丢掉 → 光标没回去、整行 append 在行尾 →
`> versioversion`（红）：同一个坑之前只在退格形态上修过，所以 `lislist` 好了、`versioversion` 还在。
现在 `D` / `C` / `G` 都按 ECMA-48 处理，回归用例直接用面板的原始字节
（`ConsoleTextTests.testRealRedrawWithCsiCursorLeftForVersion/ForPlugins`、
`testRealRedrawWithExtendedCommandLine`），模拟器 UI 用例 `testMCSManagerConsoleSheetShowsOutput`
也同时校验两种形态；前后对比截图见 [`ui-console-redraw-2026-11-05/`](ui-console-redraw-2026-11-05/)。

复现/取证工具（仅 DEBUG）：`ORZMC_DEMO_MCSM_DIAGNOSE=1` + `ORZMC_DEMO_MCSM_RAW_LOG=1`
会把每台实例的 `outputlog` 原文字节（转义成 `\u{1B}` / `\b` / `\r`）写到
`~/Library/Caches/orzmc-mcsm-raw-<daemon>_<uuid>.txt`，**只拉日志、不发命令**。

## 颜色映射（`ConsolePalette`）

控制台面板底色是 `.primary` 的 6%：浅色模式接近白、深色模式接近黑。所以：

- **黑 / 白 / 亮黑 / 亮白**按 `ColorScheme` 取"对比色"（`§0` 在深色模式下不会看不见，`§f` 在浅色模式下不会白成一片）；
- **命名色**（红绿黄蓝紫青）用中等明度的固定色，两种模式都能读；ANSI 黄压成琥珀色（浅底上纯黄几乎不可读，WARN 行全靠它）；
- **真彩色**按亮度温和调整：浅色模式压暗亮度 >72% 的颜色，深色模式提亮 <16% 的颜色，**保留色相**。

## 跟随底部（为什么没合并）

三处控制台的行来源不同，滚动策略也略有差别，暂时保留各自实现，但规则统一为"跟随最新一行"：

| 控制台 | 做法 |
|---|---|
| exaroton | `ScrollView` + `.defaultScrollAnchor(.bottom)`（日志只会往后追加） |
| MCSManager | `ScrollView` + `.defaultScrollAnchor(.bottom)`；实时增量与轮询快照共用文本缓冲 |
| 自建服务器 | `ScrollViewReader` + 新增行时 `scrollTo(last)`（行数少、需要按 id 定位） |
| macOS 本地服务端 | `ConsoleFollowState`（暂停/未读/搜索）+ `ConsoleScrollObserver` |

`ConsoleFollowState` 已迁至 `OrzSwiftKit` 的 `ConsoleCore`，应用通过兼容类型别名引用同一实现。
目前只有本地控制台使用该跟随状态机；远程控制台仍保留各自的滚动行为，避免迁移时改变交互。

## 上限

`ServerConsoleBuffer.defaultCapacity` 与 `RemoteConsoleBuffer.defaultCapacity` 都是 **2000 行**
（自建服务器 RCON 控制台另有 400 行上限：一页最多看这么多，省内存）。
上限只出现在缓冲区里，视图不做裁剪。

MCSManager 的实时输出由 `OrzMCRemoteHosting.ConsoleLineBuffer` 增量拆行，
沿用 `ConsoleTextParser` 的回车及换行语义；保留行的 ID 在追加与整行裁剪时保持稳定。
其原始文本仍由 `ConsoleTextBuffer` 以默认 256 KiB 上限管理，超限按 UTF-8 字节及完整字符边界裁剪。
轮询快照是整段替换，因此会重建行。该缓冲依赖 Minecraft 文本语义，保留在应用层；
通用行容器和跟随状态仍在 `OrzSwiftKit`，不把供应商或格式细节放进公共 UI 基础库。

## 验收

```bash
# 纯逻辑（20 例）
swift test --filter ConsoleTextTests

# 三处缓冲区的拆分/颜色（RemoteConsoleBuffer 4 例 + ServerConsoleBuffer 9 例）
swift test --filter RemoteConsoleBufferTests
swift test --filter ServerConsoleBufferTests
swift test --filter ConsoleLineBufferTests

# 端到端：iOS 模拟器里看 exaroton 控制台（假 live 会塞带 ANSI/§ 的样本行）
cd swift/app && ./scripts/dev/run-ios-ui-tests.sh
#   → testConsoleRendersANSIColorsWithoutEscapeResidue
```

人眼再看一次真机：`ORZMC_DEMO_FAKE_LIVE=1` 的样本行应显示红（ERROR）/黄（WARN 前缀与 `§e`）/绿（INFO），
且界面上不能出现 `\u{1B}` 或 `§`。
