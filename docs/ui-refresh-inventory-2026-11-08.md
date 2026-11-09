# 刷新按钮清单与交互状态（2026-11-08）

> **状态**：改前快照（2026-11-08 当日已按本文件建议 1–5 收口，见
> [`app-ui-design.md`](app-ui-design.md) §16）｜**最后更新**：2026-11-08
> **范围**：macOS 主窗口 + 「服务器」辅助窗口 + iOS 同一套页面；只统计**用户能点的刷新/重载**，
> 以及对应的自动刷新节律。重试（Retry）/重连（Reconnect）单列，避免和刷新混淆。
> **口径**：`进行中反馈` 指按钮自身或紧邻位置给出的状态；`禁用` 指按钮的 disabled 条件。

---

## 1. 有按钮的刷新入口

### 1.1 服务器窗口 / iOS 首页（`ServersContentView`，一个列表）

| # | 位置 | 刷新什么 | 进行中反馈 | 禁用条件 | 锚点 |
|---|---|---|---|---|---|
| 1 | **自建卡片**右上「刷新」（`SelfHostedServerCard.actions`） | 这一台的 SLP 状态（`refreshStatus(for:)`） | **图标换成同尺寸转圈**（macOS 22 / iOS 32，无位移） | 未配置时 `isEnabled=false`（0.35） | `selfHosted.action.refresh` |
| 2 | **exaroton 账号卡**右上「刷新」（`RemoteAccountMenu`） | 该账号的实例/额度池（`reloadList()`） | 同上（图标→转圈） | **无**（模型内部 `isLoadingList` 防重入） | **无**（`identifier: nil`） |
| 3 | **MCSM 面板卡**右上「刷新」（`RemoteAccountMenu`） | 该面板的实例与状态（`reload()`） | 同上（图标→转圈） | **无**（模型内部 `isLoading` 防重入） | `mcsm.panelAction.refresh` |
| 4 | iOS 合并页**下拉刷新** | **只刷新自建**（`selfHosted.refreshAllStatuses()`） | 系统下拉指示 | 无自建服务器时无效 | — |

> 三张卡片（自建 / exaroton 账号 / MCSM 面板）的刷新交互刚刚统一（图标→转圈）；
> 但**下拉刷新只覆盖自建**（#4），exaroton/MCSM 不参与。

### 1.2 自建服务器详情页（`SelfHostedServerDetailView`）

| # | 位置 | 刷新什么 | 进行中反馈 | 禁用条件 | 锚点 |
|---|---|---|---|---|---|
| 5 | 工具栏「刷新」 | SLP 状态 + RCON 玩家名单 | **状态卡内部** 16×16 转圈（opacity 切换，按钮本身不变） | 未配置 / 正在探测 | `selfHosted.refresh` |
| 6 | 玩家卡标题行「刷新」 | RCON `list` / `whitelist list` / `banlist` | 按钮**左侧** 16×16 小转圈（opacity） | 正在取名单 / RCON 不可用 | **无** |
| 7 | iOS 下拉刷新 | 状态 + 名单 | 系统下拉指示 | — | — |

### 1.3 远程服务器详情 / 控制台

| # | 位置 | 刷新什么 | 进行中反馈 | 禁用条件 | 锚点 |
|---|---|---|---|---|---|
| 8 | exaroton 额度池详情 · 工具栏「刷新」（**仅 macOS**） | 额度池 / 成员 / 服务器（`fetchDataWithLoading()`） | **整页大转圈遮罩**（按钮本身不变、仍可点） | **无** | **无**；`⌘R` |
| 9 | 额度池 iOS 下拉刷新 | 同上 | 系统下拉指示 | — | — |
| 10 | MCSM 控制台**页**头部「刷新」（`MCSManagerConsoleView`） | **只重拉历史日志**（`reloadHistory()`；实时流不受影响） | **无**（只有按钮禁用） | `isLoading` | **无**（只有 a11y label） |

### 1.4 主窗口 / 设置 / 插件

| # | 位置 | 刷新什么 | 进行中反馈 | 禁用条件 | 锚点 |
|---|---|---|---|---|---|
| 11 | 侧边栏搜索栏「刷新」 | 版本清单（`onReload`） | 转圈 **叠加**在图标上 + 图标变暗 0.45 | `isLoading` | a11y `Refresh version list` |
| 12 | 插件管理 · 工具栏「Check Updates」 | Hangar 更新检查（含首次目录加载） | 工具栏**单独**小转圈（`isLoadingCatalog \|\| isCheckingUpdates`） | 同上 | 无 |
| 13 | 插件管理 · 底部「Refresh」 | **本地**重扫 `plugins/`（同步，瞬时） | 无 | 无 | 无 |
| 14 | 设置 · 命令行「刷新安装记录」 | 重读 `install.conf`（同步） | 无 | 整行 `model.isBusy` | a11y `Refresh command line install record` |
| 15 | 设置 · Java「重新扫描运行时」 | 本地扫描已托管 JDK（同步） | 无 | 无 | a11y `Rescan installed Java runtimes` |

### 1.5 同族但不是"刷新"（别混在一起）

