extends RefCounted
## Deterministic drought model. Only step() and accepted cast() mutate play state.
## Constructor scenario controls are documented in sim/README.md.

const DAY_TICKS = 80
const END_TICK = 560
const WORLD_SIZE = Vector2(1000, 640)
const SHRINE = Vector2(500, 280)
const WELL = Vector2(500, 405)
const RADIUS = 150.0
const REPORT_RADIUS = 74.0

var seed_value: int
var tick: int = 0
var ended: bool = false
var power: int = 8
var people: Array[Dictionary] = []
var villages: Array[Dictionary] = []
var events: Array[Dictionary] = []
var action_log: Array[Dictionary] = []
var command_log: Array[Dictionary] = []
var caches: Array[Dictionary] = []
var well_water: float = 160.0
var metrics: Dictionary = {
	"shares": 0,
	"rituals": 0,
	"reports": 0,
	"avoidance": 0,
	"shared_food": 0.0,
	"offerings": 0.0,
	"harvested": 0.0,
	"well_drawn": 0.0
}
var _rng = RandomNumberGenerator.new()


func _init(initial_seed: int = 2401, config: Dictionary = {}) -> void:
	seed_value = initial_seed
	_rng.seed = seed_value
	villages.append(
		{
			"id": 0,
			"name": "Alder",
			"pos": Vector2(240, 340),
			"food": 58.0,
			"water": 64.0,
			"crop": 76.0
		}
	)
	villages.append(
		{
			"id": 1,
			"name": "Sedge",
			"pos": Vector2(760, 340),
			"food": 58.0,
			"water": 64.0,
			"crop": 76.0
		}
	)
	var names = [
		"Ada",
		"Bram",
		"Cora",
		"Davi",
		"Ena",
		"Finn",
		"Greta",
		"Hale",
		"Iona",
		"Jori",
		"Kira",
		"Luan",
		"Mara",
		"Neri",
		"Oren",
		"Pia",
		"Quin",
		"Rhea",
		"Sami",
		"Tavi",
		"Una",
		"Venn",
		"Wren",
		"Yara"
	]
	for id in range(24):
		var village_id = id / 12
		var angle = TAU * float(id % 12) / 12.0
		var home = villages[village_id].pos + Vector2.from_angle(angle) * _rng.randf_range(28, 76)
		var trust = {}
		for other in range(24):
			trust[other] = (
				_rng.randf_range(0.66, 0.94)
				if other / 12 == village_id
				else _rng.randf_range(0.34, 0.64)
			)
		people.append(
			{
				"id": id,
				"name": names[id],
				"village": village_id,
				"pos": home,
				"home": home,
				"hunger": _rng.randf_range(0.18, 0.38),
				"thirst": _rng.randf_range(0.18, 0.36),
				"belief": "uncertain",
				"conviction": 0.0,
				"action": "work",
				"target": home,
				"memories": [],
				"cause": "The drought continues. I must bring in the remaining crop.",
				"trust": trust,
				"traits":
				{
					"generosity": _rng.randf_range(0.2, 0.8),
					"piety": _rng.randf_range(0.2, 0.8),
					"grievance": _rng.randf_range(0.1, 0.7)
				},
				"history": ["helped", "shrine", "excluded", "ordinary"][id % 4],
				"carried_food": 0.0,
				"carried_water": 0.0,
				"private_food": 0.0,
				"goal": "idle",
				"event_id": -1,
				"next_decision": 0,
				"next_belief_action": 0,
				"next_report": 0,
				"next_well": 0,
				"depleted_caches": [],
				"cache_id": -1
			}
		)
	# These are starting conditions, not alternate simulation rules.
	for patch in config.get("villages", []):
		var village = villages[int(patch.id)]
		for field in ["food", "water", "crop"]:
			if patch.has(field):
				village[field] = clampf(float(patch[field]), 0.0, 100.0)
	for patch in config.get("people", []):
		var person = people[int(patch.id)]
		for field in ["pos", "home", "history"]:
			if patch.has(field):
				person[field] = patch[field]
		for field in ["hunger", "thirst"]:
			if patch.has(field):
				person[field] = clampf(float(patch[field]), 0.0, 1.0)
		for field in ["traits", "trust"]:
			for key in patch.get(field, {}):
				person[field][key] = clampf(float(patch[field][key]), 0.0, 1.0)
		person.target = person.pos
	well_water = clampf(float(config.get("well_water", well_water)), 0.0, 300.0)


