#!/usr/bin/env python3
# Generic ttyd web-console runner.
# ttyd 터미널(웹콘솔)의 websocket 에 명령을 보내고 출력을 캡처해 stdout 으로 돌려준다.
# SSH 가 막혔거나 DSM 주니어/설치 환경처럼 ttyd 만 열린 박스를 자동화할 때 사용.
#
# 사용법:
#   python3 ttyd-run.py <host> [cmd1] [cmd2] ...
#   예) python3 ttyd-run.py 192.168.45.246 'uname -a' 'cat /proc/mdstat'
#
# 환경변수(선택):
#   TTYD_PORT     ttyd 포트            (기본 7681)
#   TTYD_LOGIN    로그인 계정          (기본 root)
#   TTYD_PASS     비밀번호             (기본 빈값 — DSM 주니어 root 무암호)
#   TTYD_NOLOGIN  1 이면 로그인 단계 생략 (이미 셸이 뜬 ttyd, 예: TinyCore tc)
#   TTYD_DELAY    명령 간 대기초        (기본 2.4)
#
# 의존성: pip install websockets
import asyncio, json, sys, os
try:
    import websockets
except ImportError:
    sys.exit("need: pip install websockets")

host = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TTYD_HOST")
if not host:
    sys.exit("usage: ttyd-run.py <host> [cmd ...]")
cmds = sys.argv[2:]
port = os.environ.get("TTYD_PORT", "7681")
login = os.environ.get("TTYD_LOGIN", "root")
passwd = os.environ.get("TTYD_PASS", "")
nologin = os.environ.get("TTYD_NOLOGIN")
delay = float(os.environ.get("TTYD_DELAY", "2.4"))
URL = f"ws://{host}:{port}/ws"

async def main():
    async with websockets.connect(URL, subprotocols=["tty"], open_timeout=10, max_size=None) as ws:
        await ws.send(json.dumps({"AuthToken": "", "columns": 200, "rows": 50}).encode())
        out = bytearray()
        async def reader():
            try:
                async for m in ws:
                    if isinstance(m, str):
                        m = m.encode()
                    if m and chr(m[0]) == '0':
                        out.extend(m[1:])
            except Exception:
                pass
        asyncio.create_task(reader())
        async def send(s):
            await ws.send(b"0" + s.encode())
        await asyncio.sleep(1.0)
        await send("\n"); await asyncio.sleep(0.8)
        if not nologin:
            await send(login + "\n"); await asyncio.sleep(1.2)
            await send(passwd + "\n"); await asyncio.sleep(1.5)
        for c in cmds:
            await send(c + "\n"); await asyncio.sleep(delay)
        await asyncio.sleep(1.0)
        sys.stdout.write(out.decode(errors="replace"))

asyncio.run(main())
