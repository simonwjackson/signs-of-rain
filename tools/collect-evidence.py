#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 openssh ffmpeg python3Packages.pillow
"""Collect an accepted target run, encode a playable recording, and check frames."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--destination", type=Path, default=ROOT / "artifacts")
args = parser.parse_args()
output = args.destination.resolve()
output.mkdir(parents=True, exist_ok=True)
raw = output / "target"
raw.mkdir(exist_ok=True)
host = "simonwjackson@aka"
remote = host + ":.local/share/signs-of-rain/lab/"
for name in [
    "target-results.json",
    "game-target.log",
    "intervened-ending.json",
    "replay-ending.json",
    "no-intervention-ending.json",
    "gameplay.mkv",
]:
    subprocess.run(["scp", "-q", remote + name, str(raw / name)], check=True)
subprocess.run(["scp", "-q", remote + "*.png", str(raw)], check=True)
result = json.loads((raw / "target-results.json").read_text())
checks = result["checks"]
if (
    len(checks) < 20
    or not all(item["passed"] for item in checks)
    or "recording" not in result
    or "preserved_after" not in result
):
    raise SystemExit("Target acceptance is incomplete; refusing a passed report")
# Read every encoded frame. Container metadata alone is not a playable recording.
subprocess.run(
    ["ffmpeg", "-v", "error", "-i", str(raw / "gameplay.mkv"), "-f", "null", "-"],
    check=True,
)
movie = output / "gameplay.mp4"
subprocess.run(
    [
        "ffmpeg",
        "-v",
        "error",
        "-y",
        "-i",
        str(raw / "gameplay.mkv"),
        "-vf",
        "scale=1280:-2",
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-crf",
        "20",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-movflags",
        "+faststart",
        str(movie),
    ],
    check=True,
)
probe = json.loads(
    subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-count_frames",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(movie),
        ],
        text=True,
    )
)
video = next(stream for stream in probe["streams"] if stream["codec_type"] == "video")
if int(video.get("nb_read_frames", 0)) < 300:
    raise SystemExit("Recording has too few decoded frames")
frames = []
for index, seconds in enumerate([3, 12, 29, 44, 61]):
    target = output / ("recording-frame-%d.png" % index)
    subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-ss",
            str(seconds),
            "-i",
            str(movie),
            "-frames:v",
            "1",
            str(target),
        ],
        check=True,
    )
    frames.append(Image.open(target).convert("RGB"))
differences = []
for previous, following in zip(frames, frames[1:]):
    differences.append(
        sum(ImageStat.Stat(ImageChops.difference(previous, following)).mean) / 3
    )
if not all(value > 0.2 for value in differences):
    raise SystemExit("Recorded images do not show sufficient frame changes")
# A contact sheet is a review aid; the original frames and video remain available.
sheet = Image.new("RGB", (1280, 400 * 3), "#123333")
for index, frame in enumerate(frames):
    thumbnail = frame.copy()
    thumbnail.thumbnail((640, 400))
    sheet.paste(thumbnail, ((index % 2) * 640, (index // 2) * 400))
sheet.save(output / "recording-contact-sheet.png")
report = {
    "movie": "artifacts/gameplay.mp4",
    "sha256": hashlib.sha256(movie.read_bytes()).hexdigest(),
    "duration_seconds": float(probe["format"]["duration"]),
    "decoded_video_frames": int(video["nb_read_frames"]),
    "size": [video["width"], video["height"]],
    "successive_frame_mean_differences": differences,
    "human_listening_assessment": False,
    "source_pack_sha256": result["release"]["files"]["signs-of-rain.pck"],
}
(ROOT / "verification/media-results.json").write_text(
    json.dumps(report, indent=2) + "\n"
)
shutil.copyfile(raw / "target-results.json", ROOT / "verification/target-results.json")
print(json.dumps(report, indent=2))
