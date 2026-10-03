#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 git
"""Export a signed offline ARM64 APK with isolated Godot settings and user data."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile

from godot_profile import isolated_environment

ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = Path.home() / ".cache/signs-of-rain/android-toolchain/manifest.json"
SIGNING = Path.home() / ".local/share/signs-of-rain/android-signing"

spec = importlib.util.spec_from_file_location(
    "verify_android", ROOT / "tools/verify-android.py"
)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def run(arguments, env=None, cwd=ROOT):
    result = subprocess.run(
        arguments, cwd=cwd, env=env, text=True, capture_output=True, timeout=600
    )
    visible_stdout, visible_stderr = result.stdout, result.stderr
    for key, value in (env or {}).items():
        if "PASSWORD" in key and value:
            visible_stdout = visible_stdout.replace(value, "<REDACTED>")
            visible_stderr = visible_stderr.replace(value, "<REDACTED>")
    print(visible_stdout, end="", flush=True)
    print(visible_stderr, end="", flush=True)
    if result.returncode or "ERROR:" in result.stderr or "ERROR:" in result.stdout:
        raise RuntimeError("Build command failed: " + str(arguments[0]))
    return result.stdout.strip()


def signing_environment(java, initialize):
    key = SIGNING / "release.keystore"
    password = SIGNING / "password"
    if key.exists() != password.exists():
        raise ValueError(
            "Incomplete signing identity; restore key/password instead of replacing it"
        )
    if not key.exists():
        if not initialize:
            raise ValueError(
                "No signing identity. Use --init-signing once to create a project-owned key"
            )
        SIGNING.mkdir(parents=True, exist_ok=True, mode=0o700)
        SIGNING.chmod(0o700)
        fd = os.open(password, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            stream.write(secrets.token_urlsafe(32))
        environment = dict(os.environ, SIGNS_SIGNING_PASSWORD=password.read_text())
        try:
            run(
                [
                    str(java / "bin/keytool"),
                    "-genkeypair",
                    "-keystore",
                    str(key),
                    "-storetype",
                    "PKCS12",
                    "-alias",
                    "signs-of-rain",
                    "-storepass:env",
                    "SIGNS_SIGNING_PASSWORD",
                    "-keypass:env",
                    "SIGNS_SIGNING_PASSWORD",
                    "-keyalg",
                    "RSA",
                    "-keysize",
                    "3072",
                    "-validity",
                    "10000",
                    "-dname",
                    "CN=Signs of Rain prototype",
                ],
                env=environment,
            )
        except Exception:
            if not key.exists():
                password.unlink()
            raise
        key.chmod(0o600)
    return {
        "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": str(key),
        "GODOT_ANDROID_KEYSTORE_RELEASE_USER": "signs-of-rain",
        "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": password.read_text().strip(),
    }


def stage_project(source, destination, templates):
    for folder in ["assets", "game", "ui", "sim"]:
        shutil.copytree(source / folder, destination / folder)
    shutil.copyfile(source / "project.godot", destination / "project.godot")
    presets = (source / "export_presets.cfg").read_text()
    for mode in ["debug", "release"]:
        presets = presets.replace(
            "custom_template/" + mode + '=""',
            "custom_template/"
            + mode
            + "="
            + json.dumps(str(templates / ("android_" + mode + ".apk"))),
        )
    (destination / "export_presets.cfg").write_text(presets)


def build(toolchain_path, output, initialize):
    tooling = json.loads(toolchain_path.read_text())
    godot = Path(tooling["engine"]) / "bin/godot"
    java, sdk, templates = [Path(tooling[key]) for key in ["java", "sdk", "templates"]]
    for name in ["android_debug.apk", "android_release.apk"]:
        expected = tooling["templates_sha256"][name]
        with (templates / name).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != expected:
            raise ValueError("Template checksum mismatch: " + name)
    git = str(Path(tooling["git"]) / "bin/git")
    version = run([str(godot), "--version"])
    if (
        not version.startswith("4.6.1.")
        or tooling["template_version"] != "4.6.1.stable"
    ):
        raise ValueError("Replay/export checks require Godot and templates 4.6.1")
    build_tools = max(
        (sdk / "build-tools").iterdir(),
        key=lambda path: tuple(int(item) for item in path.name.split(".")),
    )
    output.mkdir(parents=True, exist_ok=True)
    revision = run([git, "rev-parse", "HEAD"])
    dirty = bool(run([git, "status", "--porcelain"]))
    signatures = signing_environment(java, initialize)
    with tempfile.TemporaryDirectory(prefix="android-export-", dir=output) as temporary:
        work = Path(temporary)
        project = work / "project"
        project.mkdir()
        stage_project(ROOT, project, templates)
        environment = isolated_environment(
            work,
            settings={
                "export/android/java_sdk_path": str(java),
                "export/android/android_sdk_path": str(sdk),
            },
        )
        environment.update(
            JAVA_HOME=str(java),
            ANDROID_HOME=str(sdk),
            PATH=str(java / "bin") + os.pathsep + os.environ.get("PATH", ""),
            **signatures,
        )
        # XDG overrides stop build imports/headless smoke from changing live game saves.
        run(
            [
                str(godot),
                "--headless",
                "--path",
                str(project),
                "--editor",
                "--import",
                "--quit",
            ],
            env=environment,
        )
        run(
            [
                str(godot),
                "--headless",
                "--path",
                str(project),
                "--quit-after",
                "8",
                "--",
                "--no-intro",
                "--mute",
                "--graphics=fast",
            ],
            env=environment,
        )
        apk = work / "signs-of-rain.apk"
        run(
            [
                str(godot),
                "--headless",
                "--path",
                str(project),
                "--export-release",
                "Android",
                str(apk),
            ],
            env=environment,
        )
        candidate = output / ".candidate.apk"
        shutil.copyfile(apk, candidate)
        report = verifier.verify(candidate, build_tools, env=environment)
        destination = output / "signs-of-rain.apk"
        candidate.replace(destination)
    report.update(
        {
            "engine": version,
            "commit": revision,
            "uncommitted_source": dirty,
            "build_host": socket.gethostname(),
            "toolchain": tooling,
            "signing_key_location": str(SIGNING / "release.keystore"),
        }
    )
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    (output / "SHA256SUMS").write_text(report["sha256"] + "  signs-of-rain.apk\n")
    print("ANDROID_BUILD_READY " + str(destination), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", type=Path, default=TOOLCHAIN)
    parser.add_argument("--output", type=Path, default=ROOT / "build/android")
    parser.add_argument("--init-signing", action="store_true")
    args = parser.parse_args()
    build(args.toolchain.resolve(), args.output.resolve(), args.init_signing)


if __name__ == "__main__":
    main()
