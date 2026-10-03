extends SceneTree
## Route real screen events through the scene, not a stand-in gesture source.
const Main = preload("res://game/main.tscn")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func finger(at: Vector2, index: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func drag(at: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = at
	event.index = index
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(at: Vector2) -> void:
	finger(at, 0, true)
	finger(at, 0, false)


func settle(game: Control) -> void:
	for i in range(180):
		game.valley.rig.advance(1.0 / 60.0)


func run() -> void:
	root.size = Vector2i(1440, 900)
	var game = Main.instantiate()
	game.intro = false
	game.muted = true
	root.add_child(game)
	await process_frame
	await process_frame
	settle(game)
	var view: Control = game.valley
	tap(game.hud.menu.get_global_rect().get_center())
	check(game.hud.sheet_open(), "real touch opens the overflow control sheet")
	if game.hud.sheet_open():
		var overview: Button = game.hud.sheet_box.find_child("overview", true, false)
		await process_frame
		await process_frame
		view.rig.wanted_distance = 42
		tap(overview.get_global_rect().get_center())
		check(
			not game.hud.sheet_open() and is_equal_approx(view.rig.wanted_distance, 110),
			"real touch activates a control-sheet action without a keyboard"
		)
	check(game.simulation.power == 8, "touching HUD controls cannot place a world miracle")
	settle(game)
	game.hud.command.emit("food")
	var target: Vector2 = view.to_screen(Vector2(240, 340))
	finger(target, 0, true)
	check(game.simulation.power == 8, "touch press never places an armed miracle")
	finger(target, 0, false)
	check(game.simulation.power == 7, "a completed tap places one food miracle")
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.position = target
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	Input.parse_input_event(emulated)
	check(game.simulation.power == 7, "emulated mouse press cannot duplicate the touch miracle")
	emulated = emulated.duplicate()
	emulated.pressed = false
	Input.parse_input_event(emulated)
	Input.flush_buffered_events()
	game.hud.command.emit("restart")
	game.hud.command.emit("rain")
	settle(game)
	var center: Vector2 = view.get_global_transform_with_canvas() * (view.size * .5)
	var yaw: float = view.rig.wanted_yaw
	finger(center, 0, true)
	drag(center + Vector2(80, 20), 0)
	check(not is_equal_approx(yaw, view.rig.wanted_yaw), "one finger orbits the real camera")
	finger(center + Vector2(80, 20), 0, false)
	check(game.simulation.power == 8, "orbit release never places a miracle")
	game.hud.command.emit("restart")
	game.hud.command.emit("food")
	settle(game)
	center = view.get_global_transform_with_canvas() * (view.size * .5)
	var distance: float = view.rig.wanted_distance
	var pan_target: Vector3 = view.rig.wanted_target
	finger(center - Vector2(80, 0), 0, true)
	finger(center + Vector2(80, 0), 1, true)
	drag(center - Vector2(100, -30), 0)
	drag(center + Vector2(130, 30), 1)
	check(view.rig.wanted_distance < distance, "spreading two fingers zooms the real camera in")
	check(not view.rig.wanted_target.is_equal_approx(pan_target), "two fingers pan the real camera")
	finger(center - Vector2(100, -30), 0, false)
	drag(center + Vector2(140, 40), 1)
	finger(center + Vector2(140, 40), 1, false)
	check(
		game.simulation.power == 8, "lifting fingers one at a time cannot cast after pan or pinch"
	)
	check(view.touch.fingers.is_empty(), "the last release clears the complete gesture")
	finger(center, 0, true)
	finger(center, 0, false, true)
	check(game.simulation.power == 8, "a canceled OS touch never casts")
	finger(center, 0, true)
	finger(center + Vector2(20, 0), 1, true)
	finger(center + Vector2(40, 0), 2, true)
	yaw = view.rig.wanted_yaw
	drag(center + Vector2(100, 0), 2)
	check(
		is_equal_approx(view.rig.wanted_yaw, yaw), "three fingers do not choose an arbitrary orbit"
	)
	finger(center, 0, false)
	finger(center + Vector2(20, 0), 1, false)
	finger(center + Vector2(100, 0), 2, false)
	check(game.simulation.power == 8, "three-finger release never casts")
	finger(center, 0, true)
	drag(center + Vector2(30, 10), 0)
	game.hud.command.emit("help")
	check(
		not view.camera_input_enabled and view.touch.fingers.is_empty(),
		"a modal immediately cancels touch input"
	)
	var camera: Transform3D = view.rig.camera.global_transform
	drag(center + Vector2(90, 30), 0)
	view._process(.2)
	check(
		view.rig.camera.global_transform.is_equal_approx(camera),
		"the camera stays still behind the modal"
	)
	finger(center + Vector2(90, 30), 0, false)
	game.hud.command.emit("close")
	yaw = view.rig.wanted_yaw
	drag(center + Vector2(140, 30), 0)
	finger(center + Vector2(140, 30), 0, false)
	check(
		is_equal_approx(view.rig.wanted_yaw, yaw), "a dismissed modal cannot restore an orphan drag"
	)
	check(game.simulation.power == 8, "a modal's release cannot place a miracle")
	finger(center, 0, true)
	game.hud.menu.emit_signal("pressed")
	check(
		game.hud.sheet_open() and view.touch.fingers.is_empty(),
		"the overflow menu is a touch-sized modal"
	)
	var actions: Array[Node] = game.hud.sheet_box.find_children("*", "Button", true, false)
	check(
		actions.size() == game.hud.MENU_ACTIONS.size() + 1,
		"every overflow action has a real button"
	)
	for action in actions:
		check(
			action.custom_minimum_size.y >= 48,
			"overflow button %s keeps a 48-pixel hit target" % action.name
		)
	game.hud.command.emit("close")
	finger(center, 0, false)
	check(game.simulation.power == 8, "opening controls cancels the pending world tap")
	finger(center, 0, true)
	root.size = Vector2i(720, 900)
	await process_frame
	await process_frame
	drag(center, 0)
	finger(center, 0, false)
	check(
		view.touch.fingers.is_empty() and game.simulation.power == 8,
		"resizing cancels the old touch coordinate frame"
	)
	view.rig.wanted_target = view.world_position(Vector2(240, 340))
	settle(game)
	target = view.to_screen(Vector2(240, 340))
	tap(target)
	check(game.simulation.power == 7, "a new tap picks correctly after resize")
	game.hud.command.emit("restart")
	game.hud.command.emit("food")
	root.size = Vector2i(960, 1200)
	await process_frame
	await process_frame
	view.position = Vector2(150, 150)
	view.size = Vector2(640, 900)
	view.scale = Vector2(.8, .8)
	view.rig.wanted_target = view.world_position(Vector2(240, 340))
	settle(game)
	target = (
		view.get_global_transform_with_canvas()
		* view.rig.camera.unproject_position(view.world_position(Vector2(240, 340)))
	)
	tap(target)
	check(
		game.simulation.command_log.size() == 1,
		"a transformed viewport still accepts exactly one tap"
	)
	if game.simulation.command_log.size() == 1:
		check(
			game.simulation.command_log[0].pos.distance_to(Vector2(240, 340)) < 1,
			"DPI-scaled picking stays at the intended terrain point"
		)
	view.scale = Vector2.ONE
	game.hud.command.emit("restart")
	game.hud.command.emit("observe")
	await physics_frame
	game.valley.focus_person(0)
	settle(game)
	await physics_frame
	var body: Vector3 = view.people[0].focus_point() - Vector3(0, .3, 0)
	target = view.get_global_transform_with_canvas() * view.rig.camera.unproject_position(body)
	tap(target)
	check(game.selected == 0, "a real touch tap selects the physics-picked person")
	await process_frame
	await process_frame
	var panel: Rect2 = game.hud.inspector.get_global_rect()
	var edge := Vector2(panel.position.x, panel.get_center().y)
	var input_count: int = game.session_inputs.size()
	finger(edge - Vector2(2, 0), 0, true)
	check(view.touch.fingers.size() == 1, "inspector edge contact starts in the world")
	finger(edge + Vector2(2, 0), 0, false)
	check(
		game.session_inputs.size() == input_count,
		"release over the inspector cannot complete a world tap"
	)
	check(game.selected == 0, "occluded release preserves selection")
	check(view.touch.fingers.is_empty(), "occluded release still cleans up the gesture")
	yaw = view.rig.wanted_yaw
	finger(edge - Vector2(2, 0), 0, true)
	drag(edge + Vector2(30, 0), 0)
	finger(edge + Vector2(30, 0), 0, false)
	check(
		not is_equal_approx(view.rig.wanted_yaw, yaw),
		"owned camera drag stays active over the inspector"
	)
	check(
		game.session_inputs.size() == input_count, "camera release over HUD never chooses the world"
	)
	finger(edge - Vector2(2, 0), 0, true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(view.touch.fingers.is_empty(), "application focus loss cancels pending touches")
	finger(edge - Vector2(2, 0), 0, false)
	check(game.selected == 0, "a focus-loss release cannot change selection")
	game.hud.command.emit("help")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not game.hud.sheet_open(), "Android Back closes the sheet first")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.selected == -1, "Android Back then closes the inspector")
	game.hud.command.emit("food")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.mode == "observe", "Android Back cancels miracle targeting")
	game.queue_free()
	await process_frame
	print("TOUCH: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
