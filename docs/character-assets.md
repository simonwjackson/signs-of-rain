# Animated villagers

Verified implementation: two dressed Quaternius humanoids, real faces and hair, a 65-bone skeleton per person, six animated cues, and supply vessels driven by the actual carried amounts. Source art is **CC0**, including the animation library. No paid assets, accounts, or mirrors were used.

## Integration

`game/villager.gd` extends `Node3D`. Construct with `new(person_id, village)`, add to the scene, then call `present(person, moving, delta)` each rendered frame. The caller alone owns world position and heading. The public root faces **local -Z**. The private model rotates the author's +Z-forward art by PI.

`present` reads only `action`, `carried_food`, and `carried_water`. It does not modify its dictionary or simulation state. Animation advances manually from the supplied delta. People differ by male/female model, two hairstyles per model, occasional beards, four clothing tints, four hair tints, subtle skin tints, and deterministic height variation. No simulation RNG is consumed.

| State | Source glTF clip | Godot imported name |
|---|---|---|
| Moving | `Walk_Loop` | `Walk` |
| Idle/default | `Idle_Loop` | `Idle` |
| Telling | `Idle_Talking_Loop` | `Idle_Talking` |
| Ritual | `Spell_Simple_Idle_Loop` | `Spell_Simple_Idle` |
| Working | `Fixing_Kneeling` | `Fixing_Kneeling` |
| Sharing | `Interact` | `Interact` |

Godot removes the `_Loop` suffix automatically. These exact imported names were read from the real AnimationPlayer. Movement takes precedence over stationary activity. Only nonzero carried quantities show the bread basket or water bucket. Both can show at once. A bucket remains upright as the hand turns.

## Actual asset inspection

| Curated source-space T-pose bounds, meters | Minimum XYZ | Maximum XYZ |
|---|---|---|
| Male, all included hair variants | (-0.899415, -0.003967, -0.184477) | (0.899415, 1.839722, 0.167542) |
| Female, all included hair variants | (-0.831941, -0.006744, -0.167255) | (0.831941, 1.779152, 0.167542) |

These are actual indexed mesh bounds, not animated bounds. T-pose width includes outstretched arms. Runtime scales male bodies by `1.74/1.81` and female bodies by `1.70/1.77`, then multiplies by `0.97 + (id % 4) * 0.02`. Hair-inclusive neutral height is about 1.69–1.79 m for the actual 24 IDs. A 0.012 m model offset clears the source's slightly negative sole coordinates.

Male asset: 10 meshes, 5 skin bindings sharing one 65-bone skeleton, 8 source materials, 20,825 triangles including mutually exclusive hair. Female: 9 meshes, 4 bindings, 6 materials, 25,206 triangles including mutually exclusive hair. Geometry includes eyes, brows, nose, ears, fingers, clothing seams, cuffs, footwear, hair and optional beard. Materials use authored albedo, normal and roughness/ORM texture maps, with shaded StandardMaterial3D overrides. Textures are capped at 1024 pixels. Curated payload is about 19.8 MB, not the 439 MB source archives.

The free base pack contains Superhero bodies rather than the advertised paid Regular bodies. Only the head/neck, eyes and brows are used; the dressed body is the free Peasant outfit. Hidden base-body triangles are pruned. Outfit and face use matching male/female bone rests. The animation library uses slightly different proportions, so the curation script transfers rest-relative rotations and vertical pelvis bob rather than copying every positional track. Root transform tracks are absent. There is no root-motion drift.

## Provenance and regeneration

See `assets/characters/provenance.json` for primary URLs, author, exact archive SHA-256 hashes, upload IDs, selected files and changes. `base-LICENSE.txt`, `outfits-LICENSE.txt`, and `anim-LICENSE.txt` are **verbatim archive files**. Each explicitly says `CC0 1.0 Universal (CC0 1.0)` and links to the public-domain dedication. `animation-README.txt` explicitly states that the file without `_RM` has root motion disabled. CC0 permits source and binary redistribution without attribution; author credit is retained anyway.

Downloads are made only with the locally written Nix-shebang `tools/fetch-characters.py`. It follows the author's free itch download flow, without authentication or payment. To regenerate, from the project root:

```sh
./tools/fetch-characters.py --itch https://quaternius.itch.io/universal-base-characters /tmp/signs-assets-research/base.zip
./tools/fetch-characters.py --itch https://quaternius.itch.io/modular-character-outfits-fantasy /tmp/signs-assets-research/outfits.zip
./tools/fetch-characters.py --itch https://quaternius.itch.io/universal-animation-library /tmp/signs-assets-research/anim.zip
python3 -m zipfile -e /tmp/signs-assets-research/base.zip /tmp/signs-assets-research/base
python3 -m zipfile -e /tmp/signs-assets-research/outfits.zip /tmp/signs-assets-research/outfits
python3 -m zipfile -e /tmp/signs-assets-research/anim.zip /tmp/signs-assets-research/anim
./assets/characters/curate.py
(cd assets/characters && sha256sum -c SHA256SUMS)
```

Upstream can change its free uploads. Compare archive hashes to provenance before regeneration. `SHA256SUMS` records curated files. Source ZIPs, FBX copies, unused outfits, the mannequin and unused animation clips are not in the project.

## Validation and limits

Verified with Godot 4.6.1 in an isolated real scene under `/tmp/signs-people-test`:

- Clean asset import, no missing texture or parse errors.
- 24 instances, 240 presentation updates each. Assertions cover input/root immutability, actual bone movement, six clip selections, and food/water visibility.
- Actual Forward+ Vulkan rendering on the local **NVIDIA GeForce RTX 3060 Laptop GPU**, not a substitute claim about aka's RX 7900 XT.
- Viewed `/tmp/signs-people-render.png`, `/tmp/signs-people-render-2.png`, and `/tmp/signs-people-close.png`. Different walking poses and a close-up establish dressed humanoids with visible faces, hair, cloth and boots. The close-up uses 4x MSAA.

Visual judgment: readable stylized human characters, not faceless placeholders. They are not photorealistic. The female outfit has a fantasy-adventurer silhouette. There is no facial animation, cloth simulation, foot IK, terrain-aware stride or grip IK. Supplies are simple procedural vessels, not textured authored props. Fixed walk cadence can slide against varying simulation speeds. The working clip loops a kneeling repair motion rather than a farming-specific animation. Normal-mapped 1024 textures and these polygon counts do not establish final landscape-scale performance. Parent must verify 24 people on terrain, camera close-up/overview, and aka Forward+ deployment.