func cast(kind: String, pos: Vector2) -> Dictionary:
	if ended:
		return _rejected("The seven-day drought has ended.")
	if kind != "rain" and kind != "food":
		return _rejected("Choose rain or food.")
	if (
		not pos.is_finite()
		or pos.x < 0
		or pos.y < 0
		or pos.x > WORLD_SIZE.x
		or pos.y > WORLD_SIZE.y
	):
		return _rejected("Choose a place inside the valley.")
	var cost = 2 if kind == "rain" else 1
	if power < cost:
		return _rejected("There is not enough power. Power does not renew.")
	var beneficiary = -1
	var nearest_distance = INF
	for village in villages:
		var distance = pos.distance_to(village.pos)
		if distance < nearest_distance:
			nearest_distance = distance
			beneficiary = village.id
	if nearest_distance > RADIUS:
		beneficiary = -1  # An outlying cache belongs to neither village.
	power -= cost
	var event_id = events.size()
	var witnesses: Array[int] = []
	for person in people:
		if person.pos.distance_to(pos) <= RADIUS:
			witnesses.append(person.id)
	var event = {
		"id": event_id,
		"tick": tick,
		"kind": kind,
		"pos": pos,
		"village": beneficiary,
		"witnesses": witnesses
	}
	events.append(event)
	command_log.append({"tick": tick, "kind": kind, "pos": pos})
	if kind == "rain":
		for village in villages:
			var distance = village.pos.distance_to(pos)
			if distance <= RADIUS:
				var strength = 1.0 - 0.65 * distance / RADIUS
				village.water = minf(100.0, village.water + 64.0 * strength)
				village.crop = minf(100.0, village.crop + 20.0 * strength)
	else:
		caches.append({"event_id": event_id, "pos": pos, "food": 38.0, "village": beneficiary})
	var fact = {"event_id": event_id, "kind": kind, "pos": pos, "village": beneficiary}
	for id in witnesses:
		_learn(people[id], fact, "witness", -1, [], 1.0)
	return {
		"ok": true,
		"reason": "Rain fell." if kind == "rain" else "A food cache appeared.",
		"event_id": event_id
	}


func _rejected(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "event_id": -1}


func step() -> void:
	if ended:
		return
	tick += 1
	for village in villages:
		village.water = maxf(0.0, village.water - 0.045)
		village.food = maxf(0.0, village.food - 0.006)
		if village.water > 5:
			village.crop = minf(100.0, village.crop + 0.045 * village.water / 100.0)
		else:
			village.crop = maxf(0.0, village.crop - 0.018)
	for cache in caches:
		cache.food = maxf(0.0, cache.food - 0.009)
	for person in people:
		_needs(person)
		var speed = 2.6 * (1.0 - 0.48 * maxf(person.hunger, person.thirst))
		person.pos = person.pos.move_toward(person.target, speed)
		_arrival(person)
	_spread_reports()
	for person in people:
		if person.goal == "idle" and tick >= person.next_decision:
			_decide(person)
	if tick >= END_TICK:
		ended = true


func _needs(person: Dictionary) -> void:
	person.hunger = minf(1.0, person.hunger + 0.0019)
	person.thirst = minf(1.0, person.thirst + 0.0027)
	if person.private_food > 0 and person.hunger > 0.22:
		var eaten = minf(person.private_food, 0.08)
		person.private_food -= eaten
		person.hunger = maxf(0.0, person.hunger - eaten * 0.06)
	# Anyone physically present may eat and drink. A report cannot feed somebody.
	for village in villages:
		if person.pos.distance_to(village.pos) > 82:
			continue
		if person.hunger > 0.10:
			var eaten = minf(village.food, 0.08)
			village.food -= eaten
			person.hunger = maxf(0.0, person.hunger - eaten * 0.06)
		if person.thirst > 0.10:
			var drunk = minf(village.water, 0.11)
			village.water -= drunk
			person.thirst = maxf(0.0, person.thirst - drunk * 0.07)


