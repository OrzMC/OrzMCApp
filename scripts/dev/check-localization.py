#!/usr/bin/env python3
"""校验应用里用到的界面文案都有简体中文翻译（`Localizable.xcstrings`）。

为什么需要它：本项目的界面文案**必须**同时提供 `zh-Hans`（产品默认语言是中文，
英文是回退）。漏一条不会编译失败、也不会在英文界面下暴露，只有切到中文才看到一句英文。

检查范围：`OrzMC/` 下常见的文案入口 —— `Text(...)` / `Button(...)` / `Label(...)` /
`Section(...)` / `Toggle(...)` / `LabeledContent(...)` / `.help(...)` /
`accessibilityLabel(...)` / `confirmationDialog(...)` / `.alert(...)` / `String(localized:)`。

约定与例外：
* 带插值的字面量（`"\\(..)"`）跳过：它们在 xcstrings 里的键是 `%@/%lld` 形式，静态文本匹配不了。
* 纯符号/占位（没有连续 3 个以上字母）跳过。
* 已知不翻译的项写在 `ALLOWLIST`（精确匹配键）。

用法：
    python3 scripts/dev/check-localization.py
退出码 1 表示有缺失。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STRINGS = ROOT / "OrzMC" / "Common" / "Localizable.xcstrings"
SOURCE_ROOT = ROOT / "OrzMC"

PATTERNS = [
    r'Text\("([^"]{3,})"\)',
    r'Button\("([^"]{3,})"',
    r'Label\("([^"]{3,})"',
    r'Section\("([^"]{3,})"\)',
    r'Toggle\("([^"]{3,})"',
    r'LabeledContent\("([^"]{3,})"\)',
    r'TextField\("([^"]{3,})"',
    r'\.help\("([^"]{5,})"\)',
    r'accessibilityLabel\("([^"]{3,})"\)',
    r'confirmationDialog\(\s*"([^"]{3,})"',
    r'\.alert\(\s*"([^"]{3,})"',
    r'String\(localized: "([^"]{3,})"\)',
    r'Picker\("([^"]{3,})"',
    r'Menu\("([^"]{3,})"',
]

# 明确不翻译的（专有名词 / 与语言无关）。精确匹配。
ALLOWLIST = {
    "OrzMC",
    "Java",
    "Paper",
    "Vanilla",
    "Fabric",
    "Forge",
    "Modrinth",
    "GitHub",
    "exaroton",
    "Exaroton",
    "RCON",
    "MOTD",
    "OP",
    "Token",
    "TOKEN",
    "macOS",
    "iOS",
}


def collect_keys(source: str) -> set[str]:
    keys: set[str] = set()
    for pattern in PATTERNS:
        for match in re.finditer(pattern, source):
            key = match.group(1)
            if "\\(" in key:          # 带插值：键在 xcstrings 里是 %@ / %lld，跳过
                continue
            if not re.search(r"[A-Za-z]{3,}", key):
                continue
            keys.add(key)
    return keys


def main() -> int:
    if not STRINGS.exists():
        print(f"[i18n] 找不到 {STRINGS}")
        return 2

    data = json.loads(STRINGS.read_text(encoding="utf-8"))
    entries = data.get("strings", {})

    missing: dict[str, list[str]] = {}
    for path in sorted(SOURCE_ROOT.rglob("*.swift")):
        for key in collect_keys(path.read_text(encoding="utf-8")):
            if key in ALLOWLIST:
                continue
            localized = entries.get(key, {}).get("localizations", {})
            if "zh-Hans" not in localized:
                missing.setdefault(key, []).append(str(path.relative_to(ROOT)))

    if missing:
        print("[i18n] 以下文案缺少 zh-Hans 翻译（Localizable.xcstrings）：")
        for key, files in sorted(missing.items()):
            print(f'  - "{key}"   ({files[0]})')
        print(f"\n共 {len(missing)} 条。补法：在 xcstrings 里加 zh-Hans 字符串单元。")
        return 1

    print("[i18n] 界面文案的中文翻译齐全")
    return 0


if __name__ == "__main__":
    sys.exit(main())
