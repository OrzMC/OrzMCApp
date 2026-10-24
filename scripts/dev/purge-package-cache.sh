#!/usr/bin/env bash
# 清掉 SwiftPM 里某个包的本地缓存（repositories + checkouts）。
#
# 为什么需要：升级 Package.resolved 里钉住的 revision 后，旧的 bare repo 缓存里没有新提交，
# Xcode 会报 `Couldn’t check out revision …: fatal: unable to read tree` —— 每次都要手动找缓存目录。
#
# 用法：scripts/dev/purge-package-cache.sh ExarotonAPI
set -euo pipefail

name="${1:?用法: purge-package-cache.sh <包名，如 ExarotonAPI>}"

shopt -s nullglob
paths=(
  "$HOME/Library/Caches/org.swift.swiftpm/repositories/${name}"-*
  "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/repositories/"${name}"-*
  "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/"${name}"
)

removed=0
for path in "${paths[@]}"; do
  rm -rf "$path"
  removed=$((removed + 1))
done

echo "✓ 已清理 ${name} 的 ${removed} 处本地缓存（下次构建会重新拉取）"
