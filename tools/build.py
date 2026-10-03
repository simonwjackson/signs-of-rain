#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 git
"""Build a resource-only Godot pack and an exact-runtime Linux launcher."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path("/nix/store/prgpch05xca3nvd945kz5kbixpjdwis1-godot-4.6.1-stable")
GODOT = Path(os.environ.get("GODOT", str(RUNTIME / "bin/godot"))).resolve()
if GODOT.parts[:3] != ("/", "nix", "store"):
    raise SystemExit("A release needs a Godot executable from a copyable Nix closure")
RUNTIME = Path(*GODOT.parts[:4])
OUT = ROOT / "build/signs-of-rain"


def run(arguments):
    result = subprocess.run(
        arguments, cwd=ROOT, text=True, capture_output=True, check=True
    )
    print(result.stdout)
    print(result.stderr)
    if "SCRIPT ERROR:" in result.stderr or "\nERROR:" in result.stderr:
        raise RuntimeError("Godot reported an error despite its exit status")
    return result


def main():
    version = run([str(GODOT), "--version"]).stdout.strip()
    if not version.startswith("4.6.1."):
        raise RuntimeError("Replay validation requires Godot 4.6.1, found " + version)
    OUT.mkdir(parents=True, exist_ok=True)
    run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT),
            "--editor",
            "--import",
            "--quit",
        ]
    )
    run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT),
            "--export-pack",
            "Linux",
            str(OUT / "signs-of-rain.pck"),
        ]
    )
    run(
        [
            str(GODOT),
            "--headless",
            "--main-pack",
            str(OUT / "signs-of-rain.pck"),
            "--quit-after",
            "8",
            "--",
            "--no-intro",
            "--mute",
        ]
    )
    launcher = OUT / "launch"
    launcher.write_text(
        "#!/usr/bin/env nix-shell\n"
        + "#!"
        + "nix-shell -i bash -p bash coreutils util-linux\n"
        + '''set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="'''
        + str(GODOT)
        + """"
if [[ ! -x "$RUNTIME" ]]; then
  printf 'The pinned Godot runtime is missing: %s\\nRestore its Nix closure before launch.\\n' "$RUNTIME" >&2
  exit 1
fi
DATA="$HOME/.local/share/signs-of-rain"
mkdir -p "$DATA"
exec 9>"$DATA/launch.lock"
flock -n 9 || { printf 'Signs of Rain is already running.\\n' >&2; exit 1; }
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" && -S "$XDG_RUNTIME_DIR/wayland-1" ]]; then
  export WAYLAND_DISPLAY=wayland-1
fi
ARGS=()
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then ARGS+=(--display-driver wayland); fi
exec "$RUNTIME" --main-pack "$ROOT/signs-of-rain.pck" --rendering-method gl_compatibility "${ARGS[@]}" "$@"
"""
    )
    launcher.chmod(0o755)
    licenses = OUT / "licenses"
    licenses.mkdir(exist_ok=True)
    for source in (ROOT / "assets/fonts").glob("*OFL.txt"):
        shutil.copyfile(source, licenses / source.name)
    for source in ["README.md", "docs/controls.md"]:
        path = ROOT / source
        if path.exists():
            shutil.copyfile(path, OUT / path.name)
    revision = run(["git", "rev-parse", "HEAD"]).stdout.strip()
    dirty = bool(run(["git", "status", "--porcelain"]).stdout.strip())
    files = {
        str(p.relative_to(OUT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(OUT.rglob("*"))
        if p.is_file() and p.name != "manifest.json"
    }
    manifest = {
        "title": "Signs of Rain",
        "engine": version,
        "runtime": str(RUNTIME),
        "commit": revision,
        "uncommitted_source": dirty,
        "files": files,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("BUILD_READY " + str(OUT))


if __name__ == "__main__":
    main()
