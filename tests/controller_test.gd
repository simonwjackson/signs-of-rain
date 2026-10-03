extends SceneTree
## Exercise event-owned input and the actual scene routing, including modal focus.
const Main = preload("res://game/main.tscn")
const Controller = preload("res://game/controller.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func button(index: int, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	return event


func axis(index: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = index
	event.axis_value = value
	return event


func send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	var controller = Controller.new()
	controller.consume(axis(JOY_AXIS_LEFT_X, .1))
	check(controller.movement().pan == Vector2.ZERO, "stick drift is inside the deadzone")
	controller.consume(axis(JOY_AXIS_LEFT_X, 1))
	check(controller.movement().pan.x == 1, "full stick produces full pan")
	controller.consume(button(JOY_BUTTON_LEFT_SHOULDER))
	check(controller.movement().zoom != 0, "held shoulder zooms")
	controller.clear()
	check(
		controller.movement().pan == Vector2.ZERO and controller.movement().zoom == 0,
		"cancel clears held input"
	)
	check(
		controller.consume(button(JOY_BUTTON_A, false)) == "",
		"button release never repeats an action"
	)
	var other := button(JOY_BUTTON_A)
	other.device = 1
	check(controller.consume(other) == "", "a second controller cannot interleave input")
	controller.release_device(0)
	check(controller.device == -1, "disconnect releases controller ownership")

	root.size = Vector2i(640, 480)
	var game = Main.instantiate()
	game.intro = false
	game.muted = true
	root.add_child(game)
	await process_frame
	await process_frame
	await physics_frame
	var before: String = game.simulation.digest()
	send(axis(JOY_AXIS_LEFT_X, 1))
	var target: Vector3 = game.valley.rig.wanted_target
	await process_frame
	await process_frame
	check(game.valley.rig.wanted_target != target, "real joystick event pans the actual camera")
	check(game.simulation.digest() == before, "camera input never changes the model")
	send(axis(JOY_AXIS_LEFT_X, 0))
	send(axis(JOY_AXIS_RIGHT_X, 1))
	var yaw: float = game.valley.rig.wanted_yaw
	await process_frame
	check(game.valley.rig.wanted_yaw != yaw, "right stick orbits without requiring pan")
	send(axis(JOY_AXIS_RIGHT_X, 0))
	send(button(JOY_BUTTON_DPAD_RIGHT))
	check(game.selected == 0, "dpad selects the first person")
	var point: Vector2 = game.valley.controller_point + game.valley.position - game.hud.position
	check(
		not game.hud.inspector.get_rect().has_point(point),
		"controller target stays outside the overlay inspector"
	)
	await process_frame
	await process_frame
	var scroll_before: int = game.hud.inspector_scroll.scroll_vertical
	var yaw_before: float = game.valley.rig.wanted_yaw
	send(button(JOY_BUTTON_RIGHT_STICK))
	send(axis(JOY_AXIS_RIGHT_Y, 1))
	for frame in range(10):
		await process_frame
	check(
		game.hud.inspector_scroll.scroll_vertical > scroll_before,
		"right-stick modifier scrolls the causal account"
	)
	check(game.valley.rig.wanted_yaw == yaw_before, "inspector scrolling does not orbit the camera")
	send(button(JOY_BUTTON_RIGHT_STICK, false))
	send(axis(JOY_AXIS_RIGHT_Y, 0))
	send(button(JOY_BUTTON_DPAD_UP))
	check(game.valley.rig.following, "dpad opens the continuous close-person view")
	send(button(JOY_BUTTON_DPAD_DOWN))
	check(not game.valley.rig.following, "dpad restores the overview")
	send(button(JOY_BUTTON_X))
	check(game.mode == "rain", "X selects rain")
	send(button(JOY_BUTTON_Y))
	check(game.mode == "food", "Y selects food")
	var casts: int = game.simulation.command_log.size()
	send(button(JOY_BUTTON_A))
	check(
		game.simulation.command_log.size() == casts + 1,
		"A casts through the actual camera-ground world input"
	)
	send(button(JOY_BUTTON_B))
	check(game.mode == "observe", "B cancels a gift")
	game.hud.buttons.pause.grab_focus()
	send(button(JOY_BUTTON_BACK))
	await process_frame
	check(game.hud.sheet_open(), "Select opens the complete action menu")
	check(
		game.hud.sheet.is_ancestor_of(root.gui_get_focus_owner()),
		"modal takes focus away from an existing toolbar focus"
	)
	for entry in range(18):
		send(button(JOY_BUTTON_DPAD_DOWN))
	check(
		game.hud.sheet.is_ancestor_of(root.gui_get_focus_owner()),
		"dpad focus wraps within the sheet"
	)
	check(not game.valley.camera_input_enabled, "modal blocks camera input")
	var blocked: Vector3 = game.valley.rig.wanted_target
	send(axis(JOY_AXIS_LEFT_X, 1))
	await process_frame
	check(game.valley.rig.wanted_target == blocked, "joystick cannot pan behind a menu")
	send(button(JOY_BUTTON_B))
	await process_frame
	check(not game.hud.sheet_open(), "B closes the menu")
	check(
		game.controller.movement().pan == Vector2.ZERO,
		"modal stick input cannot leak after closing"
	)
	var paused: bool = game.paused
	send(button(JOY_BUTTON_START))
	check(game.paused != paused, "Start toggles time")
	send(button(JOY_BUTTON_START))
	send(axis(JOY_AXIS_LEFT_X, 1))
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.controller.movement().pan == Vector2.ZERO, "focus loss cancels held camera motion")
	game._controller_connection(0, false)
	check(
		not game.controller_active and not game.valley.controller_aim,
		"disconnect removes the aim marker"
	)
	check(game.valley.people.size() == 24, "controller support retains every animated person")
	var digest: String = game.simulation.digest()
	game.valley.set_handheld(true)
	check(not game.valley.environment.glow_enabled, "handheld removes the additional glow pass")
	check(
		game.valley.sunlight.directional_shadow_max_distance == 60,
		"handheld limits shadow-map coverage"
	)
	check(game.simulation.digest() == digest, "handheld rendering cannot change simulation state")
	game.valley.set_handheld(false)
	check(
		game.valley.environment.glow_enabled,
		"desktop glow is restored when leaving handheld profile"
	)
	game.queue_free()
	await process_frame
	print("CONTROLLER: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
