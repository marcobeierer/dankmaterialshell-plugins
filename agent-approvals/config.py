#!/usr/bin/env python3
"""Print the agent configuration to merge; never modify existing settings."""

import argparse
import json
from pathlib import Path
import shlex


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("agent", choices=["opencode", "codex", "claude"])
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    if args.agent == "opencode":
        config = {
            "$schema": "https://opencode.ai/config.json",
            "plugins": [str(root / "opencode")],
        }
    else:
        config = {
            "hooks": {
                "PermissionRequest": [{
                    "hooks": [{
                        "type": "command",
                        "command": shlex.join(["python3", str(root / "bridge.py"), args.agent]),
                        "timeout": 600,
                    }],
                }],
            },
        }
    print(json.dumps(config, indent=2))


if __name__ == "__main__":
    main()
