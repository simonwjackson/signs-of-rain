#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 gcc pkg-config wayland wayland-scanner libxkbcommon
"""Optional headless test input; physical keyboard/mouse play does not need this.

Keep this process alive and send one command per stdin line:
  key EVDEV_CODE             tap a key (decimal 1..767)
  move DX DY                 relative motion (finite, each within +/-8388607)
  down|up|click BUTTON       left, right, or middle
  wait MILLISECONDS          decimal 0..10000
  type TEXT                  nonempty lowercase ASCII letters/digits
  name TEXT                  24 Backspaces (BW2 name field), then type TEXT
  quit                       release held inputs and disconnect (also on EOF)

For name, focus the BW2 name field with its caret at the end first.
Lines must contain at most 255 bytes, excluding the newline. Invalid input exits
nonzero. US_SEAT_READY follows a full fixed US keymap and an initial Shift tap;
INPUT_DONE follows each completed non-quit command. Process exit acknowledges quit.
Do not start the game before ready.
Downloads are SHA256-pinned protocol schemas, not executable code. Generated
sources and binaries exist only in a fresh /tmp directory while this runs.
"""

import argparse
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.request

PROTOCOLS = (
    (
        "virtual-keyboard-unstable-v1",
        "https://raw.githubusercontent.com/atx/wtype/master/protocol/virtual-keyboard-unstable-v1.xml",
        "7ad7870003ecd592cae47dc19d277a609b7f18fd7b7be012623cf3225a7294f5",
    ),
    (
        "wlr-virtual-pointer-unstable-v1",
        "https://raw.githubusercontent.com/swaywm/wlr-protocols/master/unstable/wlr-virtual-pointer-unstable-v1.xml",
        "3ff6d540be0bc5228195bf072bde42117ea17945a5c2061add5d3cf97d6bb524",
    ),
)


def build(directory: Path) -> Path:
    source = directory / "headless-seat.c"
    shutil.copyfile(Path(__file__).with_suffix(".c"), source)
    generated = []
    for name, url, expected in PROTOCOLS:
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read(1024 * 1024 + 1)
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f"Protocol SHA256 mismatch: {url}")
        xml = directory / f"{name}.xml"
        xml.write_bytes(data)
        code = directory / f"{name}-protocol.c"
        for mode, output in (
            ("client-header", directory / f"{name}-client-protocol.h"),
            ("private-code", code),
        ):
            subprocess.run(["wayland-scanner", mode, str(xml), str(output)], check=True)
        generated.append(str(code))
    flags = shlex.split(
        subprocess.check_output(
            ["pkg-config", "--cflags", "--libs", "wayland-client", "xkbcommon"],
            text=True,
        )
    )
    executable = directory / "headless-seat"
    subprocess.run(
        [
            "gcc",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-O2",
            "-I",
            str(directory),
            str(source),
            *generated,
            "-o",
            str(executable),
            *flags,
        ],
        check=True,
    )
    return executable


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--wayland-display", help="Explicit /tmp/signs-seat-*/wayland-* private socket"
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--build-only", action="store_true", help="compile without connecting"
    )
    mode.add_argument(
        "--check-commands",
        action="store_true",
        help="validate stdin without connecting or sending input",
    )
    args = parser.parse_args()
    if not args.build_only and not args.check_commands:
        if not args.wayland_display:
            parser.error(
                "Connected input requires an explicit private --wayland-display"
            )
        display = Path(args.wayland_display).resolve()
        private_dir = display.parent
        if (
            private_dir.parent != Path("/tmp")
            or not private_dir.name.startswith("signs-seat-")
            or not display.is_socket()
            or private_dir.stat().st_uid != os.getuid()
        ):
            parser.error("Refusing input outside an owned /tmp/signs-seat-* display")
    with tempfile.TemporaryDirectory(
        prefix="bw2-headless-seat-", dir="/tmp"
    ) as temporary:
        executable = build(Path(temporary))
        if args.build_only:
            print("BUILD_OK (no compositor or input test)", flush=True)
            return 0
        command = [str(executable)]
        if args.check_commands:
            command.append("--check-commands")
        return subprocess.run(
            command, env=dict(os.environ, WAYLAND_DISPLAY=args.wayland_display or "")
        ).returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"headless-seat: {error}", file=sys.stderr)
        sys.exit(1)
