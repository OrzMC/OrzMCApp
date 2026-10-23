#!/usr/bin/env bash
# 真机验收「我的服务器」：给本机 Minecraft 服务端打开 RCON，然后跑 SLP + RCON 全量检查。
#
# 为什么需要它：App 侧的逻辑已有假服务端单测，但"真服务端到底回什么"只能实测
# （比如 `whitelist list` / `banlist list` 的措辞各核心不同）。
#
# 用法：
#   ./scripts/dev/accept-real-server.sh                  # 自动挑最新版本目录，只做检查（不改配置）
#   ./scripts/dev/accept-real-server.sh --patch           # 需要时补上 enable-rcon / rcon.port / rcon.password（先备份）
#   ./scripts/dev/accept-real-server.sh --version 26.3 --patch --wait 180
#
# 行为约定（安全）：
#  * **不启动、不停止**服务端；改配置一律先备份为 `server.properties.bak.<时间戳>`；
#  * `--wait N` 只是"等服务端起来并加载完"，最多等 N 秒；
#  * 密码默认沿用已有的 `rcon.password`，没有就生成一个随机串并打印出来。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GAME_ROOT="${GAME_ROOT:-$HOME/minecraft}"
VERSION=""
PATCH=0
WAIT=0
RCON_PORT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?}"; shift 2 ;;
    --root) GAME_ROOT="${2:?}"; shift 2 ;;
    --patch) PATCH=1; shift ;;
    --wait) WAIT="${2:?}"; shift 2 ;;
    --rcon-port) RCON_PORT_OVERRIDE="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

# 找版本目录：挑带 server/server.properties 的那个（多个时取最新修改时间）
if [[ -z "$VERSION" ]]; then
  VERSION="$(ls -1 "$GAME_ROOT/versions" 2>/dev/null | while read -r v; do
      [[ -f "$GAME_ROOT/versions/$v/server/server.properties" ]] && echo "$v"
    done | tail -1)"
fi
[[ -n "$VERSION" ]] || { echo "✗ 在 $GAME_ROOT/versions 下没找到带 server.properties 的服务端目录" >&2; exit 1; }

PROPS="$GAME_ROOT/versions/$VERSION/server/server.properties"
[[ -f "$PROPS" ]] || { echo "✗ 找不到 $PROPS" >&2; exit 1; }

echo "服务端: $PROPS"
CURRENT_ENABLE="$(grep -E '^enable-rcon=' "$PROPS" | tail -1 | cut -d= -f2- || true)"
CURRENT_PORT="$(grep -E '^rcon\.port=' "$PROPS" | tail -1 | cut -d= -f2- || true)"
CURRENT_PASSWORD="$(grep -E '^rcon\.password=' "$PROPS" | tail -1 | cut -d= -f2- || true)"
SERVER_PORT="$(grep -E '^server-port=' "$PROPS" | tail -1 | cut -d= -f2- || echo 25565)"
echo "  当前: enable-rcon=${CURRENT_ENABLE:-<未设置>} rcon.port=${CURRENT_PORT:-<未设置>} rcon.password=${CURRENT_PASSWORD:+<已设置>}${CURRENT_PASSWORD:-<未设置>} server-port=$SERVER_PORT"

if [[ "$PATCH" == "1" ]]; then
  BACKUP="$PROPS.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$PROPS" "$BACKUP"
  echo "  已备份: $BACKUP"

  PORT="${RCON_PORT_OVERRIDE:-${CURRENT_PORT:-25575}}"
  PASSWORD="$CURRENT_PASSWORD"
  if [[ -z "$PASSWORD" ]]; then
    PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || true)"
    [[ -n "$PASSWORD" ]] || PASSWORD="orzmc-$(date +%s)"
  fi

  python3 - "$PROPS" "$PORT" "$PASSWORD" <<'PY'
import sys
from pathlib import Path

path, port, password = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
wanted = {
    "enable-rcon": "true",
    "rcon.port": port,
    "rcon.password": password,
    "broadcast-rcon-to-ops": "true",
}
lines = path.read_text(encoding="utf-8").splitlines()
seen = set()
out = []
for line in lines:
    key = line.split("=", 1)[0].strip() if "=" in line and not line.lstrip().startswith("#") else None
    if key in wanted:
        out.append(f"{key}={wanted[key]}")
        seen.add(key)
    else:
        out.append(line)
for key, value in wanted.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
print(f"  已写入: enable-rcon=true rcon.port={port} rcon.password={password}")
PY
  CURRENT_PASSWORD="$PASSWORD"
  CURRENT_PORT="$PORT"
  echo
  echo "→ 现在重启服务端（配置改动只在启动时生效）："
  echo "   在 OrzMC 里选中 $VERSION → 「重启服务器」，或你自己的启动方式。"
  echo "   起来后再跑： $0 --version $VERSION --wait 240"
  if [[ "$WAIT" == "0" ]]; then
    echo
    echo "（本次只改了配置。加 --wait N 可以在服务端起来后自动跑检查。）"
    exit 0
  fi
fi

PASSWORD="${CURRENT_PASSWORD:-}"
PORT="${RCON_PORT_OVERRIDE:-${CURRENT_PORT:-25575}}"

wait_for() {
  local host="$1" port="$2" seconds="$3" label="$4"
  local deadline=$(( $(date +%s) + seconds ))
  while [[ $(date +%s) -lt $deadline ]]; do
    if nc -z -G 2 "$host" "$port" 2>/dev/null; then
      echo "  ✓ ${label} 已就绪（${host}:${port}）"
      return 0
    fi
    sleep 3
  done
  echo "  ✗ 等 ${label} 超时（${host}:${port}，${seconds}s）" >&2
  return 1
}

if [[ "$WAIT" != "0" ]]; then
  echo
  echo "→ 等待服务端起来（最多 ${WAIT}s）…"
  wait_for 127.0.0.1 "$SERVER_PORT" "$WAIT" "游戏端口" || exit 1
  wait_for 127.0.0.1 "$PORT" 60 "RCON 端口" || {
    echo "  RCON 没起来：确认 enable-rcon=true 且服务端已重启（改配置需重启）。" >&2
    exit 1
  }
fi

echo
if [[ -z "$PASSWORD" ]]; then
  echo "→ 只做 SLP 检查（没有 rcon.password；加 --patch 可自动补齐）"
  exec python3 "$ROOT/scripts/dev/verify-real-server.py" --host 127.0.0.1 --port "$SERVER_PORT" --skip-rcon
fi

exec python3 "$ROOT/scripts/dev/verify-real-server.py" \
  --host 127.0.0.1 --port "$SERVER_PORT" --rcon-port "$PORT" --password "$PASSWORD"
