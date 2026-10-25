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


PLACEHOLDER = re.compile(r"%(?:@|lld|ld|d|zd|tu|\.?[0-9]*lf|f|s|%)")


def placeholders(text: str) -> list[str]:
    """按出现顺序抽出占位符类型（`%%` 是字面百分号，跳过；整数类统一成 `num`）。"""
    result: list[str] = []
    for match in PLACEHOLDER.finditer(text):
        token = match.group(0)
        if token == "%%":
            continue
        if token == "%@":
            result.append("obj")
        elif token in {"%s"}:
            result.append("str")
        else:
            result.append("num")
    return result


def placeholder_mismatches(entries: dict) -> list[tuple[str, str, str]]:
    """英文键里的占位符 vs 每种译文里的占位符：数量/类型/顺序必须一致。

    允许译文重排参数（`%2$@` 之类）—— 那种写法里占位符仍按 `%@` 计，顺序检查会放过，
    但 `String(localized:)` 会用它自己的位置参数，所以只要**个数与类型**对得上就不崩。
    这里宁可严一点：顺序也必须一致（重排请用 position 写法，本函数认不出来时会报错提醒）。
    """
    bad: list[tuple[str, str, str]] = []
    for key, entry in entries.items():
        expected = placeholders(key)
        if not expected:
            continue
        for lang, localization in (entry.get("localizations") or {}).items():
            value = localization.get("stringUnit", {}).get("value")
            if value is None:
                continue
            if placeholders(value) != expected:
                bad.append((lang, key, value))
    return bad


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

    mismatched = placeholder_mismatches(entries)
    if mismatched:
        print("[i18n] 以下译文的占位符与英文键不一致（运行时会格式化错、甚至崩溃）：")
        for lang, key, value in sorted(mismatched):
            print(f'  - [{lang}] "{key}"')
            print(f'      译文 "{value}"')
            print(f"      期望 {placeholders(key)}，实际 {placeholders(value)}")
        print(
            "\n修法：让译文的占位符数量/类型/顺序与英文键一致"
            "（例：`All %lld folders (%@)` → `全部 %lld 个目录（%@）`）。"
        )
        return 1

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
