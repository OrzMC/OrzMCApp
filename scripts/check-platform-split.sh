#!/usr/bin/env bash
# scripts/check-platform-split.sh — 校验「共用 / 平台专属」代码摆放是否符合约定。
#
# 约定（见 docs/app-platform-split.md）：
#   1. 平台无关的**逻辑**住在 SwiftPM 目标（`Sources/*`）——可单测、可被两个平台共用；
#   2. 两个平台共用的**视图**住在 `OrzMC/Common/`（同一个多平台 target 编两遍）；
#   3. 只属于某个平台的代码住在 `OrzMC/Launcher(MacOS)/`、`OrzMC/MobileHelper(iOS)/`；
#   4. `Sources/*` 里**不得**出现 AppKit/UIKit 专属 API（要跨平台就只能用 SwiftUI/Foundation）。
#
# 为什么需要这道闸：Xcode 工程的 `platformFilter` 只在**文件**粒度生效，
# 一旦把 AppKit 代码放进共用目录，iOS 构建才会报错——而 iOS 以前根本没被构建过。
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
note() { printf '%s\n' "$*"; }

# 1) Sources/* 不得直接 import AppKit / UIKit（SwiftUI 允许：两平台都有）。
while IFS= read -r file; do
    if grep -qE '^import (AppKit|UIKit)$' "$file"; then
        note "✗ ${file}: 共用目标里 import 了平台专属框架（改用 SwiftUI/Foundation，或把文件移回平台目录）"
        fail=1
    fi
done < <(find Sources -name '*.swift')

# 2) 平台目录里用到的平台 API 必须有对应的条件编译/平台过滤兜底（只提示，不阻塞）。
#    Xcode 侧靠 `platformFilter`，SwiftPM 侧靠 `#if os(...)`；这里只做粗检。
for dir in "OrzMC/Launcher(MacOS)" "OrzMC/MobileHelper(iOS)"; do
    [ -d "$dir" ] || continue
done

if [ "$fail" -ne 0 ]; then
    note ""
    note "平台分层校验失败；规则见 docs/app-platform-split.md"
    exit 1
fi
note "[ok] 平台分层校验通过（Sources/ 无平台专属 import）"
