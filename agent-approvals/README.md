# Agent Approvals

Answer **OpenCode V2, Codex, and Claude Code** permission requests from a
persistent, DMS-themed notification card on your **currently focused monitor**.
Requires Linux, DMS **1.6.2+**, Python 3, and **Hyprland or Niri**.

- See the agent, project directory, session identity, tool/action, explanation
  when supplied by the agent, and command or affected path.
- Expand the full request to inspect commands, file contents, edits, patches,
  permission resources, and all supplied tool arguments. Multiline text is
  displayed literally; long content scrolls.
- **Allow once**, **Deny**, or **Use terminal**. Approvals apply only to that
  request. No rules or persistent grants are created.
- Multiple sessions are queued independently. **Next request** cycles through
  the queue without answering. The card follows focus between monitors without
  changing workspace or stealing keyboard focus.

## Install

From this repository's registry:

```sh
dms plugins install agentApprovals
```

Or from a local checkout:

```sh
./agent-approvals/install.sh
```

Enable **Agent Approvals** in **Settings → Plugins**. No bar widget is needed.
The DMS daemon plugin owns a small Python subprocess; no systemd service is
required. Then connect each agent below. Installation does not edit agent settings.

## Connect your agents

Run `config.py` from the installed plugin directory (or this checkout) to print
configuration with the correct absolute paths:

```sh
python3 agent-approvals/config.py opencode
python3 agent-approvals/config.py codex
python3 agent-approvals/config.py claude
```

Merge the generated entries into the appropriate file, preserving existing
plugins, hooks, and unrelated settings. Keep the plugin directory in place.
The card only appears for agents connected this way; enabling the DMS plugin
alone shows nothing.

For JSON settings files, `jq` can append the hook without touching anything
else, for example for Claude Code:

```sh
jq --argjson h "$(python3 agent-approvals/config.py claude)" \
  '.hooks.PermissionRequest += $h.hooks.PermissionRequest' \
  ~/.claude/settings.json > ~/.claude/settings.json.new \
  && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

If the target file does not exist yet, redirect the output of `config.py` to it
directly. Edit JSONC files such as `opencode.jsonc` by hand.

### OpenCode V2

Append the generated `plugins` entry to
`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json(c)`.
Install the companion package's dependency once:

```sh
npm install --prefix /absolute/path/to/agent-approvals/opencode
```

Reload OpenCode's plugins or restart its service after configuration. The
companion uses the V2 plugin SDK, pinned to **2.2.1**. It listens to native
permission events and replies through `ctx.permission.reply`. It recovers
already-pending requests on startup/reconnection, scopes events to each plugin
location, and withdraws cards when the terminal answers or execution stops.
OpenCode's terminal prompt remains available concurrently.

### Codex

Merge the generated `hooks.PermissionRequest` entries into `~/.codex/hooks.json`
(or `$CODEX_HOME/hooks.json` if you use a custom Codex home). Start/restart Codex
and review/trust the hook through **`/hooks`**. Hooks must be enabled.

Requires a Codex release implementing the documented **PermissionRequest** hook
with `decision.behavior` output. This handles requests exposed by that hook,
including shell escalation, patch, MCP, and managed-network approvals. Older
Codex releases with only completion notifications cannot answer approvals this
way; update Codex if `/hooks` does not recognize `PermissionRequest`.

### Claude Code

Merge the generated `hooks.PermissionRequest` entries into
`~/.claude/settings.json` (or your custom Claude config directory). Restart
Claude Code so it loads the hook.

This handles tool permission requests, including Bash, file operations, and MCP
tools. The hook runs only when Claude would otherwise show a permission prompt:
actions allowed by permission rules or approved automatically in auto mode
never reach the card. Claude's sandbox **network-domain** prompts do not invoke this hook and
must still be answered in Claude. Agent questions, authentication prompts, and
MCP elicitation forms are not permission requests.

## Behavior and failure handling

The card is a dedicated notification-style layer surface, separate from DMS's
notification center. It follows the focused display regardless of the global
notification-monitor preference. It is hidden while the session is locked and
is not stored in notification history. DMS's notification DND setting does not
suppress this card. Content stays local, in memory, and may include sensitive
command arguments or file contents supplied by the agent.

For Claude and Codex, the synchronous hook waits for your decision before the
normal permission flow continues. **Use terminal** returns no decision so the
agent can show its native prompt. Closing/restarting DMS, a disconnected hook,
a missing bridge, or a nine-minute timeout never approves anything; the native
permission flow resumes. Other hooks and agent policy can still deny a request.

Requests larger than 256 KiB, malformed requests, and requests beyond the
32-entry queue fall back to the agent. Requests are never silently truncated
into an approvable payload. A short click guard prevents a double-click on one
card from approving the next request.

The bridge listens only at
`$XDG_RUNTIME_DIR/dms-agent-approvals/bridge.sock`, in a private directory. It
accepts same-user local clients; only its DMS-owned stdin pipe can submit a
decision. It runs no tool commands itself and persists no permission decisions.
All agents and DMS must run as the same desktop user with the same
`XDG_RUNTIME_DIR`. Remote/SSH/container agents need their own desktop integration.

## Troubleshooting

- **No card:** first check that the agent is connected (see
  [Connect your agents](#connect-your-agents)); installing the plugin does not
  configure any agent. For Claude Code, also check that the action actually
  needed a prompt rather than being allowed by rules or auto mode. Then check
  that the DMS plugin is enabled, Python 3 is on DMS's PATH,
  and `XDG_RUNTIME_DIR` is available to both DMS and the agent. DMS logs bridge
  startup errors. There must be only one enabled instance of this plugin.
- **Codex skips the hook:** open `/hooks`, review its definition, and trust it.
- **Claude/Codex stays at a hook spinner:** select **Use terminal**, or wait for
  the hook's nine-minute fallback. Do not register this bridge as an async hook.
- **OpenCode dependency error:** install the companion's npm dependencies and
  reload it. This companion targets V2; it does not use the V1 plugin API.
- **Request disappeared:** the agent answered/cancelled it, its hook disconnected,
  or the request timed out. Stale cards cannot grant a future request.

## Development

Focused protocol/lifecycle tests (no running agents or desktop needed):

```sh
python3 -m unittest discover -s agent-approvals/tests -p 'test_*.py'
node --test agent-approvals/tests/*.test.mjs
```

Tests use private temporary runtime directories and fake pending requests.
Actual multi-monitor presentation requires a running DMS session.

### Integration references

- [OpenCode V2 server plugins](https://opencode.ai/v2/docs/build/plugins/server)
- [Codex permission hooks](https://developers.openai.com/codex/hooks#permissionrequest)
- [Claude permission hooks](https://code.claude.com/docs/en/hooks#permissionrequest)
