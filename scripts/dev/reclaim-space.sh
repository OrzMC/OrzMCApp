#!/usr/bin/env bash
# 回收 Xcode DerivedData 里 OrzMC 的构建残留（磁盘卫生）。
#
# 为什么需要：本机 `~/Library/Developer/Xcode/DerivedData` 一度涨到 **13 GB / 60+ 个 `OrzMC-*` 目录**
# （每次临时 `-derivedDataPath` 实验都会留一个），2026-10-26 真的撞到 `No space left on device`，
# 表现是"构建失败但没有任何编译错误"，整次签名构建报废。
#
# **默认只打印、不删除**（dry-run）；加 `--apply` 才真删。
#
# 用法：
#   scripts/dev/reclaim-space.sh                        # 看清单（dry-run）
#   scripts/dev/reclaim-space.sh --apply                # 保最新 2 个、删 3 天没动过的
#   scripts/dev/reclaim-space.sh --apply --keep 1 --older-than 1
set -euo pipefail

ROOT="$HOME/Library/Developer/Xcode/DerivedData"
KEEP=2
DAYS=3
APPLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --keep) KEEP="${2:?}"; shift 2 ;;
        --older-than) DAYS="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

[[ -d "$ROOT" ]] || { echo "没有 $ROOT"; exit 0; }

# 按最近修改时间排序的所有 OrzMC-* 目录（保留最新 $KEEP 个）。
mapfile -t all < <(find "$ROOT" -maxdepth 1 -type d -name 'OrzMC-*' -exec stat -f '%m %N' {} + \
    | sort -rn | awk '{print $2}')

if [[ "${#all[@]}" -eq 0 ]]; then
    echo "没有 OrzMC-* 目录（干净）"
    exit 0
fi

total_all="$(du -sk "${all[@]}" 2>/dev/null | awk '{s+=$1} END {print int(s/1024)}')"
echo "共 ${#all[@]} 个 OrzMC-* 目录，合计 ${total_all} MB："
index=0
to_delete=()
for dir in "${all[@]}"; do
    index=$((index + 1))
    size_mb="$(du -sk "$dir" 2>/dev/null | awk '{print int($1/1024)}')"
    age_days="$(( ( $(date +%s) - $(stat -f %m "$dir") ) / 86400 ))"
    if [[ "$index" -le "$KEEP" ]]; then
        printf '  \033[32m保留\033[0m %-42s %6s MB  %s 天前\n' "$(basename "$dir")" "$size_mb" "$age_days"
    elif [[ "$age_days" -ge "$DAYS" ]]; then
        printf '  \033[33m候选\033[0m %-42s %6s MB  %s 天前\n' "$(basename "$dir")" "$size_mb" "$age_days"
        to_delete+=("$dir")
    else
        printf '  \033[32m保留\033[0m %-42s %6s MB  %s 天前（还很新）\n' "$(basename "$dir")" "$size_mb" "$age_days"
    fi
done

if [[ "${#to_delete[@]}" -eq 0 ]]; then
    echo "没有可清理的目录（都还新，或用 --older-than 放宽）"
    exit 0
fi

reclaim="$(du -sk "${to_delete[@]}" 2>/dev/null | awk '{s+=$1} END {print int(s/1024)}')"
echo
if [[ "$APPLY" -eq 0 ]]; then
    echo "（dry-run）可回收约 ${reclaim} MB。真删：scripts/dev/reclaim-space.sh --apply"
    exit 0
fi

for dir in "${to_delete[@]}"; do
    rm -rf "$dir"
done
echo "✓ 已删除 ${#to_delete[@]} 个目录，回收约 ${reclaim} MB"
echo "  剩余：$(df -h "$HOME" | awk 'NR==2 {print $4}') 可用"
