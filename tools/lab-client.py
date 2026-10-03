#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 sway pulseaudio
"""Run a single operation on the private Signs of Rain display, never Korri's."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument(
    "action", choices=["play", "input", "inspect", "resize", "audio", "close"]
)
parser.add_argument("args", nargs="*")
args = parser.parse_args()
root = Path.home() / ".local/share/signs-of-rain"
lab = root / "lab"
seat = json.loads((lab / "seat.json").read_text())
runtime = Path(seat["XDG_RUNTIME_DIR"])
if not str(runtime).startswith("/tmp/signs-seat-") or not runtime.is_dir():
    raise SystemExit(
        "Missing private Signs of Rain seat; refusing shared-display fallback"
    )
if not Path(seat["WAYLAND_DISPLAY"]).is_socket():
    raise SystemExit("Private display socket missing")
env = dict(os.environ)
for key in [
    "XDG_RUNTIME_DIR",
    "WAYLAND_DISPLAY",
    "SWAYSOCK",
    "PULSE_SERVER",
    "PULSE_SINK",
    "PULSE_SOURCE",
]:
    env[key] = seat[key]
env.pop("DISPLAY", None)
if args.action == "play":
    release = root / "current"
    os.execvpe(
        str(release / "launch"),
        [
            str(release / "launch"),
            "--",
            "--evidence=" + str(lab / "state.json"),
            *args.args,
        ],
        env,
    )
elif args.action == "input":
    helper = root / "tools/headless-seat.py"
    os.execvpe(
        str(helper), [str(helper), "--wayland-display", seat["WAYLAND_DISPLAY"]], env
    )
elif args.action == "close":
    subprocess.run(["swaymsg", '[title="Signs of Rain"]', "kill"], env=env, check=True)
elif args.action == "resize":
    width, height = [int(x) for x in args.args]
    if not 320 <= width <= 3840 or not 240 <= height <= 2160:
        raise SystemExit("Unsupported test size")
    subprocess.run(
        ["swaymsg", "output", "HEADLESS-1", "mode", f"{width}x{height}"],
        env=env,
        check=True,
    )
elif args.action == "inspect":
    for command in [
        ["swaymsg", "-t", "get_outputs"],
        ["swaymsg", "-t", "get_tree"],
        ["pactl", "list", "sink-inputs"],
    ]:
        subprocess.run(command, env=env, check=True)
elif args.action == "audio":
    seconds = min(30.0, max(1.0, float(args.args[0]) if args.args else 6.0))
    with (lab / "audio.s16le").open("wb") as output:
        process = subprocess.Popen(
            [
                "parec",
                "--device=" + seat["PULSE_SOURCE"],
                "--format=s16le",
                "--rate=48000",
                "--channels=2",
            ],
            env=env,
            stdout=output,
        )
        try:
            time.sleep(seconds)
        finally:
            process.terminate()
            process.wait(timeout=5)
    print("AUDIO_DONE", flush=True)
