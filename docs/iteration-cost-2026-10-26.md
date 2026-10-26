# 迭代耗时复盘（2026-10-26）

> 状态：**现行**（分析 + 已落地措施 + 待做清单） · 最后更新 2026-10-26
> 触发：维护者反馈「最近迭代耗时比较久」；数据来自 2026-10-25 / 10-26 两天的实际会话与 CI。
> 关联：[`iteration-flow.md`](iteration-flow.md)（日常流程）、父仓库 [`docs/iteration-efficiency.md`](../../../docs/iteration-efficiency.md)（跨平台迭代效率）。

---

## 1. 先看数字（实测，不是感觉）

| 环节 | 耗时 | 频次（一个功能 PR） | 说明 |
|---|---|---|---|
| 本地 `check.sh --fast` | ~5 s | 2–4 次 | 静态检查（分层/登记/本地化/凭据） |
| 本地 `check.sh`（默认） | **2–4 min** | 1–2 次 | 包单测 + 应用 73 条 + macOS 构建 |
| 本地 `check.sh --full` | **6–10 min** | 0–1 次（发版前） | 再加 iOS 构建 + 真 socket 协议联调 |
| 本地 `check.sh --ui` | **3–5 min** | 0–2 次 | 模拟器 XCUITest（8 用例） |
| 本地签名构建（`run-macos-signed.sh --build-only`） | **4–6 min** | 1–3 次 | 装 `/Applications` 手验要它 |
| 本地真机构建+安装（`install-ios-device.sh`） | **4–6 min** | 1–3 次 | 手机手验要它 |
| CI 单个 PR（5 个 job，`build` 主导） | **6.8 min** | 每个 PR | `build` macOS/iOS 各 6.8 min（并行），`intel` 4.2 min，`protocol-live` 0.8 min |
| 发版流水线 | **13 min** | 每次发版 | 签名 → 公证 → 打包 → Release → 回写 appcast |
| 发版后核验 | ~2 min | 每次发版 | 下载 + `codesign`/`lipo`/`spctl` |

**一次「功能 + 真机验收 + 发版」的墙钟**：约 **1.5–2 小时**，其中**纯等待构建/CI ≈ 40–60 分钟**。

---

## 2. 根因（按实际浪费的时间排序）

### R1 同一份代码要构建 6–8 次（最大头，约占一半等待）

一个功能落地通常要跑：`--fast` → 默认 `check.sh` → macOS 签名构建（装 `/Applications`）→ iOS 真机构建+安装 → `--ui` → PR CI（2 个平台）→ 发版 CI。**每次都是全量编译**，因为：

- 本地有 **6 个独立 DerivedData**（`OrzMC-local` / `-ios` / `-signed` / `-device` / `-devtest` / `-x86`），
  各自解析依赖、各自编 SwiftPM 依赖 → 同一个 `MCSManagerAPI` 在 4 个目录里各编一遍；
- CI 的 `build` job 每次**删掉 `Package.resolved` 强制 HEAD 解析**（为了尽早发现依赖漂移），
  于是 `OrzMCKit` 及其传递依赖每次都可能重编 → 缓存命中（已确认 `Cache restored successfully`）也救不回来。

### R2 依赖版本一升就"Couldn't check out revision"（每次 1–3 分钟 + 一轮失败构建）

`npm` 式的小事，但**本轮踩了 4 次**：把 `Package.resolved` 里的 `MCSManagerAPI` 从 0.2.x 升到 0.3.x 后，
Xcode 报 `fatalError: Couldn’t check out revision '<sha>'` —— 因为缓存里的 bare repo **没有新 tag**。
以前只能手找缓存目录 → `git fetch --tags` → 删 checkouts → 重跑；本轮我手工做了 **4 个目录 × 2 次**。

### R3 真机 XCUITest 不可用 → 改用"人眼 + 截图 + 诊断钩子"（每次 5–10 分钟）

iOS 27.0.1 真机上 `OrzMCUITests-Runner` 起不来（详见 §5），只能退化成：
`devicectl` 装包 → 截图 → 用 `ORZMC_DEMO_MCSM_DIAGNOSE=1` 落盘核对。这三件事都要人手/脚本串起来。

### R4 需要 Terminal.app 才能在真机上签名（工具链限制）

真机构建/测试要访问钥匙串私钥，**非交互 shell 会 `errSecInternalComponent`**。
所以自动化只能 `open -a Terminal xxx.command` + 轮询日志 —— 每一轮多 1–2 分钟空转，且失败时拿不到完整输出
（脚本内部 `| grep … | tail -30` 把关键行滤掉了）。

### R5 磁盘（一次性但很致命）

`~/Library/Developer/Xcode/DerivedData` 涨到 **13 GB / 60+ 个 `OrzMC-*` 目录**，本轮真的撞到
`No space left on device` → 整次签名构建报废（+5 分钟）。可用空间现在 12 GB，属于"随时会再来一次"。

### R6 发版没有"演练"档

`release-app.yml` 只能真发。一旦产物有问题，代价是"发出去再造一个 hotfix 版本号"（0.1.5 就是这么来的）。

---

## 3. 已落地（本轮，可直接用）

