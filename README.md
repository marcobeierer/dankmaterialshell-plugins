# DankMaterialShell Plugins

Plugins for [DankMaterialShell](https://danklinux.com/).

## Plugins

### [Herdr Status](herdr-status/)

A native DankBar widget that monitors agents in one local Herdr session.

- Colored bot icons with small superscript agent counts.
- A compact single-status mode, or separate icons in **green → yellow → red →
  blue** order for idle, working, blocked, and unread completed agents.
- A scrollable agent list and a dedicated settings view, opened with the gear
  icon beside the popout's close button.
- Display mode saved independently for each widget; horizontal and vertical bars
  are supported.

No agent plugin or helper daemon is required. Viewing the widget does not mark
results as read.

Requires Linux, DankMaterialShell **1.6+**, and a running Herdr **0.9.3+** session.

## Installation

From the repository root:

```sh
./herdr-status/install.sh
```

The installer symlinks the plugin into
`${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins`. Keep this repository
in place. To use a different plugins directory, pass it as an argument:

```sh
./herdr-status/install.sh "${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins"
```

In DMS, open **Settings → Plugins**, scan for plugins, enable **Herdr Status**, and
add it to your DankBar layout.

Click the widget, then the **gear icon** to enable **Show every status** for that
widget. The default is a single icon for the highest-priority status. Executable,
session, and refresh interval are configured in the global plugin settings.

See the [Herdr Status README](herdr-status/README.md) for configuration, status
semantics, and troubleshooting.

## License

[MIT](LICENSE)
