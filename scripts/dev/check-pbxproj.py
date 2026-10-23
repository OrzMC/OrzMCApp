#!/usr/bin/env python3
"""校验 `OrzMC.xcodeproj/project.pbxproj` 是否登记了所有应用源文件。

为什么需要它：这个工程用的是**传统 PBXGroup（逐文件登记）**，不是 Xcode 16 的
同步文件夹。新增 `.swift` 文件后如果忘了登记：

* 本地增量构建**不会报错**（旧的目标文件还在，Swift 的按文件增量编译不会重编引用方），
* CI 若恰好命中缓存也可能绿，
* 但**干净构建会失败**，或者更糟——文件里的代码静默地没有被编译进去。

这个坑真实发生过两次（`ExarotonServerCard.swift`、`EscapeClosesWindow.swift`）。

用法：
    python3 scripts/dev/check-pbxproj.py            # 仓库根目录跑
退出码 1 表示有文件没登记。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "OrzMC.xcodeproj" / "project.pbxproj"

# 只检查应用目标下的源码目录（Tests / Sources 是 SwiftPM，自动收录）。
SOURCE_DIRS = [
    ROOT / "OrzMC",
]


def main() -> int:
    if not PROJECT.exists():
        print(f"[pbxproj] 找不到工程文件: {PROJECT}")
        return 2

    text = PROJECT.read_text(encoding="utf-8")

    missing: list[Path] = []
    for base in SOURCE_DIRS:
        for path in sorted(base.rglob("*.swift")):
            # 目录里以 `+` 或空格开头的边角情况不特殊处理；按文件名匹配登记项。
            if f"/* {path.name} */" not in text:
                missing.append(path.relative_to(ROOT))

    if missing:
        print("[pbxproj] 以下文件没有登记进 OrzMC.xcodeproj（干净构建会失败）：")
        for path in missing:
            print(f"  - {path}")
        print(
            "\n登记方法：在 Xcode 里把文件拖进对应分组（或手工加 PBXBuildFile /"
            " PBXFileReference / group children / Sources phase 四项）。"
        )
        return 1

    print("[pbxproj] 应用源文件全部已登记（OrzMC.xcodeproj）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