func _arrival(person: Dictionary) -> void:
	if person.pos.distance_to(person.target) > 4.0:
		return
	var village = villages[person.village]
	match person.goal:
		"work":
			var harvest = minf(village.crop, 0.085 * (1.0 - person.thirst * 0.65))
			village.crop -= harvest
			village.food = minf(100.0, village.food + harvest)
			metrics.harvested += harvest
			if tick >= person.next_decision:
				person.goal = "idle"
		"cache":
			var cache = caches[person.cache_id]
			person.carried_food += minf(cache.food, 7.0)
			cache.food -= minf(cache.food, 7.0)
			if cache.food < 0.1:
				person.depleted_caches.append(cache.event_id)
			if person.carried_food > 0:
				_assign(
					person,
					"fetch",
					"deliver",
					village.pos,
					person.event_id,
					"I found food at the cache. I am carrying it to our common store."
				)
			else:
				person.goal = "idle"
		"well":
			person.carried_water = minf(well_water, 6.0)
			well_water -= person.carried_water
			metrics.well_drawn += person.carried_water
			person.next_well = tick + 100
			_assign(
				person,
				"fetch",
				"deliver",
				village.pos,
				-1,
				(
					"The shared well gave me water."
					if person.carried_water > 0
					else "The shared well is dry. I must return."
				)
			)
		"deliver":
			village.food = minf(100.0, village.food + person.carried_food)
			village.water = minf(100.0, village.water + person.carried_water)
			person.carried_food = 0.0
			person.carried_water = 0.0
			person.goal = "idle"
		"share":
			var recipient = villages[1 - person.village]
			var transferred = minf(person.carried_food, 100.0 - recipient.food)
			recipient.food += transferred
			person.carried_food -= transferred
			if transferred > 0:
				metrics.shares += 1
				metrics.shared_food += transferred
				_log(
					person,
					"share",
					person.event_id,
					(
						"I delivered %.1f food to %s because I remember help."
						% [transferred, recipient.name]
					)
				)
			person.next_belief_action = tick + 90
			_assign(
				person,
				"work",
				"return",
				person.home,
				person.event_id,
				"The gift is delivered. I am going home."
			)
		"ritual":
			metrics.rituals += 1
			person.next_decision = tick + 24
			person.goal = "ritual_wait"
			person.next_belief_action = tick + 110
			_log(
				person,
				"ritual",
				person.event_id,
				"I reached the shrine to honor the sign. The fields must wait."
			)
		"ritual_wait":
			if tick >= person.next_decision:
				_assign(
					person,
					"work",
					"return",
					person.home,
					person.event_id,
					"The ritual is over. I am returning to the fields."
				)
		"avoid":
			if tick >= person.next_decision:
				person.goal = "idle"
		"return":
			if person.carried_food > 0:
				village.food = minf(100.0, village.food + person.carried_food)
				person.carried_food = 0.0
			person.goal = "idle"
		"rest":
			if tick >= person.next_decision:
				person.goal = "idle"


func _decide(person: Dictionary) -> void:
	var village = villages[person.village]
	var memory = _strongest_memory(person)
	var event_id = int(memory.get("event_id", -1))
	if tick >= person.next_belief_action and not memory.is_empty():
		match person.belief:
			"care":
				if (
					village.food > 12
					and person.hunger < 0.72
					and person.pos.distance_to(village.pos) <= 85
				):
					person.carried_food += 6.0
					village.food -= 6.0
					_assign(
						person,
						"share",
						"share",
						villages[1 - person.village].pos,
						event_id,
						"%s So I will take six food to our neighbors." % memory.reason
					)
					return
			"ritual":
				if person.hunger < 0.85 and person.thirst < 0.82:
					if person.pos.distance_to(village.pos) <= 85:
						var offering = minf(1.0, village.food)
						village.food -= offering
						metrics.offerings += offering
					_assign(
						person,
						"ritual",
						"ritual",
						SHRINE,
						event_id,
						"%s So I will visit the shrine instead of working." % memory.reason
					)
					return
			"favoritism":
				var held = 0.0
				if person.pos.distance_to(village.pos) <= 85:
					held = minf(3.0, village.food)
					village.food -= held
					person.private_food += held
				person.next_belief_action = tick + 90
				person.next_decision = tick + 42
				metrics.avoidance += 1
				var away = village.pos + Vector2(-100 if person.village == 0 else 100, 15)
				_assign(
					person,
					"avoid",
					"avoid",
					away,
					event_id,
					(
						"%s So I will avoid the crossing and keep %.1f food for myself."
						% [memory.reason, held]
					)
				)
				return
	# The routine knows only caches seen locally or described in a memory.
	var cache_choice = _known_cache(person)
	if cache_choice >= 0:
		var cache = caches[cache_choice]
		person.cache_id = cache_choice
		var known_event = cache.event_id if _has_memory(person, cache.event_id) else -1
		_assign(
			person,
			"fetch",
			"cache",
			cache.pos,
			known_event,
			(
				"I remember where food appeared."
				if known_event >= 0
				else "I can see a food cache nearby."
			)
		)
		return
	if tick >= person.next_well and (person.thirst > 0.32 or person.id % 6 == 0):
		# People see their own stores at home; they do not remotely inspect the well.
		if person.pos.distance_to(village.pos) <= 100 and village.water < 18:
			_assign(
				person, "fetch", "well", WELL, -1, "Our water is low. I will try the shared well."
			)
			return
	if person.hunger > 0.65 or person.thirst > 0.65:
		person.next_decision = tick + 22
		_assign(
			person,
			"rest",
			"rest",
			village.pos,
			-1,
			"I am exhausted. I will seek food and water at home."
		)
		return
	person.next_decision = tick + _rng.randi_range(24, 42)
	var field = village.pos + Vector2(_rng.randf_range(-36, 36), _rng.randf_range(-57, -27))
	_assign(
		person, "work", "work", field, -1, "The remaining crop must be gathered before it dries."
	)


