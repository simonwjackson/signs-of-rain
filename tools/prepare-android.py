#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 openssh
"""Prepare the pinned APK export tools in an isolated cache on the build host."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request
import zipfile

SDK = "/nix/store/f5j2kjc1frfx95llzb239czpy04g162x-androidsdk"
JAVA = "/nix/store/2y0qz1r84ckgmmrnfvx9bbysnyn1zb61-openjdk-17.0.20+8"
GODOT = "/nix/store/prgpch05xca3nvd945kz5kbixpjdwis1-godot-4.6.1-stable"
ROOT = Path.home() / ".cache/signs-of-rain/android-toolchain"
BASE = "https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable/"
ARCHIVE = "Godot_v4.6.1-stable_export_templates.tpz"
# From the official 4.6.1 release SHA512-SUMS.txt, checked 2026-10-03.
SHA512 = "d80001711c07973b1fd3e88077ba99644e19db7c9e52627e16f38a2937879f809f94dbd8493936fb8204908bbc57a521d41173dce5208061fe4c99772490c541"


def digest(path, algorithm):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def prepare():
    for path in [SDK, JAVA, GODOT]:
        if not Path(path).is_dir():
            raise ValueError("Pinned Nix package missing: " + path)
    ROOT.mkdir(parents=True, exist_ok=True)
    archive = ROOT / ARCHIVE
    if not archive.exists():
        pending = archive.with_suffix(".tpz.part")
        print("DOWNLOAD " + BASE + ARCHIVE, flush=True)
        request = urllib.request.Request(
            BASE + ARCHIVE, headers={"User-Agent": "SignsOfRain-build"}
        )
        with (
            urllib.request.urlopen(request, timeout=120) as response,
            pending.open("wb") as stream,
        ):
            while chunk := response.read(8 * 1024 * 1024):
                stream.write(chunk)
        if digest(pending, "sha512") != SHA512:
            raise ValueError("Export-template archive checksum mismatch")
        pending.replace(archive)
    if digest(archive, "sha512") != SHA512:
        raise ValueError("Cached export-template archive checksum mismatch")
    templates = ROOT / "4.6.1.stable"
    templates.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        version = source.read("templates/version.txt").decode().strip()
        if version != "4.6.1.stable":
            raise ValueError("Template version mismatch: " + version)
        for name in ["android_debug.apk", "android_release.apk", "version.txt"]:
            (templates / name).write_bytes(source.read("templates/" + name))
    roots = ROOT / "nix-roots"
    roots.mkdir(exist_ok=True)
    for package, name in [(SDK, "sdk"), (JAVA, "java"), (GODOT, "godot")]:
        subprocess.run(
            [
                "nix-store",
                "--add-root",
                str(roots / name),
                "--indirect",
                "--realise",
                package,
            ],
            check=True,
        )
    manifest = {
        "engine": GODOT,
        "sdk": SDK + "/libexec/android-sdk",
        "java": JAVA,
        "templates": str(templates),
        "archive_url": BASE + ARCHIVE,
        "sha512": SHA512,
        "template_version": version,
        "templates_sha256": {
            name: digest(templates / name, "sha256")
            for name in ["android_debug.apk", "android_release.apk"]
        },
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("ANDROID_TOOLCHAIN_READY " + str(ROOT / "manifest.json"), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="simonwjackson@aka")
    parser.add_argument("--local", action="store_true")
    args = parser.parse_args()
    if args.local:
        prepare()
        return
    subprocess.run(
        ["nix", "copy", "--to", "ssh://" + args.host, SDK, JAVA, GODOT], check=True
    )
    remote = "/tmp/signs-prepare-android.py"
    subprocess.run(
        ["scp", "-q", str(Path(__file__).resolve()), args.host + ":" + remote],
        check=True,
    )
    subprocess.run(
        ["ssh", "-o", "BatchMode=yes", args.host, remote, "--local"], check=True
    )


if __name__ == "__main__":
    main()