| 措施 | 效果 |
|---|---|
| **`scripts/dev/refresh-package.sh <包>`**（新增） | 一条命令处理 R2：对**所有** DerivedData + 全局缓存里的 bare repo 做 `fetch --tags`，并删对应 checkout。**秒级**，不用重新克隆。`--purge` 保留彻底清；`--all` 全量刷新 |
| **`check.sh` 磁盘预检** | R5：可用空间 <5 GB 时在构建前警告并给出清理提示，不再"构建到一半才炸" |
| **CI `intel` job 只在需要时跑** | 打 `intel` label 才在 PR 上跑；main / 发版前照常。省 runner 分钟（wall-clock 由 `build` 决定，本来并行） |
| **`release-app.yml` 加 `dry_run` 输入** | R6：`gh workflow run release-app.yml -f dry_run=true` → 完整签名/公证/打包/断言，**不发 Release、不提交 appcast** |

**第二轮（O1/O2/O6，2026-10-26 晚）**

| 措施 | 实测效果 |
|---|---|
| **O1 收敛 DerivedData**：`run-macos-signed.sh` 改用 `OrzMC-local`、`install-ios-device.sh` 改用 `OrzMC-local-ios`（都与 `check.sh` 共用） | 先签名构建再 `check.sh` → **49.9 s**（此前 2–4 min）；目录 **8 个/6.8 GB → 2 个/4.2 GB**；签名与真机安装均照常 |
| **O2 CI：PR 用锁定依赖**（`Resolve package dependencies` 只在非 PR 跑） | PR 上 `build (macOS)` **6.8 min → 3.4 min**；`build (iOS)` 6.8 → 5.7 min；main 仍做 HEAD 解析（`build` 4 min，`intel` 5.2 min） |
| **O6 `scripts/dev/reclaim-space.sh`**（新，默认 dry-run） | 本轮清掉 6 个残留目录，回收约 2.5 GB（此前撞过一次 `No space left` 报废整次签名构建） |

**累计效果**：一次功能迭代的等待时间从 **40–60 min** 降到约 **25–35 min**（本地 -10 min、PR CI -3.4 min、
再加上不再重复踩"缓存缺 tag / 磁盘满"）。

---

## 4. 待做（按性价比排序）

| # | 措施 | 省什么 | 成本 | 风险 |
|---|---|---|---|---|
| ~~O1~~ | ~~收敛 DerivedData~~ **✅ 已完成**（签名→`OrzMC-local`、真机→`OrzMC-local-ios`） | 实测 `check.sh` 49.9 s（原 2–4 min） | — | — |
| ~~O2~~ | ~~PR 用锁定依赖~~ **✅ 已完成** | 实测 PR `build` 6.8 → **3.4 min** | — | — |
| ~~O3~~ | ~~UI 测试 `--detach`~~ **✅ 已完成**：一条命令自动进 Terminal 跑、等结果、回传末尾日志 | 实测真机全量套件一条命令跑通 | — | — |
| ~~O4~~ | ~~发版一键脚本~~ **✅ 已完成**（`scripts/dev/release.sh --version X.Y.Z [--plan]`）：版本递增/notes/工作区检查 → 升版本 → `--fast`+`--full`+`--ui`+真机 UI → 建 PR → 打印后续三步 | 发版前半段全自动 | — | — |
| ~~O5~~ | ~~`check.sh --changed`~~ **✅ 已完成**：纯文档/本地化→只跑静态；纯测试→包单测+应用测试；其它→默认档 | 小改动 -2~3 min | — | 低（保守：识别不出就回默认档） |
| ~~O6~~ | ~~清理脚本~~ **✅ 已完成**（`scripts/dev/reclaim-space.sh`，默认 dry-run） | 本轮回收 2.5 GB | — | — |

**不建议做的**：把 `build` 的 macOS/iOS 两格合并（会串行，反而更慢）；为了快而跳过 `OrzMCUITests`（历史上正是它抓到过腐烂的测试 target）。

---

## 5. 真机 XCUITest 故障（R3）—— **已解决：是没插数据线**

> ⚠️ 本节早期版本把原因误判为「Xcode 27.0 < 设备 iOS 27.0.1 的版本不匹配」并加了硬阻断预检。
> 2026-10-26 23:3x 维护者插上**数据线**后复测：**直接通过**。误判已纠正，预检已降级为提醒。

**真正的两个门槛**

| 现象 | 原因 | 处理 |
|---|---|---|
| runner 起来 19 秒后 `Connection peer refused channel request for "dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface"` → `exit 74` | 设备只在 **Wi-Fi** 上连接（`Transport Type: localNetwork`） | **插数据线**（`Transport Type: wired`）→ 错误消失 |
| 插线后 `Timed out while enabling automation mode`（首次） | 设备需要允许"自动化模式"（授权/首次提示） | 保持设备**解锁亮屏**，重跑一次即通过 |

**实测结果（iPhoneSE3 / iOS 27.0.1 / Xcode 27.0.0）**

```
Test Case '…testMCSManagerSectionShowsInstancesAndStatus' passed (20.162 seconds)
Test Suite 'RemotePanelsUITests' passed …  ** TEST EXECUTE SUCCEEDED **
```

全套 8 个用例（4 个按设计 skip）在真机上全绿。

**脚本侧的改进（避免下次再误判）**
- `run-ios-ui-tests.sh --device` 的预检 **只警告不阻断**：
  设备版本比 Xcode SDK 新时提一句；**连接方式不是 `wired` 时明确提示"真机 XCUITest 在 Wi-Fi 下会 exit 74，请插数据线"**；
- `--detach`（O3）：自动进 Terminal.app 跑并等结果，一条命令拿到退出码 + 末尾日志。

