extends SceneTree
## Scene-level boundary checks. These supplement, not replace, target input/capture.
const Main = preload("res://game/main.tscn")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func run() -> void:
	var game = Main.instantiate()
	game.muted = true  # Audio output has its own real-device verification boundary.
	root.add_child(game)
	await process_frame
	await process_frame
	game.hud.close_sheet()
	game.intro = false
	for viewport_size in [
		Vector2i(1440, 900),
		Vector2i(1024, 768),
		Vector2i(720, 900),
		Vector2i(360, 720),
		Vector2i(1280, 300),
		Vector2i(320, 240)
	]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		for name in ["observe", "rain", "food", "pause"]:
			var button: Button = game.hud.buttons[name]
			check(
				bounds.encloses(button.get_global_rect()),
				"%s reachable at %s" % [name, viewport_size]
			)
			check(button.size.y >= 44, "%s touch height at %s" % [name, viewport_size])
		check(
			bounds.encloses(game.hud.menu.get_global_rect()),
			"overflow reachable at %s, actual %s" % [viewport_size, game.hud.menu.get_global_rect()]
		)
		check(
			game.valley.size.x > 0 and game.valley.size.y > 0,
			"world survives at %s" % viewport_size
		)
		game.hud.person_chosen.emit(0)
		await process_frame
		await process_frame
		check(
			bounds.encloses(game.hud.inspector.get_global_rect()),
			"inspector stays in window at %s" % viewport_size
		)
		check(
			not game.hud.inspector.get_global_rect().intersects(game.hud.bar.get_global_rect()),
			"inspector does not cover toolbar at %s" % viewport_size
		)
		check(
			game.hud.inspector_scroll.size.y >= 44,
			"causal account has a readable scroll area at %s" % viewport_size
		)
		game.hud.person_chosen.emit(-1)
		game.hud.command.emit("help")
		await process_frame
		await process_frame
		check(
			bounds.encloses(game.hud.sheet_box.get_global_rect()),
			(
				"guide stays in window at %s, actual %s"
				% [viewport_size, game.hud.sheet_box.get_global_rect()]
			)
		)
		game.hud.command.emit("close")
		game.hud.show_ending(
			{
				"title": "The seventh evening",
				"text": "The week ends. Its stories remain.",
				"metrics": {}
			}
		)
		await process_frame
		await process_frame
		var scrolls = game.hud.sheet_box.find_children("*", "ScrollContainer", true, false)
		check(
			scrolls.size() == 1 and scrolls[0].size.y >= 44,
			"ending account has a readable scroll area at %s" % viewport_size
		)
		check(
			bounds.encloses(game.hud.sheet_box.get_global_rect()),
			"ending stays inside the window at %s" % viewport_size
		)
		game.hud.command.emit("close")
	root.size = Vector2i(1440, 900)
	await process_frame
	game.hud.buttons.rain.emit_signal("pressed")
	check(game.mode == "rain", "rain button arms targeting")
	var cast := InputEventMouseButton.new()
	cast.button_index = MOUSE_BUTTON_LEFT
	cast.pressed = true
	cast.position = game.valley.to_screen(Vector2(240, 340))
	Input.parse_input_event(cast)
	await process_frame
	check(
		game.simulation.command_log.size() == 1 and game.simulation.power == 6,
		"actual scene pointer routing casts one rain"
	)
	var old: String = game.simulation.digest()
	game.hud.buttons.restart.emit_signal("pressed")
	check(
		game.simulation.tick == 0 and game.simulation.power == 8, "restart restores tick and power"
	)
	check(game.simulation.digest() != old, "restart clears intervened state")
	game.hud.command.emit("replay")
	check(
		game.simulation.digest() == old, "scene replay reconstructs paused tick-zero intervention"
	)
	game.hud.command.emit("restart")
	game.hud.buttons.food.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(game.selected == 0, "Tab selects person even with a focused button")
	game.hud.command.emit("focus")
	check(
		game.valley.camera_evidence().followed_person == 0,
		"close camera follows the inspected person"
	)
	game.hud.person_chosen.emit(1)
	check(
		game.valley.camera_evidence().followed_person == 1,
		"changing inspected person retargets close camera"
	)
	game.hud.command.emit("restart")
	game.hud.command.emit("food")
	game.valley.chosen.emit(Vector2(240, 340), MOUSE_BUTTON_LEFT)
	game.speed = 4
	game.hud.command.emit("pause")
	for i in range(50):
		game._process(0.25)
	game.hud.command.emit("pause")
	game.hud.command.emit("rain")
	game.valley.chosen.emit(Vector2(760, 340), MOUSE_BUTTON_LEFT)
	check(game.simulation.command_log.size() == 2, "attempt has a delayed second intervention")
	game.hud.command.emit("replay")
	for i in range(25):
		game._process(0.25)
	check(game.simulation.command_log.size() == 1, "partial replay has not yet reached second cast")
	game.hud.command.emit("replay")
	for i in range(51):
		game._process(0.25)
	check(
		game.simulation.command_log.size() == 2, "restarting playback preserves its future commands"
	)
	game.hud.command.emit("restart")
	game.hud.command.emit("replay")
	for i in range(51):
		game._process(0.25)
	check(
		game.simulation.command_log.size() == 2,
		"restart out of playback preserves original attempt"
	)
	game.queue_free()
	await process_frame
	print("PRESENTATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