func _known_cache(person: Dictionary) -> int:
	var chosen = -1
	var nearest = INF
	for index in range(caches.size()):
		var cache = caches[index]
		if cache.event_id in person.depleted_caches:
			continue
		var distance = person.pos.distance_to(cache.pos)
		var visible = distance <= 105
		if visible and cache.food < 0.1:
			person.depleted_caches.append(cache.event_id)
			continue
		if (visible or _has_memory(person, cache.event_id)) and distance < nearest:
			chosen = index
			nearest = distance
	return chosen


func _assign(
	person: Dictionary, action: String, goal: String, target: Vector2, event_id: int, cause: String
) -> void:
	var changed = person.action != action or person.event_id != event_id or person.cause != cause
	person.action = action
	person.goal = goal
	person.target = target
	person.event_id = event_id
	person.cause = cause
	if changed:
		_log(person, action, event_id, cause)


func _log(person: Dictionary, action: String, event_id: int, cause: String) -> void:
	action_log.append(
		{"tick": tick, "person": person.id, "action": action, "cause": cause, "event_id": event_id}
	)


func _has_memory(person: Dictionary, event_id: int) -> bool:
	for memory in person.memories:
		if memory.event_id == event_id:
			return true
	return false


func _interpret(person: Dictionary, fact: Dictionary) -> Dictionary:
	var need = person.thirst if fact.kind == "rain" else person.hunger
	var local = fact.village == person.village
	var care = 0.28 + need * 0.95 + person.traits.generosity * 0.35
	var ritual = 0.18 + person.traits.piety * 0.85 + (0.16 if fact.kind == "rain" else 0.0)
	var favoritism = 0.10 + person.traits.grievance * 0.65
	if person.history == "helped":
		care += 0.55
	elif person.history == "shrine":
		ritual += 0.55
	elif person.history == "excluded":
		favoritism += 0.65
	if not local and fact.village >= 0:
		favoritism += 0.60 + maxf(person.hunger, person.thirst) * 0.30
		care *= 0.60
	var interpretation = "care"
	var reason = (
		"I needed %s; this help means we should help others."
		% ("water" if fact.kind == "rain" else "food")
	)
	if person.history == "helped":
		reason = "I remember being helped in a lean year; this gift asks us to share."
	if ritual > care:
		interpretation = "ritual"
		reason = (
			"I was taught to honor signs at the shrine; this %s calls for a ritual." % fact.kind
		)
	if favoritism > maxf(care, ritual):
		interpretation = "favoritism"
		if not local and fact.village >= 0:
			reason = (
				"The help went to %s, not us; I fear being left without a share."
				% villages[fact.village].name
			)
		else:
			reason = "I remember exclusion from stores; I fear this gift will favor a few."
	return {"interpretation": interpretation, "reason": reason}


func _learn(
	person: Dictionary, fact: Dictionary, source: String, via: int, chain: Array, confidence: float
) -> void:
	if _has_memory(person, fact.event_id):
		return  # Hearing an echo never counts as another piece of evidence.
	var reading = _interpret(person, fact)
	var attribution: Array[int] = []
	attribution.assign(chain)
	var memory = {
		"event_id": fact.event_id,
		"tick": tick,
		"source": source,
		"via": via,
		"interpretation": reading.interpretation,
		"reason": reading.reason,
		"chain": attribution,
		"confidence": confidence,
		"kind": fact.kind,
		"pos": fact.pos,
		"village": fact.village
	}
	person.memories.append(memory)
	var votes = {"care": 0.0, "ritual": 0.0, "favoritism": 0.0}
	var total = 0.30
	for known in person.memories:
		votes[known.interpretation] += known.confidence
		total += known.confidence
	var strongest = "care"
	for belief in ["ritual", "favoritism"]:
		if votes[belief] > votes[strongest]:
			strongest = belief
	person.belief = strongest
	person.conviction = votes[strongest] / total
	if person.goal == "work" or person.goal == "rest" or person.goal == "idle":
		person.goal = "idle"
		person.next_decision = tick
		person.cause = (
			("I saw the sign. " if source == "witness" else "A neighbor told me. ") + reading.reason
		)


