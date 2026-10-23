#!/usr/bin/env python3
"""对着**真实** Minecraft 服务端验收「我的服务器」用的两件事（不依赖 App）：

1. Server List Ping：状态是否可解析（版本 / 玩家 / MOTD / 延迟）；
2. RCON：密码能否登录、`list` / `whitelist list` / `banlist list` 是否可解析。

用途：App 侧的逻辑与假服务端已覆盖，但"真服务端的措辞到底长什么样"只能实测。
本脚本刻意把**原始回复**也打印出来，便于发现解析器需要兼容的新格式。

用法：
    python3 scripts/dev/verify-real-server.py --host 127.0.0.1 --port 25565
    python3 scripts/dev/verify-real-server.py --host 127.0.0.1 --port 25565 \
        --rcon-port 25575 --password <rcon.password>

退出码：0 = 全部通过；1 = 有失败项。
"""

from __future__ import annotations

import argparse
import json
import socket
import struct
import sys
import time

# ---------------------------------------------------------------- 打包工具


def varint(value: int) -> bytes:
    value &= 0xFFFFFFFF
    out = b""
    while True:
        byte = value & 0x7F
        value >>= 7
        out += bytes([byte | 0x80]) if value else bytes([byte])
        if not value:
            return out


def read_varint(sock: socket.socket) -> int:
    value = shift = 0
    while True:
        chunk = sock.recv(1)
        if not chunk:
            raise ConnectionError("连接被对端关闭")
        byte = chunk[0]
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value
        shift += 7
        if shift > 28:
            raise ValueError("VarInt 过长")


def read_exactly(sock: socket.socket, count: int) -> bytes:
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise ConnectionError("连接被对端关闭")
        data += chunk
    return data


# ---------------------------------------------------------------- SLP


def slp_status(host: str, port: int, timeout: float = 6.0) -> dict:
    with socket.create_connection((host, port), timeout=timeout) as sock:
        host_bytes = host.encode()
        payload = (
            varint(0x00)
            + varint(-1)                     # protocol version（-1 = 只要状态）
            + varint(len(host_bytes)) + host_bytes
            + struct.pack(">H", port)
            + varint(1)                      # next state = status
        )
        sock.sendall(varint(len(payload)) + payload)
        sock.sendall(varint(1) + varint(0x00))

        length = read_varint(sock)
        body = read_exactly(sock, length)
        packet_id = body[0]
        assert packet_id == 0x00, f"意外的 packet id: {packet_id:#x}"
        rest = body[1:]
        text_len = 0
        shift = 0
        index = 0
        while True:
            byte = rest[index]
            index += 1
            text_len |= (byte & 0x7F) << shift
            if not byte & 0x80:
                break
            shift += 7
        return json.loads(rest[index:index + text_len].decode("utf-8"))

    # 时间为 ping 测速
    # （故意不复用连接，真实客户端也是一次连接完成 status + ping）


def slp_ping(host: str, port: int, timeout: float = 6.0) -> int:
    with socket.create_connection((host, port), timeout=timeout) as sock:
        host_bytes = host.encode()
        payload = (
            varint(0x00) + varint(-1)
            + varint(len(host_bytes)) + host_bytes
            + struct.pack(">H", port) + varint(1)
        )
        sock.sendall(varint(len(payload)) + payload)
        sock.sendall(varint(1) + varint(0x00))
        read_exactly(sock, read_varint(sock))          # 丢掉 status

        ping = varint(0x01) + struct.pack(">q", 0x7FFFFFFFFFFFFFFF)
        started = time.time()
        sock.sendall(varint(len(ping)) + ping)
        read_exactly(sock, read_varint(sock))
        return int((time.time() - started) * 1000)


# ---------------------------------------------------------------- RCON


def rcon_packet(request_id: int, kind: int, body: str) -> bytes:
    payload = struct.pack("<ii", request_id, kind) + body.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", len(payload)) + payload


