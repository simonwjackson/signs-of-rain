# Signs of Rain

A standalone Godot prototype about how people interpret a god's actions. Two villages, 24 people, one week of drought. You choose where rain and food appear. People witness events, pass reports, remember interpretations, and act on them.

This is a new project. It does not load, change, or redistribute Black & White 2. The BW2 baseline and Korri packaging are separate.

## Play on aka

The installed build lives at:

```text
/home/simonwjackson/.local/share/signs-of-rain/current/launch
```

Run that launcher from a graphical session, or through SSH while aka's main Wayland session is available. It selects native Wayland when a Wayland display is present. Do not place it over a BW2 session you are using. Verification uses an independent headless display, not Korri's active seat.

The Linux build contains a Godot resource pack, a launcher, font licenses, and a SHA-256 manifest. Its runtime is the exact Nix Godot 4.6.1 closure recorded in that manifest. The installer roots that closure against garbage collection. It does not change NixOS or Korri configuration.

See [controls and experiments](docs/controls.md) before the first run. Normal play takes about five minutes. Use F for faster time and Space to pause.

## Develop and rebuild

The tested engine is:

```text
/nix/store/prgpch05xca3nvd945kz5kbixpjdwis1-godot-4.6.1-stable/bin/godot
```

With Godot 4.6.1 available, open `project.godot` or run `godot --path .`. `tools/build.py` accepts a `GODOT` executable override and rejects other engine versions. Fonts and generated wave files are included. `tools/prepare-assets.py` regenerates the authored sound.

```sh
./tools/check.py
./tools/build.py
./build/signs-of-rain/launch
./tools/deploy.py
```

The deploy script copies the pinned runtime to `simonwjackson@aka`, verifies the release hashes, and changes only this game's `current` link. It refuses deployment while this game's launcher holds its lock. Older releases remain under `releases/`. The build records whether its source tree was dirty.

This is an x86_64 NixOS delivery, not a portable Windows/macOS release. Restoring the recorded Nix closure is required if it is absent. Nix-shebang helper environments use the host's nixpkgs registry; the tested game engine itself is pinned. No Git remote or public release is configured.

## Verification and implementation

- [Acceptance evidence](verification/README.md) separates local model checks from real target input, rendering, audio, restart, and capture.
- [Simulation rules](sim/README.md) explain the model and controlled initial conditions.
- [Simulation results](verification/simulation-report.md) compare no intervention, balanced help, and one-sided help.
- [Accepted brief](docs/brief.md) records scope and presentation choices.

`sim/simulation.gd` owns all simulation state and its seeded RNG. `game/main.gd` owns time, input precedence, and replay. The valley and HUD only read supplied state. Rendering animation and sound do not change simulation randomness.

Original scenery consists of authored Godot drawing commands. Audio comes from the included generator. Alegreya and Lato remain under their bundled SIL Open Font Licenses. The optional input helper derives from our BW2 tooling at commit `d900362`. This copy requires a private display socket before connecting. Only its generic Wayland keyboard/pointer protocol is used. The BW2 name-field command is irrelevant to this game.

## Limits

The model has fixed trust, four starting histories, direct travel, no mortality, and no distorted report facts. There is no campaign, combat, construction, or creature. The design tests meaningful rule-driven consequences, not general intelligence. See the controls document for further limits and the exact scope of replay.
