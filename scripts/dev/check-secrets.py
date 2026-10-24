#!/usr/bin/env python3
"""检查本地测试凭据有没有被写进版本库。

真实服务器地址 / RCON 密码 / exaroton Token 放在**未入库**的
`scripts/dev/uitest-secrets.env` 里。这个脚本把里面的值当成"敏感字面量"，
扫描所有**会被提交**的内容（已跟踪文件 + 暂存区），命中就退出码 1。

设计上的取舍：
* **不回显任何秘密**：只报"文件:行号"和值的长度/前缀哈希，够定位、不够泄露。
* 值太短（< 6 字符）或纯数字的不检查（端口、`1`/`0` 之类会误报）。
* 没有凭据文件时直接通过 —— 所以 CI 上是空操作，安全网只在本地生效。

用法：
    scripts/dev/check-secrets.py            # 扫描已跟踪文件 + 暂存区
    scripts/dev/check-secrets.py --staged   # 只扫暂存区（pre-commit 用）
"""

from __future__ import annotations

import argparse
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
    args = parser.parse_args()

    secrets = load_secrets()
    if not secrets:
        print("· 没有本地凭据文件，跳过秘密扫描")
        return 0

    hits: list[str] = []
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
