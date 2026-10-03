#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 sway grim wf-recorder ffmpeg pulseaudio
"""Own a private headless Sway display and null sink, never the user's live seat.

Run this on aka via the process manager. Quit/EOF shuts down only owned processes
and the one created PulseAudio module. Protocol: shot NAME, record NAME,
stop-record, status, quit. NAME must be a simple filename.
"""

import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from owned_process import stop_owned

root = Path.home() / ".local/share/signs-of-rain"
root.mkdir(parents=True, exist_ok=True)
lab = root / "lab"
lab.mkdir(exist_ok=True)
seat_lock = (lab / "seat.lock").open("a")
try:
    fcntl.flock(seat_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit("A private Signs of Rain seat already owns this lab")
runtime = Path(tempfile.mkdtemp(prefix="signs-seat-", dir="/tmp"))
runtime.chmod(0o700)
config = runtime / "sway.conf"
config.write_text(
    'output * mode 1440x900\noutput * bg #123333 solid_color\ndefault_border none\nfocus_follows_mouse no\nseat seat0 fallback true\nseat seat0 attach *\ninput * xkb_layout us\nfor_window [app_id=".*"] fullscreen enable\n'
)
env = dict(
    os.environ,
    XDG_RUNTIME_DIR=str(runtime),
    WLR_BACKENDS="headless",
    WLR_RENDERER="gles2",
    WLR_RENDER_DRM_DEVICE="/dev/dri/renderD128",
    WLR_LIBINPUT_NO_DEVICES="1",
    PULSE_SERVER="unix:/run/user/1000/pulse/native",
)
for key in ["DISPLAY", "WAYLAND_DISPLAY", "SWAYSOCK"]:
    env.pop(key, None)
children = []
recorder = None
module = None


def name(value):
    if not value or Path(value).name != value or value in (".", ".."):
        raise ValueError("Simple filename required")
    return str(lab / value)


def shutdown(*unused):
    raise KeyboardInterrupt


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)
try:
    log = (lab / "compositor.log").open("w")
    sway = subprocess.Popen(
        ["sway", "--unsupported-gpu", "-c", str(config)],
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
    )
    children.append(sway)
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        sockets = list(runtime.glob("wayland-*"))
        displays = [p for p in sockets if p.is_socket()]
        if displays:
            env["WAYLAND_DISPLAY"] = str(displays[0])
            break
        if sway.poll() is not None:
            raise RuntimeError(
                "Private Sway exited; see " + str(lab / "compositor.log")
            )
        time.sleep(0.1)
    else:
        raise RuntimeError("Private display startup timeout")
    ipc = list(runtime.glob("sway-ipc.*.sock"))
    if not ipc:
        raise RuntimeError("No private Sway IPC socket")
    env["SWAYSOCK"] = str(ipc[0])
    sink = "signs_rain_" + str(os.getpid())
    result = subprocess.run(
        [
            "pactl",
            "load-module",
            "module-null-sink",
            "sink_name=" + sink,
            "rate=48000",
            "channels=2",
        ],
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    module = result.stdout.strip()
    env["PULSE_SINK"] = sink
    env["PULSE_SOURCE"] = sink + ".monitor"
    # Persist only environment data needed by explicitly scoped target scripts.
    info = {
        key: env[key]
        for key in [
            "XDG_RUNTIME_DIR",
            "WAYLAND_DISPLAY",
            "SWAYSOCK",
            "PULSE_SERVER",
            "PULSE_SINK",
            "PULSE_SOURCE",
        ]
    }
    info["seat_pid"] = sway.pid
    info["controller_pid"] = os.getpid()
    info["sink_module"] = module
    (lab / "seat.json").write_text(json.dumps(info, indent=2))
    print("PRIVATE_SEAT_READY " + json.dumps(info), flush=True)
    for line in sys.stdin:
        args = line.strip().split(" ", 1)
        if args[0] == "quit":
            break
        if args[0] == "shot":
            subprocess.run(
                ["grim", name(args[1])],
                env=env,
                check=True,
                timeout=15,
                stdin=subprocess.DEVNULL,
            )
            print("SHOT_DONE " + args[1], flush=True)
        elif args[0] == "record":
            if recorder is not None and recorder.poll() is None:
                raise RuntimeError("Already recording")
            output = name(args[1])
            existing = Path(output)
            if existing.exists():
                existing.rename(
                    existing.with_name(
                        existing.stem
                        + "-previous-"
                        + str(time.time_ns())
                        + existing.suffix
                    )
                )
            record_log = (lab / "recorder.log").open("w")
            recorder = subprocess.Popen(
                [
                    "wf-recorder",
                    "-f",
                    output,
                    "-c",
                    "libx264",
                    "-p",
                    "preset=ultrafast",
                    "-r",
                    "30",
                    "--audio=" + env["PULSE_SOURCE"],
                ],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=record_log,
                stderr=subprocess.STDOUT,
            )
            print("RECORD_STARTED", flush=True)
        elif args[0] == "stop-record":
            result = stop_owned(recorder)
            if result == "SIGKILL":
                print("RECORD_FORCED_STOP recording may be incomplete", flush=True)
            recorder = None
            print("RECORD_DONE", flush=True)
        elif args[0] == "status":
            outputs = subprocess.run(
                ["swaymsg", "-t", "get_outputs"],
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            print(outputs.stdout, flush=True)
        elif args[0]:
            print("Unknown command", flush=True)
except KeyboardInterrupt:
    pass
finally:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    errors = []
    for child in [recorder, *reversed(children)]:
        try:
            result = stop_owned(child)
            if result == "SIGKILL":
                print(
                    "FORCED_STOP owned child; recording may be incomplete", flush=True
                )
        except (OSError, TimeoutError) as error:
            errors.append(str(error))
    if module is not None:
        try:
            subprocess.run(
                ["pactl", "unload-module", module], env=env, check=True, timeout=10
            )
        except (OSError, subprocess.SubprocessError) as error:
            errors.append(str(error))
    # Keep own logs and seat.json as evidence. Each cleanup is independent.
    try:
        shutil.rmtree(runtime)
    except OSError as error:
        errors.append(str(error))
    if errors:
        raise RuntimeError("Private seat cleanup: " + "; ".join(errors))
