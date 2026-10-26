# OrzMCApp
[![Publish Docs](https://github.com/OrzMC/OrzMCApp/actions/workflows/publish-docs.yml/badge.svg)](https://github.com/OrzMC/OrzMCApp/actions/workflows/publish-docs.yml)[![pages-build-deployment](https://github.com/OrzMC/OrzMCApp/actions/workflows/pages/pages-build-deployment/badge.svg)](https://github.com/OrzMC/OrzMCApp/actions/workflows/pages/pages-build-deployment)
[![Release App](https://github.com/OrzMC/OrzMCApp/actions/workflows/release-app.yml/badge.svg)](https://github.com/OrzMC/OrzMCApp/actions/workflows/release-app.yml)

OrzMC 是用于 macOS/iOS 的 Minecraft Java Edition 启动器与辅助应用。项目文档请查看：[项目文档](https://orzmc.github.io/OrzMCApp/)

## 平台支持

| 产物 | 最低系统 | 架构 |
|:--|:--|:--|
| `OrzMC.app`（macOS GUI） | **macOS 14.0** | Universal（Intel `x86_64` + Apple Silicon `arm64`） |
| `orzmc` CLI（`swift/lib/OrzMCKit`，非对外分发） | **macOS 13.0** | `arm64` / `x86_64` |

GUI 卡在 14 是因为 `@Observable`（Observation 宏本身要求 macOS 14）；逻辑层/CLI 有意钉在 13，让卡在 Ventura 的 Intel Mac 仍能用 CLI。规则、证据与复跑命令见父仓库 [`docs/platform-support.md`](https://github.com/OrzMC/OrzMC/blob/main/docs/platform-support.md)。

## 开发

```bash
./scripts/dev/install-hooks.sh   # 一次性：安装 pre-push 本地门禁
./scripts/dev/check.sh           # 日常门禁（静态检查 + 单测 + 应用测试 + macOS 构建）
./scripts/dev/check.sh --full    # 提交前完整门禁（+ iOS 构建 + 真 socket 协议联调）
```

改动 → 提交 → PR → squash 合并的完整流程、CI job 说明、发版步骤与已知坑，
见 [`docs/iteration-flow.md`](docs/iteration-flow.md)。

iOS 归档 / TestFlight / 真机装开发签名包见 [`docs/ios-release.md`](docs/ios-release.md)：

```bash
./scripts/release-ios.sh                     # 归档 + 导出开发签名 ipa
./scripts/release-ios.sh --export app-store-connect --upload   # 归档 + 上传 TestFlight
./scripts/release-ios.sh --install           # 归档 + 装到已连接的 iPhone
```

macOS 发版：`gh workflow run release-app.yml --ref main`（版本号见 `OrzMC/Configuration/Config.xcconfig`）。

---

<!-- ORZMC:COMPLIANCE:BEGIN (auto-generated; do not edit by hand. Single source: docs/compliance/ + scripts/sync_compliance.py in the OrzMC/OrzMC umbrella repo) -->
> **NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.**
>
> OrzMC 是独立的社区开源项目，与 Mojang / Microsoft 无隶属、赞助或背书关系，对本项目负责。
>
> “Minecraft”名称、品牌与素材的一切权利归 Mojang / Microsoft 所有。
>
> 联系：[GitHub 组织](https://github.com/OrzMC) ｜ 隐私政策：https://orzmc.jokerhub.cn/privacy/
<!-- ORZMC:COMPLIANCE:END -->
