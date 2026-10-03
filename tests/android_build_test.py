#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Real ZIP/filesystem checks for APK architecture, alignment, and staging."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), ROOT / "tools" / (name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load("build-android")
verifier = load("verify-android")
preparer = load("prepare-android")
profile = load("godot_profile")


def elf_header(machine=183, alignment=16384):
    # A minimal ELF metadata fixture, not an executable or a substitute for APK tests.
    content = bytearray(120)
    content[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", content, 18, machine)
    struct.pack_into("<Q", content, 32, 64)
    struct.pack_into("<HH", content, 54, 56, 1)
    struct.pack_into("<I", content, 64, 1)
    struct.pack_into("<Q", content, 112, alignment)
    return content


def archive(path, extra=None, machine=183, alignment=16384):
    with zipfile.ZipFile(path, "w") as output:
        output.writestr(
            "lib/arm64-v8a/libgodot_android.so", elf_header(machine, alignment)
        )
        for name in [
            "project.binary",
            "game/main.tscn.remap",
            "game/valley.gd.remap",
            "sim/simulation.gd.remap",
        ]:
            output.writestr("assets/" + name, b"resource")
        for name in extra or []:
            output.writestr(name, b"extra")
    return path


def toolchain_fixture(root):
    # Real manifest/filesystem fixture; it does not claim to execute an SDK.
    manifest = {"template_version": "4.6.1.stable", "templates_sha256": {}}
    for name in ["engine", "java", "sdk", "templates", "python", "git"]:
        path = root / name
        path.mkdir()
        manifest[name] = str(path)
    for name in ["android_debug.apk", "android_release.apk"]:
        content = name.encode()
        (root / "templates" / name).write_bytes(content)
        manifest["templates_sha256"][name] = hashlib.sha256(content).hexdigest()
    (root / "manifest.json").write_text(json.dumps(manifest))
    return manifest


class AndroidBuildTest(unittest.TestCase):
    def test_remote_clone_uses_pinned_git_with_empty_host_path(self):
        git = shutil.which("git")
        self.assertIsNotNone(git, "run these tests inside nix develop")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            environment = dict(
                os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1"
            )

            def command(*args, **kwargs):
                return subprocess.check_output(
                    [git, *args], cwd=source, env=environment, text=True, **kwargs
                ).strip()

            command("init", "--quiet")
            (source / "member").write_text("source fixture")
            command("add", "member")
            tree = command("write-tree")
            revision = command(
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit-tree",
                tree,
                input="fixture\n",
            )
            command("update-ref", "refs/heads/main", revision)
            command("symbolic-ref", "HEAD", "refs/heads/main")
            bundle = root / "source.bundle"
            command("bundle", "create", str(bundle), "HEAD")
            destination = root / "remote"
            subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tools/build-android-on-host.py"),
                    "--git",
                    git,
                    "--remote-prepare",
                    str(destination),
                    str(bundle),
                ],
                env=dict(environment, PATH=""),
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                (destination / "source/member").read_text(), "source fixture"
            )
            self.assertFalse(bundle.exists())

    def test_private_profile_separates_player_data_and_editor_settings(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            player = root / "player.cfg"
            player.write_text("existing player settings")
            environment = profile.isolated_environment(root / "build")
            for kind in ["CONFIG", "DATA", "CACHE"]:
                self.assertEqual(
                    environment["XDG_" + kind + "_HOME"],
                    str(root / "build" / kind.lower()),
                )
                self.assertTrue(Path(environment["XDG_" + kind + "_HOME"]).is_dir())
            self.assertEqual(player.read_text(), "existing player settings")

    def test_private_profile_cannot_stop_shared_adb_server(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            profile.isolated_environment(
                root, settings={"export/android/shutdown_adb_on_exit": True}
            )
            settings = (root / "config/godot/editor_settings-4.6.tres").read_text()
            self.assertIn("export/android/shutdown_adb_on_exit = false", settings)
            self.assertNotIn("export/android/shutdown_adb_on_exit = true", settings)

    def test_flake_manifest_works_without_preexisting_host_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = toolchain_fixture(root)
            self.assertEqual(preparer.validate_manifest(root), manifest)
            self.assertFalse((root / "release.keystore").exists())

    def test_flake_manifest_rejects_changed_templates(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            toolchain_fixture(root)
            (root / "templates/android_release.apk").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "Template checksum mismatch"):
                preparer.validate_manifest(root)

    def test_flake_manifest_rejects_missing_sdk(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            toolchain_fixture(root)
            (root / "sdk").rmdir()
            with self.assertRaisesRegex(ValueError, "Missing toolchain directory"):
                preparer.validate_manifest(root)

    def test_arm64_archive_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = archive(Path(temporary) / "game.apk")
            result = verifier.inspect_archive(apk)
            self.assertEqual(result["native_architecture"], "arm64-v8a")
            self.assertEqual(result["elf_load_alignments"], [16384])
            self.assertEqual(result["resource_members"], 4)
            self.assertEqual(len(result["sha256"]), 64)

    def test_non_arm64_library_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = archive(Path(temporary) / "game.apk", machine=62)
            with self.assertRaisesRegex(ValueError, "ARM64 ELF64"):
                verifier.inspect_archive(apk)

    def test_secondary_architecture_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = archive(
                Path(temporary) / "game.apk", extra=["lib/x86_64/libgodot_android.so"]
            )
            with self.assertRaisesRegex(ValueError, "only ARM64"):
                verifier.inspect_archive(apk)

    def test_4k_load_alignment_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = archive(Path(temporary) / "game.apk", alignment=4096)
            with self.assertRaisesRegex(ValueError, "16 KiB"):
                verifier.inspect_archive(apk)

    def test_capture_secret_and_source_tool_members_rejected(self):
        for name in [
            "assets/artifacts/capture.png",
            "assets/tools/build.py",
            "assets/assets/password.json",
            "assets/assets/release.keystore",
        ]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                apk = archive(Path(temporary) / "game.apk", extra=[name])
                with self.assertRaises(ValueError):
                    verifier.inspect_archive(apk)

    def test_missing_runtime_member_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / "game.apk"
            with zipfile.ZipFile(apk, "w") as output:
                output.writestr("lib/arm64-v8a/libgodot_android.so", elf_header())
            with self.assertRaisesRegex(ValueError, "Missing runtime resource"):
                verifier.inspect_archive(apk)

    def test_staging_keeps_source_and_credentials_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, stage, templates = [
                root / name for name in ["source", "stage", "templates"]
            ]
            source.mkdir()
            stage.mkdir()
            templates.mkdir()
            for folder in ["assets", "game", "ui", "sim", "tools", ".git"]:
                (source / folder).mkdir()
                (source / folder / "member").write_text(folder)
            (source / "project.godot").write_text("project")
            original = 'custom_template/debug=""\ncustom_template/release=""\n'
            (source / "export_presets.cfg").write_text(original)
            builder.stage_project(source, stage, templates)
            self.assertEqual((source / "export_presets.cfg").read_text(), original)
            self.assertIn(
                str(templates / "android_release.apk"),
                (stage / "export_presets.cfg").read_text(),
            )
            self.assertFalse((stage / "tools").exists())
            self.assertFalse((stage / ".git").exists())
            self.assertEqual((stage / "assets/member").read_text(), "assets")


if __name__ == "__main__":
    unittest.main()