| 位置 | 行为 | 说明 |
|---|---|---|
| exaroton 实例详情 · `Reconnect` | 重连 WebSocket | 断线恢复，不重新拉列表 |
| exaroton 内存区 · `Retry` | 重拉内存（失败后） | 错误恢复入口 |
| exaroton 动作失败 · `Retry` | 重试上一次动作 | 不是读取 |
| MCSM 停止进度 · `Force Stop` | 强杀 | 生命周期动作 |

---

## 2. 自动刷新（没有按钮，但决定"刷新按钮有没有用"）

| 位置 | 节律 | 判据 |
|---|---|---|
| 自建列表（`ServersContentView.task(id:)`） | 30 秒 | 有服务器时循环 |
| 自建详情（`SelfHostedServerDetailView.task(id:)`） | 20 秒 | 页面可见 + 已配置 |
| exaroton 账号 | 心跳 5 秒 | `RemoteStatusRefreshPolicy`：WS 安静 30 秒才走 HTTP；最小间隔 10 秒 |
| MCSM 面板 | 心跳 5 秒 | 同一策略（MCSM 无 WS → 实际按 10 秒最小间隔轮询） |
| MCSM 控制台 | 实时流优先 | 通道不可用 → 3 秒轮询 `outputlog` |
| 额度池详情 | 进入时一次 + 下拉 | 无定时 |

---

## 3. 交互模式分类（当前并存 5 种）

| 模式 | 用在哪 | 问题 |
|---|---|---|
| **A. 图标 → 同尺寸转圈** | #1 #2 #3 | 最新统一，无位移，推荐作为标准 |
| **B. 图标不变 + 旁边/叠加转圈** | #5 #6 #11 | 三处三种做法（状态卡内 16×16 / 按钮左侧 16×16 / 图标上叠加+变暗） |
| **C. 完全没有进行中反馈** | #10 #13 #14 #15 | #10 是网络请求，用户会怀疑没点上；#13–#15 是同步本地扫描，可接受 |
| **D. 整页遮罩** | #8 | 与"按钮自己表达状态"不一致，且按钮仍可点（可能并发） |
| **E. 下拉刷新** | #4 #7 #9 | iOS 独有；#4 覆盖范围与卡片上的刷新不一致 |

**禁用态也并存四种**：`OrzMCActionButton` 的 0.35、系统 toolbar 自动变暗、侧边栏 0.45 + 转圈、
以及"没有禁用"（#2 #3 #8，只靠模型内部 guard，界面上看不出）。

---

## 4. 不一致清单（按影响）

**P0**

1. **MCSM 控制台页的刷新还是旧写法**（#10）：`Image + .borderless`，没有 hover、没有转圈、
   没有 tooltip、没有 identifier；与卡片上的刷新不是一套，用户看不出在加载。
2. **合并页下拉刷新只刷自建**（#4）：用户会以为"整页都刷新了"，但 exaroton/MCSM 仍是旧数据。

**P1**

3. **账号卡/面板卡刷新没有禁用态**（#2 #3）：`isLoading` 时按钮仍亮，只在模型里被 guard 掉 ——
   点下去没反应，和自建卡片（刷新中按钮变成转圈）观感不同。
4. **额度池刷新是整页遮罩**（#8），且按钮不禁用、可重复点。
5. **help 文案不区分对象**：#2/#3 都是 `Reload this account's servers`，MCSM 是"面板"不是"账号"；
   #10 只重拉历史，却只叫 `Refresh`。

**P2**

6. **快捷键只有额度池有 ⌘R**；服务器页/详情页没有统一快捷键。
7. **锚点缺失**：#2（exaroton 账号刷新）、#6（玩家卡刷新）、#8（额度池刷新）、#10（控制台刷新）。
8. **自建详情页两个刷新并存**（工具栏 #5 + 玩家卡 #6）：都能刷名单，但反馈形式不同。

---

## 5. 建议

1. **抽一个设计系统组件 `OrzMCRefreshButton`**（复用 `OrzMCActionButton` 的命中区/禁用透明度）：
   `isRefreshing` 时同槽位转圈、`isEnabled` 变暗、hover、`help` + `identifier`。
   替换 #10、#5、#6、#8；#11 的"图标变暗 + 叠加转圈"也改成同一套。
2. **合并页下拉刷新改为"全部"**：#4 = 自建 `refreshAllStatuses()` + 每个 exaroton 账号
   `reloadList()` + 每个 MCSM 面板 `reload()`（并发，各组卡片自己显示转圈）。
3. **给 #2/#3 加 `isEnabled: !isLoading`**，让"刷新中"在界面上看得见（与自建一致）。
4. **统一 help 文案**：账号卡 `Reload this account's servers`、面板卡 `Reload this panel's instances`、
   控制台 `Reload the log history`（明确它不动实时流）。
5. **页面级 ⌘R**：服务器页 = 全部刷新（与下拉同义）；详情页 = 当前页刷新（自建状态/额度池已有）。
6. **补齐 identifier**：`exaroton.accountAction.refresh`（账号 id 前缀化）、`selfHosted.players.refresh`、
   `creditPool.refresh`、`mcsm.console.refresh`。
