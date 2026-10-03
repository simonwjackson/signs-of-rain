extends Control
## Composition and input ordering. Only this node advances the simulation.
const Simulation = preload("res://sim/simulation.gd")
const Valley = preload("res://game/valley.gd")
const Hud = preload("res://ui/hud.gd")
const Sound = preload("res://game/sound.gd")
const Layout = preload("res://ui/layout.gd")
const Controller = preload("res://game/controller.gd")
const FrameTimes = preload("res://game/frame_times.gd")
const TICK_SECONDS := 0.5
var simulation: RefCounted
var valley: Control
var hud: Control
var sound: Node
var seed_value := 2401
var mode := "observe"
var paused := true
var selected := -1
var speed := 1
var elapsed := 0.0
var intro := true
var ended_shown := false
var action_count := 0
var muted := false
var reduced_motion := false
var previous_commands: Array = []
var has_previous_attempt := false
var replay_commands: Array = []
var replay_index := 0
var replaying := false
var evidence_path := ""
var evidence_elapsed := 0.0
var session_inputs: Array[Dictionary] = []
var restart_count := 0
var previous_digest := ""
var tick_on_restart := 0
var controller = Controller.new()
var controller_active := false
var handheld := false
var modal_scroll := 0.0
var frame_times = FrameTimes.new()


func _ready() -> void:
	if OS.get_name() == "Android":
		_apply_android_density()
		get_window().dpi_changed.connect(_apply_android_density)
	var graphics := _saved_graphics()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seed_value = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--evidence="):
			evidence_path = argument.trim_prefix("--evidence=")
		elif argument == "--no-intro":
			intro = false
		elif argument == "--mute":
			muted = true
		elif argument == "--handheld":
			handheld = true
		elif argument.begins_with("--graphics="):
			graphics = argument.trim_prefix("--graphics=")
	valley = Valley.new()
	add_child(valley)
	valley.set_graphics(graphics)
	if handheld:
		valley.set_handheld(true)
	Input.joy_connection_changed.connect(_controller_connection)
	valley.chosen.connect(_world_input)
	hud = Hud.new()
	hud.size = size
	add_child(hud)
	hud.command.connect(_command)
	hud.modal_changed.connect(_sync_input_gate)
	if OS.get_name() == "Android":
		get_tree().quit_on_go_back = false
	hud.person_chosen.connect(_select)
	sound = Sound.new()
	add_child(sound)
	sound.set_enabled(not muted)
	hud.update_toggles(muted, reduced_motion, valley.graphics == "fast")
	resized.connect(_arrange)
	_restart(false)
	if intro:
		hud.show_help(true, seed_value)
	_arrange()
	_emit_evidence()


## Android reports screen pixels; UI controls use density-independent canvas units.
func _apply_android_density() -> void:
	get_window().content_scale_factor = Layout.density_scale(DisplayServer.screen_get_dpi())


func _arrange() -> void:
	var usable := Rect2(Vector2.ZERO, size)
	if OS.get_name() == "Android":
		var to_screen := get_viewport().get_screen_transform() * get_global_transform_with_canvas()
		usable = Layout.safe_rect(size, DisplayServer.get_display_safe_area(), to_screen)
	var plan := Layout.plan(usable.size, selected >= 0)
	valley.position = usable.position + plan.world.position
	valley.size = plan.world.size
	hud.position = usable.position
	hud.size = usable.size
	hud.arrange()
	valley.controller_point = hud.controller_world_point(
		Rect2(valley.position - hud.position, valley.size)
	)


func _sync_input_gate() -> void:
	var enabled: bool = not hud.sheet_open()
	if valley.camera_input_enabled != enabled:
		controller.clear()
		modal_scroll = 0
	valley.camera_input_enabled = enabled
	if not enabled and controller_active:
		hud.focus_sheet.call_deferred()


func _snapshot() -> Dictionary:
	return {
		"seed": seed_value,
		"tick": simulation.tick,
		"ended": simulation.ended,
		"power": simulation.power,
		"people": simulation.people,
		"villages": simulation.villages,
		"events": simulation.events,
		"action_log": simulation.action_log,
		"caches": simulation.caches,
		"well_water": simulation.well_water,
	}


func _refresh() -> void:
	var snapshot := _snapshot()
	valley.set_state(snapshot)
	valley.selected = selected
	valley.mode = mode
	valley.motion = not reduced_motion and not paused
	valley.effects_static = reduced_motion
	_sync_input_gate()
	hud.refresh(snapshot, selected, mode, paused, speed, replaying)


