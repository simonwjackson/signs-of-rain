extends SceneTree
const Main = preload("res://game/main.tscn")
const S = preload("res://ui/style.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func mouse_button(at: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func move(at: Vector2, relative: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	event.button_mask = mask
	Input.parse_input_event(event)


func settle(game: Control) -> void:
	for i in range(180):
		game.valley.rig.advance(1.0 / 60.0)


func run() -> void:
	root.size = Vector2i(1440, 900)
	var game = Main.instantiate()
	game.muted = true
	game.intro = false
	root.add_child(game)
	await process_frame
	await process_frame
	settle(game)
	var crop: MultiMeshInstance3D = game.valley.terrain.get_node("LivingCropAlder")
	var before_crop: float = crop.material_override.get_shader_parameter("vitality")
	game.hud.command.emit("food")
	game.valley.chosen.emit(Vector2(240, 340), MOUSE_BUTTON_LEFT)
	await process_frame
	await process_frame
	check(
		game.simulation.tick == 0 and game.valley.caches.size() == 1,
		"food has real resource geometry even when cast while paused"
	)
	game.hud.command.emit("rain")
	game.valley.chosen.emit(Vector2(240, 340), MOUSE_BUTTON_LEFT)
	await process_frame
	await process_frame
	check(
		(
			game.simulation.tick == 0
			and float(crop.material_override.get_shader_parameter("vitality")) > before_crop
		),
		"paused rain updates rendered crops without advancing model time"
	)
	var center := Vector2(710, 400)
	move(center, Vector2.ZERO)
	await process_frame
	await process_frame
	var rain_color: Color = game.valley.cursor_mesh.surface_get_material(0).albedo_color
	game.hud.command.emit("food")
	await process_frame
	await process_frame
	var food_color: Color = game.valley.cursor_mesh.surface_get_material(0).albedo_color
	check(
		rain_color.is_equal_approx(S.RAIN) and food_color.is_equal_approx(S.WHEAT),
		"stationary target ring changes with the armed miracle"
	)
	game.hud.command.emit("observe")
	for button in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		settle(game)
		var before: Transform3D = game.valley.rig.camera.global_transform
		mouse_button(center, button, true)
		await process_frame
		game.hud.command.emit("help")
		await process_frame
		mouse_button(center, button, false)
		await process_frame
		game.hud.command.emit("close")
		move(center + Vector2(80, 20), Vector2(80, 20))
		await process_frame
		await process_frame
		check(
			game.valley.rig.camera.global_transform.is_equal_approx(before),
			"modal cancels drag %d when release happens over the overlay" % button
		)
	game.hud.command.emit("restart")
	await process_frame
	await process_frame
	settle(game)
	var before: Transform3D = game.valley.rig.camera.global_transform
	mouse_button(center, MOUSE_BUTTON_MIDDLE, true)
	game.hud.command.emit("restart")
	await process_frame
	move(center, Vector2(60, 10), MOUSE_BUTTON_MASK_MIDDLE)
	await process_frame
	check(
		game.valley.rig.camera.global_transform.is_equal_approx(before),
		"restart cancels an unfinished camera drag"
	)
	mouse_button(center, MOUSE_BUTTON_MIDDLE, false)
	game.queue_free()
	await process_frame
	print("VIEW INTERACTION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
