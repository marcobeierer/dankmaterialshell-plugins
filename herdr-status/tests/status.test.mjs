import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const status = vm.createContext({})
vm.runInContext(await readFile(new URL("../Status.js", import.meta.url), "utf8"), status)

// Shapes as printed by herdr-app 0.1.16 `ls` and herdr 0.9 `agent list`.
const terminal = (address, word, extra = {}) =>
  ({ terminal: address, pane: "p" + address, status: word, app: word ? "claude-code" : null, name: null, sub_agents: [], ...extra })

const window = (...tabs) => JSON.stringify({
  spaces: [{ id: "sp1", name: "repo", tabs: tabs.map((terminals, index) => ({ id: "tb" + index, name: String(index + 1), terminals })) }],
  recent: [],
})

const agentList = (...agents) => JSON.stringify({
  id: "cli:agent:list",
  result: { type: "agent_list", agents: agents.map(([pane_id, agent_status]) => ({ pane_id, agent_status, agent: "opencode", cwd: "/repo" })) },
})

const summarizeApp = text => status.summarize([status.parseApp(text)])
const addresses = snapshot => [...snapshot.agents.map(agent => agent.id)]

test("only app terminals whose program reports a status count as agents", () => {
  const agents = status.parseApp(window([terminal("t1", null), terminal("t2", "working")], [terminal("t3", null)]))
  assert.equal(agents.length, 1)
  assert.equal(agents[0].source, "app")
  assert.equal(agents[0].id, "t2")
  assert.equal(agents[0].name, "claude-code")
  assert.equal(agents[0].detail, "repo / 1")
})

test("CLI agents keep their pane, title, and directory", () => {
  const agents = status.parseCli(agentList(["1-2", "blocked"]))
  assert.equal(agents.length, 1)
  assert.equal(agents[0].source, "cli")
  assert.equal(agents[0].id, "1-2")
  assert.equal(agents[0].state, "blocked")
  assert.equal(agents[0].name, "opencode")
  assert.equal(agents[0].detail, "/repo")
})

test("no agents is idle", () => {
  assert.equal(summarizeApp(window([terminal("t1", null)])).state, "idle")
  assert.equal(status.summarize([]).state, "idle")
  assert.equal(status.summarize([status.parseCli(agentList())]).state, "idle")
})

test("attention outranks unread results, which outrank work, unknown, and idle", () => {
  const all = [terminal("t1", "idle"), terminal("t2", "working"), terminal("t3", "done"), terminal("t4", "blocked")]
  assert.equal(summarizeApp(window(all)).state, "blocked")
  assert.equal(summarizeApp(window(all.slice(0, 3))).state, "done")
  assert.equal(summarizeApp(window(all.slice(0, 2))).state, "working")
  assert.deepEqual(addresses(summarizeApp(window(all))), ["t4", "t3", "t2", "t1"])
})

test("an unrecognised status never reads as all idle", () => {
  const app = summarizeApp(window([terminal("t1", "idle"), terminal("t2", "thinking")]))
  assert.equal(app.state, "unknown")
  assert.equal(app.counts.unknown, 1)
  assert.equal(status.summarize([status.parseCli(agentList(["1-1", "idle"], ["1-2", "thinking"]))]).state, "unknown")
})

test("an app agent error needs attention, as in the Herdr app", () => {
  const snapshot = summarizeApp(window([terminal("t1", "idle"), terminal("t2", "error")]))
  assert.equal(snapshot.state, "blocked")
  assert.equal(snapshot.counts.blocked, 1)
})

test("app and CLI agents are counted together", () => {
  const snapshot = status.summarize([
    status.parseApp(window([terminal("t1", "working"), terminal("t2", "idle")])),
    status.parseCli(agentList(["1-1", "blocked"], ["1-2", "working"])),
  ])
  assert.equal(snapshot.state, "blocked")
  assert.deepEqual({ ...snapshot.counts }, { blocked: 1, done: 0, working: 2, idle: 1, unknown: 0 })
  assert.deepEqual(addresses(snapshot), ["1-1", "t1", "1-2", "t2"])
})

test("agents with the same status keep their sources' order", () => {
  const snapshot = status.summarize([
    status.parseApp(window([terminal("t9", "working")], [terminal("t2", "working")])),
    status.parseCli(agentList(["1-1", "working"])),
  ])
  assert.deepEqual(addresses(snapshot), ["t9", "t2", "1-1"])
})

test("errors and malformed responses are rejected instead of shown as idle", () => {
  assert.throws(() => status.parseApp('{"error":"no window"}'), /no window/)
  assert.throws(() => status.parseApp("{}"), /Unexpected response from herdr-app ls/)
  assert.throws(() => status.parseApp('{"spaces":[{"tabs":[{"terminals":[{"status":"idle"}]}]}]}'), /Invalid terminal/)
  assert.throws(() => status.parseApp("not json"))
  assert.throws(() => status.parseCli('{"error":{"message":"no session"}}'), /no session/)
  assert.throws(() => status.parseCli(window([])), /Unexpected response from herdr agent list/)
  assert.throws(() => status.parseCli('{"result":{"type":"agent_list","agents":[{"pane_id":"1-1"}]}}'), /Invalid agent/)
})
