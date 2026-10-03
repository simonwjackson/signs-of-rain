extends SceneTree

const Simulation = preload("res://sim/simulation.gd")
var checks: int = 0
var failures: Array[String] = []
var evidence: Dictionary = {}


func _initialize() -> void:
	_test_rejection_and_space()
	_test_information_and_trust()
	_test_interpretation_and_behavior()
	_test_finite_resources()
	_test_cache_information_boundaries()
	_test_competing_evidence()
	_test_replays_and_contrasts()
	_test_mixed_command_replay()
	var report = {
		"checks": checks, "failures": failures, "passed": failures.is_empty(), "evidence": evidence
	}
	DirAccess.make_dir_recursive_absolute("res://verification")
	var file = FileAccess.open("res://verification/simulation-results.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	else:
		_check(false, "Verification report can be written")
	print("SIMULATION: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _advance(sim, count: int) -> void:
	for index in range(count):
		sim.step()


func _isolated_config(person_zero: Dictionary = {}) -> Dictionary:
	var patches = []
	for id in range(24):
		patches.append({"id": id, "pos": Vector2(960, 600), "hunger": 0.1, "thirst": 0.1})
	patches[0] = {
		"id": 0,
		"pos": Vector2(240, 340),
		"home": Vector2(240, 340),
		"hunger": 0.1,
		"thirst": 0.1,
		"history": "ordinary",
		"traits": {"piety": 0.45, "generosity": 0.3, "grievance": 0.2}
	}
	patches[0].merge(person_zero, true)
	return {"people": patches}


func _test_rejection_and_space() -> void:
	var sim = Simulation.new()
	var before = sim.digest()
	for command in [
		["lightning", Vector2(240, 340)],
		["rain", Vector2(-1, 200)],
		["food", Vector2(1001, 340)],
		["rain", Vector2(NAN, 20)]
	]:
		var rejected = sim.cast(command[0], command[1])
		_check(not rejected.ok and rejected.event_id == -1, "Invalid cast is rejected")
		_check(sim.digest() == before, "Rejected cast leaves all state, including RNG, unchanged")
	var far = sim.cast("rain", Vector2(20, 20))
	_check(
		far.ok and sim.events[0].witnesses.is_empty(), "Unwitnessed rain is a valid spatial choice"
	)
	_check(
		sim.villages[0].water == 64 and sim.villages[1].water == 64,
		"Rain outside catchment does not add remote water"
	)
	_check(
		sim.people.all(func(person): return person.memories.is_empty()),
		"Unwitnessed event changes no minds"
	)
	_check(
		sim.power == 6 and sim.command_log.size() == 1,
		"Accepted rain costs two and records one command"
	)
	sim.cast("rain", Vector2(240, 340))
	sim.cast("rain", Vector2(760, 340))
	sim.cast("rain", Vector2(500, 100))
	before = sim.digest()
	_check(not sim.cast("food", Vector2(240, 340)).ok, "An exhausted power budget rejects casting")
	_check(sim.digest() == before, "Out-of-power rejection has no side effects")
	var central = Simulation.new()
	var edge = Simulation.new()
	central.cast("rain", Vector2(240, 340))
	edge.cast("rain", Vector2(390, 340))
	_check(
		central.villages[0].water > edge.villages[0].water, "Rain strength depends on cast distance"
	)
	_check(edge.villages[1].water == 64, "Rain never waters the distant village")


func _test_information_and_trust() -> void:
	var config = _isolated_config(
		{"pos": Vector2(380, 340), "home": Vector2(380, 340), "history": "ordinary"}
	)
	config.people[1] = {
		"id": 1,
		"pos": Vector2(449, 340),
		"home": Vector2(449, 340),
		"hunger": 0.1,
		"thirst": 0.1,
		"trust": {0: 1.0},
		"history": "ordinary"
	}
	var trusted = Simulation.new(2401, config)
	trusted.cast("rain", Vector2(240, 340))
	_check(trusted.events[0].witnesses == [0], "Only the person inside the radius witnesses rain")
	_check(
		trusted.people[0].memories[0].source == "witness", "Direct observation is marked witness"
	)
	_check(
		trusted.people[1].memories.is_empty(),
		"Nearby non-witness does not receive global knowledge"
	)
	_advance(trusted, 5)
	_check(trusted.people[1].memories.is_empty(), "A trusted report still takes at least six ticks")
	_advance(trusted, 12)
	var learned = not trusted.people[1].memories.is_empty()
	_check(learned, "Trusted contact eventually receives a report")
	if learned:
		var memory = trusted.people[1].memories[0]
		_check(
			memory.source == "report" and memory.via == 0 and memory.chain == [0],
			"Reports preserve sender and attribution chain"
		)
		_check(
			memory.confidence < 1.0 and memory.tick >= 6,
			"Reported information has reduced confidence and delayed learning time"
		)
		_check(
			memory.pos == Vector2(240, 340),
			"Reported position comes from the witness's remembered fact"
		)
	var distrust_config = config.duplicate(true)
	distrust_config.people[1].trust = {0: 0.05}
	var distrust = Simulation.new(2401, distrust_config)
	distrust.cast("rain", Vector2(240, 340))
	_advance(distrust, 17)
	_check(
		distrust.people[1].memories.is_empty(),
		"Otherwise identical distrusted contact cannot transmit the story"
	)
	var cautious_config = config.duplicate(true)
	cautious_config.people[1].trust = {0: 0.5}
	var cautious = Simulation.new(2401, cautious_config)
	cautious.cast("rain", Vector2(240, 340))
	_advance(cautious, 14)
	_check(
		cautious.people[1].memories.is_empty(),
		"Moderate trust adds delay beyond the high-trust contact"
	)
	cautious.step()
	_check(
		cautious.people[1].memories.size() == 1 and cautious.people[1].memories[0].tick == 15,
		"Moderate-trust report arrives at the computed fifteen-tick delay"
	)
	var chain_config = config.duplicate(true)
	chain_config.people[2] = {
		"id": 2,
		"pos": Vector2(520, 340),
		"home": Vector2(520, 340),
		"hunger": 0.1,
		"thirst": 0.1,
		"trust": {0: 0.0, 1: 1.0}
	}
	var chain_run = Simulation.new(2401, chain_config)
	chain_run.cast("rain", Vector2(240, 340))
	_advance(chain_run, 13)
	var third_learned = not chain_run.people[2].memories.is_empty()
	_check(third_learned, "A second-hand contact can learn from an actual reporter")
	if third_learned:
		var memory = chain_run.people[2].memories[0]
		_check(
			memory.chain == [0, 1] and memory.via == 1 and memory.source == "report",
			"Two-hop reporting retains the whole witness-to-reporter attribution"
		)
		_check(
			memory.confidence < chain_run.people[1].memories[0].confidence and memory.tick >= 12,
			"Every additional report hop costs confidence and time"
		)
	var distant_config = config.duplicate(true)
	distant_config.people[1].pos = Vector2(800, 100)
	var distant = Simulation.new(2401, distant_config)
	distant.cast("rain", Vector2(240, 340))
	_advance(distant, 17)
	_check(
		distant.people[1].memories.is_empty(), "Trust without proximity cannot transmit a report"
	)
	var initial_confidence = trusted.people[0].conviction
	_advance(trusted, 120)
	_check(
		(
			trusted.people[0].memories.size() == 1
			and trusted.people[0].conviction == initial_confidence
		),
		"Returning reports never amplify the witness's evidence"
	)
	_check(
		trusted.people.all(func(person): return person.memories.size() <= 1),
		"One event remains one memory across the contact network"
	)
	evidence.information = {
		"direct_witnesses": trusted.events[0].witnesses,
		"trusted_receiver_learned": learned,
		"distrusted_receiver_memories_at_17": distrust.people[1].memories.size(),
		"distant_receiver_memories_at_17": distant.people[1].memories.size()
	}


func _test_interpretation_and_behavior() -> void:
	var low_need = Simulation.new(
		2401,
		_isolated_config(
			{"thirst": 0.02, "traits": {"piety": 0.55, "generosity": 0.3, "grievance": 0.1}}
		)
	)
	var high_need = Simulation.new(
		2401,
		_isolated_config(
			{"thirst": 0.9, "traits": {"piety": 0.55, "generosity": 0.3, "grievance": 0.1}}
		)
	)
	low_need.cast("rain", Vector2(240, 340))
	high_need.cast("rain", Vector2(240, 340))
	_check(
		low_need.people[0].belief == "ritual" and high_need.people[0].belief == "care",
		"Changing thirst alone changes the interpretation of the identical witnessed rain"
	)
	var help = Simulation.new(2401, _isolated_config({"history": "helped"}))
	var shrine = Simulation.new(2401, _isolated_config({"history": "shrine"}))
	var excluded = Simulation.new(2401, _isolated_config({"history": "excluded"}))
	var control = Simulation.new(2401, _isolated_config({"history": "shrine"}))
	for sim in [help, shrine, excluded]:
		sim.cast("rain", Vector2(240, 340))
		sim.step()
	control.step()
	_check(
		(
			help.people[0].belief == "care"
			and shrine.people[0].belief == "ritual"
			and excluded.people[0].belief == "favoritism"
		),
		"Changing history alone yields three interpretations of the same event"
	)
	_check(
		help.people[0].action == "share" and help.people[0].carried_food == 6,
		"Care memory withdraws actual food for a neighbor shipment"
	)
	_check(
		shrine.people[0].action == "ritual" and shrine.people[0].target == Simulation.SHRINE,
		"Ritual memory sends the person to the shrine instead of the crop"
	)
	_check(
		excluded.people[0].action == "avoid" and excluded.people[0].private_food == 3,
		"Favoritism memory causes avoidance and actual private hoarding"
	)
	_check(
		is_equal_approx(shrine.villages[0].food - help.villages[0].food, 5.0),
		"History-driven choices change public supplies by measured amounts"
	)
	_check(
		control.people[0].belief == "uncertain" and control.people[0].action == "work",
		"Shrine history without a memory does not cause a ritual"
	)
	for sim in [help, shrine, excluded]:
		_check(
			sim.action_log[0].event_id == 0 and not sim.action_log[0].cause.is_empty(),
			"Belief-driven action retains its causal memory link"
		)
	_advance(help, 270)
	_advance(shrine, 270)
	_advance(excluded, 270)
	_check(
		help.metrics.shared_food >= 6 and help.metrics.shares >= 1,
		"Care produces completed deliveries, not just action labels"
	)
	_check(
		shrine.metrics.rituals >= 1 and shrine.metrics.offerings >= 1,
		"Rituals require arrival and consume time and offerings"
	)
	_check(
		excluded.metrics.avoidance > 0 and excluded.people[0].pos.x < 240,
		"Avoidance moves the person away from the crossing"
	)
	var mixed = Simulation.new()
	mixed.cast("rain", Vector2(240, 340))
	var local_beliefs = {}
	for person in mixed.people:
		if person.village == 0:
			local_beliefs[person.belief] = true
	_check(
		local_beliefs.size() >= 2,
		"One village contains competing interpretations, not one village-wide belief"
	)
	evidence.causal_controls = {
		"needs_only": [low_need.people[0].belief, high_need.people[0].belief],
		"helped_history": help.summary().metrics,
		"shrine_history": shrine.summary().metrics,
		"excluded_history": excluded.summary().metrics
	}


func _test_finite_resources() -> void:
	var sim = Simulation.new(2401, _isolated_config())
	var initial_food = sim.villages[0].food
	sim.cast("food", Vector2(30, 500))
	_check(
		sim.villages[0].food == initial_food and sim.caches[0].food == 38,
		"Food appears as a finite spatial cache, not instant village stock"
	)
	_check(
		sim.events[0].village == -1,
		"An outlying food cache does not imply favoritism toward the nearest village"
	)
	_check(sim.people[0].memories.is_empty(), "An unseen food cache grants no event knowledge")
	var empty_store_config = _isolated_config(
		{"history": "ordinary", "traits": {"piety": 0.0, "generosity": 0.0, "grievance": 0.0}}
	)
	empty_store_config.villages = [{"id": 0, "food": 0, "water": 0, "crop": 0}]
	var fetched = Simulation.new(2401, empty_store_config)
	fetched.cast("food", Vector2(240, 340))
	_advance(fetched, 2)
	_check(
		fetched.people[0].carried_food == 7 and fetched.villages[0].food == 0,
		"A person physically picks up seven food before the village receives it"
	)
	_check(
		is_equal_approx(fetched.caches[0].food, 38.0 - 7.0 - 0.018),
		"Fetching removes exactly the carried food, apart from measured spoilage"
	)
	fetched.step()
	_check(
		fetched.people[0].carried_food == 0 and fetched.villages[0].food == 7,
		"Arrival transfers the same seven food into the common store"
	)
	var local = Simulation.new(
		2401,
		_isolated_config(
			{"history": "ordinary", "traits": {"piety": 0.9, "generosity": 0.0, "grievance": 0.0}}
		)
	)
	local.cast("food", Vector2(240, 340))
	_advance(local, 300)
	_check(local.caches[0].food < 38, "Food caches lose real supplies to fetching or spoilage")
	var dry = Simulation.new(
		2401,
		{
			"villages":
			[
				{"id": 0, "food": 0, "water": 0, "crop": 0},
				{"id": 1, "food": 0, "water": 0, "crop": 0}
			],
			"well_water": 0
		}
	)
	_advance(dry, Simulation.END_TICK)
	_check(
		dry.summary().metrics.mean_hunger > 0.95 and dry.summary().metrics.mean_thirst > 0.95,
		"Empty fields, stores, and well cannot generate sustenance from routines"
	)
	_check(
		dry.metrics.well_drawn == 0 and dry.metrics.harvested == 0,
		"A dry well and empty dry crop remain materially empty"
	)


func _test_cache_information_boundaries() -> void:
	var unseen = Simulation.new(2401, _isolated_config())
	var cache_pos = Vector2(30, 500)
	unseen.cast("food", cache_pos)
	var stays_uninformed = true
	for index in range(30):
		unseen.step()
		var person = unseen.people[0]
		stays_uninformed = stays_uninformed and person.memories.is_empty()
		stays_uninformed = stays_uninformed and person.pos.distance_to(cache_pos) > 105
		stays_uninformed = (
			stays_uninformed and person.goal != "cache" and person.target != cache_pos
		)
	_check(
		stays_uninformed,
		"Uninformed person never targets an out-of-sight cache during thirty routine ticks"
	)

	# Six collectors empty the cache before a remote person can hear about it.
	# Only starting geometry, needs, histories, stores, and trust are controlled.
	var config = _isolated_config({"pos": Vector2(380, 340), "home": Vector2(380, 340)})
	config.villages = [{"id": 0, "food": 0, "water": 0, "crop": 0}]
	var receiver_trust = {}
	for id in range(24):
		receiver_trust[id] = 1.0 if id == 0 else 0.0
	config.people[1] = {
		"id": 1,
		"pos": Vector2(449, 340),
		"home": Vector2(449, 340),
		"hunger": 0.1,
		"thirst": 0.1,
		"history": "ordinary",
		"trust": receiver_trust,
		"traits": {"piety": 0.0, "generosity": 0.0, "grievance": 0.0}
	}
	for id in range(2, 8):
		config.people[id] = {
			"id": id,
			"pos": Vector2(240, 340),
			"hunger": 0.1,
			"thirst": 0.1,
			"history": "ordinary",
			"traits": {"piety": 0.0, "generosity": 0.0, "grievance": 0.0}
		}
	var remembered = Simulation.new(2401, config)
	remembered.cast("food", Vector2(240, 340))
	_advance(remembered, 2)
	var collected = 0.0
	for id in range(2, 8):
		collected += remembered.people[id].carried_food
	_check(
		remembered.caches[0].food == 0 and is_equal_approx(collected, 38.0 - 0.018),
		"Other people physically empty the cache before the remote receiver learns about it"
	)
	_check(
		remembered.people[1].memories.is_empty(),
		"Remote receiver is still uninformed at cache depletion"
	)
	_advance(remembered, 4)
	var receiver = remembered.people[1]
	_check(
		(
			receiver.memories.size() == 1
			and receiver.memories[0].source == "report"
			and receiver.memories[0].via == 0
		),
		"Remote cache destination is learned through the configured witness, not global state"
	)
	_check(
		(
			receiver.pos.distance_to(Vector2(240, 340)) > 105
			and receiver.goal == "cache"
			and receiver.target == Vector2(240, 340)
		),
		"A remembered cache is selected despite remote depletion that the traveler cannot see"
	)
	_advance(remembered, 8)
	_check(
		(
			receiver.pos.distance_to(Vector2(240, 340)) > 105
			and receiver.goal == "cache"
			and receiver.depleted_caches.is_empty()
		),
		"Remote depletion does not cancel the ongoing cache journey or inject depletion knowledge"
	)
	_advance(remembered, 120)
	_check(
		0 in receiver.depleted_caches and receiver.goal != "cache",
		"The traveler marks the cache depleted after actually reaching it and stops targeting it"
	)
	evidence.cache_information = {
		"uninformed_ticks_checked": 30,
		"collected_before_report": collected,
		"reported_at": receiver.memories[0].tick if not receiver.memories.is_empty() else -1,
		"depletion_discovered_by_visit": 0 in receiver.depleted_caches
	}


func _test_competing_evidence() -> void:
	# A direct rain observation supports care. Two food reports support ritual.
	# The two senders are nearby; the recipient cannot see either food event.
	var config = _isolated_config(
		{
			"thirst": 0.8,
			"history": "ordinary",
			"traits": {"piety": 0.55, "generosity": 0.3, "grievance": 0.1},
			"trust": {1: 1.0, 2: 1.0}
		}
	)
	config.villages = [{"id": 0, "food": 10, "crop": 0}]
	for id in [1, 2]:
		config.people[id] = {
			"id": id,
			"pos": Vector2(260, 300),
			"home": Vector2(260, 300),
			"hunger": 0.1,
			"thirst": 0.1,
			"history": "shrine",
			"traits": {"piety": 0.9, "generosity": 0.0, "grievance": 0.0}
		}
	var cautious_config = config.duplicate(true)
	cautious_config.people[0].trust = {1: 0.5, 2: 0.5}
	var trusted = Simulation.new(2401, config)
	var cautious = Simulation.new(2401, cautious_config)
	for sim in [trusted, cautious]:
		sim.cast("rain", Vector2(240, 340))
		sim.cast("food", Vector2(260, 155))
		sim.cast("food", Vector2(260, 155))
		_check(
			sim.people[0].memories.size() == 1 and sim.people[0].belief == "care",
			"Competing-evidence recipient begins with only a directly observed care memory"
		)
		_advance(sim, 15)
	var high = trusted.people[0]
	var low = cautious.people[0]
	var both_received = high.memories.size() == 3 and low.memories.size() == 3
	_check(
		both_received, "Both trust conditions receive all three unique pieces of competing evidence"
	)
	if both_received:
		var matching_facts = true
		for index in range(3):
			var a = high.memories[index]
			var b = low.memories[index]
			matching_facts = (
				matching_facts and a.event_id == b.event_id and a.interpretation == b.interpretation
			)
			matching_facts = (
				matching_facts and a.source == b.source and a.via == b.via and a.pos == b.pos
			)
		_check(
			(
				matching_facts
				and high.memories[1].interpretation == "ritual"
				and high.memories[2].interpretation == "ritual"
			),
			"Trust controls hold remembered facts, sources, and competing interpretations fixed"
		)
		_check(
			(
				is_equal_approx(high.memories[1].confidence + high.memories[2].confidence, 1.84)
				and is_equal_approx(low.memories[1].confidence + low.memories[2].confidence, 0.92)
			),
			"Paired report trust changes ritual evidence from 1.84 to 0.92 against one direct care vote"
		)
	_check(
		high.belief == "ritual" and low.belief == "care",
		"Confidence weighting, rather than counting two reports, determines the dominant belief"
	)
	_check(
		(
			is_equal_approx(high.conviction, 1.84 / 3.14)
			and is_equal_approx(low.conviction, 1.0 / 2.22)
		),
		"Conviction reflects the exact confidence-weighted competing evidence"
	)
	# Both reporters already made one offering each. Only the high-trust
	# recipient adds a third offering after receiving the competing evidence.
	_check(
		(
			high.action == "ritual"
			and high.target == Simulation.SHRINE
			and trusted.metrics.offerings == 3
		),
		"High-confidence reports trigger the next shrine trip and an additional real offering"
	)
	_check(
		low.action == "fetch" and low.goal == "cache" and cautious.metrics.offerings == 2,
		"Lower-confidence reports leave care dominant: fetch food without adding an offering"
	)
	evidence.competing_confidence = {
		"high_trust_belief": high.belief,
		"low_trust_belief": low.belief,
		"high_trust_conviction": high.conviction,
		"low_trust_conviction": low.conviction,
		"high_trust_action": high.action,
		"low_trust_action": low.action,
		"high_trust_memories": high.memories.size(),
		"low_trust_memories": low.memories.size(),
		"high_trust_total_offerings": trusted.metrics.offerings,
		"low_trust_total_offerings": cautious.metrics.offerings
	}


func _replay_commands(seed: int, commands: Array):
	var replay = Simulation.new(seed)
	var command_index = 0
	while not replay.ended:
		while command_index < commands.size() and commands[command_index].tick == replay.tick:
			var command = commands[command_index]
			replay.cast(command.kind, command.pos)
			command_index += 1
		replay.step()
	return replay


func _run_mixed_schedule():
	var sim = Simulation.new(5709)
	while not sim.ended:
		match sim.tick:
			0:
				sim.cast("rain", Vector2(240, 340))
				sim.cast("food", Vector2(240, 340))
			80:
				sim.cast("food", Vector2(760, 340))
				sim.cast("rain", Vector2(760, 340))
			200:
				sim.cast("food", Simulation.SHRINE)
				sim.cast("food", Vector2(160, 340))
		sim.step()
	return sim


func _test_mixed_command_replay() -> void:
	var first = _run_mixed_schedule()
	var second = _run_mixed_schedule()
	_check(
		first.power == 0 and first.command_log.size() == 6 and first.caches.size() == 4,
		"Mixed schedule accepts six commands and spends eight power on two rain and four food casts"
	)
	var expected = [
		[0, "rain"], [0, "food"], [80, "food"], [80, "rain"], [200, "food"], [200, "food"]
	]
	var ordered = first.command_log.size() == expected.size()
	for index in range(mini(first.command_log.size(), expected.size())):
		ordered = ordered and first.command_log[index].tick == expected[index][0]
		ordered = ordered and first.command_log[index].kind == expected[index][1]
	ordered = ordered and first.command_log.size() == 6
	if ordered:
		ordered = (
			first.command_log[4].pos == Simulation.SHRINE
			and first.command_log[5].pos == Vector2(160, 340)
		)
	_check(
		ordered,
		"Command log preserves insertion order for same-tick pairs, including two food positions"
	)
	_check(
		first.digest() == second.digest(),
		"Independent mixed seeded schedules reproduce food, rain, and cache state exactly"
	)
	var replay = _replay_commands(first.seed_value, first.command_log)
	_check(
		replay.digest() == first.digest(),
		"Ordered same-tick mixed command replay reproduces the complete final digest"
	)
	var reversed_pair = first.command_log.duplicate(true)
	if reversed_pair.size() >= 2:
		var first_command = reversed_pair[0]
		reversed_pair[0] = reversed_pair[1]
		reversed_pair[1] = first_command
	var reordered = _replay_commands(first.seed_value, reversed_pair)
	_check(
		(
			reordered.digest() != first.digest()
			and not reordered.events.is_empty()
			and reordered.events[0].kind == "food"
		),
		"Reversing a same-tick pair is detectable in event identity and the complete state"
	)
	evidence.mixed_replay = {
		"seed": first.seed_value,
		"digest": first.digest(),
		"commands": first.command_log.size(),
		"caches": first.caches.size(),
		"same_tick_pairs": 3,
		"replay_matches": replay.digest() == first.digest(),
		"reversed_pair_differs": reordered.digest() != first.digest(),
		"metrics": first.summary().metrics
	}


func _run_strategy(strategy: String):
	var sim = Simulation.new(2401)
	while not sim.ended:
		# Four rain commands spend the entire same eight-power budget.
		if strategy != "none" and sim.tick in [40, 120, 240, 320]:
			var village_id = 0
			if strategy == "balanced" and sim.tick in [120, 320]:
				village_id = 1
			sim.cast("rain", sim.villages[village_id].pos)
		sim.step()
	return sim


func _test_replays_and_contrasts() -> void:
	var runs = {}
	for strategy in ["none", "balanced", "one_sided"]:
		var first = _run_strategy(strategy)
		var second = _run_strategy(strategy)
		_check(
			first.digest() == second.digest(),
			"%s independently repeated seeded run has identical complete-state digest" % strategy
		)
		_check(
			first.tick == Simulation.END_TICK and first.ended,
			"%s has a bounded seventh-evening ending" % strategy
		)
		_check(
			first.metrics.well_drawn <= 160.000001 and first.well_water >= 0,
			"%s never draws more than the finite shared well" % strategy
		)
		var valid = true
		for village in first.villages:
			valid = (
				valid
				and village.food >= 0
				and village.food <= 100
				and village.water >= 0
				and village.water <= 100
				and village.crop >= 0
				and village.crop <= 100
			)
		for person in first.people:
			valid = (
				valid
				and person.hunger >= 0
				and person.hunger <= 1
				and person.thirst >= 0
				and person.thirst <= 1
			)
			var ids = {}
			for memory in person.memories:
				valid = valid and not ids.has(memory.event_id)
				ids[memory.event_id] = true
				valid = valid and memory.confidence > 0 and memory.confidence <= 1
		_check(valid, "%s keeps resource, need, confidence, and unique-evidence bounds" % strategy)
		var causal_links_valid = true
		for entry in first.action_log:
			if entry.action in ["share", "ritual", "avoid", "tell"]:
				causal_links_valid = causal_links_valid and entry.event_id >= 0
			if entry.event_id < 0:
				continue
			var known_in_time = false
			for memory in first.people[entry.person].memories:
				if memory.event_id == entry.event_id and memory.tick <= entry.tick:
					known_in_time = true
			causal_links_valid = causal_links_valid and known_in_time
		_check(
			causal_links_valid,
			"%s every memory-linked action follows its actor's actual learning time" % strategy
		)
		var digest = first.digest()
		first.step()
		_check(
			not first.cast("food", Vector2(240, 340)).ok and first.digest() == digest,
			"%s ended state cannot advance or accept commands" % strategy
		)
		# Replay the recorded successful commands on a clean instance, in order.
		var replay = _replay_commands(first.seed_value, first.command_log)
		_check(
			replay.digest() == digest,
			"%s successful command log reproduces the entire state" % strategy
		)
		runs[strategy] = first
		evidence[strategy] = {
			"digest": digest,
			"metrics": first.summary().metrics,
			"events": first.events.size(),
			"commands": first.command_log.size(),
			"power_left": first.power,
			"action_log_entries": first.action_log.size()
		}
	var none = runs.none.summary().metrics
	var balanced = runs.balanced.summary().metrics
	var one = runs.one_sided.summary().metrics
	_check(
		none.shares == 0 and none.rituals == 0 and none.reports == 0 and none.avoidance == 0,
		"No intervention has routines but no miracle-derived behaviors"
	)
	_check(
		runs.none.action_log.size() > 0 and none.harvested > 0 and none.well_drawn > 0,
		"No intervention still has work, fetching, consumption, and drought"
	)
	_check(
		balanced.mean_thirst < none.mean_thirst,
		"Balanced rain measurably lowers thirst versus no intervention"
	)
	_check(
		(
			balanced.rituals > 0
			and balanced.shares > 0
			and balanced.reports > 0
			and balanced.avoidance > 0
		),
		"Balanced help generates actual ritual, sharing, reporting, and avoidance"
	)
	var balanced_gap = absf(balanced.villages[0].mean_thirst - balanced.villages[1].mean_thirst)
	var one_gap = absf(one.villages[0].mean_thirst - one.villages[1].mean_thirst)
	_check(
		one_gap > balanced_gap + 0.05,
		"One-sided rain causes a larger measured inter-village thirst gap"
	)
	_check(
		(
			runs.none.digest() != runs.balanced.digest()
			and runs.balanced.digest() != runs.one_sided.digest()
		),
		"Three strategies have distinct material and social state, not dialogue-only outcomes"
	)
	evidence.contrasts = {
		"balanced_thirst_gap": balanced_gap,
		"one_sided_thirst_gap": one_gap,
		"balanced_thirst_reduction": none.mean_thirst - balanced.mean_thirst
	}
