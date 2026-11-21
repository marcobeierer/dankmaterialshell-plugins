#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 1 && ( $1 == --help || $1 == -h ) ]]; then
    printf 'Usage: %s [plugins-directory]\n' "${0##*/}"
    exit 0
fi
if [[ $# -gt 1 || ( $# -eq 1 && -z $1 ) ]]; then
    printf 'Usage: %s [plugins-directory]\n' "${0##*/}" >&2
    exit 1
fi

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
plugins_dir="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins}"
for file in plugin.json AgentApprovals.qml ApprovalModel.js bridge.py opencode/index.js; do
    if [[ ! -f "$source_dir/$file" ]]; then
        printf 'Missing plugin file: %s\n' "$source_dir/$file" >&2
        exit 1
    fi
done
command -v python3 >/dev/null
mkdir -p -- "$plugins_dir"
plugins_dir="$(cd -- "$plugins_dir" && pwd -P)"
destination="$plugins_dir/AgentApprovals"
if [[ -L "$destination" && "$(readlink -f -- "$destination")" == "$source_dir" ]]; then
    printf 'Already installed: %s\n' "$destination"
elif [[ -e "$destination" || -L "$destination" ]]; then
    printf 'Refusing to overwrite existing path: %s\n' "$destination" >&2
    exit 1
else
    ln -sT -- "$source_dir" "$destination"
    printf 'Installed: %s -> %s\n' "$destination" "$source_dir"
fi
printf '\nIn DMS: Settings → Plugins → Scan for Plugins → enable Agent Approvals.\n'
printf 'Then configure your agents using %s/README.md.\n' "$source_dir"
printf 'Keep this source directory in place; the installation is a symlink.\n'
