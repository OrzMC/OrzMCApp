#!/usr/bin/env bash
# 真 socket 协议联调：起本地假 SLP / RCON 服务端，跑 LiveProbeSmokeTests，退出时清理。
#
# 为什么要有这一层：假字节流单测只覆盖协议细节，抓不到"SOCKET 分段 / 多字节 VarInt / 超时"
# 这类真实路径问题（VarInt 左移溢出就是真 socket 才暴露的）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SLP_PORT="${SLP_PORT:-25566}"
RCON_PORT="${RCON_PORT:-25575}"
PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

python3 "$ROOT/scripts/test-servers/slp_server.py" "$SLP_PORT" >/dev/null 2>&1 &
PIDS+=("$!")
python3 "$ROOT/scripts/test-servers/rcon_server.py" "$RCON_PORT" >/dev/null 2>&1 &
PIDS+=("$!")

# 等服务端起来（最多 5 秒）
for port in "$SLP_PORT" "$RCON_PORT"; do
  for _ in $(seq 1 50); do
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if ! nc -z 127.0.0.1 "$port" 2>/dev/null; then
    echo "test server on port $port did not start" >&2
    exit 1
  fi
done

cd "$ROOT"
ORZMC_LIVE_PROBE="127.0.0.1:$SLP_PORT" \
ORZMC_LIVE_RCON="127.0.0.1:$RCON_PORT:testpass" \
  swift test --filter 'LiveProbeSmokeTests'
