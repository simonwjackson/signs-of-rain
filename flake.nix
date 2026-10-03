{
  description = "Signs of Rain: pinned Godot 4.6.1 and ARM64 Android export tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c06b4ae3d6599a672a6210b7021d699c351eebda";

  outputs =
    { self, nixpkgs }:
    let
      # The Android SDK build tools run on the project's x86_64 Linux hosts.
      systems = [ "x86_64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      toolsFor =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              android_sdk.accept_license = true;
              allowUnfree = true;
            };
          };
          godot =
            assert pkgs.godot.version == "4.6.1-stable";
            pkgs.godot;
          sdk =
            (pkgs.androidenv.composeAndroidPackages {
              buildToolsVersions = [ "36.0.0" ];
              platformVersions = [ "36" ];
              abiVersions = [ "arm64-v8a" ];
              includeEmulator = false;
              includeNDK = false;
              includeCmake = false;
            }).androidsdk;
          archiveUrl = "https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable/Godot_v4.6.1-stable_export_templates.tpz";
          archiveHash = "d80001711c07973b1fd3e88077ba99644e19db7c9e52627e16f38a2937879f809f94dbd8493936fb8204908bbc57a521d41173dce5208061fe4c99772490c541";
          archive = pkgs.fetchurl {
            url = archiveUrl;
            sha512 = archiveHash;
          };
          templates =
            pkgs.runCommand "signs-of-rain-android-templates-4.6.1"
              {
                nativeBuildInputs = [ pkgs.unzip ];
              }
              ''
                mkdir -p "$out"
                unzip -p ${archive} templates/android_debug.apk > "$out/android_debug.apk"
                unzip -p ${archive} templates/android_release.apk > "$out/android_release.apk"
                unzip -p ${archive} templates/version.txt > "$out/version.txt"
                test "$(cat "$out/version.txt")" = "4.6.1.stable"
              '';
          toolchain = pkgs.writeTextFile {
            name = "signs-of-rain-android-toolchain";
            destination = "/manifest.json";
            text = builtins.toJSON {
              engine = "${godot}";
              sdk = "${sdk}/libexec/android-sdk";
              java = "${pkgs.jdk17}";
              python = "${pkgs.python3}";
              git = "${pkgs.git}";
              templates = "${templates}";
              archive_url = archiveUrl;
              sha512 = archiveHash;
              template_version = "4.6.1.stable";
              templates_sha256 = {
                "android_debug.apk" = "4f4ae88bab8a49e138e780cdcf4ad0cdb8c0d1c6efa8c0c4dc05a40517664ea1";
                "android_release.apk" = "1ed57d6df30f8dc436c251b91208fc88590bbc2bde22445bb3f476f934a6cca6";
              };
            };
          };
          environment = {
            GODOT = "${godot}/bin/godot";
            GDFORMAT = "${pkgs.gdtoolkit_4}/bin/gdformat";
            GDLINT = "${pkgs.gdtoolkit_4}/bin/gdlint";
            RUFF = "${pkgs.ruff}/bin/ruff";
            JAVA_HOME = "${pkgs.jdk17}";
            ANDROID_HOME = "${sdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${sdk}/libexec/android-sdk";
          };
          packages = [
            godot
            sdk
            pkgs.jdk17
            pkgs.python3
            pkgs.git
            pkgs.openssh
            pkgs.nix
            pkgs.gdtoolkit_4
            pkgs.ruff
          ];
          app =
            name: script: extra:
            let
              wrapper = pkgs.writeShellApplication {
                inherit name;
                runtimeInputs = packages;
                text = ''
                  root="$(git rev-parse --show-toplevel)"
                  test -f "$root/project.godot"
                  ${nixpkgs.lib.concatStringsSep "\n" (
                    nixpkgs.lib.mapAttrsToList (
                      key: value: "export ${key}=${nixpkgs.lib.escapeShellArg value}"
                    ) environment
                  )}
                  ${extra}
                  exec python3 "$root/tools/${script}" "$@"
                '';
              };
            in
            {
              type = "app";
              program = "${wrapper}/bin/${name}";
            };
        in
        {
          inherit
            pkgs
            godot
            sdk
            templates
            toolchain
            environment
            packages
            app
            ;
        };
    in
    {
      packages = eachSystem (
        system:
        let
          tools = toolsFor system;
        in
        {
          default = tools.toolchain;
          android-toolchain = tools.toolchain;
          android-templates = tools.templates;
          android-sdk = tools.sdk;
          godot = tools.godot;
        }
      );
      devShells = eachSystem (
        system:
        let
          tools = toolsFor system;
        in
        {
          default = tools.pkgs.mkShell (
            tools.environment
            // {
              inherit (tools) packages;
              SIGNS_ANDROID_TOOLCHAIN = "${tools.toolchain}";
              shellHook = ''export PATH="${tools.sdk}/libexec/android-sdk/platform-tools:$PATH"'';
            }
          );
        }
      );
      apps = eachSystem (
        system:
        let
          tools = toolsFor system;
          check =
            tools.app "signs-check" "check.py"
              ''export SIGNS_CHECK_REPORT="$root/build/local-checks.json"'';
        in
        {
          default = check;
          inherit check;
          prepare-android = tools.app "signs-prepare-android" "prepare-android.py" "";
          build-android =
            tools.app "signs-build-android" "build-android-on-host.py"
              ''export SIGNS_ANDROID_TOOLCHAIN="${tools.toolchain}"'';
          build-linux = tools.app "signs-build-linux" "build.py" "";
        }
      );
      checks = eachSystem (
        system:
        let
          tools = toolsFor system;
        in
        {
          game =
            tools.pkgs.runCommand "signs-of-rain-checks"
              (
                tools.environment
                // {
                  nativeBuildInputs = tools.packages;
                }
              )
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                cp -r ${self} source
                chmod -R u+w source
                cd source
                python3 tools/check.py
                mkdir -p "$out"
                cp verification/local-checks.json "$out/local-checks.json"
              '';
        }
      );
      formatter = eachSystem (system: (toolsFor system).pkgs.nixfmt);
    };
}
