#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [plugins-directory]\n' "${0##*/}"
    printf 'Default: ${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins\n'
}

if [[ $# -eq 1 && ( $1 == --help || $1 == -h ) ]]; then
    usage
    exit 0
fi
if [[ $# -gt 1 || ( $# -eq 1 && -z $1 ) ]]; then
    usage >&2
    exit 1
fi

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
plugins_dir="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins}"

for file in plugin.json WindowPicker.qml WindowModel.js; do
    if [[ ! -f "$source_dir/$file" ]]; then
        printf 'Missing plugin file: %s\n' "$source_dir/$file" >&2
        exit 1
    fi
done

mkdir -p -- "$plugins_dir"
plugins_dir="$(cd -- "$plugins_dir" && pwd -P)"
destination="$plugins_dir/WindowPicker"

if [[ -L "$destination" && "$(readlink -f -- "$destination")" == "$source_dir" ]]; then
    printf 'Already installed: %s\n' "$destination"
elif [[ -e "$destination" || -L "$destination" ]]; then
    printf 'Refusing to overwrite existing path: %s\n' "$destination" >&2
    exit 1
else
    ln -sT -- "$source_dir" "$destination"
    printf 'Installed: %s -> %s\n' "$destination" "$source_dir"
fi

printf '\nIn DMS: Settings → Plugins → Scan for Plugins → enable Window Picker.\n'
printf 'Bind your shortcut to: dms ipc call windowPicker toggle\n'
printf 'Requires DMS 1.6.2+ with Hyprland or Niri. No bar widget is needed.\n'
printf 'Keep this source directory in place; the installation is a symlink.\n'
