#!/usr/bin/env python3
"""把 DocC 静态站点的**根路径**变成"直接是文档首页"。

背景（2026-11-09）：`docc process-archive transform-for-static-hosting` 生成的站点，
根 `index.html` 只是一个跳转到 `/documentation/<module>/` 的占位页；直接打开站点会先看到
一次重定向（空白闪一下）才进文档首页。

DocC 的 SPA 用 `location.pathname` 决定渲染哪一页：把文档首页的 HTML 复制到站点根目录
即可让静态资源仍然走 `/documentation/<module>/`；再在 `<head>` 里、DocC bundle 之前
`history.replaceState` 到文档首页路径，SPA 就会**直接渲染文档首页**（浏览器的 URL 也变成
可分享的文档首页地址，但没有一次真实导航/白屏）。

验证（本地）：

    python3 scripts/dev/make-docs-landing.py /tmp/docsite/OrzMCApp --base-path /OrzMCApp
    (cd /tmp/docsite && python3 -m http.server 8099)   # 打开 http://127.0.0.1:8099/OrzMCApp/

用法：
    python3 scripts/dev/make-docs-landing.py <site-dir> --base-path /<Repo>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="让 DocC 站点根路径直接渲染文档首页")
    parser.add_argument("site", type=Path, help="transform-for-static-hosting 的输出目录")
    parser.add_argument("--base-path", required=True, help="托管基路径，例如 /OrzMCApp")
    parser.add_argument("--module", help="文档模块名（默认从 documentation/ 下自动取）")
    args = parser.parse_args()

    site: Path = args.site
    documentation = site / "documentation"
    if not documentation.is_dir():
        print(f"[docs-landing] 找不到 {documentation}（不是 DocC 站点？）", file=sys.stderr)
        return 1

    module = args.module
    if module is None:
        modules = sorted(p.name for p in documentation.iterdir() if p.is_dir())
        if not modules:
            print(f"[docs-landing] {documentation} 下没有模块目录", file=sys.stderr)
            return 1
        module = modules[0]

    source = documentation / module / "index.html"
    if not source.is_file():
        print(f"[docs-landing] 找不到 {source}", file=sys.stderr)
        return 1

    base = args.base_path.rstrip("/")
    page = source.read_text(encoding="utf-8")
    # SPA 需要文档首页的路径；放在 <head> 里、defer 的 DocC bundle 之前执行。
    shim = f'<script>history.replaceState(null, "", "{base}/documentation/{module}/");</script>'
    marker = "<head>"
    index = page.find(marker)
    if index < 0:
        print("[docs-landing] 文档首页没有 <head>，无法注入", file=sys.stderr)
        return 1

    landing = page[: index + len(marker)] + shim + page[index + len(marker) :]
    (site / "index.html").write_text(landing, encoding="utf-8")
    print(f"[docs-landing] 根路径 → {base}/documentation/{module}/（无跳转白屏）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
