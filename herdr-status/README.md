# Herdr Status for DankMaterialShell

A native DankBar widget for all agents in one local **Herdr** session, regardless
of which coding agent they use. No OpenCode plugin, helper daemon, package
installation, or configuration changes to Herdr are required.

| Color | Meaning |
| --- | --- |
| Green | All agents idle, or no agents running |
| Red | An agent is blocked and needs attention |
| Blue | An agent has unread completed results |
| Yellow | An agent is working |
| Gray | Herdr is unavailable or an agent's status is unknown |

The bar shows the number of agents in the displayed state. Click for a scrollable
agent list, or right-click to refresh. It refreshes every two seconds by default.
Opening the widget does not acknowledge results or change Herdr focus.

## Install

Requires DankMaterialShell **1.6+** and Herdr **0.9.3+** on Linux. Herdr must
already be running. The widget uses the installed CLI's `herdr agent list` API.

From this project directory:

```sh
./install.sh
```

The installer creates a symlink to this directory, so keep the source in place.
It is safe to rerun and refuses to overwrite another installation. It does not
install dependencies or restart the shell. For a custom plugins directory:

```sh
./install.sh "${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins"
```

In DMS, open **Settings → Plugins**, scan for plugins, and enable **Herdr Status**.
Add it to your DankBar layout. Both horizontal and vertical bars are supported.
If DMS uses a different configuration directory, pass its `plugins/` subdirectory
to the installer instead (newer Dux Shell releases use `~/.config/dms`).

In the plugin settings:

- **Herdr executable:** defaults to `herdr`. If it is not on DMS's `PATH`, use
  the absolute path returned by `command -v herdr`, for example
  `/home/you/.local/bin/herdr`. This is a path, not a shell command; `~` is not
  expanded and arguments are not accepted here.
- **Named session:** empty selects the default session. Set a name to monitor a
  different session. This widget does not aggregate multiple named sessions or
  saved SSH machines.
- **Refresh interval:** 1–30 seconds.
- **Show Herdr label:** hide the label for a more compact pill.

The widget's child process clears inherited `HERDR_SOCKET_PATH` and
`HERDR_SESSION` overrides so session selection is explicit. Custom Herdr config
locations via `HERDR_CONFIG_PATH` still follow the desktop environment.

## Status semantics

Aggregation and acknowledgement rules live in [`Status.js`](Status.js). The
widget follows Herdr's public `agent_status` values; it does not independently
inspect terminal output or track completion history. Accuracy, including when
results count as viewed, therefore depends on Herdr and the agent's integration.
Agent titles and paths stay local and are rendered as plain text.

## Troubleshooting

Run `herdr agent list` (or `herdr --session NAME agent list`) from a terminal.
If this fails, start the intended Herdr session first. If it succeeds but the
widget is gray, set an absolute executable path in the plugin settings and
right-click the widget. Requests time out after five seconds and retry
automatically. A failed request never leaves a stale green indicator.

After editing the plugin, reload it with:

```sh
dms ipc call plugin-scan reload herdrStatus
```

No shell restart or installation has been performed by creating these files.
