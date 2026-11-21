import asyncio
import importlib.util
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("bridge", ROOT / "bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def event(session="session-1"):
    return {
        "hook_event_name": "PermissionRequest",
        "session_id": session,
        "cwd": "/project with spaces",
        "tool_name": "Bash",
        "tool_input": {"command": "printf '<b>literal</b>\\n'", "description": None},
    }


class BridgeLifecycle(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="agent-approvals-")
        self.env = {**os.environ, "XDG_RUNTIME_DIR": self.directory.name}
        self.process = subprocess.Popen(
            [sys.executable, "-u", str(ROOT / "bridge.py"), "serve"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=self.env, bufsize=0,
        )
        self.children = []
        self.assertEqual(self.read_event(), {"type": "ready"})

    def tearDown(self):
        for child in self.children + [self.process]:
            if child.poll() is None:
                child.terminate()
            child.communicate(timeout=3)
        self.directory.cleanup()

    def read_event(self):
        self.assertTrue(select.select([self.process.stdout], [], [], 3)[0], "No bridge event")
        return json.loads(self.process.stdout.readline())

    def hook(self, source="claude", session="session-1"):
        child = subprocess.Popen(
            [sys.executable, str(ROOT / "bridge.py"), source],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env,
        )
        self.children.append(child)
        child.stdin.write(json.dumps(event(session)).encode())
        child.stdin.close()
        child.stdin = None
        return child

    def decide(self, request_id, decision):
        self.process.stdin.write(bridge.encode({"id": request_id, "decision": decision}))
        self.process.stdin.flush()

    def result(self, child):
        stdout, stderr = child.communicate(timeout=3)
        self.assertEqual(child.returncode, 0, stderr)
        return json.loads(stdout)

    def test_both_agents_return_only_single_request_allow(self):
        for source in ("claude", "codex"):
            with self.subTest(source=source):
                child = self.hook(source)
                request = self.read_event()["request"]
                self.assertEqual(request["details"], event())
                self.assertEqual(request["source"], source)
                self.decide(request["id"], "allow")
                self.assertEqual(self.result(child), {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest", "decision": {"behavior": "allow"},
                    },
                })
                self.assertEqual(self.read_event(), {"type": "remove", "id": request["id"]})

    def test_concurrent_sessions_and_stale_ids_cannot_cross_approve(self):
        first = self.hook(session="first")
        first_id = self.read_event()["request"]["id"]
        second = self.hook("codex", "second")
        second_id = self.read_event()["request"]["id"]
        self.assertNotEqual(first_id, second_id)
        self.decide(first_id, "deny")
        self.assertEqual(self.result(first)["hookSpecificOutput"]["decision"]["behavior"], "deny")
        self.read_event()
        self.decide(first_id, "allow")
        self.decide(second_id, "always")
        self.assertFalse(select.select([second.stdout], [], [], 0.1)[0])
        self.decide(second_id, "defer")
        self.assertEqual(self.result(second), {})
        self.read_event()

    def test_hook_disconnect_withdraws_card(self):
        child = self.hook()
        request_id = self.read_event()["request"]["id"]
        child.terminate()
        child.communicate(timeout=3)
        self.assertEqual(self.read_event(), {"type": "remove", "id": request_id})

    def test_dms_pipe_closure_defers_pending_requests(self):
        child = self.hook()
        self.read_event()
        self.process.stdin.close()
        self.process.stdin = None
        self.assertEqual(self.result(child), {})
        self.process.wait(timeout=3)

    def test_missing_bridge_defers_without_approval(self):
        self.process.terminate()
        self.process.communicate(timeout=3)
        self.assertEqual(self.result(self.hook()), {})

    def test_agent_socket_cannot_submit_a_decision(self):
        path = Path(self.directory.name) / "dms-agent-approvals/bridge.sock"
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(str(path))
            client.sendall(bridge.encode(bridge.normalize("claude", event())))
            request_id = self.read_event()["request"]["id"]
            client.sendall(bridge.encode({"id": request_id, "decision": "allow"}))
            client.settimeout(3)
            self.assertEqual(client.recv(4096), b"")
        self.assertEqual(self.read_event(), {"type": "remove", "id": request_id})

    def test_second_broker_does_not_unlink_live_socket(self):
        duplicate = subprocess.run(
            [sys.executable, str(ROOT / "bridge.py"), "serve"], input=b"",
            capture_output=True, env=self.env, timeout=3,
        )
        self.assertNotEqual(duplicate.returncode, 0)
        child = self.hook()
        request_id = self.read_event()["request"]["id"]
        self.decide(request_id, "defer")
        self.assertEqual(self.result(child), {})
        self.read_event()


class RequestBounds(unittest.TestCase):
    def test_only_permission_events_can_be_approved(self):
        with self.assertRaises(ValueError):
            bridge.normalize("claude", {**event(), "hook_event_name": "PreToolUse"})

    def test_oversized_request_is_rejected_not_truncated(self):
        payload = event()
        payload["tool_input"]["command"] = "x" * bridge.MAX_BYTES
        with self.assertRaises(ValueError):
            bridge.normalize("codex", payload)

    def test_fallback_never_emits_permission_updates(self):
        for decision in ("defer", "always", None, "unexpected"):
            self.assertEqual(bridge.hook_output(decision), {})


class BrokerDeadlines(unittest.IsolatedAsyncioTestCase):
    async def test_timeout_and_queue_overflow_defer(self):
        with tempfile.TemporaryDirectory(prefix="agent-approvals-") as directory:
            broker = bridge.Broker()
            events = []
            broker.emit = events.append
            path = str(Path(directory) / "socket")
            async with await asyncio.start_unix_server(broker.client, path=path) as server:
                for limit in (0, 32):
                    with patch.object(bridge, "MAX_PENDING", limit), patch.object(bridge, "WAIT_SECONDS", 0.02):
                        reader, writer = await asyncio.open_unix_connection(path)
                        writer.write(bridge.encode(bridge.normalize("codex", event())))
                        await writer.drain()
                        reply = await asyncio.wait_for(reader.readline(), 1)
                        self.assertEqual(json.loads(reply), {"decision": "defer"})
                        writer.close()
                        await writer.wait_closed()
                        await asyncio.sleep(0)
                self.assertEqual([item["type"] for item in events], ["request", "remove"])


if __name__ == "__main__":
    unittest.main()
