# Herdr Status for DankMaterialShell

A native DankBar widget for all agents in one local **Herdr** session, regardless
of which coding agent they use. No OpenCode plugin, helper daemon, package
installation, or configuration changes to Herdr are required.

| Color | Agent status |
| --- | --- |
| Green | Idle |
| Yellow | Working |
| Red | An agent is blocked and needs attention |
| Blue | An agent has unread completed results |
| Gray | Herdr is unavailable or an agent's status is unknown |

Each status uses the same bot icon, with color indicating its state and a small
superscript number showing the agent count. Click for a scrollable agent list,
or right-click to refresh. It refreshes every two seconds by default. Opening the
widget does not acknowledge results or change Herdr focus.

## Display modes

- **Single status (default):** one bot for the highest-priority status, with the
  number of agents in that state. Priority is blocked, unread completed, working,
  unknown, then idle. An empty session shows a green bot without a count.
- **Every status:** separate bots in **green → yellow → red → blue** order
  (idle, working, blocked, unread completed), each with a count, including zero.
  A gray bot is appended when agents have unknown status.

Icons run across horizontal bars and stack on vertical bars. In either mode, a
connection failure shows a single gray bot without stale counts.

### Screenshots

Captured from a running DankBar widget on Hyprland.

| Single status | Every status |
| --- | --- |
| ![Single yellow bot showing one working agent](screenshots/single-status.png) | ![Four idle, zero working, one blocked, and zero unread completed agents](screenshots/every-status.png) |

## Install

Requires DankMaterialShell **1.6+** and Herdr **0.9.3+** on Linux. Herdr must
already be running. The widget uses the installed CLI's `herdr agent list` API.

### Custom repository (recommended)

Add this repository as a custom DMS registry, then install the plugin:

```sh
dms registry add marcobeierer https://github.com/marcobeierer/dankmaterialshell-plugins.git
dms plugins install herdrStatus
```

Register the repository only once. DMS downloads the plugin from the
`herdr-status` subdirectory; you do not need to clone the repository or run
`install.sh`. Herdr itself must be installed separately.

If `dms registry add` is unavailable in your build, use the
[manual registry configuration](../README.md#manual-registry-configuration).

For future updates:

```sh
dms plugins update herdrStatus
```

### Local checkout (development)

From this plugin directory:

```sh
./install.sh
```

The installer creates a symlink to this directory, so keep the source in place.
It is safe to rerun and refuses to overwrite another installation. It does not
install dependencies or restart the shell. For a custom plugins directory:

```sh
./install.sh "${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins"
```

Use either this development symlink or a registry-managed installation, not both.

### Enable the widget

In DMS, open **Settings → Plugins**, scan for plugins, and enable **Herdr Status**.
Add it to your DankBar layout. Both horizontal and vertical bars are supported.
If DMS uses a different configuration directory, pass its `plugins/` subdirectory
to the installer instead (newer Dux Shell releases use `~/.config/dms`).

## Settings

### Global plugin settings

Open **Settings → Plugins → Herdr Status** to configure:

- **Herdr executable:** defaults to `herdr`. If it is not on DMS's `PATH`, use
  the absolute path returned by `command -v herdr`, for example
  `/home/you/.local/bin/herdr`. This is a path, not a shell command; `~` is not
  expanded and arguments are not accepted here.
- **Named session:** empty selects the default session. Set a name to monitor a
  different session. This widget does not aggregate multiple named sessions or
  saved SSH machines.
- **Refresh interval:** 1–30 seconds.

The widget's child process clears inherited `HERDR_SOCKET_PATH` and
`HERDR_SESSION` overrides so session selection is explicit. Custom Herdr config
locations via `HERDR_CONFIG_PATH` still follow the desktop environment.

### Per-widget display settings

1. Click the bot icon to open the agent list.
2. Click the **gear icon** next to the close button to open the dedicated settings
   view.
3. Toggle **Show every status** to switch display modes.
4. Click the **back arrow** to return to the agent list, or close the popout.

Changes are saved automatically on that widget's DankBar entry and survive
reloads and restarts. Different widgets can use different display modes. Widgets
sharing the same bar entry across monitors share this setting. Display mode is
not a global plugin setting.

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

If plugin settings still show an older version after editing their QML file,
fully restart DMS; reloading the plugin may leave the settings component cached.

## License

[MIT](../LICENSE) © 2026 Marco Beierer.
