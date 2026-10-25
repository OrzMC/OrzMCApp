# 远程托管供应商抽象层（多供应商 / 多实例）

> 状态：生效中（P2-7 第 1 步已完成，2026-10-25）· 对应代码 `Sources/OrzMCRemoteHosting/` +
> `OrzMC/Common/ExarotonUI/Model/ExarotonHostingProvider.swift`
> 交接入口：[`../../../HANDOFF.md`](../../../HANDOFF.md) §1 · 待办看板：[`backlog-2026-10-25.md`](backlog-2026-10-25.md) P2-7

## 目标

远程托管从「只支持 exaroton、单账号」扩展到**多供应商 + 每供应商多实例（多账号/多面板）**，
并且以后再加一家供应商**不需要动界面和状态中心**。

## 已拍板（维护者 2026-10-25）

1. MCSM 走**独立 OpenAPI 依赖**（`OrzMC/MCSManagerAPI`，与 `ExarotonAPI` 同构：`openapi.yml` +
   generator build plugin + `X-Request-API-Key` 中间件），不把两家接口揉进一个包；
2. 抽象层在 API 依赖**之上**，统一"实例 + 状态 + 动作"；
3. **能下沉的尽量下沉**到 `Sources/*`（可复用、可单测、各端不重复实现）；
4. 多供应商界面**按供应商分组**，不做"provider 过滤"。

## 分层

```
┌─ 界面（OrzMC/Common/*UI）─────────────── 只认 RemoteInstanceSummary / ProviderKind
├─ app 适配器（ExarotonHostingProvider …）─ 知道"怎么调某一家"
├─ 抽象层（Sources/OrzMCRemoteHosting）─── 供应商无关；不 import 任何 SDK
└─ API 客户端（ExarotonAPI / MCSMAPI）──── 各自 OpenAPI 生成，互不相识
```

抽象层不能 `import ExarotonAPI`：否则第二家供应商进来就要改抽象层。
反过来，SDK 也不该知道界面存在。

## 接口（`Sources/OrzMCRemoteHosting/RemoteHostingProvider.swift`）

```swift
public enum ProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case exaroton
    case mcsmanager          // MCSManager 面板：URL + apikey
}

public struct RemoteInstanceID {          // 全局键：供应商 + 该供应商内部的 ID
    let provider: ProviderKind
    let rawValue: String                  // description = "exaroton:ATMiLQGZ43vW2k3W"
}

public struct RemoteInstanceSummary {     // 列表/卡片要用的一切
    let id: RemoteInstanceID
    let name: String
    let address: String?                  // 有多个时给**稳定**那个
    let state: RemoteServerState          // online/offline/starting/stopping/restarting/unknown
    var provider: ProviderKind { id.provider }
}

public protocol RemoteHostingProvider: Sendable {
    var kind: ProviderKind { get }
    func listInstances() async throws -> [RemoteInstanceSummary]
    func perform(_ action: RemoteServerAction, on instance: RemoteInstanceID) async throws
}

public struct ClosureRemoteHostingProvider: RemoteHostingProvider { … }  // 两个闭包就能接入
```

### 不变量（有意为之，改之前先想清楚）

| 不变量 | 为什么 |
|---|---|
| **实例的键是 `RemoteInstanceID`（供应商 + 原始 ID），不是裸字符串** | 两家供应商的 ID 会撞（随机串 / 数字）；状态中心、订阅、Keychain 条目都以它为准 |
| `perform` 收到**别家**的实例时立刻抛 `wrongProvider`，不调底层闭包 | 多账号/多供应商交错时，"拿错模型"必须是显式失败，不能静默操作错服务器 |
| 动作被拒绝 → 抛 `actionFailed`（现有 exaroton 动作返回 `Bool`，适配器负责翻译） | 否则调用方会以为请求提交成功；用户侧提示仍由模型写进 `actionErrors`，适配器不重复弹窗 |
| 分组顺序固定为 `ProviderKind.allCases`，组内保持输入顺序 | 界面不能随网络返回顺序抖动 |
| 分组时**去掉重复实例**（保留第一份） | 多账号把同一实例拉了两遍时 `ForEach` 的 `Identifiable` 会渲染错行 |
| 状态**不在供应商里推**，仍走唯一状态中心 | 见下节 |

## 状态：仍然只有一个来源

供应商只**喂数据**（`listInstances()` / 适配器把 WS 推送写进状态中心），
判"该不该轮询"的逻辑只有一份：`RemoteStatusRefreshPolicy` + 唯一写入口 `publishStatus` +
订阅 `statusEvents()`。详见 [`remote-status-source.md`](remote-status-source.md)。

⚠️ 三条红线（P2-7 全程有效）：
1. **不要**改"WebSocket 是否安静 30 秒"这个轮询判据；
2. 状态徽章只有 `OrzMCStatusBadge` 一个实现；
3. 控制台解析按 Unicode 标量遍历，行尾 `\r` 不能丢整行（[`console-rendering.md`](console-rendering.md)）。

## 分组（`RemoteHostingGrouping`）

```swift
RemoteHostingGrouping.groups(from: instances)
// → [RemoteHostingGroup(.exaroton, [...]) , RemoteHostingGroup(.mcsmanager, [...])]
```

界面按这个结果渲染 section；**没有实例的供应商不出现**（不给空 section）。

## 进度

| 步骤 | 内容 | 状态 |
|---|---|---|
| 1 | `RemoteHostingProvider` / `ProviderKind` / `RemoteInstanceSummary` 定稿 + exaroton 适配器（行为不变） | ✅ 2026-10-25 |
| 2 | `ExarotonStatusCenter` → 供应商无关的 `RemoteStatusCenter` | 待做 |
| 3 | `Sources/MCSMAPI`（新仓库 `OrzMC/MCSManagerAPI`）：列实例 + 实例状态 | 待做 |
| 4 | app 侧 MCSM 适配器（只读）：列实例 + 轮询状态，凭据进 Keychain，UI 按供应商分组 | 待做 |
| 5 | 动作 / 命令 / 多账号管理界面 | 待做 |

验收口径（维护者）：新增一个 MCSM 面板（URL + apikey）后，在同一个「远程托管」页里能看到实例并
实时看到状态变化；切换/删除账号不影响其他账号的轮询。

## 涉及文件

| 文件 | 作用 |
|---|---|
| `Sources/OrzMCRemoteHosting/RemoteHostingProvider.swift` | `ProviderKind` / `RemoteInstanceID` / `RemoteInstanceSummary` / 协议 / 分组 / 闭包适配器 |
| `Sources/OrzMCRemoteHosting/RemoteServerState.swift` | 归一化状态、动作、列表策略（搜索 + 动作可用性） |
| `OrzMC/Common/ExarotonUI/Model/ExarotonHostingProvider.swift` | exaroton 适配器：`servers` → 摘要（状态取 `effectiveStatus`）、动作 → 现有 start/stop/restart |
| `Tests/OrzMCRemoteHostingTests/RemoteHostingProviderTests.swift` | 抽象层单测（命名空间、分组、闭包适配器、错误透传） |
| `OrzMCTests/ExarotonHostingProviderTests.swift` | exaroton 适配器单测（映射、静态地址优先、无 id 跳过、拒绝别家实例） |
