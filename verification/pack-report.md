# Export boundary correction

The final main-checkout rebuild imported ignored test captures. Git ignore rules do not define Godot's export boundary. The game ran correctly, but the pack contained unnecessary development data.

`export_presets.cfg` now excludes `artifacts/`, asset curation scripts, and provenance JSON. Actual font/character licenses remain included. Source provenance remains in Git.

`tools/build.py` now runs `tests/pack_test.gd` against the actual exported main pack, from outside the source checkout. The test enumerates pack directories, rejects unexpected top-level roots and development data, and requires the main scene, simulation, camera, and both character models.

| Actual test | Result |
| --- | --- |
| Original main pack with captured evidence. | 168 members, 46 boundary failures, exit 1. |
| Corrected pack, with a real sentinel screenshot deliberately present under `artifacts/`. | 89 members, zero boundary failures, exit 0. |
| Corrected main-pack launch. | The real scene ran headlessly without script or resource errors. |

The final rebuild therefore has a different pack hash from the gameplay recording. This change removes development data; it does not change game logic or presentation. Full play evidence identifies its recorded pack in `target-results.json`. Post-landing input/render/audio verification of the installed clean pack is retained under `artifacts/target/landed-smoke.json` and `final-runtime-audit.json`.
