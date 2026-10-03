extends SceneTree
## Real window content scaling keeps 48-unit targets and full-density 3D picking.
const Main = preload("res://game/main.tscn")
const Layout = preload("res://ui/layout.gd")
var failures := 0
var checks := 0


func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	expect(is_equal_approx(Layout.density_scale(160), 1), "Android baseline density uses 1x")
	expect(
		is_equal_approx(Layout.density_scale(480), 3),
		"480 DPI uses three physical pixels per UI unit"
	)
	expect(is_equal_approx(Layout.density_scale(0), 1), "missing density stays readable")
	root.size = Vector2i(1848, 2448)
	root.content_scale_factor = Layout.density_scale(480)
	var game := Main.instantiate()
	game.intro = false
	game.muted = true
	root.add_child(game)
	await process_frame
	await process_frame
	expect(game.size.is_equal_approx(Vector2(616, 816)), "canvas reflows in logical units")
	expect(game.hud.buttons.observe.size.y >= 48, "buttons keep 48 logical-unit targets")
	var valley: Control = game.valley
	var expected_pixels := Vector2i(roundi(valley.size.x * 3), roundi(valley.size.y * 3))
	expect(
		valley.viewport.size == expected_pixels,
		"3D viewport retains physical density before Fast scaling"
	)
	var point := Vector2(500, 320)
	var canvas_point: Vector2 = (
		valley.get_global_transform_with_canvas().affine_inverse() * valley.to_screen(point)
	)
	var picked: Vector2 = valley.simulation_position(valley.ground_at(canvas_point))
	expect(
		picked.distance_to(point) < 3, "terrain picking maps logical input to full-density viewport"
	)
	game.hud.command.emit("food")
	var physical_touch: Vector2 = valley.to_screen(point) * root.content_scale_factor
	for contact in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = contact
		event.position = physical_touch
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	expect(game.simulation.power == 7, "physical-density touch routes through the scene once")
	if game.simulation.command_log.size() == 1:
		expect(
			game.simulation.command_log[0].pos.distance_to(point) < 3,
			"density-routed miracle lands at the terrain point"
		)
	expect(valley.touch.fingers.is_empty(), "touch sequence closes at density-scaled coordinates")
	game.queue_free()
	await process_frame
	print("DENSITY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