func _strongest_memory(person: Dictionary) -> Dictionary:
	var chosen = {}
	for memory in person.memories:
		if (
			memory.interpretation == person.belief
			and (chosen.is_empty() or memory.confidence >= chosen.confidence)
		):
			chosen = memory
	return chosen


func _spread_reports() -> void:
	for sender in people:
		if tick < sender.next_report or sender.memories.is_empty():
			continue
		var sent = false
		for receiver in people:
			if sender.id == receiver.id or sender.pos.distance_to(receiver.pos) > REPORT_RADIUS:
				continue
			var trust = float(receiver.trust.get(sender.id, 0.0))
			if trust < 0.30:
				continue
			for memory in sender.memories:
				if _has_memory(receiver, memory.event_id) or receiver.id in memory.chain:
					continue
				var delay = int(ceil(6.0 + (1.0 - trust) * 18.0))
				var confidence = memory.confidence * trust * 0.92
				if tick - memory.tick < delay or confidence < 0.16:
					continue
				var chain = memory.chain.duplicate()
				chain.append(sender.id)
				# Copy only the sender's information, never the global event record.
				_learn(receiver, memory, "report", sender.id, chain, confidence)
				sender.next_report = tick + 18
				metrics.reports += 1
				var cause = (
					"I told %s about %s, which %s."
					% [
						receiver.name,
						memory.kind,
						"I witnessed" if memory.source == "witness" else "was reported to me"
					]
				)
				_log(sender, "tell", memory.event_id, cause)
				if sender.goal == "work":
					sender.action = "tell"
					sender.event_id = memory.event_id
					sender.cause = cause
					sender.next_decision = mini(sender.next_decision, tick + 4)
				sent = true
				break
			if sent:
				break


func summary() -> Dictionary:
	var result = metrics.duplicate(true)
	var hunger = 0.0
	var thirst = 0.0
	var exhausted = 0
	var beliefs = {"uncertain": 0, "care": 0, "ritual": 0, "favoritism": 0}
	var village_needs = []
	for village in villages:
		var local_hunger = 0.0
		var local_thirst = 0.0
		for person in people:
			if person.village == village.id:
				local_hunger += person.hunger
				local_thirst += person.thirst
		village_needs.append(
			{
				"name": village.name,
				"mean_hunger": local_hunger / 12.0,
				"mean_thirst": local_thirst / 12.0,
				"food": village.food,
				"water": village.water
			}
		)
	for person in people:
		hunger += person.hunger
		thirst += person.thirst
		beliefs[person.belief] += 1
		if maxf(person.hunger, person.thirst) >= 0.8:
			exhausted += 1
	result.mean_hunger = hunger / people.size()
	result.mean_thirst = thirst / people.size()
	result.exhausted = exhausted
	result.beliefs = beliefs
	result.villages = village_needs
	var title = "The seventh evening" if ended else "The drought continues"
	var text = (
		"%d gifts reached neighbors; %d shrine visits were completed. %d people are exhausted. "
		% [metrics.shares, metrics.rituals, exhausted]
	)
	text += (
		"Food and water are finite. Gifts can feed people, "
		+ "but journeys, offerings, and withheld food have costs."
	)
	return {"title": title, "text": text, "metrics": result}


func digest() -> String:
	var state = {
		"seed_value": seed_value,
		"tick": tick,
		"ended": ended,
		"power": power,
		"people": people,
		"villages": villages,
		"events": events,
		"action_log": action_log,
		"command_log": command_log,
		"caches": caches,
		"well_water": well_water,
		"metrics": metrics,
		"rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state)
	}
	return JSON.stringify(_canonical(state), "", true, true).sha256_text()


func _canonical(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Dictionary:
		var output = {}
		for key in value:
			output[str(key)] = _canonical(value[key])
		return output
	if value is Array:
		var output = []
		for item in value:
			output.append(_canonical(item))
		return output
	return value
