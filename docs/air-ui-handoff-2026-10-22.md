# Air 接力：页面设计与交互优化

> 状态：通过 Git 分支在 Air 接力，继续评审/修正｜更新时间：2026-10-22

## 当前任务与事实源

维护者要求使用 `apple-native-product-design`、`swiftui-pro`、`swift-concurrency-pro` 审查并改善 `swift/app` 的页面和导航体验。本轮已输出建议，尚未实施审查提出的修正。先读：

1. 父仓库 `AGENTS.md`、`HANDOFF.md`。
2. app 的 `docs/ui-handoff.md`（历史实现与验收记录）。
3. `docs/app-ui-design.md`（设计系统和多窗口决策）。
4. `docs/ui-review-2026-10-22.md`（本轮审查依据、问题位置、验收标准）。

源设备工作目录 `/Users/bot/OrzMC/swift/app`；`main`，HEAD 为 `fa571e70c632ef1e514158b7deb5711001f8d111`。大量 UI 改动尚未提交，包含新文件与文件删除。没有创建 UI 分支、提交、推送或 bump 父仓库指针。不要只 git pull 就认为拿到了本轮成果。

## Air 上通过 Git 接力（以本节为准）

维护者已授权提交推送，改用 Git 接力；旧 patch/tar 交接包不再需要。父仓库分支为 `feat/ui-refresh-handoff`，app 子模块分支为 `feat/ui-refresh`。两个分支均保留供审阅，不自动合并或发版。

新工作区：

```bash
git clone --branch feat/ui-refresh-handoff --recurse-submodules https://github.com/OrzMC/OrzMC.git
cd OrzMC
git status -sb
git submodule status swift/app
cd swift/app
git switch feat/ui-refresh
```

已有正式父仓库工作区，先核对未提交内容，干净时再执行：

```bash
git fetch origin
git switch --track origin/feat/ui-refresh-handoff  # 已有同名本地分支则直接 switch
git pull --ff-only
git submodule update --init --recursive
cd swift/app
git fetch origin
git switch feat/ui-refresh
```

app HEAD 必须与父仓库记录指针一致；如已有工作或分支前进，先比较，不要 reset/clean。构建镜像 `~/orzmc-build/app`、iOS DerivedData、macOS 可再生成缓存和旧交接包已获授权清理，不能再依赖它们恢复源码。当前 OrzMC 仍从 macOS `app-dd/Build/Products` 运行，因此该 Products 目录保留，待关闭应用后可按需删除。构建产物可以从正式工作树重新生成。

## 技能与工具

Air EasyApple：`/Users/joker/Documents/EasyApple`。三个共享技能已链接到 `~/.agents/skills/`；Xcode 官方技能在 Air 上已导出。必要时运行 `bash /Users/joker/Documents/EasyApple/tools/install-agent-skills.sh`，新会话核对技能可见性。

EasyApple 最新已推送提交：`a5912d4 docs: 同步 Apple 技能与环境文档`。本轮没有修改 EasyApple。

## 建议先处理的交互问题

1. 本地控制台 Follow：上滚不自动暂停，后续日志会拉回底部；需要阅读位置、回到最新和 Reduce Motion 规则。
2. 远程 Start/Stop/Restart：请求期间缺少模型级防重入；成功 alert 改为非模态反馈，区分请求已接受和服务端已运行。
3. Settings 根目录：TextField 逐字写 AppModel.rootDir，触发目录扫描与进度重置；改成草稿校验后提交。
4. 远程日志：Clear 只清本地字符串，下一行会重拼旧缓冲；Optional.publisher 不是持久日志流，throttle 设计需要修正。
5. 后续再看版本切换与内嵌控制台关系、远程空/错/刷新状态、Launch 对齐和中文进度、RAM 保存顺序。

这是审查建议优先级；先复核代码和桌面行为，再逐项小范围实现，不顺手重构无关架构。

## 视觉验收与证据边界

上轮实现构建/测试结果与部分 AX 验证已记在 ui-handoff；本轮只进行了代码审查和 Air 窗口检查：已有 OrzMC 进程前台，1 个窗口，标题 `Minecraft - 1.21.11`。没有重新构建，也没有截图或帧率测量，不代表新增审查建议已经修复。

在登录桌面会话重点验：Launch 高度/字段基线/焦点环、Settings 四页、中文长文案、Remote 列表/详情/Actions/Console/额度池、控制台搜索与实际导出、2000 行缓冲 Follow、关闭主窗口后控制台与探活、受控实例停止全部。

Remote 必须分别记录实际 960/1200pt 宽度；已有记录显示请求 1200 可能被桌面裁至 1129，不能当作 1200 验收通过。不要从 SSH 调用 screencapture；需要截图由维护者在桌面会话操作。

## 硬约束与验证

- 保持单主启动器 Window 和唯一 AppModel；独立控制台共享模型。
- 代码只在 app 子模块改；父仓库仅按授权记录指针。禁用 git add -A / git add .。
- TextField 使用 LabeledContent 行标签、空 label 与示例 prompt，避免重复占位文案。
- 语义颜色走 OrzMCTheme，控制台 consoleSurface，外链 Link，静态文案 Localizable.xcstrings。
- Sources/* 不导入 AppKit/UIKit；保留 macOS 14 / iOS 18 的实际目标兼容性。
- 维护者已授权本轮分支提交与推送；未授权自动合并或发版。后续改动继续使用 Conventional Commits 中文提交，多行消息写文件后 commit -F。

每项修正说明“改了什么、为什么、如何验证”，并跑：

```bash
# 在正式父仓库根；Air 本机执行时可用 localhost 替代 ssh air
ORZMC_BUILD_HOST=localhost scripts/air/run.sh app
ORZMC_BUILD_HOST=localhost scripts/air/run.sh app-ios
ORZMC_BUILD_HOST=localhost scripts/air/run.sh app-test
(cd swift/app && ./scripts/check-platform-split.sh)
```

localhost SSH 需要本机远程登录与认证可用；否则使用 Air 已配置可用的主机别名，或核对脚本中的原始命令在正式工作树直接执行。不要在工作树与构建镜像相同路径时运行 rsync。

把新问题、实际尺寸、测试结果、未验证项继续追加到 ui-handoff.md，保留历史。
