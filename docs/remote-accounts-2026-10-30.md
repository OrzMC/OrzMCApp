# 远程托管多账号与实例展示

> 状态：实现已提交 PR #123｜最后更新：2026-10-30

维护者在 UI 交接之后明确扩大范围：每个供应商支持多个账号，每个账号展示其全部实例；主界面已经满意，本轮聚焦远程服务器页。

## 结构与复用

页面固定为 exaroton → MCSManager 两个供应商分组，各组有添加账号入口；账号下展示实例。账号标题、编辑表单壳、实例名称与状态布局分别复用 `RemoteAccountHeader`、`RemoteAccountEditor`、`RemoteInstanceHeading`，供应商标题使用 `RemoteProviderHeader`。

exaroton 保留额度池、软件与内存等特有展示和详情；MCSManager 保留面板地址、测试连接、控制台和强杀。不会给 exaroton 增加强杀。

## 凭据与隔离

- exaroton 账号元数据存 `EXAROTON_ACCOUNTS`，Token 按账号 UUID 分别存 Keychain。
- 旧 `EXAROTON_TOKEN` 仅在新 Keychain 条目及账号元数据保存成功之后删除；保存失败保留旧凭据并显示错误。
- 每个账号独立持有 `ExarotonServerModel`、状态中心、操作门禁和连接；凭据在该模型生命周期内固定。
- 编辑凭据替换该账号模型；删除账号停止它的轮询与 WebSocket，不影响其它账号。同一服务器可在不同账号组中出现，各组各自持有状态中心，不跨账号去重。
- MCSManager 同一地址允许不同 API Key，重复判断使用地址与凭据，不再依赖可修改的显示名称；每条记录仍有独立 UUID、Keychain 条目及模型。

## 验证记录

- `check.sh --fast`：通过。
- `check.sh`：最终完整门禁通过（SwiftPM 单测、应用单测、macOS 构建）；新增凭据迁移与账号隔离测试通过。
- iOS Simulator App / 测试构建通过；多 exaroton 账号、详情自动进入、真实 Mac 凭据列表、远程详情截图共 4 项定向验收全绿（`/tmp/orzmc-accounts-after.xcresult`）。
- 首轮完整 UI 回归发现 DEBUG 详情自动进入失效，已修正，定向用例通过；整套回归的最终结果记录在 PR #123 与父仓库 HANDOFF 会话日志。
- Mac 开发签名包已安装，`install-dev-app.sh --accept` 退出 0：两个真实 MCSM 账号分别列出两台实例，四路只读控制台流均 LIVE。
- 维护者指定先做 Mac，通过 Mac 凭据在模拟器开发；真机验收由维护者之后统一进行。
- 截图：`ui-remote-accounts/before.png` / `after.png` / `multiple-exaroton.png` / `configured-mcsm.png`。均为 SE3、375pt 宽。改前为单个假 exaroton 实例、未配置 MCSM；改后额外通过 Mac 凭据注入真实 MCSM 账号，展示新增账号层级。

## Terminal 启动问题

同一条 `open -Ra Terminal` 沙箱内失败、沙箱外成功；完整路径在沙箱内启动还会误报 `kLSNoExecutableErr`，但可执行文件实际存在。脚本已使用系统完整路径及明确错误提示；agent 必须在沙箱外执行 `--detach`。沙箱外启动 `.command` 并写回探针结果已通过，与 Ghostty 默认终端无关。

## 原交接中尚未完成的项

`ui-handoff-2026-10-30.md` UI-1 真机判据、UI-3 exaroton 停止秒数及完整大字号巡检仍需另行完成；本次多账号改动不将这些标记为完成。真机验收按维护者最新安排后续统一进行。本次不发版；PR 合入前不 bump 父指针。

## 模拟器复用 Mac 凭据

仅 DEBUG 支持 `ORZMC_DEMO_MCSM_PANELS`（现有面板元数据 JSON）与 `ORZMC_DEMO_MCSM_KEYS`（按账号 UUID 映射的凭据 JSON）。由测试进程环境传入 App，不将 Mac 的 Keychain 或配置数据库复制到模拟器，不将凭据写入仓库。

`testSnapshotConfiguredRemoteAccounts` 只读加载和截图，使用 `ORZMC_UITEST_SNAPSHOTS=1` 显式开启；exaroton 使用已有 `ORZMC_DEMO_TOKEN` 注入。只读验收覆盖 Mac 上的管理员/普通用户两个账号，各自两台实例。

## exaroton 账号名称（2026-10-30）

账号卡不重复显示供应商副标题。未填写名称或从旧单账号数据迁入的占位名称，通过 exaroton 的只读 `GET /account/` 获取 `name`；失败时显示通用“账号”占位，用户仍可手动命名。新版本显式填写的名称不会被自动结果覆盖；旧记录无法区分手填和默认的 `exaroton`，因此该名称按旧默认值处理。切换 Token 或删除账号后到达的旧请求结果会被丢弃。旧记录没有自动命名标记时仍能读取并迁移。

Mac 现有凭据与模拟器测试凭据一致；只读实测 `User-Agent: OrzMC` 请求账号接口返回 200 且包含名称，应用内真实账号 UI 用例、完整 Mac 门禁及整套模拟器 UI 回归通过。Python 默认 User-Agent 被服务端返回 403，不能将该探针结果视作账号或凭据失效。不会输出或提交凭据。

同一演示场景的改前/改后截图为 `ui-remote-accounts/multiple-exaroton.png` 与 `ui-remote-accounts/account-polish-after.png`（iPhone SE 模拟器，不含真实账号信息）。Mac 开发包已安装并通过只读面板自检。
