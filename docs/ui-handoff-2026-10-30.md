# UI 优化 + 验收：Codex 交接文档（2026-10-30）

> **状态**：待接手（本轮**未开工**，一切从 §4 的 P0 开始）｜**最后更新**：2026-10-30
> **交接对象**：Codex（或下一个接手的 agent）
> **工作目录**：`/Users/joker/Documents/OrzMC/swift/app`（父仓库 `/Users/joker/Documents/OrzMC` 的子模块）
> **配套文档**：
> [`app-ui-design.md`](app-ui-design.md)（设计系统 + **字段/行布局约定，动手前必读**）、
> [`app-platform-split.md`](app-platform-split.md)（代码放哪）、
> [`iteration-flow.md`](iteration-flow.md)（门禁与截图巡检流程）、
> [`console-acceptance.md`](console-acceptance.md)（控制台怎么验收）。

---

## 0. 一句话状态

B1（控制台实时流）+ B2（强杀 / 停止进度）已于 2026-10-28 合入 `main` 但**未发版**（0.1.6 仍是已发布版本）；
本轮不做功能开发，只做 **UI 观感打磨 + 验收链路收尾**：先修掉"真机必失败"的那条 UI 用例（P0），
再按截图取证逐项打磨 iOS 小屏观感，最终交付一条**真机全绿**的 UI 用例集 + 维护者可复现的验收记录。

---

## 1. 环境事实（2026-10-30 实测，别再猜）

| 项 | 值 |
|---|---|
| 父仓库 | `/Users/joker/Documents/OrzMC`（`main`，工作区干净） |
| 子模块 | `swift/app`（`OrzMC/OrzMCApp`），`main` @ `24f803e3`，**与远端一致、工作区干净** |
| 已发布版本 | **0.1.6 (58)**；`OrzMC/Configuration/Config.xcconfig` 仍是 `0.1.6 / 58`（0.1.7 未发，本轮不动版本号） |
| 工具链 | Xcode 27.0 (27A266a) / macOS 27.0.1 / `SWIFT_VERSION=6.0`、`SWIFT_STRICT_CONCURRENCY=Complete` |
| 依赖 pin | `OrzMC.xcodeproj/.../Package.resolved`：`mcsmanagerapi 0.5.0`、`exarotonapi 0.0.10`、`sparkle 2.10.0`；`orzmckit` / `orzswiftkit` / `mojangapi` / `papermc` 走分支（版本字段为空） |
| 模拟器 | `OrzMC-UI` = `571ACD8A-64EB-4427-B803-D41836EB2B9F`（iPhone SE 3rd gen，默认目标）；另有 `iPhone 17 Pro` 等大屏对照 |
| 真机 | iPhone SE3 `00008110-0001712226A0401E`（**当前未连接**；XCUITest 必须插数据线） |
| AI 的能力边界 | **iOS 侧能自己"看"界面**（XCUITest 截图 → `xcresult` 导出 → 直接读图）；**macOS 侧不能**（无屏幕录制权限）→ macOS 观感只能由维护人眼验收 |

> ⚠️ 不要在父仓库用 `git add -A` / `git add .`（会误暂存 22 个子模块指针）。
> 多行提交信息写进文件后 `git commit -F <file>`（`-m` 里的反引号会被 shell 吃掉）。

---

## 2. 本轮三句话（开工前先复述，做完对照）

1. **做什么** — 让远程托管（Exaroton + MCSManager）在 **iPhone SE 小屏**上"第一眼看懂、别扭的地方不再别扭"，
   并让 UI 自动化在**真机**上可信（不再有"必失败"的用例）。
2. **怎么做** — 先截图取证（不许凭想象改 UI）→ 按 §4 优先级逐项改 → 每项**前后截图对比** → 跑门禁。
3. **怎么验收** — `check.sh` 全档绿 + 模拟器 UI 用例绿 + **真机 UI 用例连跑 3 次绿** + 维护者按 §6.4 复跑一遍。

---

## 3. 已经做完的（不要重做、不要回退）

