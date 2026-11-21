import { Plugin } from "@opencode/plugin"
import { start } from "./integration.js"

export default Plugin.define({
  id: "dms.agent-approvals",
  setup: start,
})