func _process(delta: float) -> void:
	if simulation == null:
		return
	if evidence_path != "":
		frame_times.record(delta)
	var advanced := false
	if not paused and not simulation.ended:
		elapsed += minf(delta, 0.25) * speed
		while elapsed >= TICK_SECONDS and not simulation.ended:
			elapsed -= TICK_SECONDS
			if replaying:
				_apply_replay()
			simulation.step()
			if replaying:
				_apply_replay()
			_after_tick()
			advanced = true
	if advanced:
		_refresh()
	if controller_active:
		if hud.sheet_open():
			if absf(modal_scroll) > Controller.DEADZONE:
				hud.scroll_controller(modal_scroll, delta)
		else:
			var movement: Dictionary = controller.movement()
			if movement.scrolling and selected >= 0:
				hud.scroll_controller(movement.orbit.y, delta)
			else:
				valley.controller_motion(movement, delta)
	evidence_elapsed += delta
	if evidence_elapsed >= 1.0:
		evidence_elapsed = 0
		_emit_evidence()


func _after_tick() -> void:
	var actions: Array = simulation.action_log
	for i in range(action_count, actions.size()):
		var action: Dictionary = actions[i]
		if action.action in ["share", "tell"]:
			valley.action_mark(action.action, int(action.person))
	action_count = actions.size()
	if simulation.ended and not ended_shown:
		ended_shown = true
		paused = true
		hud.show_ending(simulation.summary())
		_emit_evidence()