| 主题 | 落在哪 | 别再动 |
|---|---|---|
| 状态徽章唯一实现 | `Sources/OrzMCDesignSystem/StatusBadge.swift`（旋转靠 `TimelineView` 时间驱动） | 不要改回 `@State` + `repeatForever` |
| 远程状态单一写入口 | `Sources/OrzMCRemoteHosting/RemoteStatusCenter.swift`（键是 `RemoteInstanceID`） | 不要退回裸字符串 id，不要改"WS 安静 30 秒"轮询判据 |
| 多供应商分组 | `OrzMC/Common/ExarotonUI/List/ExarotonServerList.swift`（exaroton 段）+ `OrzMC/Common/MCSManagerUI/MCSManagerSection.swift`（MCSM 段） | **维护者已拍板：按供应商分组、不做 provider 过滤/分段控件** |
| MCSM 停止进度 + 强杀 | `MCSManagerSection.stopHint(...)` + `Sources/OrzMCRemoteHosting/RemoteStopProgress.swift` | 秒数必须每秒刷新；强杀必须二次确认 |
| 控制台渲染统一 | 解析 `Sources/OrzMCFoundation/ConsoleText.swift`、渲染 `Sources/OrzMCDesignSystem/ConsoleText.swift` | 规则见 `console-rendering.md` |
| 空/加载/失败态区分 | `ExarotonServerList` 的 `emptyCard` / `loadingCard` / `errorCard` + `Sources/OrzMCDesignSystem/ContentState.swift` | 不要再把三种态合并成一段文案 |

---

## 4. 候选任务（按优先级；每项都要"先取证再改"）

> 优先级口径：**P0 = 阻塞验收**（用例不可信）｜**P1 = 用户一眼能看出别扭**｜**P2 = 打磨/一致性**。
> 未标"需拍板"的可以直接做；标了"需拍板"的，先给维护者看截图 + 一句话方案再动手。

### UI-1（P0）真机上"必失败"的动画用例：换掉不稳定的判据

- **现象**：`OrzMCUITests/RemotePanelsUITests.swift:528` `testStatusBadgeKeepsSpinningAfterReentering`
  在 iPhone SE3 / iOS 27.0.1 **必失败**；模拟器绿；`app main` 上同样失败 → 与本轮功能无关，是**用例判据**的问题。
- **现在的判据**：截两次徽章区域（间隔 0.4s）比像素集合，靠"像素有变化"判定在转。
- **先做的事**：跑一次并把 `xcresult` 附件导出来看（§6.3），确认是真机截帧重复、还是裁剪区域算错
  （`badgeIsSpinning(around:)` 用文案锚点算区域，真机上 `frame` 可能是 0 或含状态栏）。
- **可接受的方向**（按顺序试，选**最小改动**）：
  1. 裁剪区域改为"从徽章文案元素 `frame` 内缩"并排除背景/文字本身；
  2. 采 3 帧，只要**有一对**差异超阈值即通过（真机偶发截到同一帧）；
  3. 判据从"差异像素个数"改成"差异像素占比 > x%"，并对截图降采样以抵抗抗锯齿差异。
- **红线**：**不许 `XCTSkip`、不许删断言、不许把动画改成常驻静态图**。
  如果三条都不奏效，停下来跟维护者确认是否允许加一个 **DEBUG-only** 的可访问性计数（`TimelineView` 每跳一次 +1），
  这是"判据换实现"，要维护者点头。
- **验收**：真机连跑 3 次全绿；模拟器绿；`git diff` 只碰用例（不改产品代码）。

### UI-2（P1）iPhone SE 小屏：远程托管页的信息层级

- **现象**：远程托管页从上到下是 `summaryCard` → exaroton 服务器/额度池 → 最后才是 MCSM 分组，
  SE3 上 MCSM 组在首屏折叠线以下（已知事实，见 `HANDOFF.md` §0.1）；无 exaroton token 时页面上是
  `emptyCard` + MCSM 两块空态叠在一起，容易让人以为"只能连 exaroton"。
- **取证**：用 `ORZMC_DEMO_MCSM_FAKE=1` + `ORZMC_DEMO_TAB=managed` 跑 §6.3 的截图流程，
  再补一张"完全没有账号"的（不加任何 DEMO 变量）。
- **可动的范围**：段落的**顺序 / 折叠 / 空态合并 / 摘要卡文案**，以及"未配置任何供应商时给一个两选一的引导"。
- **不可动**：不做 provider 过滤或顶部 Segmented（已拍板）；不改模型层（`ExarotonServerModel` / `MCSManagerModel`）。
- **验收**：改前/改后截图（375pt 宽）放 PR 描述；现有 UI 用例全绿；维护者认"第一眼能看懂有两家供应商"。

