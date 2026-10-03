# Verification evidence

The delivered experience is the 3D rebuild, not the earlier flat-map prototype. The model stays the same. Tests run against the real Godot implementation and the actual installed game.

Historical Linux evidence: 344 local checks and 37 target checks passed. The current local source results are in `local-checks.json`; the older target reports are not Android acceptance. The 80.981-second recording contains 2,429 decoded video frames at 1280×800. Its recorded pack SHA-256 is `827612ea24cf7a4190bed39ac236ed8aacb62f432c9cb4e7485b46762ba64f9b`. A later [export boundary correction](pack-report.md) removes development captures without changing game code.

## Local checks

Run `nix run .#check`, or `./tools/check.py` inside `nix develop`. The command imports the real project, runs engine tests and real subprocess/filesystem tests, then checks GDScript/Python formatting and lint. It fails on Godot error output even when Godot returns zero.

| Boundary | What it establishes |
| --- | --- |
| Simulation | Sight, delayed trust-dependent reports, no echo inflation, competing confidence-weighted interpretations, material actions, finite resources, ordered mixed-miracle replay, and a definite ending. |
| Presentation | Real scene pointer routing, controls and causal accounts at six sizes, restart, replay, and preserving future replay commands. |
| Camera | Continuous perspective movement, head focus, face-to-landscape zoom, manual tilt preservation, terrain clearance, bounded panning, and ground-ray picking. |
| Characters | 24 actual animated models preserve model input and world transforms. Bone-attached supplies follow carried quantities. Face focus follows the animated head. |
| Terrain | Deterministic heights without simulation RNG, crop/well display, wetness reset, and actual heightfield collision. |
| Interaction | Paused casts update 3D resources, modal/restart cancels camera drag, target colors track mode, and opaque buildings/terrain block person picking. |
| Operations | Verified atomic release copies, incomplete-copy rejection, traversal rejection, shared-seat input refusal, and bounded termination of a real resistant child. |
| Android input | Real screen-event taps, one/two/three-finger arbitration, camera gestures without accidental gifts, HUD occlusion on release, modal/focus/resize cancellation, and Android Back policy. |
| Android layout | Folded/unfolded/short containers, 48-unit controls, overflow sheets, and physical safe-area scaling/translation. A 3× window tests physical-resolution rendering and input picking with a logical UI. |
| Android packaging | Staging isolation, path traversal rejection, APK runtime-resource boundaries, ARM64 ELF contents, and 16 KiB alignment. Artifact signatures and manifests are checked on the actual APK, not inferred from fixture tests. |

Committed source-check results are in `local-checks.json`. `nix run .#check` writes fresh results to ignored `build/local-checks.json`. `nix flake check` runs the same full suite in an isolated source copy. The build also inspects the actual exported pack, requiring runtime resources and rejecting development data. `simulation-results.json` and `simulation-report.md` contain independent seeded strategy comparisons and complete-state digests. They are not substitutes for real-device play.

## Android evidence

The signed APK is exported on aka from the pinned official Godot 4.6.1 Android templates. `build/android/manifest.json` records its exact source commit, build host, certificate, signature verification, ARM64 ELF load alignments, ZIP alignment, manifest, and resource boundary. No Android permissions are requested. Signing credentials stay outside the checkout and APK.

`./tools/test-mobile-render.py` uses an owned private compositor and the actual Mobile renderer on aka's RX 7900 XT. It captures a 360×720 folded shape, 720×900 unfolded shape, a 1848×2448 window at 3× UI density, and a 1280×300 short shape. Images and metadata remain in `artifacts/android-render/`. The report checks that BW2/Korri processes stayed running. These captures establish desktop Mobile rendering and layout, not Android runtime compatibility or performance.

Wireless ADB paired the phone and installed the hash-verified APK on `SM-F971U1` running Android 17. Installation reported `Success`, and the running app process was observed. Physical multitouch, fold transitions, safe-area reporting, phone FPS/heat, and ARM replay determinism remain unverified. See [the Android build and installation instructions](../docs/android.md).

## Historical aka Linux acceptance

Run `ssh -tt simonwjackson@aka .local/share/signs-of-rain/tools/target-test.py` after deployment. This starts an independent Sway compositor and a named PulseAudio sink. It never injects events into the Korri display. It closes only its own game, recorder, input device, compositor, and sink.

`target-results.json` records the exact build manifest, real keyboard/pointer command sequence, world snapshots, camera states, audio measurements, and assertion results. Its release field identifies the tested pack and commit. Reports are historical evidence; use that manifest rather than assume they describe every later source revision.

Verified target behavior includes:

- Vulkan Forward+ on the RX 7900 XT, with actual images at person, face, village, and landscape scales.
- Physical wheel zoom, middle-button orbit, visible-person ray selection, ground placement after resize/close zoom, and 3D ground-target accuracy.
- Rain and food casts that spend the limited power and create local observations. Uninformed people do not gain instant knowledge.
- Completed sharing, rituals, reports, and avoidance in the actual seven-day run.
- An exact accepted-command replay with the same complete final-state digest, then no intervention reaching a different ending.
- Restart and cold relaunch restoring the exact initial seeded state. Normal exits return zero.
- Game audio captured from its dedicated sink measured PCM16 RMS 123.37 and peak 289. The real mute control reduced both to zero. This proves signal routing and mute, not human listening quality.
- The BW2 play executable hash and running process IDs match before and after. The local BW2 repository remains clean. No Korri settings or services were changed.

The actual mixed-miracle run completed eight deliveries, 12 rituals, 75 reports, and 14 withdrawal decisions. Its replay matched the complete final digest. Doing nothing produced no supernatural memories and reached a different ending. The mixed run exhausted 21 people versus 18 with no intervention: journeys and rituals displaced useful work. This is a tradeoff, not a claim that intervention always helps.

The six rendered window sizes are 1440×900, 1024×768, 720×900, 360×720, 1280×300, and 320×240. Small windows use a scrollable person account and a window-level menu. The world is harder to read there, but controls remain accessible.

Recorded FPS samples are in target snapshots. The saved portrait, face, landscape, and ending samples each reported 62 FPS. They are short play observations, not frame-time percentiles or a general hardware benchmark. Godot warns that this headless compositor lacks optional icon and FIFO protocols. No script, shader, or engine error is accepted.

## Recording and captures

`artifacts/gameplay.mp4` joins the actual camera tour and an intervened game run. Time advances at the player-selected 4× speed during gameplay. The collector decodes every source video frame, re-encodes the result, counts decoded frames, and compares extracted images. It does not synthesize game frames.

`media-results.json` records the MP4 SHA-256, dimensions, duration, frame count, and source pack hash. Images and raw logs remain under `artifacts/target/`. `recording-contact-sheet.png` helps review the video but does not replace the original.

The remote originals are under `~/.local/share/signs-of-rain/lab/`. The collection command is `./tools/collect-evidence.py`. Large captures are deliberately outside Git. The authored source, licenses, hashes, commands, and small JSON reports are committed.

## Limits

This is a bounded prototype. No campaign, combat, creature, mortality, obstacle navigation, dynamic trust, invented report facts, facial animation, cloth physics, or foot/grip IK. Characters can slide or cross scenery on arbitrary routes. The camera stays above terrain but can pass through buildings. Water pools are visual scenery; the common well level is the resource-backed water surface. Only the latest rain footprint changes ground wetness.

Determinism is verified with the supplied Godot 4.6.1 build, not across engine versions or CPU architectures. Mouse/keyboard and engine-routed screen events are verified. Physical phone gameplay acceptance, controller, screen-reader play, other operating systems, and human sound-quality evaluation are not.