func _world_input(point: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_command("observe")
		return
	if button != MOUSE_BUTTON_LEFT or hud.sheet_open():
		return
	session_inputs.append(
		{"tick": simulation.tick, "type": "world_click", "point": [point.x, point.y], "mode": mode}
	)
	if mode == "observe":
		_select(valley.person_at_pointer())
	elif not replaying:
		var result: Dictionary = simulation.cast(mode, point)
		if result.ok:
			valley.miracle(mode, point)
			sound.play(mode)
			var event: Dictionary = simulation.events.back()
			var benefit := (
				"Rain restores a village"
				if mode == "rain" and event.village >= 0
				else "Rain misses both village centers" if mode == "rain" else "Food arrives"
			)
			hud.toast("%s. %d witnesses." % [benefit, event.witnesses.size()])
		else:
			hud.toast(result.reason)
	_refresh()
	_emit_evidence()


func _select(id: int) -> void:
	var changed := selected != id
	selected = id
	if changed and id >= 0 and valley.is_following_person():
		valley.focus_person(id)
	mode = "observe"
	_refresh()
	_arrange()
	sound.play("touch")
	_emit_evidence()


func _command(name: String) -> void:
	session_inputs.append({"tick": simulation.tick, "type": "control", "name": name})
	match name:
		"observe", "rain", "food":
			if replaying and name != "observe":
				hud.toast("This is a replay. Restart to make different choices.")
				return
			mode = name
			if name != "observe":
				selected = -1
			_arrange()
		"pause":
			if not simulation.ended:
				paused = not paused
		"speed":
			speed = 2 if speed == 1 else 4 if speed == 2 else 1
			hud.toast("Time runs at %d×" % speed)
		"begin":
			intro = false
			hud.close_sheet()
			paused = false
		"close":
			hud.close_sheet()
			if intro:
				intro = false
				paused = false
		"help":
			hud.show_help(false, seed_value)
		"people":
			hud.show_people(simulation.people)
		"restart":
			_restart(false)
			hud.toast("Same people. Same seed. A different chance.")
		"replay":
			if (
				simulation.tick == 0
				and simulation.command_log.is_empty()
				and not has_previous_attempt
			):
				hud.toast("Let time pass or intervene first, then replay the attempt.")
			else:
				_restart(true)
				paused = false
		"focus":
			if selected < 0:
				_select(0)
			valley.focus_person(selected)
		"overview":
			valley.overview()
		"next":
			_select((selected + 1) % 24)
		"save":
			_save_replay()
		"mute":
			muted = not muted
			sound.set_enabled(not muted)
			hud.toast("Sound off" if muted else "Sound on")
		"motion":
			reduced_motion = not reduced_motion
		"graphics":
			valley.set_graphics("high" if valley.graphics == "fast" else "fast")
			_save_graphics(valley.graphics)
			hud.toast("Faster graphics" if valley.graphics == "fast" else "Full graphics")
		"quit":
			_emit_evidence()
			get_tree().quit()
	hud.update_toggles(muted, reduced_motion, valley.graphics == "fast")
	_refresh()
	_emit_evidence()


## Mobile starts faster. A saved choice always wins on every platform.
static func default_graphics(platform: String, integrated: bool) -> String:
	return "fast" if platform == "Android" or integrated else "high"


func _saved_graphics() -> String:
	var stored := ConfigFile.new()
	if stored.load("user://settings.cfg") == OK:
		return str(stored.get_value("graphics", "preset", "high"))
	var integrated := (
		RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	)
	return default_graphics(OS.get_name(), integrated)


func _save_graphics(preset: String) -> void:
	var stored := ConfigFile.new()
	stored.load("user://settings.cfg")
	stored.set_value("graphics", "preset", preset)
	var result := stored.save("user://settings.cfg")
	if result != OK:
		hud.toast("Cannot save the graphics choice: " + error_string(result))


func _restart(as_replay: bool) -> void:
	if simulation != null:
		previous_digest = simulation.digest()
		tick_on_restart = simulation.tick
		if (
			not replaying
			and (not as_replay or not simulation.command_log.is_empty() or simulation.tick > 0)
		):
			previous_commands = simulation.command_log.duplicate(true)
			has_previous_attempt = true
		restart_count += 1
	replaying = as_replay
	replay_commands = previous_commands.duplicate(true) if as_replay else []
	replay_index = 0
	simulation = Simulation.new(seed_value)
	mode = "observe"
	selected = -1
	paused = true
	elapsed = 0
	ended_shown = false
	action_count = 0
	valley.reset()
	hud.close_sheet()
	if replaying:
		_apply_replay()
	_refresh()
	_arrange()


func _apply_replay() -> void:
	while (
		replay_index < replay_commands.size()
		and int(replay_commands[replay_index].tick) == simulation.tick
	):
		var item: Dictionary = replay_commands[replay_index]
		var point: Vector2 = item.pos
		var result: Dictionary = simulation.cast(item.kind, point)
		if result.ok:
			valley.miracle(item.kind, point)
			sound.play(item.kind)
		replay_index += 1


func _save_replay() -> void:
	var data := {
		"version": 1,
		"seed": seed_value,
		"commands": _json_value(replay_commands if replaying else simulation.command_log),
		"tick": simulation.tick,
		"digest": simulation.digest()
	}
	var path := "user://last-replay.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		hud.toast("Cannot write replay: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "  "))
	hud.toast("Replay saved to " + ProjectSettings.globalize_path(path))


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_route_controller(event)
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		controller_active = false
		controller.clear()
		valley.controller_aim = false
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_route_touch(event)
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var keys := {
		KEY_1: "observe",
		KEY_2: "rain",
		KEY_3: "food",
		KEY_SPACE: "pause",
		KEY_F: "speed",
		KEY_R: "restart",
		KEY_M: "mute",
		KEY_H: "help",
		KEY_P: "replay",
		KEY_C: "focus",
		KEY_V: "overview"
	}
	if event.keycode == KEY_ESCAPE:
		_back()
	elif hud.sheet_open():
		if event.keycode == KEY_ENTER and intro:
			_command("begin")
		return
	elif event.keycode == KEY_TAB:
		_select((selected + 1) % 24)
	elif keys.has(event.keycode):
		_command(keys[event.keycode])
	else:
		return
	get_viewport().set_input_as_handled()


func _controller_connection(id: int, connected: bool) -> void:
	if not connected:
		controller.release_device(id)
		if controller.device < 0:
			controller_active = false
			valley.controller_aim = false