### UI-3（P1）Exaroton 停止也有"等了多久"（与 MCSM 对齐）

- **现状不对称**：MCSM 停止中显示 `Stopping… 12s`，久等变红并给强杀入口（`MCSManagerSection.stopHint`）；
  exaroton 只有一个 `feedback` 行（`ExarotonServerActionSection.feedback`），没有秒数、没有久等提示。
- **要做**：exaroton 侧复用 `RemoteStopProgress`（`Sources/OrzMCRemoteHosting/RemoteStopProgress.swift`）
  显示 `Stopping… Ns` + 久等文案；`TimelineView(.periodic(by: 1))` 只重绘那一行。
- **红线**：exaroton **没有 kill**（平台托管），**不要加强杀按钮**；`ExarotonHostingProvider` 对 `.kill`
  的 `actionNotSupported` 也不要改成静默降级。
- **验收**：`swift test --filter RemoteStopProgress` 绿；模拟器截图（`ORZMC_DEMO_FAKE_SERVER=1` +
  `ORZMC_DEMO_FAKE_STATUS=stopping`）；真机看一眼秒数在动。

### UI-4（P1）大字号 / 窄屏下的挤压

- **风险点**：MCSM 实例行（昵称 + 地址 + `3/20` + 徽章 + 进度 + `⋯`）在 `Dynamic Type = xxxLarge` 或
  375pt 宽下会挤压；`stopHint` 的红字长句（"Still stopping after 60s — it may be stuck."）折行后难读。
- **做法**：模拟器切 Accessibility 大字号截图取证；能靠 `ViewThatFits` / `.lineLimit` / 换行位置解决的，
  按 `app-ui-design.md` 的约定改（不要手写 `HStack` 拼表单行）。
- **验收**：大字号截图里**不重叠、不截断关键数字**；默认字号下视觉零变化。

### UI-5（P2）设计系统收敛（视觉零差异）

- 把 `OrzMC/Common/**` 里新代码中写死的 `padding(12)` / `cornerRadius(10)` / 颜色字面量收敛到
  `OrzMCTheme.Spacing|Radius|Palette`；新代码里**不再出现**裸数值（老代码不强求一次改完）。
- **验收**：改前/改后截图对比**应完全一致**；`check.sh --fast` 绿。

### UI-6（P2）截图巡检发现项（先列表，不许直接改产品行为）

- 跑完 §6.3 的截图巡检后，把"看着别扭但不确定该怎么改"的点整理成一张表（位置 / 现象 / 两个候选方案）
  交给维护者挑。**这一项不算完成度，只是交材料。**

---

## 5. 红线（破坏任何一条，改动会被打回）

1. **代码分层**：`Sources/*` 里不许出现 AppKit/UIKit（`scripts/check-platform-split.sh` 会挂）；
   平台差异写进 `OrzMC/` 下的 `#if os(iOS)` / `#else` 或靠 pbxproj `platformFilter`。
2. **本地化**：改 `OrzMC/Common/Localizable.xcstrings` 后必须过 `scripts/dev/check-localization.py`
   （它检查占位符**数量与顺序**一致；写反会让 `String(localized:)` 崩）。新增文案给 `comment:`。
3. **可访问性标识**：**不要**在 SwiftUI 容器（`VStack`/`Section`/卡片）上设 `accessibilityIdentifier` ——
   SwiftUI 会把它下发给子元素并覆盖子元素自己的 identifier（踩过：徽章查不到）。
4. **单一实现**：状态徽章只走 `OrzMCStatusBadge`；控制台解析/渲染不新写一套；停止进度只走 `RemoteStopProgress`。
5. **动画**：秒级刷新用 `TimelineView`（不要 `Timer` + `@State` 驱动整列表）；
   尊重 `@Environment(\.accessibilityReduceMotion)`（已有示例：`ServerConsoleView:219`、`GameList:31`）。
6. **不加破坏性副作用**：UI 用例里**不点**能改变真实服务器状态的按钮（`testStartServerThenConsoleStreams` 这类
   默认 skip / 显式环境变量开启，别改默认值）；exaroton 相关用例**别消耗额度**。
7. **提交**：分支 `feat/ui-polish-<主题>` 或 `fix/ui-test-<主题>`；Conventional Commits + 中文；
   显式 `git add <路径>`；PR 到 `main`，CI 全绿再 squash 合并。

