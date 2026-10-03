#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 grim pulseaudio ffmpeg sway
"""Real target acceptance through private Wayland input, pixels, audio and replay.

Run on aka after deploy. Owns and closes only its private compositor, input
helper, recorder, sound sink, and game. No debug action API or shared-seat input.
"""

import hashlib
import json
import math
import os
from pathlib import Path
import queue
import struct
import subprocess
import threading
import time

from owned_process import stop_owned

ROOT = Path.home() / ".local/share/signs-of-rain"
TOOLS = ROOT / "tools"
LAB = ROOT / "lab"
LAB.mkdir(exist_ok=True)
report = {
    "checks": [],
    "snapshots": {},
    "input_protocol": [],
    "release": json.loads((ROOT / "current/manifest.json").read_text()),
}
children = []
seat = None
helper = None
game = None
recording = False


class LineProcess:
    def __init__(self, command, name):
        self.lines = queue.Queue()
        self.process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        children.append(self.process)
        self.log = (LAB / (name + ".log")).open("w")
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.process.stdout:
            self.log.write(line)
            self.log.flush()
            self.lines.put(line.rstrip())

    def expect(self, text, timeout=40):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                line = self.lines.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            if text in line:
                return line
        raise TimeoutError("Missing process acknowledgement: " + text)

    def send(self, command, acknowledgement="INPUT_DONE"):
        self.process.stdin.write(command + "\n")
        self.process.stdin.flush()
        return self.expect(acknowledgement)


def state():
    return json.loads((LAB / "state.json").read_text())


def wait_state(predicate, timeout=100):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if game is not None and game.poll() is not None:
            raise RuntimeError("Game exited during acceptance; see game-target.log")
        try:
            result = state()
            if predicate(result):
                return result
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.08)
    raise TimeoutError("Game state did not reach the expected condition")


def check(condition, name):
    report["checks"].append({"name": name, "passed": bool(condition)})
    print(("PASS " if condition else "FAIL ") + name, flush=True)
    if not condition:
        raise AssertionError(name)


def input_command(command):
    report["input_protocol"].append(command)
    helper.send(command)


def key(code):
    input_command("key " + str(code))
    time.sleep(0.07)


def shot(name):
    # Let the input acknowledgement and a real display frame settle.
    time.sleep(0.2)
    seat.send("shot " + name + ".png", "SHOT_DONE")


def save_state(name):
    current = state()
    (LAB / (name + ".json")).write_text(json.dumps(current, indent=2))
    report["snapshots"][name] = {
        "tick": current["tick"],
        "digest": current["digest"],
        "commands": current["commands"],
        "summary": current["summary"],
        "fps": current["fps"],
        "camera": current.get("camera"),
    }
    return current


def click_world(kind, x, y):
    key(3 if kind == "rain" else 4)
    current = wait_state(lambda s: s["selected"] == -1)
    target = {(240, 340): "alder", (760, 340): "sedge", (490, 290): "shrine"}[(x, y)]
    px, py = [round(value) for value in current["screen_targets"][target]]
    input_command("move -10000 -10000")
    input_command(f"move {px} {py}")
    before = len(current["commands"])
    input_command("click left")
    after = wait_state(lambda s: len(s["commands"]) == before + 1)
    check(after["commands"][-1]["kind"] == kind, "real pointer cast " + kind)
    landed = after["commands"][-1]["pos"]
    check(
        math.dist(landed, [x, y]) < 3.0,
        "3D camera ray lands near the intended " + target + " ground",
    )
    return after


def launch():
    global game
    (LAB / "state.json").unlink(missing_ok=True)
    log = (LAB / "game-target.log").open("a")
    game = subprocess.Popen(
        [str(TOOLS / "lab-client.py"), "play"], stdout=log, stderr=subprocess.STDOUT
    )
    children.append(game)
    wait_state(lambda s: s["tick"] == 0 and s["power"] == 8, timeout=40)


