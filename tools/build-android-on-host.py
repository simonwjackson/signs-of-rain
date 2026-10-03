#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 openssh git rsync
"""Build a committed source snapshot remotely and retrieve its verified APK."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(arguments, cwd=ROOT):
    return subprocess.run(arguments, cwd=cwd, check=True, text=True)


def prepare(root, bundle, git):
    destination = Path(root).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    run(
        [git, "clone", "--quiet", bundle, str(destination / "source")],
        cwd=destination,
    )
    Path(bundle).unlink()


def build(host, initialize):
    if not re.fullmatch(
        r"[a-zA-Z0-9_][a-zA-Z0-9_.-]*(?:@[a-zA-Z0-9_][a-zA-Z0-9_.-]*)?", host
    ):
        raise ValueError("A simple SSH host or user@host is required")
    dirty = subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True
    )
    if dirty:
        raise ValueError("Commit the source before producing a remote release")
    toolchain = os.environ.get("SIGNS_ANDROID_TOOLCHAIN")
    if not toolchain:
        raise ValueError("Use nix run .#build-android or run inside nix develop")
    tooling = json.loads((Path(toolchain) / "manifest.json").read_text())
    python = str(Path(tooling["python"]) / "bin/python3")
    git = str(Path(tooling["git"]) / "bin/git")
    run(["nix", "copy", "--to", "ssh://" + host, toolchain])
    with tempfile.TemporaryDirectory(prefix="signs-android-upload-") as temporary:
        bundle = Path(temporary) / "source.bundle"
        run(["git", "bundle", "create", str(bundle), "HEAD"])
        stamp = str(time.time_ns())
        # Paths are relative to the remote user's home, not a local username.
        remote = ".cache/signs-of-rain/android-build/" + stamp
        script = "/tmp/signs-android-on-host-" + stamp + ".py"
        remote_bundle = "/tmp/signs-android-" + stamp + ".bundle"
        run(["scp", "-q", str(Path(__file__).resolve()), host + ":" + script])
        run(["scp", "-q", str(bundle), host + ":" + remote_bundle])
        run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                host,
                python,
                script,
                "--git",
                git,
                "--remote-prepare",
                remote,
                remote_bundle,
            ]
        )
        arguments = [
            "ssh",
            "-o",
            "BatchMode=yes",
            host,
            python,
            remote + "/source/tools/build-android.py",
            "--toolchain",
            toolchain + "/manifest.json",
        ]
        if initialize:
            arguments.append("--init-signing")
        run(arguments)
        destination = ROOT / "build/android"
        destination.mkdir(parents=True, exist_ok=True)
        run(
            [
                "scp",
                "-q",
                "-r",
                host + ":" + remote + "/source/build/android/.",
                str(destination),
            ]
        )
        manifest = json.loads((destination / "manifest.json").read_text())
        if manifest["uncommitted_source"]:
            raise ValueError(
                "Remote build changed source; refusing a clean release claim"
            )
        note = {
            "host": host,
            "remote_checkout": remote + "/source",
            "local_apk": str(destination / "signs-of-rain.apk"),
        }
        (destination / "remote-build.json").write_text(
            json.dumps(note, indent=2) + "\n"
        )
        print("APK_RETRIEVED " + str(destination / "signs-of-rain.apk"), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="simonwjackson@aka")
    parser.add_argument("--init-signing", action="store_true")
    parser.add_argument("--remote-prepare", nargs=2, metavar=("DIRECTORY", "BUNDLE"))
    parser.add_argument(
        "--git", help="Pinned Git executable for remote clone preparation"
    )
    args = parser.parse_args()
    if args.remote_prepare:
        if not args.git:
            parser.error("--remote-prepare requires the pinned --git executable")
        prepare(*args.remote_prepare, args.git)
    else:
        build(args.host, args.init_signing)


if __name__ == "__main__":
    main()
