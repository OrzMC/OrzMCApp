#!/usr/bin/env bash
# 让某个 SwiftPM 包的新版本（tag / 新提交）能被立刻解析到 —— **不用重新克隆**。
#
# 为什么需要（2026-10-26 实测，一次迭代里踩了 4 次）：
#   把 `Package.resolved` 里钉的版本升上去之后，Xcode 常常报
#       fatalError: Couldn’t check out revision '<sha>'
#   原因是**缓存里的 bare repo 没有那个新提交/新 tag**（各个 DerivedData 各有一份缓存）。
#   过去只能：手动找缓存目录 → `git fetch --tags` → 删 checkouts → 重跑，
#   而现在这一条命令全做完（4 个 DerivedData 目录 + 全局 SwiftPM 缓存一起处理）。
#
# 用法：
#   scripts/dev/refresh-package.sh MCSManagerAPI          # 增量：fetch tags + 删 checkout（秒级）
#   scripts/dev/refresh-package.sh MCSManagerAPI --purge  # 彻底：连 bare repo 一起删（慢，会重新克隆）
#   scripts/dev/refresh-package.sh --all                  # 对所有已知本地包做一遍
#
# 与 `purge-package-cache.sh` 的区别：那个是"彻底删"，这个是"就地刷新"，不会丢掉已有对象。
set -euo pipefail

DERIVED_DATA_GLOB=("$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages)
GLOBAL_REPOS=("$HOME"/Library/Caches/org.swift.swiftpm/repositories)

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

PURGE=0
NAME=""
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        --all) NAME="--all" ;;
        -h|--help) usage 0 ;;
        -*) echo "未知参数：$arg" >&2; usage 1 ;;
        *) NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || usage 1

shopt -s nullglob

# 所有已知包名（取 repositories/<name>-<hash> 里 `-` 前面的部分）。
known_packages() {
    local dir
    for dir in "${DERIVED_DATA_GLOB[@]}" "${GLOBAL_REPOS[@]}"; do
        [ -d "$dir" ] || continue
        for repo in "$dir"/repositories/*; do
            [ -d "$repo" ] || continue
            basename "$repo" | sed -E 's/-[0-9a-f]+$//'
        done
    done | sort -u
}

refresh_one() {
    local name="$1" fetched=0 dropped=0
    local repo
    for dir in "${DERIVED_DATA_GLOB[@]}" "${GLOBAL_REPOS[@]}"; do
        [ -d "$dir" ] || continue
        for repo in "$dir/repositories/${name}"-*; do
            [ -d "$repo" ] || continue
            if [ "$PURGE" -eq 1 ]; then
                rm -rf "$repo"
                dropped=$((dropped + 1))
            elif git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
                # 只 fetch tags（+ prune）：几秒，且不动已有对象。
                git -C "$repo" fetch --tags --prune --quiet origin 2>/dev/null || true
                fetched=$((fetched + 1))
            fi
        done
        # checkout 必须删掉：Xcode 会按新的 resolved 版本重新 checkout。
        for co in "$dir/checkouts/${name}"; do
            [ -d "$co" ] && { rm -rf "$co"; dropped=$((dropped + 1)); }
        done
    done

    if [ "$PURGE" -eq 1 ]; then
        echo "✓ ${name}：已彻底清理（删了 ${dropped} 处 bare repo / checkout，下次会重新克隆）"
    else
        echo "✓ ${name}：已刷新 ${fetched} 个 bare repo 的 tags，删了 ${dropped} 处 checkout（下次构建重新 checkout）"
    fi
}

if [ "$NAME" = "--all" ]; then
    mapfile -t names < <(known_packages)
    [ "${#names[@]}" -gt 0 ] || { echo "没找到任何本地 SwiftPM 缓存" >&2; exit 1; }
    echo "共 ${#names[@]} 个包：${names[*]}"
    for name in "${names[@]}"; do refresh_one "$name"; done
else
    refresh_one "$NAME"
fi

echo
echo "接着重跑构建即可；若仍报 Couldn't check out revision，用 --purge 彻底清一次。"
