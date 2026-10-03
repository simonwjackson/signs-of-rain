# Simulation verification — 2026-10-03

**Verified: 104 checks passed; zero failures in the actual Godot 4.6.1 headless runner.** This report covers simulation behavior only. It does not verify rendering, audio, input, or deployment.

## Command

From the project worktree:

```sh
/nix/store/prgpch05xca3nvd945kz5kbixpjdwis1-godot-4.6.1-stable/bin/godot4 --headless --path . --script tests/simulation_test.gd
```

Output: `SIMULATION: 104 checks, 0 failures`. Exit status: `0`. The runner writes `verification/simulation-results.json` and exits nonzero if any behavioral check fails.

## Verified behavior

- Accepted casts affect only local catchments, physical caches, and witnesses. Outlying caches do not claim a village beneficiary. Rain strength falls with distance.
- Bad kind, out-of-bounds/NaN position, insufficient power, and ended-state casts leave the complete state and RNG unchanged.
- Non-witnesses learn only through contact. Identical geometry with different trust produces six- versus fifteen-tick minimum delays, or no report. Trust without proximity is insufficient.
- Two-hop reports preserve the witness-to-reporter chain and lose confidence at each hop. A repeated story remains one memory, not new evidence.
- Changing only thirst changes the interpretation of identical rain. Changing only history produces care, ritual, or favoritism while traits, needs, supplies, position, seed, and event remain fixed.
- Those history controls cause actual six-food shipments, shrine travel and offerings, or private three-food hoards and withdrawal from the crossing. Deliveries and shrine visits complete in the model; they are not merely action labels.
- Food pickup and delivery conserve a measured seven-unit load. An unseen cache does not give event knowledge. Empty stores, fields, and well cannot produce sustenance.
- All memory-linked action records follow their actor's actual learning time.
- Each contrasting run was separately executed twice and also replayed from its successful command log. The complete SHA256 state digest matched in all three executions per strategy, including beliefs, memories, resources, actions, and RNG state.
- Every complete strategy run stops at tick 560. Further stepping/casting does not change its state. Needs, resources, and confidence remain bounded; the well never supplies more than its initial 160 water.

## Review follow-up: 21 additional checks

No simulation implementation or public API changed. These fixtures use only constructor starting conditions, `cast()`, and `step()`; they do not inject memories, beliefs, actions, or depletion.

### Mixed commands and same-tick replay

Seed `5709` executes six accepted commands, spending eight power and creating four caches:

| Tick | First command | Second command |
| --- | --- | --- |
| 0 | Rain at Alder | Food at Alder |
| 80 | Food at Sedge | Rain at Sedge |
| 200 | Food at the shrine | Food at `(160, 340)` |

Two independent complete runs and ordered command-log replay match digest `fdf2b8729a7c6df4f852ef5fb12df5003be48a1aa3c63a2faaaf70b7d1ded7f0`. The log preserves both command kind order and the positions of same-kind food commands. Reversing the first same-tick pair changes event identity and the full digest. This checks ordered paused casting and cache state, not cross-engine determinism.

### Cache information boundaries

An uninformed person performs 30 routine ticks without targeting a distant cache. In a second fixture, six collectors physically take `37.982` food by tick 2; the other `0.018` is measured spoilage. The receiver learns about that already-empty cache through a witness at tick 6. The receiver selects it while outside visual range and continues the journey without remote depletion knowledge. Only after reaching the cache does the receiver mark it depleted and stop targeting it.

### Confidence-weighted competing evidence

The paired fixture changes only the receiver's trust in two reporters. Both runs receive the same direct care observation and the same two reported ritual interpretations, with the same sources. Initial stores keep sharing ineligible, so the receiver can make its next decision when the reports arrive.

| Measure | Reporter trust 1.0 | Reporter trust 0.5 |
| --- | ---: | ---: |
| Direct care evidence | 1.0 | 1.0 |
| Two reports' total ritual evidence | 1.84 | 0.92 |
| Dominant belief | Ritual | Care |
| Conviction | 0.585987 | 0.450450 |
| Next eligible action | Shrine trip | Cache collection |
| Additional recipient offering | 1 food | 0 food |

The reporters each make one offering in both fixtures; total offerings are therefore three versus two. The recipient's action and added offering, not just its belief label, differ. Counting reports without confidence would incorrectly choose ritual in both runs and fail these checks.

## Same-seed contrasting runs

Seed: `2401`. All runs last 560 ticks. Both intervention strategies spend all eight power on rain at ticks `40, 120, 240, 320`. Balanced rain alternates Alder/Sedge. One-sided rain always targets Alder. No intervention issues no commands.

| Final measure | No intervention | Balanced rain | Alder-only rain |
| --- | ---: | ---: | ---: |
| Mean hunger, 0–1 | 0.684484 | 0.692105 | 0.591150 |
| Mean thirst, 0–1 | 0.866548 | 0.703807 | 0.656744 |
| Alder mean thirst | 0.858200 | 0.721950 | 0.442822 |
| Sedge mean thirst | 0.874897 | 0.685663 | 0.870667 |
| Completed food deliveries | 0 | 4 | 2 |
| Food delivered | 0 | 24 | 12 |
| Completed shrine visits | 0 | 16 | 7 |
| Reports delivered | 0 | 51 | 24 |
| Avoidance decisions | 0 | 24 | 25 |
| Exhausted people | 18 | 10 | 17 |
| Well water collected | 160 | 18 | 72 |
| People believing favoritism | 0 | 6 | 12 |

Balanced rain reduces average thirst by `0.162742` versus no intervention. Alder-only rain produces a `0.427844` inter-village thirst gap, versus `0.036287` under balanced rain.

**Tradeoff, not a moral score:** balanced rain does not minimize hunger or average thirst in these measured runs. Travel and ritual replace work and well trips. One-sided rain improves the favored village enough to lower the overall mean, while Sedge stays almost as thirsty as with no intervention. The causal controls verify action effects; the table alone does not isolate every contribution to these aggregate differences.

Exact digests and unrounded metrics are in `simulation-results.json`.

## Scope and limitations

- Public contract fields and methods are preserved. `sim/README.md` documents controlled constructor patches and extra read-only well/cache/carrying state.
- The simulation has no mortality, evolving trust, distorted report content, obstacles, or complex households. Exhaustion slows people; it does not remove them.
- Person ID order resolves simultaneous access to supplies. Confidence votes and four fixed history variants limit interpretation range.
- The initial 160-water common well is finite, but belief-driven journeys can leave some of it unused. This is a measured tradeoff, not replenishing water.
- Determinism is verified in the supplied Godot build, not across all engine versions or CPU architectures.
- Presentation, sound, game restart UI, aka installation, and real-device gameplay remain the parent's verification boundary. No parent-owned files were edited, staged, or committed by this worker.

Recommended next step: integrate the renderer with this fixed API and run the shipped-game input/render/audio/ending/restart checks on aka. This requires target access and does not replace the headless behavioral tests.