---

## 6. 验收协议（照抄执行）

### 6.1 门禁

```bash
cd /Users/joker/Documents/OrzMC/swift/app
./scripts/dev/check.sh --fast      # 秒级：平台分层 / pbxproj 登记 / 本地化一致性 / 状态源守卫 / 密钥扫描
./scripts/dev/check.sh             # 2~4 min：静态 + 包单测 + 应用测试 + macOS 构建（改 UI 必跑）
./scripts/dev/check.sh --changed   # 按改动范围选档（纯文档/纯测试不跑完整档）
./scripts/dev/check.sh --ui        # iOS UI 自动化（默认 SE3 尺寸模拟器，1~2 min）
./scripts/dev/check.sh --full      # 发版前才需要（含 iOS 构建 + 真 socket 联调）
```

单个用例复跑（省时间）：`UI_ONLY_TESTING=OrzMCUITests/RemotePanelsUITests/testFoo ./scripts/dev/check.sh --ui`

### 6.2 真机（必须插数据线）

```bash
./scripts/dev/run-ios-ui-tests.sh --device 00008110-0001712226A0401E --detach
```

- `--detach` 会把活丢进 Terminal.app 并在这里等结果（真机签名要访问钥匙串，SSH/agent 会话拿不到）。
- 失败时先看末尾日志里的 `error:`；`DTX 握手被拒` / `exit 74` = 没插线或设备锁屏/没开自动化模式。
- 装包给人眼看：`./scripts/dev/install-ios-device.sh`（默认 Debug 构建 + 安装 + 启动）。

### 6.3 截图巡检（**这是"看得见界面"的唯一正当渠道**）

```bash
# ① 先让脚本把 xctestrun 准备好（构建 + 自动 patch）
UI_ONLY_TESTING=OrzMCUITests/RemotePanelsUITests/testSnapshotTour ./scripts/dev/run-ios-ui-tests.sh

# ② 再手动跑一次，把 resultBundle 落到固定位置
TEST_RUNNER_ORZMC_UITEST_SNAPSHOTS=1 xcodebuild test-without-building \
  -xctestrun "$(ls -t ~/Library/Developer/Xcode/DerivedData/OrzMC-local-ios/Build/Products/*_iphonesimulator*.xctestrun | head -1)" \
  -destination 'platform=iOS Simulator,id=571ACD8A-64EB-4427-B803-D41836EB2B9F' \
  -only-testing:OrzMCUITests/RemotePanelsUITests/testSnapshotTour \
  -only-testing:OrzMCUITests/RemotePanelsUITests/testSnapshotTourRemote \
  -resultBundlePath /tmp/rb.xcresult

# ③ 导出附件（截图带名字，如 01-selfhosted-top）
xcrun xcresulttool export attachments --path /tmp/rb.xcresult --output-path /tmp/snaps
```

现有巡检覆盖：自建页顶部/三个名单页签/控制台空态与回复/设置上下/添加服务器/远程列表/远程详情三段。
**MCSM 分组还没有巡检用例** —— 加一条 `testSnapshotTourMCSM`（`ORZMC_DEMO_MCSM_FAKE=1`）是 UI-2 的取证前提。

### 6.4 维护者验收（最终)

```bash
./scripts/dev/install-dev-app.sh --accept     # macOS：装开发包到 /Applications + 无界面自检（10~20s）
./scripts/dev/install-ios-device.sh           # iOS：装到 SE3，人眼过一遍远程托管页
```

**别为了验收去跑公证/发版**（`scripts/release.sh` 不在本轮范围）。

---

## 7. 交付物

1. 一个 PR（或按主题拆 2 个）：UI-1 单独一个（纯测试）+ UI-2~UI-5 合一个；
2. PR 描述里：**每项都有改前/改后截图** + 一句"为什么这么改"；
3. 更新本文档的 §4（完成项打 ✅ 并写实测数字）+ 必要时更新 `docs/app-ui-design.md`
   （只在新旧约定不一致时改）；
4. 合入后回父仓库 bump `swift/app` 指针（`chore(submodule): bump swift/app ...`，单独一次提交）；
5. 更新父仓库 `HANDOFF.md` §5 会话日志（一条即可）。

---

## 8. 什么时候停下来问维护者（不要自己拍）

