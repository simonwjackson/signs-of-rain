# Simulation contract

The parent owns presentation and deployment. The simulation worker owns `sim/` and `tests/simulation_test.gd` plus simulation-specific test reports under `verification/`.

Use `res://sim/simulation.gd`, extending RefCounted, no scene or real-time dependencies. Public constructor `new(seed_value: int = 2401, config: Dictionary = {})`. `config` supports controlled real scenarios for tests, with documentation. Seed all stochastic choices on an instance-local RandomNumberGenerator.

Public data, read by presentation but mutated only by the simulation:

- `seed_value: int`, `tick: int`, `ended: bool`, `power: int` initially 8, `people: Array[Dictionary]`, `villages: Array[Dictionary]`, `events: Array[Dictionary]`, `action_log: Array[Dictionary]`, `command_log: Array[Dictionary]`.
- Constants `DAY_TICKS = 80`, `END_TICK = 560`, `WORLD_SIZE = Vector2(1000, 640)`, `SHRINE = Vector2(500, 280)`. Simulation advances at two ticks per real second at normal speed. Seven days last 4m40s.
- Two villages named Alder and Sedge, at Vector2(240, 340) and Vector2(760, 340). Twelve people each. Fields: id (0/1), name, pos, food (float), water (float), crop (float). Resources in approximately 0..100 ranges. Include histories/needs variants inside each village, not one belief per village.
- Person fields: id int 0..23, name, village int, pos Vector2, home Vector2, hunger float 0..1, thirst float 0..1, belief String (`uncertain`, `care`, `ritual`, `favoritism`), conviction float 0..1, action String (`work`, `fetch`, `share`, `ritual`, `tell`, `avoid`, `rest`), target Vector2, memories Array[Dictionary], cause String, trust Dictionary, traits Dictionary. Extra fields permitted.
- Memory fields: event_id int, tick int learned at, source String (`witness` or `report`), via int sender or -1, interpretation String, reason String, chain Array[int] attribution through reporters, confidence float. Preserve distinct observation/report semantics and bounded factual information. Do not inject global true event positions into uninformed minds.
- Event fields: id int, tick int, kind String (`rain`/`food`), pos Vector2, village int affected beneficiary, witnesses Array[int]. Food location can be a cache. Rain affects nearby crops/water. Cast radius is public `RADIUS = 150.0`. Give real spatial choice and finite resources.
- Action log fields: tick int, person int, action String, cause String, event_id int or -1. Log meaningful decisions, not every tick. Keep an inspectable link to the memory responsible.

Public methods:

- `cast(kind: String, pos: Vector2) -> Dictionary`: accepts rain/food in world bounds if enough power and not ended, costs 2 for rain/1 for food; returns `{ok: bool, reason: String, event_id: int}`. Failures do not consume power or RNG or record commands. Successful commands record tick/kind/pos. Pause does not block casting; tick identifies replay order. Physical benefits and local witnesses occur now, not omniscient spread.
- `step() -> void`: fixed deterministic tick, gathers/decays resources, advances hunger/thirst and movement, then proximity-based reports and deliberate actions. Stop at END_TICK. Need-driven routines exist without miracles. Trust and needs/history affect interpretation. Beliefs materially affect sharing vs holding supplies, shrine travel/ritual, reporting, or avoiding the other village. Stories spread with time and contact, not global broadcast. Avoid counting a story twice as new evidence from echo loops.
- `summary() -> Dictionary`: human-readable `title` String, `text` String, plus `metrics` Dictionary with total shares, rituals, reports, avoidance, mean hunger, mean thirst. End can arrive without everyone surviving or being fed; report tradeoffs, not moral score.
- `digest() -> String`: stable SHA256 of complete deterministic simulation state including RNG state, all beliefs/memories/actions/resource state. Serialization converts Vector2 to numeric arrays, ordered dictionaries where needed. Tests compare two separately executed runs, not hardcoded implementation hashes.

Tests use the public simulation API. Document controlled constructor setup options to prove needs/history interpretation changes and belief-driven actions causally, not just correlationally. Include same-seed runs with no intervention, balanced help, and one-sided help, plus command rejection. Do not write UI files or project.godot. Godot path available from parent. Avoid typed inference from Variant errors; explicit types at interfaces, `=` for flexible local dictionary data. User authorized autonomous implementation and these behavioral verification boundaries; do not wait for another question.