def rcon_read(sock: socket.socket) -> tuple[int, int, str]:
    length = struct.unpack("<i", read_exactly(sock, 4))[0]
    data = read_exactly(sock, length)
    request_id, kind = struct.unpack("<ii", data[:8])
    body = data[8:].split(b"\x00")[0].decode("utf-8", "replace")
    return request_id, kind, body


def rcon(host: str, port: int, password: str, command: str, timeout: float = 6.0) -> str:
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.sendall(rcon_packet(1, 3, password))
        rid, kind, _ = rcon_read(sock)
        if rid == -1 or kind != 2:
            raise PermissionError("RCON 密码被拒绝")

        sock.sendall(rcon_packet(2, 2, command))
        chunks: list[str] = []
        while True:
            try:
                _, kind, body = rcon_read(sock)
            except (ConnectionError, struct.error):
                break
            if kind != 0:
                break
            if body:
                chunks.append(body)
            # 多包响应：稍等一下看还有没有
            sock.settimeout(0.2)
            try:
                sock.recv(1, socket.MSG_PEEK)
            except (TimeoutError, socket.timeout):
                break
            finally:
                sock.settimeout(timeout)
        return "\n".join(chunks)


# ---------------------------------------------------------------- 解析（与 App 里一致）


def names_after_colon(reply: str) -> list[str]:
    text = reply.strip()
    if ":" not in text:
        return []
    tail = text.split(":", 1)[1].strip()
    if not tail:
        return []
    result = []
    for entry in tail.replace("\r", "").split(","):
        name = entry.split("(")[0].strip()
        if name and name not in {"-", "none"}:
            result.append(name)
    return result


# ---------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description="真实服务端验收：SLP + RCON")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=25565)
    parser.add_argument("--rcon-port", type=int)
    parser.add_argument("--password")
    parser.add_argument("--skip-rcon", action="store_true")
    args = parser.parse_args()

    failures = 0

    print(f"=== SLP {args.host}:{args.port}")
    try:
        status = slp_status(args.host, args.port)
        latency = slp_ping(args.host, args.port)
        version = status.get("version", {}).get("name")
        players = status.get("players", {})
        print(f"  版本: {version}   协议: {status.get('version', {}).get('protocol')}")
        print(f"  玩家: {players.get('online')}/{players.get('max')}   延迟: {latency} ms")
        description = status.get("description")
        print(f"  MOTD: {json.dumps(description, ensure_ascii=False)[:120]}")
        sample = players.get("sample") or []
        if sample:
            print(f"  在线名单(sample): {', '.join(p.get('name', '?') for p in sample)}")
        else:
            print("  在线名单(sample): 服务端未提供（App 会退回到 RCON 的 list）")
    except Exception as exc:                      # noqa: BLE001 - 验收脚本，报错即可
        print(f"  ✗ 失败: {exc}")
        failures += 1

    if args.skip_rcon:
        return 1 if failures else 0

    print(f"\n=== RCON {args.host}:{args.rcon_port or 25575}")
    if not args.rcon_port or not args.password:
        print("  ⚠️  未提供 --rcon-port / --password，跳过 RCON 检查")
        print("      （server.properties 里需要 enable-rcon=true、rcon.port、rcon.password）")
        return 1 if failures else 0

    for command in ("list", "whitelist list", "banlist list"):
        try:
            reply = rcon(args.host, args.rcon_port, args.password, command)
            print(f'  $ {command}')
            print(f"    原文: {reply!r}")
            if command == "list":
                parsed = names_after_colon(reply)
                print(f"    解析: {parsed or '（无人在线）'}")
            elif command == "whitelist list":
                print(f"    解析: {names_after_colon(reply)}")
            else:
                print(f"    解析: {names_after_colon(reply)}")
        except Exception as exc:                  # noqa: BLE001
            print(f"  ✗ {command} 失败: {exc}")
            failures += 1

    print()
    if failures:
        print(f"✗ 有 {failures} 项失败")
        return 1
    print("✓ SLP 与 RCON 全部通过（App 里「测试连接」应显示 `版本 · 在线/上限 · RCON OK`）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
