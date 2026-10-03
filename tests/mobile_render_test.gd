extends SceneTree
## Run only on a private graphical display. This is not an Android device test.
const Main = preload("res://game/main.gd")
var output := ""
var ui_scale := 1.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			output = argument.trim_prefix("--shots=")
		elif argument.begins_with("--ui-scale="):
			ui_scale = argument.trim_prefix("--ui-scale=").to_float()
	call_deferred("run")


func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.is_empty() or image.save_png(output.path_join(name + ".png")) != OK:
		push_error("Cannot capture the real Mobile renderer")
		quit(1)


func run() -> void:
	if output == "" or RenderingServer.get_current_rendering_method() != "mobile":
		push_error("A shot directory and actual Mobile renderer are required")
		quit(1)
		return
	root.content_scale_factor = ui_scale
	var game := Main.new()
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for frame in range(20):
		await process_frame
	await capture("intro")
	game._command("begin")
	game._command("pause")
	for frame in range(8):
		await process_frame
	await capture("valley")
	game.hud.show_controls()
	await capture("controls")
	var file := FileAccess.open(output.path_join("render.json"), FileAccess.WRITE)
	(
		file
		. store_string(
			(
				JSON
				. stringify(
					{
						"renderer": RenderingServer.get_current_rendering_method(),
						"adapter": RenderingServer.get_video_adapter_name(),
						"window": [root.size.x, root.size.y],
						"logical_canvas": [game.size.x, game.size.y],
						"ui_scale": ui_scale,
						"people": game.valley.people.size(),
						"android_device": false,
					},
					"\t"
				)
			)
		)
	)
	if game.valley.people.size() != 24:
		push_error("Mobile scene does not contain all 24 people")
		quit(1)
	else:
		print("MOBILE_RENDER_PASS %s" % output)
		quit(0)
