#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Verify a transferred pack and atomically publish only a complete release."""

import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def verify_release(directory: Path) -> dict:
    manifest = json.loads((directory / "manifest.json").read_text())
    for name, expected in manifest["files"].items():
        relative = Path(name)
        path = directory / relative
        if (
            relative.is_absolute()
            or ".." in relative.parts
            or path.is_symlink()
            or not path.is_file()
            or not path.resolve().is_relative_to(directory.resolve())
        ):
            raise ValueError("Unsafe release member: " + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError("SHA256 mismatch: " + name)
    return manifest


def stage_release(source: Path, root: Path) -> Path:
    verify_release(source)
    manifest_bytes = (source / "manifest.json").read_bytes()
    release_id = hashlib.sha256(manifest_bytes).hexdigest()[:16]
    releases = root / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    destination = releases / release_id
    if destination.exists():
        if (
            destination.is_symlink()
            or (destination / "manifest.json").read_bytes() != manifest_bytes
        ):
            raise ValueError("Existing release is not the expected verified directory")
        verify_release(destination)
        return destination
    temporary = Path(tempfile.mkdtemp(prefix=".stage-", dir=releases))
    try:
        # Publication only happens after the copied bytes pass verification.
        content = temporary / "content"
        shutil.copytree(source, content, symlinks=True)
        verify_release(content)
        content.rename(destination)
    finally:
        shutil.rmtree(temporary)
    return destination


def publish_link(destination: Path, root: Path) -> None:
    verify_release(destination)
    link = root / "current.next"
    link.unlink(missing_ok=True)
    link.symlink_to(destination)
    link.replace(root / "current")


def main() -> None:
    source = Path(sys.argv[1]).resolve()
    root = Path.home() / ".local/share/signs-of-rain"
    if root.is_symlink():
        raise SystemExit("Refusing a symlinked project root")
    root.mkdir(parents=True, exist_ok=True)
    with (root / "launch.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(
                "Stop only the running Signs of Rain instance before deployment"
            )
        manifest = verify_release(source)
        destination = stage_release(source, root)
        # Retain the exact engine before switching the live link.
        subprocess.run(
            [
                "nix-store",
                "--add-root",
                str(root / "runtime"),
                "--indirect",
                "--realise",
                manifest["runtime"],
            ],
            check=True,
        )
        publish_link(destination, root)
        print(
            json.dumps(
                {
                    "release": str(destination),
                    "pack_sha256": manifest["files"]["signs-of-rain.pck"],
                    "source_commit": manifest["commit"],
                    "dirty": manifest["uncommitted_source"],
                }
            )
        )


if __name__ == "__main__":
    main()
