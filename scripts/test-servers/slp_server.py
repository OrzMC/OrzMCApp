"""最小 Server List Ping 服务端（真 socket 联调用）。

用途：`Tests/OrzMCProtocolTests/LiveProbeSmokeTests` 需要一个**真实**的 TCP 对端。
假字节流单测覆盖协议细节，但抓不到"SOCKET 分段 / 多字节 VarInt / 超时"这类真实路径问题
（历史上 VarInt 左移溢出就是靠它才暴露的）。

用法：`python3 scripts/test-servers/slp_server.py [port]`
"""
import json
import socket
import sys
import threading

# 绑定所有网卡：模拟器用 127.0.0.1，真机用 Mac 的局域网地址（0.0.0.0 两边都能连）。
HOST = ""
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 25566
STATUS = {
    "version": {"name": "26.3", "protocol": 777},
    "players": {"max": 20, "online": 2, "sample": [{"name": "alice", "id": "1"}, {"name": "bob", "id": "2"}]},
    "description": {"text": "§a本地测试服 ", "extra": [{"text": "§7(假服务端)"}]},
}

def varint(n):
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            out += bytes([b])
            return out

def read_varint(sock):
    value = shift = 0
    while True:
        b = sock.recv(1)
        if not b:
            raise ConnectionError
        byte = b[0]
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value
        shift += 7

def read_packet(sock):
    length = read_varint(sock)
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise ConnectionError
        data += chunk
    return data

def handle(sock):
    try:
        read_packet(sock)                       # handshake
        read_packet(sock)                       # status request
        payload = json.dumps(STATUS).encode()
        body = b"\x00" + varint(len(payload)) + payload
        sock.sendall(varint(len(body)) + body)
        read_packet(sock)                       # ping
        pong = b"\x01" + b"\xff\xff\xff\xff\xff\xff\xff\x7f"
        sock.sendall(varint(len(pong)) + pong)
    except Exception as exc:
        print("conn error", exc, flush=True)
    finally:
        sock.close()

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((HOST, PORT))
srv.listen(8)
print(f"slp server on {HOST or '0.0.0.0'}:{PORT}", flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
