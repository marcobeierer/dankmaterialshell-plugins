import { lstat } from "node:fs/promises"
import { createConnection } from "node:net"
import { join } from "node:path"
import { setTimeout as delay } from "node:timers/promises"

const MAX_BYTES = 256 * 1024

// This adapter only replies to native pending requests. It never changes rules.
export function start(ctx) {
  const controller = new AbortController()
  const requests = new Map()
  let reconciling = false
  const keyOf = (sessionID, requestID) => JSON.stringify([sessionID, requestID])

  function cancel(key) {
    const entry = requests.get(key)
    if (!entry) return
    entry.cancelled = true
    entry.socket?.destroy()
    requests.delete(key)
  }

  async function show(request) {
    const key = keyOf(request.sessionID, request.id)
    if (controller.signal.aborted || requests.has(key)) return
    const entry = { request, cancelled: false, socket: null }
    requests.set(key, entry)
    try {
      const session = await ctx.session.get({ sessionID: request.sessionID })
      if (session.location.directory !== ctx.location.directory) {
        cancel(key)
        return
      }
      let input
      if (request.source?.type === "tool") {
        const messages = await ctx.session.context({ sessionID: request.sessionID })
        const message = messages.find(item => item.id === request.source.messageID)
        const tool = message?.content?.find(item => item.type === "tool" && item.id === request.source.id)
        input = tool?.state?.input
      }
      const payload = JSON.stringify({
        source: "opencode",
        session: request.sessionID,
        cwd: session.location.directory,
        title: session.title || "",
        action: request.action,
        reason: request.message || String(request.metadata?.description || ""),
        details: { ...request, ...(input === undefined ? {} : { input }) },
      }) + "\n"
      if (Buffer.byteLength(payload) > MAX_BYTES) return
      const runtime = process.env.XDG_RUNTIME_DIR
      if (!runtime) return
      const info = await lstat(runtime)
      if (!info.isDirectory() || info.uid !== process.getuid() || (info.mode & 0o077)) return
      // A terminal response may have arrived while context was being fetched.
      if (entry.cancelled || controller.signal.aborted) return
      await ctx.permission.get({ sessionID: request.sessionID, requestID: request.id })
      if (entry.cancelled || controller.signal.aborted) return
      const decision = await new Promise(resolve => {
        const socket = createConnection(join(runtime, "dms-agent-approvals", "bridge.sock"))
        entry.socket = socket
        let output = ""
        let settled = false
        const finish = decision => {
          if (settled) return
          settled = true
          clearTimeout(deadline)
          socket.destroy()
          resolve(decision)
        }
        const deadline = setTimeout(() => finish("defer"), 542_000)
        socket.setTimeout(2000, () => finish("defer"))
        socket.on("connect", () => {
          socket.setTimeout(0)
          socket.write(payload)
        })
        socket.setEncoding("utf8")
        socket.on("data", chunk => {
          output += chunk
          if (output.length > 4096) return finish("defer")
          if (!output.includes("\n")) return
          try {
            finish(JSON.parse(output.split("\n", 1)[0]).decision)
          } catch {
            finish("defer")
          }
        })
        socket.on("error", () => finish("defer"))
        socket.on("close", () => finish("defer"))
      })
      entry.socket = null
      if (entry.cancelled || controller.signal.aborted || !["allow", "deny"].includes(decision)) return
      // The native API owns the race with answers from the terminal and rejects
      // replies to an expired request ID. Never translate into a saved approval.
      await ctx.permission.reply({
        sessionID: request.sessionID,
        requestID: request.id,
        decision: decision === "allow" ? "once" : "reject",
        ...(decision === "deny" ? { message: "Denied by the user in Agent Approvals." } : {}),
      })
    } catch {
      // A missing request, service failure, or bridge failure leaves native UI
      // authoritative. Do not log command arguments or session contents.
      entry.socket?.destroy()
    }
  }

  function receive(event) {
    if (event.type === "permission.asked") {
      if (!event.location || event.location.directory === ctx.location.directory)
        void show(event.data)
      return
    }
    if (event.type === "permission.replied") {
      cancel(keyOf(event.data.sessionID, event.data.requestID))
      return
    }
    for (const [key, entry] of requests) {
      if (entry.request.sessionID === event.data.sessionID) cancel(key)
    }
  }

  async function recover() {
    let cursor
    do {
      const page = await ctx.session.list(cursor ? { cursor } : { directory: ctx.location.directory, limit: 100 })
      for (const session of page.data) {
        if (controller.signal.aborted) return
        try {
          const pending = await ctx.permission.list({ sessionID: session.id })
          for (const request of pending) void show(request)
        } catch {
          // A session may disappear while paging.
        }
      }
      cursor = page.cursor.next
    } while (cursor && !controller.signal.aborted)
  }

  // Consume events promptly; context reads and user interaction run separately.
  void (async () => {
    while (!controller.signal.aborted) {
      try {
        const stream = ctx.event.subscribe({
          types: ["permission.asked", "permission.replied", "session.execution.interrupted", "session.deleted"],
          signal: controller.signal,
        })
        const consume = (async () => {
          for await (const event of stream) receive(event)
        })()
        void recover().catch(() => {})
        await consume
      } catch {
        // Public event streams are live-only. Resync after reconnecting.
      }
      for (const key of requests.keys()) cancel(key)
      try {
        await delay(1000, undefined, { signal: controller.signal })
      } catch {
        break
      }
    }
  })()

  // Also retire requests if a cancellation event was missed. Settled/deferred
  // entries stay deduplicated until the native request disappears.
  const timer = setInterval(async () => {
    if (reconciling || controller.signal.aborted) return
    reconciling = true
    try {
      for (const [key, entry] of requests) {
        try {
          await ctx.permission.get({ sessionID: entry.request.sessionID, requestID: entry.request.id })
        } catch {
          cancel(key)
        }
      }
    } finally {
      reconciling = false
    }
  }, 2000)

  return () => {
    controller.abort()
    clearInterval(timer)
    for (const key of requests.keys()) cancel(key)
  }
}
