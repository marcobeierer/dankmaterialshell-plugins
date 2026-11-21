#!/usr/bin/env python3
"""Local permission-request transport. Only the DMS stdin pipe can decide."""

import argparse
import asyncio
import fcntl
import json
import os
from pathlib import Path
import select
import socket
import stat
import struct
import sys
import time
import uuid

MAX_BYTES = 256 * 1024
MAX_PENDING = 32
WAIT_SECONDS = 540
DECISIONS = {"allow", "deny", "defer"}


def socket_path():
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    info = runtime.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("XDG_RUNTIME_DIR must be a private directory owned by this user")
    return runtime / "dms-agent-approvals" / "bridge.sock"


def encode(value):
    return (json.dumps(value, ensure_ascii=True, allow_nan=False) + "\n").encode()


def normalize(source, payload):
    if not isinstance(payload, dict):
        raise ValueError("Expected a JSON object")
    if source in {"claude", "codex"}:
        if payload.get("hook_event_name") != "PermissionRequest":
            raise ValueError("Only PermissionRequest hooks can request a decision")
        tool_input = payload.get("tool_input")
        if "tool_input" not in payload:
            raise ValueError("Missing tool input")
        request = {
            "source": source,
            "session": payload.get("session_id"),
            "cwd": payload.get("cwd"),
            "action": payload.get("tool_name"),
            "title": payload.get("agent_type") or "",
            "reason": (tool_input.get("description") or "") if isinstance(tool_input, dict) else "",
            "details": payload,
        }
    elif source == "opencode":
        request = {**payload, "source": source}
    else:
        raise ValueError("Unknown agent")
    return validate_request(request)


def validate_request(request):
    if not isinstance(request, dict) or request.get("source") not in {"claude", "codex", "opencode"}:
        raise ValueError("Unknown agent")
    for field in ("session", "cwd", "action"):
        if not isinstance(request.get(field), str) or not request[field]:
            raise ValueError(f"Missing {field}")
    for field in ("title", "reason"):
        if not isinstance(request.get(field, ""), str):
            raise ValueError(f"Invalid {field}")
    if "details" not in request:
        raise ValueError("Missing request details")
    # Never silently truncate an approvable request.
    if len(encode(request)) > MAX_BYTES:
        raise ValueError("Request too large; review it in the agent")
    return request


def hook_output(decision):
    if decision not in {"allow", "deny"}:
        return {}
    result = {"behavior": decision}
    if decision == "deny":
        result["message"] = "Denied by the user in Agent Approvals."
    return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": result}}


def request_decision(request):
    """Disconnect, timeout, and missing DMS all leave the native prompt in charge."""
    parent = os.getppid()
    deadline = time.monotonic() + WAIT_SECONDS + 2
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(2)
        connection.connect(str(socket_path()))
        connection.sendall(encode(request))
        result = b""
        while time.monotonic() < deadline and os.getppid() == parent:
            if not select.select([connection], [], [], 1)[0]:
                continue
            chunk = connection.recv(4096)
            if not chunk:
                return "defer"
            result += chunk
            if len(result) > 4096:
                return "defer"
            if b"\n" in result:
                message = json.loads(result.split(b"\n", 1)[0])
                decision = message.get("decision") if isinstance(message, dict) else None
                return decision if decision in DECISIONS else "defer"
    return "defer"


class Broker:
    def __init__(self):
        self.pending = {}
        self.clients = set()

    def emit(self, event):
        sys.stdout.write(encode(event).decode())
        sys.stdout.flush()

    def decide(self, message):
        if not isinstance(message, dict) or not isinstance(message.get("id"), str):
            return
        if not isinstance(message.get("decision"), str) or message["decision"] not in DECISIONS:
            return
        future = self.pending.get(message.get("id"))
        if future is not None and not future.done():
            future.set_result(message["decision"])

    async def client(self, reader, writer):
        task = asyncio.current_task()
        self.clients.add(task)
        request_id = None
        disconnected = None
        try:
            peer = writer.get_extra_info("socket").getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            if struct.unpack("3i", peer)[1] != os.getuid():
                return
            line = await asyncio.wait_for(reader.readline(), 5)
            if not line.endswith(b"\n") or len(line) > MAX_BYTES:
                return
            payload = json.loads(line)
            request = validate_request(payload)
            # Hook clients already normalized their event. Preserve the full event
            # as details; only the envelope, never its input, drives the UI.
            if len(self.pending) >= MAX_PENDING:
                writer.write(encode({"decision": "defer"}))
                await writer.drain()
                return
            request_id = uuid.uuid4().hex
            future = asyncio.get_running_loop().create_future()
            self.pending[request_id] = future
            self.emit({"type": "request", "request": {**request, "id": request_id}})
            disconnected = asyncio.create_task(reader.read(1))
            done, _ = await asyncio.wait(
                [future, disconnected], timeout=WAIT_SECONDS, return_when=asyncio.FIRST_COMPLETED
            )
            # Any extra client data is a disconnect, never a decision channel.
            if disconnected not in done:
                decision = future.result() if future in done else "defer"
                writer.write(encode({"decision": decision}))
                await writer.drain()
        except (ValueError, KeyError, TypeError, OSError, asyncio.TimeoutError):
            pass
        finally:
            if disconnected:
                disconnected.cancel()
            if request_id:
                self.pending.pop(request_id, None)
                self.emit({"type": "remove", "id": request_id})
            writer.close()
            self.clients.discard(task)

    async def run(self):
        path = socket_path()
        path.parent.mkdir(mode=0o700, exist_ok=True)
        info = path.parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("Bridge directory must be private and owned by this user")
        lock_fd = os.open(path.parent / "bridge.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(lock_fd, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            path.unlink(missing_ok=True)
            server = await asyncio.start_unix_server(self.client, path=str(path), limit=MAX_BYTES)
            os.chmod(path, 0o600)
            reader = asyncio.StreamReader(limit=4096)
            protocol = asyncio.StreamReaderProtocol(reader)
            transport, _ = await asyncio.get_running_loop().connect_read_pipe(lambda: protocol, sys.stdin)
            self.emit({"type": "ready"})
            try:
                async with server:
                    while line := await reader.readline():
                        try:
                            self.decide(json.loads(line))
                        except (ValueError, TypeError):
                            continue
            finally:
                transport.close()
                for task in list(self.clients):
                    task.cancel()
                await asyncio.gather(*self.clients, return_exceptions=True)
                path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["serve", "claude", "codex", "opencode"])
    args = parser.parse_args()
    if args.mode == "serve":
        asyncio.run(Broker().run())
        return
    decision = "defer"
    try:
        raw = sys.stdin.buffer.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError("Request too large; review it in the agent")
        payload = json.loads(raw)
        request = normalize(args.mode, payload)
        # The broker accepts a normalized envelope, not arbitrary hook stdout.
        decision = request_decision(request)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Agent Approvals: {error}; use the agent's permission prompt.", file=sys.stderr)
    print(json.dumps({"decision": decision} if args.mode == "opencode" else hook_output(decision)))


if __name__ == "__main__":
    main()
