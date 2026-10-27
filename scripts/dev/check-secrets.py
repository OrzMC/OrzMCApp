#!/usr/bin/env python3
"""检查本地测试凭据有没有被写进版本库。

真实服务器地址 / RCON 密码 / exaroton Token 放在**未入库**的
`scripts/dev/uitest-secrets.env` 里。这个脚本把里面的值当成"敏感字面量"，
扫描所有**会被提交**的内容（已跟踪文件 + 暂存区），命中就退出码 1。

设计上的取舍：
* **不回显任何秘密**：只报"文件:行号"和值的长度/前缀哈希，够定位、不够泄露。
* 值太短（< 6 字符）或纯数字的不检查（端口、`1`/`0` 之类会误报）。
* 没有凭据文件时直接通过 —— 所以 CI 上是空操作，安全网只在本地生效。

只扫**新增内容**（暂存区的 + 还没进 origin/main 的提交），不扫整个仓库：
凭据的分布在历史上早就定了，推之前要防的是"这次改动把它带进来"。整库扫描还会被
项目自身的品牌词误伤（域名里就有一样的词）。

用法：
    scripts/dev/check-secrets.py            # 扫暂存区 + 未推送的提交（pre-push 用）
    scripts/dev/check-secrets.py --staged   # 只扫暂存区（pre-commit 用）
    scripts/dev/check-secrets.py --all      # 整库审计（人工用，会有误报）
"""

from __future__ import annotations

import argparse
import re
import hashlib
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SECRETS = ROOT / "scripts/dev/uitest-secrets.env"
# 这些文件里出现值是正常的（模板本身没有真值，防止误伤）
EXEMPT = {
    "scripts/dev/uitest-secrets.env",
    "scripts/dev/uitest-secrets.example.env",
    "scripts/dev/check-secrets.py",
}


def load_secrets() -> dict[str, str]:
    if not SECRETS.is_file():
        return {}
    secrets: dict[str, str] = {}
    for raw in SECRETS.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip().strip('"').strip("'")
        # 太短/纯数字的值（端口、开关）不当秘密，避免满屏误报
        if len(value) < 6 or value.isdigit():
            continue
        secrets[key.strip()] = value
    return secrets


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    ).stdout


def added_lines(staged_only: bool) -> list[tuple[str, int, str]]:
    """返回 (文件名, 行号, 内容) —— 只取**新增**的文本行。"""
    ranges = ["--cached"] if staged_only else ["--cached"]
    if not staged_only:
        # 还没推到 origin/main 的提交也算"新增"
        base = git("rev-parse", "--verify", "origin/main").strip()
        if base:
            ranges += [f"{base}...HEAD"]
    seen: dict[tuple[str, int], str] = {}
    for spec in ranges:
        diff = git("diff", "-U0", spec, "--no-color", "--no-ext-diff")
        path = ""
        line_no = 0
        for raw in diff.splitlines():
            if raw.startswith("+++ b/"):
                path = raw[6:]
            elif raw.startswith("@@"):
                # @@ -a,b +c,d @@
                plus = raw.split("+")[1].split("@@")[0].strip()
                start = plus.split(",")[0]
                line_no = int(start) - 1
            elif raw.startswith("+") and not raw.startswith("+++"):
                line_no += 1
                if path:
                    seen[(path, line_no)] = raw[1:]
            elif raw.startswith("-"):
                continue
    return [(path, number, text) for (path, number), text in sorted(seen.items())]


def candidate_files(staged_only: bool) -> list[Path]:
    names: set[str] = set()
    if not staged_only:
        names.update(n for n in git("ls-files").splitlines() if n)
    names.update(n for n in git("diff", "--cached", "--name-only").splitlines() if n)
    files = []
    for name in sorted(names):
        if name in EXEMPT:
            continue
        path = ROOT / name
        if not path.is_file() or path.is_symlink():
            continue
        # 二进制/大文件跳过
        if path.stat().st_size > 2_000_000:
            continue
        files.append(path)
    return files


def hint(value: str) -> str:
    digest = hashlib.sha256(value.encode()).hexdigest()[:8]
    return f"len={len(value)} sha8={digest}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--staged", action="store_true", help="只扫暂存区（pre-commit 用）")
    parser.add_argument("--all", action="store_true", help="整库审计（会被品牌词误伤）")
    args = parser.parse_args()

    secrets = load_secrets()
    if not secrets:
        print("· 没有本地凭据文件，跳过秘密扫描")
        return 0

    hits: list[str] = []
    if not args.all:
        for path, line_number, text in added_lines(args.staged):
            if path in EXEMPT:
                continue
            for key, value in secrets.items():
                # 用**词边界**匹配：短口令（如 `jokerhub`）常常是域名/主机名的一部分
                # （`mcs.jokerhub.cn`），按子串匹配会一直误报，误报多了这个检查就没人看了。
                # 真正的口令是独立 token，加了边界照样能抓。
                pattern = r"(?<![A-Za-z0-9_.-])" + re.escape(value) + r"(?![A-Za-z0-9_.-])"
                if re.search(pattern, text):
                    hits.append(f"{path}:{line_number} 命中 {key}（{hint(value)}）")
        if hits:
            print("✗ 检测到本地测试凭据出现在**本次新增**的内容里：", file=sys.stderr)
            for item in hits:
                print(f"  {item}", file=sys.stderr)
            print(
                "\n处理方式：把这几行改成从环境变量读取，或删除；"
                "如果已经推送过，立刻在服务端轮换凭据（改 RCON 密码 / 重置 Token）。",
                file=sys.stderr,
            )
            return 1
        print(f"✓ 新增内容里没有凭据（检查 {len(secrets)} 个值）")
        return 0

    for path in candidate_files(args.staged):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for line_number, line in enumerate(text.splitlines(), start=1):
            for key, value in secrets.items():
                if value in line:
                    hits.append(
                        f"{path.relative_to(ROOT)}:{line_number} 命中 {key}（{hint(value)}）"
                    )

    if hits:
        print("✗ 检测到本地测试凭据出现在将提交的内容里：", file=sys.stderr)
        for item in hits:
            print(f"  {item}", file=sys.stderr)
        print(
            "\n处理方式：把这几行改成从环境变量读取，或删除；"
            "如果已经推送过，立刻在服务端轮换凭据（改 RCON 密码 / 重置 Token）。",
            file=sys.stderr,
        )
        return 1

    print(f"✓ 未发现凭据泄露（扫描 {len(secrets)} 个值）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
