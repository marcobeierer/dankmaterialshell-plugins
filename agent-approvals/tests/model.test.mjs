import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const model = vm.createContext({})
vm.runInContext(await readFile(new URL("../ApprovalModel.js", import.meta.url), "utf8"), model)

test("queues preserve identities, deduplicate, and remove only the answered request", () => {
  const first = { id: "first" }
  const second = { id: "second" }
  let requests = model.append([], first)
  requests = model.append(requests, second)
  requests = model.append(requests, first)
  assert.equal(requests.length, 2)
  const remaining = model.remove(requests, "first")
  assert.equal(remaining.length, 1)
  assert.equal(remaining[0], second)
  assert.equal(model.remove(remaining, "stale")[0], second)
})

test("full context preserves multiline changes and every supplied field", () => {
  const input = {
    file_path: "/repo/file",
    old_string: "one\ntwo",
    new_string: "<b>three</b>\nfour",
    extra: "z".repeat(20_000),
  }
  const details = model.details({ details: { tool_input: input, permission_mode: "default" } })
  assert.ok(details.includes(input.old_string))
  assert.ok(details.includes(input.new_string))
  assert.ok(details.includes(input.extra))
  assert.ok(details.includes('"permission_mode": "default"'))
})
