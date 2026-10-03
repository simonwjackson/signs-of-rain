#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Real filesystem and subprocess checks for publication and private-input policy."""

import hashlib
import importlib.util
import json
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from owned_process import stop_owned  # noqa: E402

spec = importlib.util.spec_from_file_location(
    "installer", ROOT / "tools/install-release.py"
)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def bundle(directory, value):
    directory.mkdir()
    (directory / "signs-of-rain.pck").write_bytes(value)
    (directory / "launch").write_text("launch")
    files = {
        name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
        for name in ["signs-of-rain.pck", "launch"]
    }
    (directory / "manifest.json").write_text(json.dumps({"files": files}))
    return directory


class OperationsTest(unittest.TestCase):
    def test_complete_copy_and_repeat_deploy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = bundle(root / "upload", b"pack A")
            installed = root / "installed"
            destination = installer.stage_release(source, installed)
            installer.publish_link(destination, installed)
            self.assertEqual(
                (installed / "current/signs-of-rain.pck").read_bytes(), b"pack A"
            )
            self.assertEqual(installer.stage_release(source, installed), destination)
            self.assertEqual(list((installed / "releases").glob(".stage-*")), [])

    def test_interrupted_old_copy_never_becomes_current(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            installed = root / "installed"
            good = installer.stage_release(bundle(root / "a", b"pack A"), installed)
            installer.publish_link(good, installed)
            source = bundle(root / "b", b"pack B")
            data = (source / "manifest.json").read_bytes()
            incomplete = installed / "releases" / hashlib.sha256(data).hexdigest()[:16]
            incomplete.mkdir()
            (incomplete / "manifest.json").write_bytes(data)
            (incomplete / "launch").write_text("launch")
            with self.assertRaises((ValueError, OSError)):
                destination = installer.stage_release(source, installed)
                installer.publish_link(destination, installed)
            self.assertEqual((installed / "current").resolve(), good)

    def test_copied_bytes_checked_before_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            installed = root / "installed"
            destination = installer.stage_release(
                bundle(root / "upload", b"pack A"), installed
            )
            (destination / "signs-of-rain.pck").write_bytes(b"damaged")
            with self.assertRaises(ValueError):
                installer.publish_link(destination, installed)
            self.assertFalse((installed / "current").exists())

    def test_outside_manifest_member_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = bundle(root / "upload", b"pack A")
            (root / "outside").write_bytes(b"private")
            (source / "manifest.json").write_text(
                json.dumps(
                    {"files": {"../outside": hashlib.sha256(b"private").hexdigest()}}
                )
            )
            with self.assertRaises(ValueError):
                installer.stage_release(source, root / "install")

    def test_input_without_explicit_private_socket_refused(self):
        for args in [[], ["--wayland-display", "/run/user/1000/wayland-1"]]:
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/headless-seat.py"), *args],
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("US_SEAT_READY", result.stdout)
            self.assertNotIn("FIXED_US_KEYMAP", result.stdout)

    def test_unresponsive_owned_child_gets_bounded_kill(self):
        child = subprocess.Popen(
            [sys.executable, str(ROOT / "tests/resistant_child.py")],
            stdout=subprocess.PIPE,
            text=True,
        )
        try:
            readable, _, _ = select.select([child.stdout], [], [], 3)
            self.assertTrue(readable)
            self.assertEqual(child.stdout.readline().strip(), "READY")
            self.assertEqual(stop_owned(child, (0.05, 0.05, 1)), "SIGKILL")
            self.assertIsNotNone(child.poll())
            self.assertEqual(stop_owned(child), "already exited")
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=3)
            child.stdout.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