def audio_capture(name, seconds=2.0):
    info = json.loads((LAB / "seat.json").read_text())
    path = LAB / (name + ".s16le")
    env = dict(os.environ, PULSE_SERVER=info["PULSE_SERVER"])
    with path.open("wb") as output:
        child = subprocess.Popen(
            [
                "parec",
                "--device=" + info["PULSE_SOURCE"],
                "--latency-msec=20",
                "--process-time-msec=10",
                "--format=s16le",
                "--rate=48000",
                "--channels=2",
            ],
            env=env,
            stdout=output,
        )
        try:
            time.sleep(seconds)
        finally:
            child.terminate()
            child.wait(timeout=5)
    samples = [item[0] for item in struct.iter_unpack("<h", path.read_bytes())]
    rms = math.sqrt(sum(item * item for item in samples) / max(1, len(samples)))
    result = {
        "rms_pcm16": rms,
        "peak_pcm16": max((abs(x) for x in samples), default=0),
        "samples": len(samples),
        "source": info["PULSE_SOURCE"],
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }
    return result


def preserved_runtime():
    executable = (
        Path.home()
        / ".local/share/bw2-research/runtime/play-compat/pfx/drive_c/BW2/white.exe"
    )
    processes = []
    for path in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            command = path.read_bytes()
        except OSError:
            continue
        if b"C:/BW2/white.exe" in command:
            processes.append(int(path.parent.name))
    return {
        "bw2_pids": sorted(processes),
        "bw2_executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
    }


