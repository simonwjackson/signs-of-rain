# Signs of Rain

A standalone 3D Godot prototype about how people interpret a god's actions. Two villages, 24 people, one week of drought. You choose where rain and food appear. People witness events, pass reports, remember interpretations, and act on them.

A continuous perspective camera moves from a person's face to the surrounding mountain valley. The scene uses stylized human characters, skeletal animation, textured materials, terrain relief, vegetation, directional shadows, water, and atmosphere.

This is a new project. It does not load, change, or redistribute Black & White 2. The BW2 baseline and Korri packaging are separate.

## Play on aka

The installed build lives at:

```text
/home/simonwjackson/.local/share/signs-of-rain/current/launch
```

Run that launcher from a graphical session, or through SSH while aka's main Wayland session is available. It selects native Wayland when a Wayland display is present. Do not place it over a BW2 session you are using. Verification uses an independent headless display, not Korri's active seat.

The Linux build contains a Godot resource pack, a launcher, font and character licenses, and a SHA-256 manifest. It uses Forward+ and requires Vulkan support. Its runtime is the exact Nix Godot 4.6.1 closure recorded in that manifest. The installer roots that closure against garbage collection. It does not change NixOS or Korri configuration.

See [controls and experiments](docs/controls.md) before the first run. Normal play takes about five minutes. Use F for faster time and Space to pause.

## Android

The Android prototype keeps the 3D game and adds one-finger orbit, two-finger pan/pinch, tap actions, safe-area layout, and density-scaled controls. Every action is available without a keyboard. It uses Godot's Mobile renderer and starts with Faster graphics.

Build the signed ARM64 APK on aka with `nix run .#build-android -- --host simonwjackson@aka` from a clean committed checkout after toolchain preparation. The output is `build/android/signs-of-rain.apk`. See [installation, reproduction, and device-test limits](docs/android.md).

The package and desktop Mobile rendering are checked. Wireless ADB installed the APK on `SM-F971U1` running Android 17. Physical touch, folding, heat, and phone frame rate remain unverified. The Android build does not replace the installed Linux launcher.

## Develop and rebuild

The project lives at `~/code/sandbox/signs-of-rain`. `flake.lock` pins nixpkgs revision `c06b4ae3d6599a672a6210b7021d699c351eebda`. The flake supplies Godot 4.6.1, JDK 17, Android SDK/Build Tools 36, Python, GDScript tooling, and Ruff. Android templates have a fixed official SHA-512. The SDK follows the `home-kiosk` composition pattern, without an NDK, emulator, or CMake.

```sh
nix develop
nix run .#check
nix flake check
nix run .#prepare-android -- --host simonwjackson@aka
nix run .#build-android -- --host simonwjackson@aka
```

Run commands from this checkout. `nix run .#check` writes results under ignored `build/local-checks.json`, so checks do not make the release source dirty. `nix flake check` runs the full suite in an isolated source copy. Both run the real engine tests and Python tests.

Inside `nix develop`, open `project.godot` or run `godot --path .`. The shell also exposes `adb` for wireless pairing and APK installation. Fonts and generated wave files are included. `tools/prepare-assets.py` regenerates the authored sound.

For the separate Linux release:

```sh
nix run .#build-linux
./build/signs-of-rain/launch
./tools/deploy.py
```

The deploy script copies the pinned runtime to `simonwjackson@aka`, verifies the release hashes, and changes only this game's `current` link. It refuses deployment while this game's launcher holds its lock. Older releases remain under `releases/`. The build records whether its source tree was dirty.

This is an x86_64 NixOS delivery, not a portable Windows/macOS release. Restoring the recorded Nix closure is required if it is absent. Use the flake commands for the locked toolchain. Direct Nix-shebang helper environments still use the host's nixpkgs registry. Signing stays outside Nix builds and the Nix store. No Git remote or public release is configured.

## Verification and implementation

- [Acceptance evidence](verification/README.md) separates local model checks from real target input, rendering, audio, restart, and capture.
- [Simulation rules](sim/README.md) explain the model and controlled initial conditions.
- [Simulation results](verification/simulation-report.md) compare no intervention, balanced help, and one-sided help.
- [3D direction](docs/3d-direction.md) records the user's approved stylized-realistic camera and presentation requirements. It supersedes the old 2D rendering plan in [the initial brief](docs/brief.md).

`sim/simulation.gd` owns all simulation state and its seeded RNG. `game/main.gd` owns time, input precedence, and replay. The valley and HUD only read supplied state. Rendering animation and sound do not change simulation randomness.

The terrain and scenery consist of authored 3D geometry and shaders. Animated dressed characters derive from three Quaternius CC0 archives, with actual licenses and source hashes retained. See [character provenance](docs/character-assets.md). Audio comes from the included generator. Alegreya and Lato remain under their bundled SIL Open Font Licenses. The optional input helper derives from our BW2 tooling at commit `d900362`. This copy requires a private display socket before connecting. Only its generic Wayland keyboard/pointer protocol is used. The BW2 name-field command is irrelevant to this game.

## Limits

The model has fixed trust, four starting histories, direct travel, no mortality, and no distorted report facts. Character art has no facial animation, cloth simulation, or foot/grip IK. Arbitrary routes can cross scenery. There is no campaign, combat, construction, or creature. The design tests meaningful rule-driven consequences, not general intelligence. See the controls document for further limits and the exact scope of replay.
