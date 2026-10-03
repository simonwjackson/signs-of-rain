extends SceneTree
## Graphics presets change rendering cost only. They never touch the simulation.
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


func run() -> void:
	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var game = Main.instantiate()
	game.muted = true
	game.intro = false
	root.add_child(game)
	await process_frame
	await process_frame
	var view: Control = game.valley
	var before: String = game.simulation.digest()
	view.set_graphics("fast")
	check(view.graphics == "fast", "fast preset is reported")
	check(view.viewport.msaa_3d == Viewport.MSAA_DISABLED, "fast preset drops 4x MSAA")
	check(
		view.viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR,
		"fast preset uses FSR upscaling"
	)
	check(view.viewport.scaling_3d_scale < 1.0, "fast preset renders 3D below window resolution")
	check(not view.environment.ssil_enabled, "fast preset disables screen-space indirect light")
	check(not view.environment.volumetric_fog_enabled, "fast preset disables volumetric fog")
	check(view.environment.fog_enabled, "fast preset keeps distance fog for depth")
	check(view.sunlight.shadow_enabled, "fast preset keeps sun shadows")
	check(
		view.sunlight.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"fast preset uses two shadow cascades"
	)
	check(game.simulation.digest() == before, "changing graphics never changes simulation state")
	view.set_graphics("high")
	check(view.viewport.msaa_3d == Viewport.MSAA_4X, "high preset restores 4x MSAA")
	check(view.viewport.scaling_3d_scale == 1.0, "high preset renders at full resolution")
	check(
		view.environment.ssil_enabled and view.environment.volumetric_fog_enabled,
		"high preset restores full lighting"
	)
	check(
		view.sunlight.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"high preset restores four shadow cascades"
	)
	view.set_graphics("unknown")
	check(view.graphics == "high", "an unknown preset keeps a valid preset")
	game.hud.command.emit("graphics")
	check(view.graphics == "fast", "the menu command toggles faster graphics")
	var stored := ConfigFile.new()
	check(
		(
			stored.load("user://settings.cfg") == OK
			and stored.get_value("graphics", "preset", "") == "fast"
		),
		"the chosen preset persists across launches"
	)
	game.hud.command.emit("graphics")
	check(view.graphics == "high", "the menu command toggles back to full graphics")
	game.queue_free()
	await process_frame
	if not had_settings:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("GRAPHICS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
