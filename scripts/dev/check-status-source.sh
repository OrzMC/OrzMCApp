#!/usr/bin/env bash
# 远程服务器状态必须只有一个来源（见 docs/remote-status-source.md）。
#
# 界面里直接读 `server.serverStatus` 会绕过 WebSocket 推送 → 和详情页不一致
# （真机反馈过"进详情页像自动启动服务器"）。这里把这类写法在 CI 挡住。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# 允许出现的地方：
#   Extension/ExarotonAPI+.swift —— `serverStatus` 的定义
#   Model/ —— 模型内部（含 effectiveStatus 的实现）
#   ExarotonServerView —— `status ?? server.serverStatus` 那个兜底（调用方没传状态时）
#   Tests/ OrzMCTests/ —— 测试
offenders="$(grep -rn --include='*.swift' '\.serverStatus' OrzMC Sources 2>/dev/null \
  | grep -v 'Extension/ExarotonAPI+.swift' \
  | grep -v '/Model/' \
  | grep -v 'effectiveStatus' \
  | grep -v 'status ?? server.serverStatus' \
  || true)"

if [[ -n "$offenders" ]]; then
  echo "✗ 远程状态必须走 model.effectiveStatus(for:)，不要直接读 server.serverStatus：" >&2
  echo "$offenders" >&2
  echo "  原因见 docs/remote-status-source.md" >&2
  exit 1
fi

echo "✓ 远程状态来源统一"
