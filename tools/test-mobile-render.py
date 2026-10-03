#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 sway
"""Capture the Mobile renderer on an owned headless compositor, never a live seat."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from godot_profile import isolated_environment
from owned_process import stop_owned

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot")
if not GODOT:
    raise SystemExit("Missing Godot; run this script inside nix develop")
CASES = [
    ("folded", 360, 720, 1.0),
    ("unfolded", 720, 900, 1.0),
    ("density", 1848, 2448, 3.0),
    ("short", 1280, 300, 1.0),
]


def live_processes():
    output = subprocess.check_output(["ps", "-eo", "pid,args"], text=True)
    return sorted(
        line.strip()
        for line in output.splitlines()
        if any(
            name in line
            for name in ["BW2/white.exe", "sunshine", "korri-compositor-sway.conf"]
        )
    )


def run(arguments, env):
    result = subprocess.run(
        arguments, env=env, text=True, capture_output=True, timeout=120
    )
    if result.returncode or "ERROR:" in result.stdout or "ERROR:" in result.stderr:
        raise RuntimeError(result.stdout + result.stderr)
    return result


def test(output):
    output.mkdir(parents=True, exist_ok=True)
    before = live_processes()
    compositor = None
    with tempfile.TemporaryDirectory(prefix="signs-mobile-render-") as temporary:
        temporary = Path(temporary)
        runtime = temporary / "runtime"
        runtime.mkdir(mode=0o700)
        project = temporary / "project"
        project.mkdir()
        for folder in ["assets", "game", "ui", "sim", "tests"]:
            shutil.copytree(ROOT / folder, project / folder)
        shutil.copyfile(ROOT / "project.godot", project / "project.godot")
        config = temporary / "sway.conf"
        config.write_text(
            'output * mode 720x900\noutput * bg #123333 solid_color\ndefault_border none\nfocus_follows_mouse no\nfor_window [app_id=".*"] fullscreen enable\n'
        )
        env = isolated_environment(temporary)
        env.update(
            XDG_RUNTIME_DIR=str(runtime),
            WLR_BACKENDS="headless",
            WLR_RENDERER="gles2",
            WLR_RENDER_DRM_DEVICE="/dev/dri/renderD128",
            WLR_LIBINPUT_NO_DEVICES="1",
        )
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "SWAYSOCK"]:
            env.pop(key, None)
        run(
            [
                GODOT,
                "--headless",
                "--path",
                str(project),
                "--editor",
                "--import",
                "--quit",
            ],
            env,
        )
        try:
            with (output / "compositor.log").open("w") as log:
                compositor = subprocess.Popen(
                    ["sway", "--unsupported-gpu", "-c", str(config)],
                    env=env,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                )
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    displays = [
                        path for path in runtime.glob("wayland-*") if path.is_socket()
                    ]
                    sockets = list(runtime.glob("sway-ipc.*.sock"))
                    if displays and sockets:
                        env["WAYLAND_DISPLAY"] = str(displays[0])
                        env["SWAYSOCK"] = str(sockets[0])
                        break
                    if compositor.poll() is not None:
                        raise RuntimeError(
                            "Owned compositor exited; see compositor.log"
                        )
                    time.sleep(0.1)
                else:
                    raise RuntimeError("Owned compositor startup timeout")
                for name, width, height, scale in CASES:
                    destination = output / name
                    destination.mkdir(exist_ok=True)
                    run(
                        [
                            "swaymsg",
                            "output",
                            "HEADLESS-1",
                            "mode",
                            f"{width}x{height}",
                        ],
                        env,
                    )
                    result = run(
                        [
                            GODOT,
                            "--path",
                            str(project),
                            "--display-driver",
                            "wayland",
                            "--audio-driver",
                            "Dummy",
                            "--rendering-method",
                            "mobile",
                            "--script",
                            "tests/mobile_render_test.gd",
                            "--",
                            "--mute",
                            "--graphics=fast",
                            "--shots=" + str(destination),
                            "--ui-scale=" + str(scale),
                        ],
                        env,
                    )
                    (destination / "game.log").write_text(result.stdout + result.stderr)
        finally:
            stop_owned(compositor)
    after = live_processes()
    report = {
        "actual_android_device": False,
        "cases": [
            json.loads((output / name / "render.json").read_text())
            for name, *_ in CASES
        ],
        "preserved_live_processes": before == after,
        "before": before,
        "after": after,
    }
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    if before != after:
        raise RuntimeError(
            "Live application process set changed during the isolated test"
        )
    print("MOBILE_RENDER_READY " + str(output), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path, default=ROOT / "artifacts/android-render"
    )
    args = parser.parse_args()
    test(args.output.resolve())


if __name__ == "__main__":
    main()
