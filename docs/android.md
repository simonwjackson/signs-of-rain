# Android prototype

The Android build keeps the 3D valley, all 24 animated people, and the existing simulation. It exports a signed ARM64 APK from Godot 4.6.1. It does not use a browser, BW2 content, Korri, or a Play Store release.

## Install

The delivered file is `build/android/signs-of-rain.apk`. Its SHA-256 is in `build/android/SHA256SUMS`. The manifest records the source commit, build host, template hashes, signature checks, and package contents.

Open the APK on the phone and approve installation from that source. Samsung Auto Blocker can prevent installation. Change that protection only if you trust the file, then restore it after installation. The game requests no Android permissions. It runs offline after installation.

For an authorized phone connected over ADB, use:

```sh
adb -s PHONE_SERIAL install -r build/android/signs-of-rain.apk
adb -s PHONE_SERIAL shell am start -n org.signsofrain.prototype/com.godot.game.GodotAppLauncher
```

Replace `PHONE_SERIAL` with the intended phone from `adb devices -l`. Do not install on another connected device. Android developer verification and installer rules depend on the device's region and software. A signature alone does not bypass those rules.

The package is `org.signsofrain.prototype`, version `0.1.0`, code `1`. The template targets Android API 35 and declares a minimum of API 24. The Mobile renderer also needs suitable graphics hardware. Orientation follows the device, and the activity supports resizing.

## Play

Tap to select a person or place the selected miracle. Drag one finger to orbit. Drag two fingers to pan, or pinch to zoom. A drag never casts a miracle on release. The bottom row contains Look, Rain, Food, Pause, and the controls menu. Every other action stays in that scrollable menu. See [all controls](controls.md).

Android scales the UI from its reported DPI. Targets remain at least 48 canvas units. The valley renders at physical display density before its graphics scale applies. Picking converts canvas units into viewport pixels. Safe-area insets apply before the layout policy. Resizing and modal sheets cancel active gestures.

Android starts with Faster graphics. It keeps shadows, ordinary fog, glow, water, vegetation, and animation. Godot 4.6.1 Mobile does not support the desktop SSAO, SSIL, volumetric fog, or FSR path. Unsupported effects stay off even in High mode. Fast uses bilinear upscaling and the existing 1.4-megapixel budget. The phone shadow atlas is 2048 pixels. These choices reduce detail and lighting cost; they do not establish a frame rate.

## Rebuild on aka

Run these commands from a clean committed checkout:

```sh
./tools/check.py
./tools/prepare-android.py --host simonwjackson@aka
./tools/build-android-on-host.py --host simonwjackson@aka
```

Use `--init-signing` with the last command only for the first build on a new host. The build creates the project's signing key under `~/.local/share/signs-of-rain/android-signing/` on that host. Back up both `release.keystore` and `password` privately. They never belong in Git, the APK, or an attachment. Keep the same key for compatible APK updates. Losing it can require uninstalling the old app, which removes its local settings and replay file.

Preparation copies the pinned Nix tool closures and verifies the official export-template archive against its recorded SHA-512. It extracts only the Android templates. The standard template export uses JDK 17 and cached Android Build Tools 36.0.0 for signing. It does not compile the Godot engine, use Gradle, or need the SDK's NDK/CMake packages. The template's target API remains 35. This toolchain is pinned to the recorded Nix store paths.

The remote build uses an isolated Git clone. The exporter uses a second temporary copy containing only runtime folders. Godot configuration, cache, and user data stay inside that temporary build. The scripts do not change the build host's normal Godot settings, game saves, installed Linux launcher, system services, or live graphical session.

The builder rejects other engine versions, changed templates, export errors, bad APK signatures, wrong architectures, development files, and bad 16 KiB library alignment. It publishes the APK only after verification. Keep the official Android template assets `dexopt/baseline.prof`, `dexopt/baseline.profm`, and `assets.sparsepck`; they are runtime data, not development captures.

## Verification limits

`tools/check.py` runs the simulation, camera, terrain, characters, presentation, graphics, touch, layout, density, and packaging tests. Screen events exercise the real Godot input path. These are engine tests, not a physical touchscreen test.

`tools/test-mobile-render.py` captures the actual Mobile renderer on an owned headless compositor. It uses separate configuration, runtime, cache, and user-data directories, and muted audio. It checks folded, unfolded, high-density, and wide-short shapes. This is a desktop Vulkan test, not an ARM64 Android run or a phone benchmark.

No Fold8 was connected during the initial build. Installation, real multitouch, fold transitions, safe-area reporting, interrupted audio, sustained frame time, heat, battery use, and ARM replay determinism still need a device test. Do not infer phone performance from laptop results.

## Platform references

- [Godot 4.6 Android export](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html).
- [Godot 4.6 renderers](https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html).
- [Official 4.6.1 templates](https://godotengine.org/download/archive/4.6.1-stable/).
- [Samsung Auto Blocker](https://www.samsung.com/us/support/answer/ANS10003636/).
- [Android developer verification](https://developer.android.com/developer-verification).

The versioned scaling docs and newer upstream excerpts disagree about Mobile FSR. The tagged 4.6.1 engine creates its FSR implementation only when the renderer supports storage textures. Mobile's `_render_buffers_can_be_storage()` returns false. This build therefore uses bilinear on Mobile. Sources: [Mobile renderer](https://github.com/godotengine/godot/blob/4.6.1-stable/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp) and [shared renderer setup](https://github.com/godotengine/godot/blob/4.6.1-stable/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp).
