# Deterministic simulation

`simulation.gd` is a `RefCounted` model. It has no scene, input, wall-clock, audio, or rendering dependencies. Use the public interface in `docs/simulation-contract.md`. The presentation reads state; only `cast()` and `step()` change play state.

## Rules and units

- One step is half a second. Seven days are 560 steps. Ended state is immutable through the public play methods.
- Power starts at eight and never renews. Rain costs two. Food costs one. Rejected commands change nothing, including RNG state and command history.
- Rain has a 150-unit radius. At a village center it adds up to 64 water and 20 standing crop, capped at 100. Strength falls to 35% at the radius edge. Outside both village catchments it adds no village resources.
- Food creates a 38-unit cache at the chosen position. It must be found, collected, and carried. A cache more than 150 units from either village has beneficiary `-1`: it is not assigned to a village. Any person can collect it.
- The common well at `WELL = Vector2(500, 405)` starts with 160 water. It never refills. Each trip carries at most six water home.
- The fields contain finite standing crop. Workers harvest it. Wet fields grow slowly; dry fields lose crop. Stores, exposed caches, and water have small losses. All resource values stay nonnegative; village stores cap at 100. Excess delivery/production at a full store is lost, except a sharing traveler who carries surplus home.
- People get hungry and thirsty every step. They consume village food and water only within 82 units of a village center. Private hoards feed only their holder. Need rises to a maximum of one; it slows movement and can cause rest. Exhaustion is a need of at least 0.8. There is no mortality model.

## Information and decisions

A cast gives a memory only to people within 150 units. Reports require contact within 74 units and recipient trust of at least 0.30. The delay is `ceil(6 + (1 - trust) * 18)` steps after the sender learned the event. A sender can report once per 18 steps. Each hop multiplies confidence by `trust * 0.92`; confidence below 0.16 does not pass.

Memories retain witness/report status, event identity, learned time, sender, all reporter IDs, confidence, and the remembered kind, position, and beneficiary. A reporter copies its own remembered facts, not the global event record. An event can enter a person's memory only once. An echo cannot add confidence or another vote. These reports do not mutate or invent facts; their uncertainty is represented by confidence and attribution.

Interpretation scores depend on the person's current relevant need, personal generosity/piety/grievance, history, and whether another village received the help. Each village contains four history variants. Every unique memory casts a confidence-weighted vote for care, ritual, or favoritism. The strongest vote determines belief; conviction shows its fraction of all evidence plus a small uncertain prior. No supernatural action means no supernatural belief, even for a person raised at the shrine.

Belief changes actions, not just text:

| Belief | Action and material cost |
| --- | --- |
| Care | Withdraw six food, walk to the other village, and deposit it on arrival. No donation when local food is at most 12 or personal hunger reaches 0.72. |
| Ritual | Remove up to one food as an offering when leaving home, walk to the shrine, stay 24 steps, and return. Travel replaces harvesting. Severe need can stop new pilgrimages. |
| Favoritism | Take up to three food for private use and move away from the crossing. Avoidance reduces work and contact opportunities. |
| Uncertain | Gather crop, collect visible/remembered caches, try the shared well when home water is low, and rest when exhausted. These routines also run between belief actions. |

Sharing and ritual counts increment on arrival, not departure. Avoidance counts decisions to withdraw from contact. A person's `cause` explains the current action; the action log retains its originating event ID. A journey is completed before a new memory can replace its destination. People cannot use remote resource amounts to select caches or inspect the well. They can see a nearby cache without knowing that its origin was a miracle.

## Starting scenarios for causal tests

`Simulation.new(seed_value, config)` always uses the same rules and random setup sequence. Config patches initial state **after** seeded initialization; there are no test-only mechanics, timers, forced beliefs, forced memories, or forced actions.

Supported config keys:

| Key | Value |
| --- | --- |
| `people` | Array of dictionaries with `id` (0–23) and any supported person fields below. |
| `villages` | Array of dictionaries with `id` (0–1) and optional `food`, `water`, `crop`, each clamped to 0–100. |
| `well_water` | Initial common well supply, clamped to 0–300. Default 160. |

Person patches support:

- `pos`, `home`: `Vector2` positions. They permit controlled sight/contact geometry. The scenario author keeps positions in world bounds. Village membership does not change.
- `hunger`, `thirst`: clamped to 0–1.
- `history`: `helped`, `shrine`, `excluded`, or `ordinary`.
- `traits`: a partial dictionary of `generosity`, `piety`, `grievance`, each clamped to 0–1.
- `trust`: a partial dictionary of **integer person IDs** to trust, clamped to 0–1. Recipient trust in the sender controls reception. Unspecified relationships retain their seeded values.

Example, with the same scene and rules but one changed history:

```gdscript
const Simulation = preload("res://sim/simulation.gd")
var scenario = {"people": [{"id": 0, "history": "helped",
    "hunger": 0.1, "thirst": 0.1,
    "traits": {"piety": 0.45, "generosity": 0.3, "grievance": 0.2}}]}
var sim = Simulation.new(2401, scenario)
sim.cast("rain", Vector2(240, 340))
sim.step()
```

The tests hold geography, supplies, traits, event, and seed fixed while changing history. Care withdraws six food for a delivery; ritual removes one offering and changes the destination; exclusion holds three privately. Another paired test changes only thirst, producing a different reading of the same rain. Spatial/trust pairs test information access independently.

## Additional read-only presentation state

- `WELL`, `well_water` and `caches` allow the renderer to show the common well and remaining food caches. Cache fields: `event_id`, `pos`, `food`, `village`.
- People also expose `history`, `goal`, `event_id`, `carried_food`, `carried_water`, and `private_food` for causal inspection. Timing fields and depleted-cache records are implementation state.
- Summary metrics include `shared_food`, `offerings`, `harvested`, `well_drawn`, `exhausted`, belief counts, and per-village needs, in addition to the six contracted metrics.

## Verification

From the project root:

```sh
/nix/store/prgpch05xca3nvd945kz5kbixpjdwis1-godot-4.6.1-stable/bin/godot4 \
  --headless --path . --script tests/simulation_test.gd
```

This does not require the main scene. It exits nonzero on a failed check and writes `verification/simulation-results.json`. The digest canonicalizes vectors and dictionary keys, includes full precision resource state and RNG state, and hashes the complete simulation state with SHA256. Tests compare independent executions and command-log replay, not a fixed expected digest.

Determinism is verified within the supplied Godot 4.6.1 build. Cross-engine-version or cross-CPU floating-point equivalence is not promised. This is a 24-person rule model, not a general theory of religion or a calibrated survival model. Fixed person iteration resolves simultaneous access to supplies in stable ID order. Report facts do not distort, trust does not evolve, and history is fixed. A kind action need not improve every aggregate outcome: journeys and rituals can leave food unharvested, and aid can displace well trips.
