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
│ ConsoleTextParser             │  ANSI SGR / § 解析、控制字符丢弃、\r 覆盖、多行拆分
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
* **渲染只有一份**：`ConsoleLineText`，三处控制台都指向它。
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
| 其它 CSI（清行/光标）、OSC（标题/超链接）、两字节 ESC | **丢弃**（只影响终端，不该出现在文本里） |
| `§0–§f` | Minecraft 颜色（映射到标准 RGB） |
| `§l` / `§r` | 加粗 / 重置；`§k §m §n §o`（随机/删除线/下划线/斜体）只吃掉码 |
| `\r`（单行内） | 后写覆盖前面的：`10%\r50%\r100%` → `100%` |
| `\r\n` | 一个换行 |
| 其余 C0 控制字符 | 丢弃（**保留 `\t`**：缩进有意义） |
| 被截断的序列（`ESC` 结尾、`ESC [` 结尾、行尾 `§`） | 丢掉控制符，保留可见文本 |

实现细节：全部按 **Unicode 标量**遍历。Swift 把 `"\r\n"` 当作**一个** `Character`，
按字符比较会漏掉这个换行（第一版就是这么错的，被 `testCRLFIsOneLineBreak` 挡住）。

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
| 自建服务器 | `ScrollViewReader` + 新增行时 `scrollTo(last)`（行数少、需要按 id 定位） |
| macOS 本地服务端 | `ConsoleFollowState`（暂停/未读/搜索）+ `ConsoleScrollObserver` |

`ConsoleFollowState` 已经是一个可单测的纯值类型（`Tests/OrzMCLauncherTests`），
真要合并时**把它下沉到 `OrzMCFoundation`** 即可，视图不必再重写一遍滚动逻辑。

## 上限

`ServerConsoleBuffer.defaultCapacity` 与 `RemoteConsoleBuffer.defaultCapacity` 都是 **2000 行**
（自建服务器 RCON 控制台另有 400 行上限：一页最多看这么多，省内存）。
上限只出现在缓冲区里，视图不做裁剪。

## 验收

```bash
# 纯逻辑（20 例）
swift test --filter ConsoleTextTests

# 三处缓冲区的拆分/颜色（RemoteConsoleBuffer 4 例 + ServerConsoleBuffer 9 例）
swift test --filter RemoteConsoleBufferTests
swift test --filter ServerConsoleBufferTests

# 端到端：iOS 模拟器里看 exaroton 控制台（假 live 会塞带 ANSI/§ 的样本行）
cd swift/app && ./scripts/dev/run-ios-ui-tests.sh
#   → testConsoleRendersANSIColorsWithoutEscapeResidue
```

人眼再看一次真机：`ORZMC_DEMO_FAKE_LIVE=1` 的样本行应显示红（ERROR）/黄（WARN 前缀与 `§e`）/绿（INFO），
且界面上不能出现 `\u{1B}` 或 `§`。
