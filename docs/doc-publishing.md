# 文档发布（DocC → GitHub Pages）

> **状态**：生效中｜**最后更新**：2026-11-09
> **入口**：[`OrzMC/Common/documentation.docc/`](../OrzMC/Common/documentation.docc/)（`Home.md` 是首页）
> **站点**：https://orzmc.github.io/OrzMCApp/ （gh-pages 分支）
> **workflow**：[`.github/workflows/publish-docs.yml`](../.github/workflows/publish-docs.yml)

## 1. 触发方式

| 方式 | 什么时候 | 说明 |
|---|---|---|
| **push 到 `main`** | `OrzMC/Common/documentation.docc/**` 或本 workflow 自己变了 | 只盯 DocC 内容，避免每次改 Swift 代码都白跑一台 macOS runner |
| **手动** | 发版后、或想立刻刷新 | `gh workflow run publish-docs.yml --ref main` |

同一时间只允许一个部署（`concurrency: publish-docs`，新任务取消旧任务），避免 gh-pages 被乱序覆盖。

## 2. 流水线做了什么

```
checkout → resolvePackageDependencies（干净解析，不恢复缓存）
  → xcodebuild docbuild（Release 配置，仅 macOS 文档）
  → docc process-archive transform-for-static-hosting
        --output-path docs-site --hosting-base-path /OrzMCApp
  → touch docs-site/.nojekyll
  → scripts/dev/make-docs-landing.py（根路径直接是文档首页）
  → 断言站点完整 → 部署到 gh-pages（clean + single-commit）
```

产物在 `docs-site/`（**不再写进仓库的 `docs/`**，那里是 Markdown 文档源，两者互不干扰）。

**不缓存 DerivedData / SourcePackages**（2026-11-09 实测）：恢复出来的 SourcePackages 带着旧的二进制产物
（Sparkle / SwiftLint），SwiftPM 会重新下载并稳定报 `badResponse`（同一个 URL 本地正常）；干净解析虽然多花几分钟
（整条流水线约 20 分钟），但结果稳定。以后若要加速，只缓存**没有** `SourcePackages/artifacts` 的那部分。

## 3. 为什么根路径不会再"闪一下重定向"

DocC 的静态站点把根 `index.html` 生成成"跳转到 `/documentation/<module>/`"的占位页；
它的 SPA 又用 `location.pathname` 决定渲染哪一页 —— 所以直接打开站点会先经历一次跳转。

`scripts/dev/make-docs-landing.py` 做两件事：

1. 把 `documentation/<module>/index.html` 复制成站点根 `index.html`（静态资源仍然走绝对路径
   `/OrzMCApp/...`，不受影响）；
2. 在 `<head>`、DocC bundle 之前注入
   `history.replaceState(null, "", "/OrzMCApp/documentation/<module>/")`。

SPA 启动时就"看到"自己位于文档首页 → **直接渲染文档首页**，浏览器地址也变成可分享的文档地址，
但没有一次真实导航/白屏。

> 只复制页面、不加 replaceState 的话，SPA 会因为路径是 `/` 而显示 "page not found"（已实测）。

## 4. 本地预览 / 验证

```bash
# 1) 构建并生成静态站点
xcodebuild docbuild -scheme OrzMC -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/orzmc-docs-dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
ARCHIVE="$(find /tmp/orzmc-docs-dd -type d -name 'OrzMC.doccarchive' -print -quit)"
xcrun docc process-archive transform-for-static-hosting "$ARCHIVE" \
  --output-path /tmp/docsite/OrzMCApp --hosting-base-path /OrzMCApp
touch /tmp/docsite/OrzMCApp/.nojekyll
python3 scripts/dev/make-docs-landing.py /tmp/docsite/OrzMCApp --base-path /OrzMCApp

# 2) 起一个本地服务器（必须带 /OrzMCApp 前缀）
(cd /tmp/docsite && python3 -m http.server 8099)
open http://127.0.0.1:8099/OrzMCApp/
```

无头验证（本机有 Chrome 时）：

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --virtual-time-budget=8000 --window-size=1200,900 \
  --screenshot=/tmp/docs.png "http://127.0.0.1:8099/OrzMCApp/"
```

期望：截图直接是文档首页（左侧导航 + `OrzMC` 概览），没有任何空白跳转。

## 5. 维护约定

- **文档写进 DocC**：`OrzMC/Common/documentation.docc/*.md`（首页 `Home.md`），与 App target 一起构建；
  仓库里的 `docs/*.md` 是**工程文档**（交接、设计、发版记录），不进 DocC 站点。
- 新增文章后记得在 `Home.md`（或对应 Topics 页）里加链接，否则只能在搜索/导航里找到。
- 改完本地按 §4 预览一次；`make-docs-landing.py` 是纯脚本，可以单测/本地直接跑。
- 旧 workflow 把产物写进 `docs/` 并整体缓存 —— **别改回去**：那会污染 Markdown 文档目录，
  而且缓存会让落地页之类的模板改动被旧产物覆盖。
