#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Run the actual engine tests and source checks, failing on Godot log errors."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from godot_profile import isolated_environment

ROOT = Path(__file__).resolve().parents[1]


def executable(name, variable):
    path = os.environ.get(variable) or shutil.which(name)
    if not path:
        raise SystemExit("Missing " + name + "; use nix run .#check or nix develop")
    return path


GODOT = executable("godot", "GODOT")
GDFORMAT = executable("gdformat", "GDFORMAT")
GDLINT = executable("gdlint", "GDLINT")
RUFF = executable("ruff", "RUFF")
if not subprocess.check_output([GODOT, "--version"], text=True).startswith("4.6.1."):
    raise SystemExit("Replay validation requires Godot 4.6.1")
commands = [
    [GODOT, "--headless", "--path", ".", "--editor", "--import", "--quit"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/simulation_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/presentation_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/camera_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/character_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/terrain_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/view_interaction_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/picking_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/graphics_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/controller_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/frame_times_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/touch_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/touch_layout_test.gd"],
    [GODOT, "--headless", "--path", ".", "--script", "tests/density_test.gd"],
    [sys.executable, "tests/operations_test.py"],
    [sys.executable, "tests/android_build_test.py"],
    [GDFORMAT, "--check", "game", "ui", "sim", "tests"],
    [GDLINT, "game", "ui", "sim", "tests"],
    [RUFF, "check", "tools", "tests"],
    [RUFF, "format", "--check", "tools", "tests"],
]
# Engine tests must not read or change the player's settings or editor profile.
private = tempfile.TemporaryDirectory(prefix="signs-check-")
environment = isolated_environment(private.name)
results = []
for command in commands:
    result = subprocess.run(
        command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=90
    )
    print(result.stdout)
    print(result.stderr)
    passed = (
        result.returncode == 0
        and "ERROR:" not in result.stderr
        and "ERROR:" not in result.stdout
    )
    results.append(
        {
            "command": command,
            "passed": passed,
            "exit": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    )
private.cleanup()
report = Path(
    os.environ.get("SIGNS_CHECK_REPORT", str(ROOT / "verification/local-checks.json"))
)
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text(json.dumps(results, indent=2) + "\n")
raise SystemExit(0 if all(item["passed"] for item in results) else 1)
