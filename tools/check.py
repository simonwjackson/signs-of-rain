#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Run the actual engine tests and source checks, failing on Godot log errors."""

import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get(
    "GODOT", "/nix/store/prgpch05xca3nvd945kz5kbixpjdwis1-godot-4.6.1-stable/bin/godot"
)
GD = "/nix/store/pj444b1388w76r3zi7y75r3fgbrqg8ji-gdtoolkit-4.5.0/bin/"
RUFF = "/nix/store/nmylkiq687h76gk4snd3kqqvwbwg1vnd-ruff-0.15.5/bin/ruff"
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
    [sys.executable, "tests/operations_test.py"],
    [GD + "gdformat", "--check", "game", "ui", "sim", "tests"],
    [GD + "gdlint", "game", "ui", "sim", "tests"],
    [RUFF, "check", "tools", "tests"],
    [RUFF, "format", "--check", "tools", "tests"],
]
results = []
for command in commands:
    result = subprocess.run(
        command, cwd=ROOT, capture_output=True, text=True, timeout=90
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
report = ROOT / "verification/local-checks.json"
report.parent.mkdir(exist_ok=True)
report.write_text(json.dumps(results, indent=2) + "\n")
raise SystemExit(0 if all(item["passed"] for item in results) else 1)
