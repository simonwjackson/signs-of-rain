"""Isolate build/test editor and game data without stopping the shared ADB server."""

import json
import os
from pathlib import Path


def isolated_environment(root, *, settings=None):
    """Return a private Godot profile; caller-owned signing stays in environment variables."""
    root = Path(root)
    environment = dict(os.environ)
    for kind in ("CONFIG", "DATA", "CACHE"):
        directory = root / kind.lower()
        directory.mkdir(parents=True, exist_ok=True)
        environment["XDG_" + kind + "_HOME"] = str(directory)
    editor = root / "config/godot"
    editor.mkdir(exist_ok=True)
    options = dict(settings or {})
    # A headless editor can discover ANDROID_HOME and kill the shared daemon on
    # exit. This policy is mandatory even when callers supply editor settings.
    options["export/android/shutdown_adb_on_exit"] = False
    content = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    content += "".join(
        key + " = " + json.dumps(value) + "\n" for key, value in options.items()
    )
    (editor / "editor_settings-4.6.tres").write_text(content)
    return environment