func _route_controller(event: InputEvent) -> void:
	if controller.device >= 0 and event.device != controller.device:
		return
	var first := not controller_active
	controller_active = true
	hud.controller_controls = true
	valley.controller_aim = true
	var action: String = controller.consume(event)
	if first:
		_refresh()
	if hud.sheet_open():
		controller.clear()
		if event is InputEventJoypadMotion and event.axis == JOY_AXIS_RIGHT_Y:
			modal_scroll = event.axis_value
		hud.focus_sheet()
		if (
			event is InputEventJoypadButton
			and event.pressed
			and (
				event.button_index
				in [
					JOY_BUTTON_DPAD_UP,
					JOY_BUTTON_DPAD_LEFT,
					JOY_BUTTON_DPAD_DOWN,
					JOY_BUTTON_DPAD_RIGHT
				]
			)
		):
			hud.focus_sheet(
				-1 if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT] else 1
			)
		elif action == "back" or action == "menu":
			_back()
		elif action == "pause":
			_command("begin" if intro else "close")
		else:
			# Godot's native focus/accept actions retain controller events in sheets.
			return
	elif action == "activate":
		valley.controller_activate()
	elif action == "back":
		_back()
	elif action == "menu":
		hud.show_controls()
	elif action == "previous":
		_select(posmod(selected - 1, 24))
	elif action == "next":
		_select((selected + 1) % 24)
	elif action != "":
		_command(action)
	get_viewport().set_input_as_handled()


## Screen events arrive in logical viewport coordinates. Transform into
## valley-local canvas units here; Valley converts them to 3D viewport pixels.
func _route_touch(event: InputEvent) -> void:
	if hud.sheet_open():
		valley.cancel_camera_input()
		return
	if event is InputEventScreenTouch and event.pressed:
		if hud.blocks_world_input(event.position):
			valley.cancel_camera_input()
			return
		var bounds := Rect2(Vector2.ZERO, valley.size)
		var at: Vector2 = (
			valley.get_global_transform_with_canvas().affine_inverse() * event.position
		)
		if not bounds.has_point(at):
			return
	if event is InputEventScreenTouch and not event.pressed:
		if hud.blocks_world_input(event.position):
			# Finish an owned gesture, but do not cast/select behind a HUD surface.
			# Keep the original GUI event intact for contacts that started there.
			var release := event.duplicate() as InputEventScreenTouch
			release.canceled = true
			event = release
	var local: Vector2 = valley.get_global_transform_with_canvas().affine_inverse() * event.position
	if valley.touch_input(event, local):
		hud.touch_controls = true
		get_viewport().set_input_as_handled()


func _back() -> void:
	if hud.sheet_open():
		_command("close")
	elif selected >= 0:
		_select(-1)
	else:
		_command("observe")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(hud):
		_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(valley):
		valley.cancel_camera_input()
		controller.clear()
		modal_scroll = 0


func _json_value(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = _json_value(value[key])
		return result
	if value is Array or value is PackedInt32Array:
		var result := []
		for item in value:
			result.append(_json_value(item))
		return result
	return value


func _emit_evidence() -> void:
	if evidence_path == "" or simulation == null:
		return
	var temporary := evidence_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write opt-in evidence file: " + evidence_path)
		evidence_path = ""
		return
	var snapshot := _snapshot()
	snapshot["digest"] = simulation.digest()
	snapshot["commands"] = simulation.command_log
	snapshot["input_events"] = session_inputs
	snapshot["paused"] = paused
	snapshot["selected"] = selected
	snapshot["speed"] = speed
	snapshot["replaying"] = replaying
	snapshot["restart_count"] = restart_count
	snapshot["previous_digest"] = previous_digest
	snapshot["tick_on_restart"] = tick_on_restart
	snapshot["summary"] = simulation.summary()
	snapshot["window_size"] = [size.x, size.y]
	snapshot["world_rect"] = [valley.position.x, valley.position.y, valley.size.x, valley.size.y]
	snapshot["fps"] = Engine.get_frames_per_second()
	snapshot["frame_intervals"] = frame_times.report()
	snapshot["renderer"] = RenderingServer.get_current_rendering_method()
	snapshot["handheld"] = handheld
	snapshot["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	snapshot["render_primitives"] = Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
	)
	snapshot["graphics"] = valley.graphics
	snapshot["camera"] = valley.camera_evidence()
	var camera_position: Vector3 = snapshot["camera"]["position"]
	snapshot["camera"]["terrain_clearance"] = (
		camera_position.y - valley.terrain.height_at(Vector2(camera_position.x, camera_position.z))
	)
	var targets := {}
	for entry in [
		["alder", Vector2(240, 340)], ["sedge", Vector2(760, 340)], ["shrine", Vector2(490, 290)]
	]:
		targets[entry[0]] = valley.to_screen(entry[1])
	snapshot["screen_targets"] = targets
	file.store_string(JSON.stringify(_json_value(snapshot)))
	file.close()
	var result := DirAccess.rename_absolute(temporary, evidence_path)
	if result != OK:
		push_warning("Cannot publish evidence: " + error_string(result))
		evidence_path = ""
