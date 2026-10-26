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
| O3 | **`run-ios-ui-tests.sh --detach`**：内部用 `osascript` 起 Terminal 并等待，输出回传 + 保留完整日志 | R4 每轮 -1~2 min，且失败可诊断 | 1h | 低 |
| O4 | **发版一键脚本** `scripts/dev/release.sh`：校验版本号递增 → 检查 release-notes 存在 → `--full` + `--ui` → 触发 `dry_run` → 断言产物 → bump 父仓库 | 发版从 30 min 手忙 → 15 min | 2h | 低 |
| O5 | **`check.sh --changed`**：按 `git diff --name-only` 只跑受影响的部分（纯文档/纯本地化改动不再跑完整档） | 小改动每次 -2~3 min | 半天 | 中（漏跑风险，需白名单） |
| ~~O6~~ | ~~清理脚本~~ **✅ 已完成**（`scripts/dev/reclaim-space.sh`，默认 dry-run） | 本轮回收 2.5 GB | — | — |

**不建议做的**：把 `build` 的 macOS/iOS 两格合并（会串行，反而更慢）；为了快而跳过 `OrzMCUITests`（历史上正是它抓到过腐烂的测试 target）。

---

## 5. 真机 XCUITest 故障（R3 的具体进展）

| 步骤 | 结果 |
|---|---|
| 复现 | `run-ios-ui-tests.sh --device …` → `OrzMCUITests-Runner … exited with code 74 before establishing connection` |
| 排除 1：设备锁 | `devicectl device info lockState` → `passcodeRequired: false`、`unlockedSinceBoot: true`（且截图确认屏幕亮着、已解锁） |
| 排除 2：签名 | runner 用 `Apple Development: zhizhou wang (X3C2MG74H2)` 签名，`embedded.mobileprovision` 有效期到 2027-10-18 |
| 排除 3：设备信任/开发者模式 | `Developer Mode: Enabled`、`Pairing State: paired`、destination 被认作合法（`-showdestinations` 无 Ineligible） |
| 排除 4：工程/脚本（我们的 `patch-xctestrun.py`） | 用**干净的 `xcodebuild test`**（全新 DerivedData、不经过打补丁的 xctestrun）同样失败 |
| **抓到真因** | runner 起来后 19 秒：`Connection peer refused channel request for "dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface"` → `Exiting due to IDE disconnection` |
| 含义 | 宿主机（testmanagerd 客户端）↔ 设备 `testmanagerd` 的 **DTX 握手被设备拒绝**，与我们的代码/签名/xctestrun 无关 |
| 已试 | 重装 runner / App、彻底 `uninstall`、`devicectl device process launch`（能起）→ 都不解决 |
| 下一步 | ① **重启设备**（本轮已执行，等设备解锁后复测，见下）② 若仍失败 → 设备 iOS **27.0.1** 比本机 Xcode **27.0.0** 新，升级 Xcode 到 27.0.1+ 再试 |

**结论（2026-10-26 22:1x，重启设备后复测）**：重启 + 解锁后**同样失败**（同样是 19 秒后 DTX 被拒），
因此排除"设备端状态坏"，定为 **Xcode / iOS 版本不匹配**：

| 项 | 版本 |
|---|---|
| 本机 Xcode | **27.0 (27A266a)**，iOS SDK **27.0** |
| 目标设备 | iPhoneSE3，iOS **27.0.1**（24A446） |

设备 OS 比 Xcode 自带的 iOS SDK 新 → 设备侧 `testmanagerd` 拒绝宿主的 DTX 通道请求。
**修法：升 Xcode 到 27.0.1+**（或把设备降到 27.0）。在此之前，真机 UI 用 `--simulator` 代替。

**已加预检（防止再白等 6 分钟）**：`run-ios-ui-tests.sh --device` 现在会先比
「设备 iOS 版本」与「Xcode 的 `-sdk iphoneos` 版本」，不兼容时 **3 秒内**直接报：

```
✗ 设备 iOS 27.0.1 比本机 Xcode 的 iOS SDK 27.0 新
  这种组合下真机 XCUITest 会在 DTX 握手处被设备拒绝（runner exit 74），不是工程问题。
  修法：把 Xcode 升到与设备同版本或更新…
```

（不装 Xcode 也能验：`--simulator` 跑同一套 8 个用例。）
