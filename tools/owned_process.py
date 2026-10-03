"""Bounded shutdown for a child process this caller created, never a name search."""

import signal
import subprocess


def stop_owned(child: subprocess.Popen | None, limits=(8.0, 5.0, 3.0)) -> str:
    if child is None or child.poll() is not None:
        return "already exited"
    for action, delay in zip(
        (signal.SIGINT, signal.SIGTERM, signal.SIGKILL), limits, strict=True
    ):
        child.send_signal(action)
        try:
            child.wait(timeout=delay)
            return action.name
        except subprocess.TimeoutExpired:
            continue
    raise TimeoutError(f"Owned child {child.pid} did not exit after SIGKILL")
