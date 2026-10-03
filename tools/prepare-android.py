#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 openssh
"""Realise the locked flake toolchain and copy its closure to the build host."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path.home() / ".cache/signs-of-rain/android-toolchain"


def validate_manifest(toolchain):
    manifest = json.loads((toolchain / "manifest.json").read_text())
    if manifest["template_version"] != "4.6.1.stable":
        raise ValueError("Replay/export checks require Godot templates 4.6.1")
    for name in ["engine", "java", "sdk", "templates", "python", "git"]:
        if not Path(manifest[name]).is_dir():
            raise ValueError("Missing toolchain directory: " + manifest[name])
    templates = Path(manifest["templates"])
    for name in ["android_debug.apk", "android_release.apk"]:
        with (templates / name).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != manifest["templates_sha256"][name]:
            raise ValueError("Template checksum mismatch: " + name)
    return manifest


def realise():
    if not (ROOT / "flake.lock").is_file():
        raise ValueError(
            "Run preparation from a Signs of Rain checkout with flake.lock"
        )
    result = subprocess.run(
        ["nix", "build", str(ROOT) + "#android-toolchain", "--no-link", "--json"],
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    return Path(json.loads(result.stdout)[0]["outputs"]["out"])


def prepare(toolchain):
    manifest = validate_manifest(toolchain)
    CACHE.mkdir(parents=True, exist_ok=True)
    roots = CACHE / "nix-roots"
    roots.mkdir(exist_ok=True)
    subprocess.run(
        [
            "nix-store",
            "--add-root",
            str(roots / "toolchain"),
            "--indirect",
            "--realise",
            str(toolchain),
        ],
        check=True,
    )
    (CACHE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("ANDROID_TOOLCHAIN_READY " + str(CACHE / "manifest.json"), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="simonwjackson@aka")
    parser.add_argument("--local", action="store_true")
    parser.add_argument(
        "--toolchain", type=Path, help="Already realised flake toolchain directory"
    )
    args = parser.parse_args()
    toolchain = args.toolchain.resolve() if args.toolchain else realise()
    if args.local:
        prepare(toolchain)
        return
    if not re.fullmatch(
        r"[a-zA-Z0-9_][a-zA-Z0-9_.-]*(?:@[a-zA-Z0-9_][a-zA-Z0-9_.-]*)?", args.host
    ):
        raise ValueError("A simple SSH host or user@host is required")
    subprocess.run(
        ["nix", "copy", "--to", "ssh://" + args.host, str(toolchain)], check=True
    )
    manifest = validate_manifest(toolchain)
    python = str(Path(manifest["python"]) / "bin/python3")
    remote = "/tmp/signs-prepare-android.py"
    subprocess.run(
        ["scp", "-q", str(Path(__file__).resolve()), args.host + ":" + remote],
        check=True,
    )
    subprocess.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            args.host,
            python,
            remote,
            "--local",
            "--toolchain",
            str(toolchain),
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
