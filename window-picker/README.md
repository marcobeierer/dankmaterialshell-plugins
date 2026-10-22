# Window Picker

A keyboard-driven window picker for DankMaterialShell **1.6.2+**, supporting
**Hyprland** and **Niri**. No helper process or DankBar widget is required.

- Lists open windows under workspace headings, including the output name.
- Searches window titles, application IDs/classes, workspace names, and outputs.
  Search is case-insensitive; space-separated terms must all match.
- Updates as windows open, close, change title, or move between workspaces.
- **↑/↓** or **Tab/Shift+Tab** selects a result, wrapping at the ends.
- **Enter** confirms; clicking a result also confirms. The picker closes, switches
  to the window's workspace/output, and focuses that window.
- **Esc**, the close button, clicking outside, or repeating the shortcut cancels.
- Includes Hyprland special workspaces. On Niri, workspace numbers are local to
  each output; matching numbers on different outputs remain separate groups.

## Installation

From this repository's [custom registry](../README.md#from-this-registry):

```sh
dms plugins install windowPicker
```

For local development, from the repository root:

```sh
./window-picker/install.sh
```

Optionally pass a different plugin directory as the first argument. The installer
creates a symlink and refuses to overwrite an existing installation. Keep the
checkout in place, and use either the symlink or the registry installation, not
both for this plugin ID.

In DMS, open **Settings → Plugins**, scan for plugins, and enable **Window Picker**.
It runs as a DMS daemon plugin, meaning one in-shell instance, not an OS service.

## Keyboard shortcut

Bind a free shortcut in your compositor to:

```sh
dms ipc call windowPicker toggle
```

For example, **Super+W** on Hyprland (`hyprland.conf`):

```ini
bind = SUPER, W, exec, dms ipc call windowPicker toggle
```

Or Niri (`config.kdl`, inside your existing `binds` block):

```kdl
Mod+W { spawn "dms" "ipc" "call" "windowPicker" "toggle"; }
```

Replace any conflicting binding or choose another key. This plugin deliberately
does not modify your compositor configuration. The IPC methods `open` and `close`
are also available if you want explicit show/hide bindings.

## Troubleshooting

- **Other shortcuts stop working until Esc:** check for a duplicate compositor
  binding that enters a keyboard submap. Hyprland executes both bindings, so the
  picker can close normally while the submap remains active. Remove the conflicting
  binding; `hyprctl submap` shows the current keyboard mode.
- **IPC target not found:** enable the plugin, and check that the command reaches
  your running DMS session. After updating plugin files, reload the plugin or DMS.
- **No matching windows:** clear the search using its clear button.
- **No open windows:** check that DMS's compositor connection is available. Only
  windows exposed by that compositor are listed; layer-shell panels are not windows.
- **Window closed during confirmation:** the picker reports it instead of focusing
  a different result. Open the picker again to select another window.
- Other compositors are not currently supported because workspace metadata and
  window activation differ between compositors.

## License

[MIT](../LICENSE)
