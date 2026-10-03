{
  buildPkgs,
  runtimePkgs,
  source,
}:
let
  exporter =
    assert buildPkgs.godot.version == "4.6.1-stable";
    buildPkgs.godot;
  runtime =
    assert runtimePkgs.godot.version == "4.6.1-stable";
    runtimePkgs.godot;
  gameSource = buildPkgs.lib.fileset.toSource {
    root = source;
    fileset = buildPkgs.lib.fileset.unions [
      (source + /assets)
      (source + /game)
      (source + /sim)
      (source + /ui)
      (source + /project.godot)
      (source + /export_presets.cfg)
    ];
  };
  # Export once on the build workstation. PCK data contains no native executable.
  pack =
    buildPkgs.runCommand "signs-of-rain-linux-pack"
      {
        nativeBuildInputs = [ exporter ];
      }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_DATA_HOME="$HOME/data"
        export XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$XDG_CONFIG_HOME/godot" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
        cat > "$XDG_CONFIG_HOME/godot/editor_settings-4.6.tres" <<'SETTINGS'
        [gd_resource type="EditorSettings" format=3]

        [resource]
        export/android/shutdown_adb_on_exit = false
        SETTINGS
        cp -r ${gameSource} source
        chmod -R u+w source
        cd source
        rm -f assets/characters/curate.py assets/characters/provenance.json
        # Retain desktop formats and include ETC2/ASTC for ARM GLES/Vulkan drivers.
        sed -i '0,/texture_format\/etc2_astc=false/s//texture_format\/etc2_astc=true/' export_presets.cfg
        godot --headless --path . --editor --import --quit > import.log 2>&1
        cat import.log
        if grep -E 'SCRIPT ERROR:|^ERROR:' import.log; then exit 1; fi
        mkdir -p "$out/licenses"
        godot --headless --path . --export-pack Linux "$out/signs-of-rain.pck" > export.log 2>&1
        cat export.log
        if grep -E 'SCRIPT ERROR:|^ERROR:' export.log; then exit 1; fi
        cp assets/fonts/*OFL.txt assets/characters/*LICENSE.txt "$out/licenses/"
        godot --headless --main-pack "$out/signs-of-rain.pck" --quit-after 8 -- --no-intro --mute > smoke.log 2>&1
        cat smoke.log
        if grep -E 'SCRIPT ERROR:|^ERROR:' smoke.log; then exit 1; fi
      '';
in
buildPkgs.runCommand "signs-of-rain"
  {
    passthru = { inherit pack runtime; };
    meta = {
      description = "Signs of Rain, a 3D village simulation";
      mainProgram = "signs-of-rain";
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/signs-of-rain"
    ln -s ${pack}/signs-of-rain.pck "$out/share/signs-of-rain/signs-of-rain.pck"
    ln -s ${pack}/licenses "$out/share/signs-of-rain/licenses"
    cat > "$out/bin/signs-of-rain" <<'LAUNCHER'
    #!${runtimePkgs.runtimeShell}
    pack=${pack}/signs-of-rain.pck
    if [ "$#" -ge 2 ] && [ "$1" = --main-pack ]; then
      pack="$2"
      shift 2
    fi
    exec ${runtime}/bin/godot --main-pack "$pack" ${
      buildPkgs.lib.optionalString (
        runtimePkgs.stdenv.hostPlatform.system == "aarch64-linux"
      ) "--rendering-method gl_compatibility --rendering-driver opengl3_es"
    } "$@"
    LAUNCHER
    chmod +x "$out/bin/signs-of-rain"
  ''
