extends SceneTree
## Walking must read as continuous travel: steady ground speed within each half-second
## simulation step, no Walk/Idle flicker between steps, and feet that keep pace.
const Main = preload("res://game/main.tscn")
const FRAME := 1.0 / 60.0
const STRIDE_SPEED := 1.25  # Walk clip foot travel, measured from the glTF skeleton.
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


## Advances the game by frames without yielding, so every frame has a known delta.
func frames(game: Node, count: int, record: Callable = Callable()) -> void:
	for i in count:
		game._process(FRAME)
		game.valley._process(FRAME)
		if record.is_valid():
			record.call()


func run() -> void:
	var game = Main.instantiate()
	game.muted = true
	game.intro = false
	root.add_child(game)
	await process_frame
	await process_frame
	game.paused = false
	game.speed = 1
	game._refresh()
	frames(game, 60 * 12)
	var digest_before: String = game.simulation.digest()
	var ids: Array = game.valley.people.keys()
	var trace := {}
	var clips := {}
	var ticks: Array[int] = []
	for id in ids:
		trace[id] = []
		clips[id] = []
	var record := func() -> void:
		ticks.append(game.simulation.tick)
		for id in ids:
			var actor: Node3D = game.valley.people[id]
			trace[id].append(actor.position)
			clips[id].append(actor._clip)
	frames(game, 60 * 4, record)
	# The person who walked the whole window, so every frame should be travel.
	var walker := -1
	for id in ids:
		if not clips[id].has("Idle") and _spread(trace[id]) > 1.0:
			var all_walk := true
			for clip in clips[id]:
				all_walk = all_walk and clip == "Walk"
			if all_walk:
				walker = id
				break
	var moving_people := 0
	var flickers := 0
	for id in ids:
		var series: Array = clips[id]
		var walked := series.count("Walk")
		if walked > 30:
			moving_people += 1
		for i in range(2, series.size()):
			# Walk -> other -> Walk within a single half-second step is flicker.
			if series[i] == "Walk" and series[i - 1] != "Walk":
				var back := i - 2
				while back >= 0 and series[back] != "Walk" and i - back <= 30:
					back -= 1
				if back >= 0 and series[back] == "Walk" and i - back <= 30:
					flickers += 1
	check(moving_people >= 3, "several people travel during the window (%d)" % moving_people)
	check(
		flickers == 0,
		"walkers never drop to another clip for under a step (%d flickers)" % flickers
	)
	check(walker >= 0, "at least one person walks for the whole four seconds")
	if walker >= 0:
		var speeds: Array[float] = []
		var points: Array = trace[walker]
		for i in range(1, points.size()):
			var step: Vector3 = points[i] - points[i - 1]
			speeds.append(Vector2(step.x, step.z).length() / FRAME)
		var steady := 0
		var counted := 0
		var mean := _mean(speeds)
		for i in speeds.size():
			# Skip frames that straddle a simulation step; the next segment may differ.
			if i > 0 and ticks[i + 1] != ticks[i]:
				continue
			counted += 1
			if absf(speeds[i] - mean) <= mean * .2:
				steady += 1
		check(
			counted > 0 and float(steady) / counted >= .95,
			"ground speed stays within 20%% of its mean (%d of %d frames)" % [steady, counted]
		)
		var actor = game.valley.people[walker]
		var feet: float = actor.walk_rate * STRIDE_SPEED * actor._model.scale.x
		print(
			(
				"WALK_METRICS person=%d travel=%.3fm/s steady=%d/%d rate=%.2f feet=%.3fm/s"
				% [walker, mean, steady, counted, actor.walk_rate, feet]
			)
		)
		check(
			absf(feet - mean) <= mean * .25 or actor.walk_rate <= .36,
			"stride speed %.2f m/s keeps pace with travel %.2f m/s" % [feet, mean]
		)
	game.paused = true
	game._refresh()
	var held: Vector3 = game.valley.people[ids[0]].position
	frames(game, 30)
	check(
		game.valley.people[ids[0]].position.is_equal_approx(held),
		"pausing freezes people where they stand"
	)
	game.paused = false
	game._refresh()
	game._restart(false)
	frames(game, 2)
	check(game.simulation.tick == 0, "restart returns to the first step")
	check(digest_before != "", "simulation digest is available")
	game.queue_free()
	await process_frame
	print("WALK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _spread(points: Array) -> float:
	return Vector2(points[0].x, points[0].z).distance_to(Vector2(points[-1].x, points[-1].z))


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(1, values.size())
