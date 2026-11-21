import assert from "node:assert/strict"
import { mkdir, mkdtemp, rm } from "node:fs/promises"
import { createServer } from "node:net"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { setTimeout as delay } from "node:timers/promises"
import test from "node:test"
import { start } from "../opencode/integration.js"

async function until(predicate) {
  for (let index = 0; index < 200; index++) {
    if (predicate()) return
    await delay(5)
  }
  assert.fail("Expected lifecycle event did not arrive")
}

async function fixture(t) {
  const runtime = await mkdtemp(join(tmpdir(), "agent-approvals-"))
  await mkdir(join(runtime, "dms-agent-approvals"), { mode: 0o700 })
  const previous = process.env.XDG_RUNTIME_DIR
  process.env.XDG_RUNTIME_DIR = runtime
  const clients = []
  const server = createServer(socket => {
    const entry = { socket, closed: false, request: null }
    clients.push(entry)
    let buffer = ""
    socket.on("data", chunk => {
      buffer += chunk
      if (buffer.includes("\n")) entry.request = JSON.parse(buffer.split("\n")[0])
    })
    socket.on("close", () => { entry.closed = true })
    socket.on("error", () => {})
  })
  await new Promise(resolve => server.listen(join(runtime, "dms-agent-approvals/bridge.sock"), resolve))
  const queue = []
  const pending = new Map()
  const replies = []
  const ctx = {
    location: { directory: "/repo" },
    session: {
      get: async () => ({ title: "Fix bug", location: { directory: "/repo" } }),
      context: async () => [{ id: "message", content: [{ type: "tool", id: "tool", state: { input: { command: "echo first\necho second" } } }] }],
      list: async () => ({ data: [], cursor: {} }),
    },
    permission: {
      get: async ({ requestID }) => {
        if (!pending.has(requestID)) throw new Error("Request already resolved")
        return pending.get(requestID)
      },
      list: async () => [...pending.values()],
      reply: async reply => {
        if (!pending.has(reply.requestID)) throw new Error("Request already resolved")
        replies.push(reply)
        pending.delete(reply.requestID)
      },
    },
    event: {
      async *subscribe({ signal }) {
        while (!signal.aborted) {
          if (queue.length) yield queue.shift()
          else await delay(2)
        }
      },
    },
  }
  const stop = start(ctx)
  t.after(async () => {
    stop()
    for (const entry of clients) entry.socket.destroy()
    await new Promise(resolve => server.close(resolve))
    if (previous === undefined) delete process.env.XDG_RUNTIME_DIR
    else process.env.XDG_RUNTIME_DIR = previous
    await rm(runtime, { recursive: true, force: true })
  })
  function ask(id = "request") {
    const request = {
      id, sessionID: "session", action: "shell", resources: ["echo *"],
      source: { type: "tool", messageID: "message", id: "tool" },
    }
    pending.set(id, request)
    queue.push({ type: "permission.asked", location: { directory: "/repo" }, data: request })
  }
  return { clients, queue, pending, replies, ask, stop }
}

test("OpenCode approval uses the exact session/request and never saves a grant", async t => {
  const f = await fixture(t)
  f.ask()
  await until(() => f.clients[0]?.request)
  assert.equal(f.clients[0].request.details.input.command, "echo first\necho second")
  assert.equal(f.clients[0].request.cwd, "/repo")
  f.clients[0].socket.write('{"decision":"allow"}\n')
  await until(() => f.replies.length)
  assert.deepEqual(f.replies, [{ sessionID: "session", requestID: "request", decision: "once" }])
})

test("terminal reply retires the card and prevents a stale desktop approval", async t => {
  const f = await fixture(t)
  f.ask()
  await until(() => f.clients[0]?.request)
  f.pending.delete("request")
  f.queue.push({ type: "permission.replied", data: { sessionID: "session", requestID: "request" } })
  await until(() => f.clients[0].closed)
  assert.equal(f.replies.length, 0)
})

test("disconnect, defer, and unknown decisions never reply to the agent", async t => {
  const f = await fixture(t)
  for (const [index, decision] of ["defer", "always", null].entries()) {
    f.ask(String(index))
    await until(() => f.clients[index]?.request)
    if (decision) f.clients[index].socket.end(JSON.stringify({ decision }) + "\n")
    else f.clients[index].socket.destroy()
    await until(() => f.clients[index].closed)
  }
  assert.equal(f.replies.length, 0)
})

test("plugin unload closes outstanding cards without a permission reply", async t => {
  const f = await fixture(t)
  f.ask()
  await until(() => f.clients[0]?.request)
  f.stop()
  await until(() => f.clients[0].closed)
  assert.equal(f.replies.length, 0)
})
