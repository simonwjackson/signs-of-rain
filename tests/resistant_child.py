#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Real child for bounded process-shutdown tests. It exits only on SIGKILL."""

import signal

signal.signal(signal.SIGINT, signal.SIG_IGN)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
print("READY", flush=True)
while True:
    signal.pause()
