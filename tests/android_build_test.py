#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Real ZIP/filesystem checks for APK architecture, alignment, and staging."""

import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), ROOT / "tools" / (name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load("build-android")
verifier = load("verify-android")


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


class AndroidBuildTest(unittest.TestCase):
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
