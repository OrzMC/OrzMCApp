"""最小 RCON 服务端（真 socket 联调用）：auth + **多包响应**。

`list` 故意拆成两个响应包，用来验证客户端会把后续包也读完（以前只取第一包）。
用法：`python3 scripts/test-servers/rcon_server.py [port]`
"""
import socket
import struct
import sys
import threading

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 25575
PASSWORD = "testpass"

# 给"玩家管理"联调用的固定回复（措辞模仿原版服务端）。
ANSWERS = {
    "whitelist list": "There are 2 whitelisted player(s): alice, carol",
    "banlist list": "There are 1 ban(s):\ndave (griefing)",
    "list": "There are 2 of a max of 20 players online: alice, bob",
}

def varint_packet(rid, rtype, body):
    payload = struct.pack("<ii", rid, rtype) + body.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", len(payload)) + payload

def handle(conn):
    try:
        while True:
            head = conn.recv(4)
            if not head:
                return
            length = struct.unpack("<i", head)[0]
            data = b""
            while len(data) < length:
                chunk = conn.recv(length - len(data))
                if not chunk:
                    return
                data += chunk
            rid, rtype = struct.unpack("<ii", data[:8])
            body = data[8:].split(b"\x00")[0].decode("utf-8", "replace")
            if rtype == 3:                                  # auth
                if body == PASSWORD:
                    conn.sendall(varint_packet(rid, 2, ""))
                else:
                    conn.sendall(varint_packet(-1, 2, ""))
            elif rtype == 2:                                # command
                reply = ANSWERS.get(body, "ok: " + body)
                if body == "list":
                    # 故意拆成两包，验证客户端会把后续包也读回来
                    conn.sendall(varint_packet(rid, 0, "There are 2 of a max of 20 players online:"))
                    conn.sendall(varint_packet(rid, 0, " alice, bob"))
                else:
                    conn.sendall(varint_packet(rid, 0, reply))
    finally:
        conn.close()

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((HOST, PORT))
srv.listen(5)
print(f"rcon server listening on {HOST}:{PORT}", flush=True)
while True:
    conn, _ = srv.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