try:
    report["preserved_before"] = preserved_runtime()
    game_log = LAB / "game-target.log"
    if game_log.exists():
        game_log.rename(LAB / ("game-target-" + str(time.time_ns()) + ".log"))
    seat = LineProcess([str(TOOLS / "private-seat.py")], "seat-target")
    seat.expect("PRIVATE_SEAT_READY", 90)
    helper = LineProcess([str(TOOLS / "lab-client.py"), "input"], "input-target")
    helper.expect("US_SEAT_READY", 90)
    launch()
    shot("title")
    key(28)  # Enter the valley.
    key(19)  # R, start an exact paused attempt.
    initial = wait_state(
        lambda s: s["paused"] and s["tick"] == 0 and s["restart_count"] == 1
    )
    initial_digest = initial["digest"]
    check(initial["commands"] == [], "restart begins with no interventions")
    # Prove the person-to-landscape camera through real physical input.
    seat.send("record camera-tour.mkv", "RECORD_STARTED")
    recording = True
    key(15)
    key(46)  # C: focus selected person.
    wait_state(lambda s: s["camera"]["distance"] < 1.8, 15)
    shot("person-close")
    save_state("camera-person")
    current = state()
    check(
        current["camera"]["distance"] < 1.8,
        "close camera reaches a person without a mode switch",
    )
    left, top, width, height = current["world_rect"]
    input_command("move -10000 -10000")
    input_command(f"move {round(left + width / 2)} {round(top + height / 2)}")
    input_command("scroll -9")
    close = wait_state(lambda s: s["camera"]["distance"] < 1.1, 15)
    check(
        close["camera"]["distance"] < 1.1,
        "real mouse wheel reaches face-scale distance",
    )
    check(
        close["camera"]["terrain_clearance"] >= 0.49,
        "face-scale camera remains above actual terrain",
    )
    shot("person-face")
    save_state("camera-face")
    yaw = close["camera"]["yaw"]
    input_command("down middle")
    input_command("move 110 -20")
    input_command("up middle")
    orbit = wait_state(lambda s: abs(s["camera"]["yaw"] - yaw) > 0.3, 15)
    check(
        abs(orbit["camera"]["yaw"] - yaw) > 0.3,
        "middle drag orbits the actual 3D camera",
    )
    shot("person-orbit")
    # Click the visible torso/head through real camera geometry, not an inspector shortcut.
    input_command("click left")
    picked = wait_state(lambda s: s["selected"] == 0)
    check(
        picked["selected"] == 0,
        "actual close-view pointer picks the inspected 3D person",
    )
    input_command("scroll 32")
    wide = wait_state(
        lambda s: (
            s["camera"]["distance"] > 90
            and s["camera"]["pitch"] > 25
            and abs(s["camera"]["distance"] - s["camera"]["target_distance"]) < 0.1
        ),
        15,
    )
    check(wide["camera"]["pitch"] > 25, "zoom climbs continuously to a landscape view")
    shot("landscape-wide")
    save_state("camera-landscape")
    key(47)  # V: overview.
    wait_state(
        lambda s: (
            abs(s["camera"]["distance"] - s["camera"]["target_distance"]) < 0.1
            and not s["camera"]["following"]
        ),
        15,
    )
    seat.send("stop-record", "RECORD_DONE")
    recording = False
    # Read real containers at the size ladder, with a visible inspector.
    for width, height in [
        (1440, 900),
        (1024, 768),
        (720, 900),
        (360, 720),
        (1280, 300),
        (320, 240),
    ]:
        subprocess.run(
            [str(TOOLS / "lab-client.py"), "resize", str(width), str(height)],
            check=True,
        )
        wait_state(lambda s: s["window_size"] == [width, height], 15)
        shot(f"layout-{width}x{height}")
        if width == 320 and height == 240:
            input_command("move -10000 -10000")
            input_command("move 294 210")
            input_command("click left")
            shot("layout-menu-320x240")
            key(1)
    subprocess.run([str(TOOLS / "lab-client.py"), "resize", "1440", "900"], check=True)
    wait_state(lambda s: s["window_size"] == [1440, 900], 15)
    key(1)  # Escape selection so the valley expands before targeting.
    key(19)
    wait_state(lambda s: s["paused"] and s["tick"] == 0)
    # Resource targeting after resize and zoom, then discard this probe attempt.
    subprocess.run([str(TOOLS / "lab-client.py"), "resize", "1024", "768"], check=True)
    wait_state(lambda s: s["window_size"] == [1024, 768], 15)
    key(15)
    key(46)
    wait_state(lambda s: s["camera"]["distance"] < 1.8, 15)
    key(4)
    input_command("move -10000 -10000")
    input_command("move 500 590")
    input_command("click left")
    close_cast = wait_state(lambda s: len(s["commands"]) == 1)
    check(
        close_cast["commands"][0]["kind"] == "food" and close_cast["power"] == 7,
        "real resized close-camera ground picking places food",
    )
    shot("close-ground-cast")
    key(19)
    subprocess.run([str(TOOLS / "lab-client.py"), "resize", "1440", "900"], check=True)
    wait_state(
        lambda s: (
            s["window_size"] == [1440, 900]
            and s["tick"] == 0
            and s["power"] == 8
            and abs(s["camera"]["distance"] - s["camera"]["target_distance"]) < 0.1
        ),
        15,
    )
    report["audio_on"] = audio_capture("audio-on")
    key(50)
    time.sleep(0.2)
    report["audio_muted"] = audio_capture("audio-muted")
    check(
        report["audio_on"]["rms_pcm16"] > 5, "game produces audio on its dedicated sink"
    )
    check(report["audio_muted"]["rms_pcm16"] < 1, "mute silences that dedicated sink")
    key(50)
    seat.send("record gameplay.mkv", "RECORD_STARTED")
    recording = True
    first = click_world("rain", 240, 340)
    check(first["power"] == 6, "rain consumes exactly two power")
    check(
        all(not p["memories"] for p in first["people"][12:]),
        "unobserving village has no instant miracle knowledge",
    )
    check(
        len({p["belief"] for p in first["people"][:12]}) >= 2,
        "same witnessed rain yields competing interpretations",
    )
    shot("rain")
    key(2)  # Look.
    key(15)  # Ada.
    key(57)  # Time on.
    key(33)
    key(33)  # 4x.
    wait_state(lambda s: s["tick"] >= 40)
    shot("care")
    key(15)  # Bram.
    shot("ritual")
    wait_state(lambda s: s["tick"] >= 75)
    click_world("food", 490, 290)
    shot("food")
    wait_state(lambda s: s["tick"] >= 140)
    click_world("rain", 760, 340)
    wait_state(lambda s: s["tick"] >= 210)
    click_world("food", 760, 340)
    key(2)
    for _ in range(13):
        key(15)
    shot("reported-history")
    wait_state(lambda s: s["tick"] >= 300)
    click_world("rain", 240, 340)
    check(state()["power"] == 0, "five accepted miracles spend the finite budget")
    wait_state(lambda s: s["ended"], 90)
    first_end = save_state("intervened-ending")
    shot("intervened-ending")
    check(
        first_end["tick"] == 560 and first_end["paused"],
        "real game reaches bounded ending and stops time",
    )
    metrics = first_end["summary"]["metrics"]
    check(
        metrics["shares"] > 0
        and metrics["rituals"] > 0
        and metrics["reports"] > 0
        and metrics["avoidance"] > 0,
        "actual run completes sharing, rituals, reports, and avoidance",
    )
    seat.send("stop-record", "RECORD_DONE")
    recording = False
    subprocess.run([str(TOOLS / "lab-client.py"), "resize", "320", "240"], check=True)
    wait_state(lambda s: s["window_size"] == [320, 240], 15)
    shot("ending-320x240")
    subprocess.run([str(TOOLS / "lab-client.py"), "resize", "1440", "900"], check=True)
    wait_state(lambda s: s["window_size"] == [1440, 900], 15)
    key(1)  # Escape ending.
    key(25)  # P: replay exact accepted input times, through the actual control.
    wait_state(lambda s: s["replaying"] and s["tick"] < 20)
    wait_state(lambda s: s["ended"], 100)
    replay_end = save_state("replay-ending")
    check(
        replay_end["digest"] == first_end["digest"],
        "live UI replay reproduces complete final simulation digest",
    )
    key(1)
    key(19)
    reset = wait_state(
        lambda s: not s["replaying"] and s["tick"] == 0 and s["power"] == 8
    )
    check(
        reset["digest"] == initial_digest, "restart restores exact seeded initial state"
    )
    shot("restarted")
    key(57)
    wait_state(lambda s: s["ended"], 100)
    none_end = save_state("no-intervention-ending")
    check(
        none_end["commands"] == [] and none_end["tick"] == 560,
        "no-intervention play also reaches its ending",
    )
    check(
        none_end["digest"] != first_end["digest"],
        "player decisions produce a different completed world",
    )
    shot("no-intervention-ending")
    subprocess.run([str(TOOLS / "lab-client.py"), "close"], check=True)
    check(game.wait(timeout=15) == 0, "normal window close exits the launcher cleanly")
    launch()
    key(28)
    key(19)
    cold = wait_state(
        lambda s: s["paused"] and s["tick"] == 0 and s["restart_count"] == 1
    )
    check(
        cold["digest"] == initial_digest,
        "cold relaunch restores the same seed without stale state",
    )
    shot("cold-relaunch")
    subprocess.run([str(TOOLS / "lab-client.py"), "close"], check=True)
    check(game.wait(timeout=15) == 0, "second normal exit is clean")
    log = (LAB / "game-target.log").read_text()
    check(
        "AMD Radeon RX 7900 XT" in log and "Vulkan" in log and "Forward+" in log,
        "actual 3D renderer is Forward+ Vulkan on the RX 7900 XT",
    )
    check(
        "SCRIPT ERROR" not in log and "\nERROR:" not in log,
        "target game log contains no script or engine errors",
    )
    report["preserved_after"] = preserved_runtime()
    check(
        report["preserved_after"] == report["preserved_before"],
        "BW2 executable and running process identity remain unchanged",
    )
    probe = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(LAB / "gameplay.mkv"),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    report["recording"] = json.loads(probe.stdout)
    kinds = {stream["codec_type"] for stream in report["recording"]["streams"]}
    check(
        {"video", "audio"} <= kinds,
        "recording contains rendered video and dedicated game audio",
    )
    print("TARGET_ACCEPTANCE_PASSED", flush=True)
finally:
    if game is not None and game.poll() is None:
        subprocess.run([str(TOOLS / "lab-client.py"), "close"], check=False, timeout=10)
        stop_owned(game)
    if helper is not None and helper.process.poll() is None:
        helper.process.stdin.write("quit\n")
        helper.process.stdin.flush()
        helper.process.wait(timeout=10)
    if seat is not None and seat.process.poll() is None:
        if recording:
            seat.send("stop-record", "RECORD_DONE")
        seat.process.stdin.write("quit\n")
        seat.process.stdin.flush()
        seat.process.wait(timeout=30)
    (LAB / "target-results.json").write_text(json.dumps(report, indent=2) + "\n")
