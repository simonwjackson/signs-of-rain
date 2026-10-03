#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Verify the actual signed APK, ARM64 library, manifest, and resource boundary."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile

PACKAGE = "org.signsofrain.prototype"
RUNTIME_ROOTS = {
    "game",
    "ui",
    "sim",
    "assets",
    ".godot",
    "project.binary",
    "assets.sparsepck",
    "_cl_",
}


def inspect_archive(apk):
    with zipfile.ZipFile(apk) as archive:
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError("Corrupt APK member: " + corrupt)
        names = archive.namelist()
        libraries = [name for name in names if name.startswith("lib/")]
        if not libraries or any(
            not name.startswith("lib/arm64-v8a/") for name in libraries
        ):
            raise ValueError("Expected only ARM64 native libraries")
        library = archive.read("lib/arm64-v8a/libgodot_android.so")
        if (
            library[:6] != b"\x7fELF\x02\x01"
            or struct.unpack_from("<H", library, 18)[0] != 183
        ):
            raise ValueError("Godot native library is not little-endian ARM64 ELF64")
        offset = struct.unpack_from("<Q", library, 32)[0]
        size, count = struct.unpack_from("<HH", library, 54)
        alignments = []
        for index in range(count):
            header = offset + index * size
            if struct.unpack_from("<I", library, header)[0] == 1:
                alignment = struct.unpack_from("<Q", library, header + 48)[0]
                if alignment < 16384:
                    raise ValueError(
                        "Native library lacks 16 KiB load-segment alignment"
                    )
                alignments.append(alignment)
        if not alignments:
            raise ValueError("Native library has no load segments")
        resources = [
            name.removeprefix("assets/")
            for name in names
            if name.startswith("assets/") and not name.endswith("/")
        ]
        for name in resources:
            if name in {"dexopt/baseline.prof", "dexopt/baseline.profm"}:
                continue  # Runtime ART profiles from the verified Android template.
            if name.split("/", 1)[0] not in RUNTIME_ROOTS:
                raise ValueError("Development data in APK: " + name)
            if Path(name).suffix in {".py", ".json", ".mp4", ".keystore", ".jks"}:
                raise ValueError("Private or development data in APK: " + name)
        for required in [
            "project.binary",
            "game/main.tscn.remap",
            "game/valley.gd.remap",
            "sim/simulation.gd.remap",
        ]:
            if required not in resources:
                raise ValueError("Missing runtime resource: " + required)
        with apk.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        return {
            "native_architecture": "arm64-v8a",
            "elf_load_alignments": alignments,
            "resource_members": len(resources),
            "bytes": apk.stat().st_size,
            "sha256": digest,
        }


def run(arguments, env=None):
    result = subprocess.run(
        arguments, env=env, text=True, capture_output=True, timeout=90
    )
    if result.returncode:
        raise ValueError("APK verification failed: " + result.stdout + result.stderr)
    return result.stdout


def verify(apk, build_tools, env=None):
    env = dict(os.environ if env is None else env)
    if env.get("JAVA_HOME"):
        env["PATH"] = (
            str(Path(env["JAVA_HOME"]) / "bin") + os.pathsep + env.get("PATH", "")
        )
    report = inspect_archive(apk)
    signature = run(
        [
            str(build_tools / "apksigner"),
            "verify",
            "--verbose",
            "--print-certs",
            str(apk),
        ],
        env,
    )
    if "Verified using v2 scheme (APK Signature Scheme v2): true" not in signature:
        raise ValueError("APK needs a verified v2 signature")
    report["signature"] = signature
    report["zip_alignment"] = run(
        [str(build_tools / "zipalign"), "-c", "-P", "16", "4", str(apk)], env
    )
    manifest = run(
        [
            str(build_tools / "aapt2"),
            "dump",
            "xmltree",
            str(apk),
            "--file",
            "AndroidManifest.xml",
        ],
        env,
    )
    if PACKAGE not in manifest or "resizeableActivity" not in manifest:
        raise ValueError("Unexpected application package or missing resize support")
    if re.search(r"uses-permission\b", manifest):
        raise ValueError("The offline game must not request Android permissions")
    report["manifest"] = manifest
    report["actual_device_tested"] = False
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--build-tools", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = verify(args.apk.resolve(), args.build_tools.resolve())
    text = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text)
    print(text)


if __name__ == "__main__":
    main()
