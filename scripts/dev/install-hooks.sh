#!/usr/bin/env bash
# 安装本仓库的 git 钩子（每个 clone 各装一次；钩子不入版本库）。
#
#   ./scripts/dev/install-hooks.sh          # 安装/更新
#   ./scripts/dev/install-hooks.sh --check  # 只检查是否已安装
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

HOOKS_DIR="$(git rev-parse --git-path hooks)"
SRC="$ROOT/scripts/dev/git-hooks"

if [ "${1:-}" = "--check" ]; then
  status=0
  for hook in "$SRC"/*; do
    name="$(basename "$hook")"
    if [ -f "$HOOKS_DIR/$name" ] && cmp -s "$hook" "$HOOKS_DIR/$name"; then
      echo "[hooks] ✓ $name"
    else
      echo "[hooks] ✗ $name（未安装或已过期，跑 ./scripts/dev/install-hooks.sh）"
      status=1
    fi
  done
  exit $status
fi

mkdir -p "$HOOKS_DIR"
for hook in "$SRC"/*; do
  name="$(basename "$hook")"
  install -m 755 "$hook" "$HOOKS_DIR/$name"
  echo "[hooks] 已安装 $name → $HOOKS_DIR/$name"
done

echo "[hooks] 完成。逃生阀：SKIP_PREPUSH=1 git push；完整门禁：PREPUSH_FULL=1 git push"
