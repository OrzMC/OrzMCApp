# 远程服务器状态：唯一来源

> 状态：生效中（2026-10-24）· 对应改动 `ExarotonServerModel.liveStatuses`

## 问题

远程服务器状态有两个来源：

| 来源 | 特点 |
|---|---|
| HTTP `GET /servers`（列表快照） | 首次加载 / 手动刷新时拿一次；之后不会自己变 |
| WebSocket 推送（`status` 事件） | 实时；但只有**连上之后**才有 |

以前只有详情页消费推送，列表读快照，于是：

- 服务器已经在线/正在启动，列表还显示「离线」；
- 用户一进详情页，收到推送后状态"跳"成在线 —— 看起来像 **App 自己把服务器启动了**；
- 额度池详情页又是第三份数据（自己再拉一次），三处可能各不相同。

## 现在的规则

```swift
model.effectiveStatus(for: server)   // 唯一入口
```

- **WebSocket 推送优先**（`liveStatuses[id]`），HTTP 快照兜底（`server.serverStatus`）；
- 状态**真的变化**时才 `reloadList()`，用服务端权威数据刷新名字/玩家数/地址
  （一次启动会推好几条，逐条 reload 既浪费也容易打架）；
- 列表卡片、详情概览、动作可用性、流订阅、自动重连、额度池详情，**全部**走这个入口。

## 各自负责什么

| 场景 | 谁提供状态 |
|---|---|
| 首次加载 / 下拉刷新 / 回到前台 | HTTP 快照（`GET /servers`） |
| 停在列表页（没有 WS） | **每 15 秒低频轮询 HTTP**（WS 是按服务器连的，只有进详情才连） |
| 详情页打开期间 | WebSocket 推送（实时）；状态一变化再 `reloadList()` 校准名字/玩家数/地址 |

## SDK 侧的一个坑（已修，2026-10-24）

`ExarotonAPI v0.0.9` 的 `ServerStatus` 枚举**漏了官方状态码 `9 = TRANSFERRING`**。
它不只是"少显示一个值"：WebSocket 的 `status` 消息整条 `Server` 解码会抛错，
于是**这次状态更新被整个丢掉**——服务器启动/停止时的迁移阶段（正是 9）状态会卡住。

- 修复：`ExarotonAPI 0.0.10` 补 `TRANSFERRING = 9`，并让未知状态码退化成 `.UNKNOWN`
  （不再让整条消息失败）。App 侧把 `.UNKNOWN` 当过渡态展示（"状态未知"，禁用动作）；
- 实测证据（真实账号、HTTP 轮询与 WS 推送并排）：
  `10 PREPARING → 6 LOADING → 2 STARTING → 1 ONLINE → 3 STOPPING → 5 SAVING → 0 OFFLINE`，
  两边一致，说明传输层本身没问题。

## 约定

1. **界面代码不允许直接读 `server.serverStatus`** —— 一律 `model.effectiveStatus(for: server)`。
   `scripts/dev/check-status-source.sh` 会检查（`check.sh` 里已接入），例外只有
   `Extension/ExarotonAPI+.swift`（`serverStatus` 的定义处）和模型内部。
2. 订阅流只在「在线」时进行（`RemoteStreamingPolicy`）—— 离线时订阅会拿到历史日志，
   看起来像"服务器在跑"。
3. 新增界面若需要状态，先想清楚是"实时状态"还是"快照里的历史状态"；
   前者必须走 `effectiveStatus`。