- UI-2 要把 MCSM 段提到 exaroton 段**之前**（涉及产品口径，不只是观感）；
- UI-1 三条判据方案都不奏效、需要加 DEBUG-only 可访问性计数；
- 任何需要"改产品行为/模型层/发版"的念头；
- 任何需要消耗 exaroton 额度或动真实服务器（面板 `/kill` 真的会杀实例）的操作。

---

## 9. 给 Codex 的提示词（可整体复制给下一个会话）

```text
你在 OrzMC 父仓库（/Users/joker/Documents/OrzMC）的子模块 swift/app（OrzMCApp）里工作。

先读三份文件，再动手：
1. swift/app/docs/ui-handoff-2026-10-30.md（本轮任务的单一事实源：环境、任务、红线、验收命令）
2. swift/app/docs/app-ui-design.md（设计系统 + 字段/行布局约定）
3. 父仓库 HANDOFF.md §0.1（环境事实与已知坑）

本轮目标：UI 观感打磨 + 验收链路收尾（不做功能开发、不发版）。顺序：
P0 UI-1 修掉真机上必失败用例 testStatusBadgeKeepsSpinningAfterReentering（只改用例判据，不许 skip）；
P1 UI-2 iPhone SE 小屏远程托管页信息层级（先截图取证；按供应商分组是拍板口径，不许改成过滤器）；
P1 UI-3 exaroton 停止也显示"Stopping… Ns"（复用 RemoteStopProgress；exaroton 没有 kill，不许加强杀）；
P1 UI-4 大字号/窄屏挤压；P2 UI-5 设计令牌收敛（视觉零差异）。

工作方式：
- 先跑 ./scripts/dev/check.sh --fast 确认基线干净；
- 每次改 UI 前先按 §6.3 导出截图，改完再导一次，PR 里放前后对比；
- 每项改完跑 ./scripts/dev/check.sh（改 UI 必跑全档）+ ./scripts/dev/check.sh --ui；
- 真机验证 ./scripts/dev/run-ios-ui-tests.sh --device 00008110-0001712226A0401E --detach（必须插线）；
- 严格守 §5 红线（本地化校验、不在容器上设 accessibilityIdentifier、状态徽章/控制台/停止进度各自唯一实现、
  不点会改真实服务器状态的按钮）。

交付：分支 + PR 到 main，CI 全绿；PR 描述含每项前后截图；合入后回父仓库 bump swift/app 指针
（显式 git add swift/app，不用 git add -A），并更新父仓库 HANDOFF.md §5。

遇到 §8 列的情形（要把 MCSM 段提前、要加 DEBUG-only 计数、要改模型/发版、要动真实服务器）先停下来问维护者。
```

---

## 10. 相关文件速查

| 你要改的东西 | 文件 |
|---|---|
| iOS 两个 Tab 入口 | `OrzMC/MobileHelper(iOS)/App/Views/ContentView.swift` |
| 远程托管页（exaroton 段 + MCSM 段挂载点） | `OrzMC/Common/ExarotonUI/List/ExarotonServerList.swift` |
| 远程详情 / 动作区 / 内存区 | `OrzMC/Common/ExarotonUI/List/ExarotonServerDetail.swift`、`List/Components/ExarotonServerActionSection.swift`、`List/Components/ExarotonMemorySection.swift` |
| MCSM 分组 / 停止进度 / 强杀确认 | `OrzMC/Common/MCSManagerUI/MCSManagerSection.swift` |
| MCSM 控制台面板 / 面板编辑器 | `OrzMC/Common/MCSManagerUI/MCSManagerConsoleSheet.swift`、`MCSManagerPanelEditor.swift` |
| 设计令牌 / 徽章 / 面板 / 内容态 | `Sources/OrzMCDesignSystem/{OrzMCTheme,StatusBadge,PanelStyle,ContentState,FieldRowStyle}.swift` |
| 停止进度判定 | `Sources/OrzMCRemoteHosting/RemoteStopProgress.swift`（判定）+ `OrzMC/Common/MCSManager/MCSManagerModel.swift`（计时） |
| UI 用例 / 截图巡检 | `OrzMCUITests/RemotePanelsUITests.swift` |
| 文案 | `OrzMC/Common/Localizable.xcstrings`（改完跑 `scripts/dev/check-localization.py`） |
