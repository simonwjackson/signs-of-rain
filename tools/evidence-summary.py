#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("path")
parser.add_argument("--people", action="store_true")
args = parser.parse_args()
data = json.loads(Path(args.path).read_text())
fields = [
    "tick",
    "power",
    "paused",
    "ended",
    "selected",
    "speed",
    "replaying",
    "restart_count",
    "digest",
    "previous_digest",
    "tick_on_restart",
    "window_size",
    "world_rect",
    "fps",
    "commands",
    "input_events",
    "summary",
]
print(json.dumps({key: data.get(key) for key in fields}, indent=2))
if args.people:
    for person in data["people"]:
        print(
            person["id"],
            person["name"],
            person["pos"],
            person["belief"],
            person["action"],
            len(person["memories"]),
            person["cause"],
        )
