extends SceneTree
## Opt-in actual GLES rendering under an owned display, never an FPS benchmark.
const Main = preload("res://game/main.tscn")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var output := OS.get_environment("SIGNS_RENDER_OUTPUT")
	if output == "":
		printerr("Set SIGNS_RENDER_OUTPUT to an owned capture directory")
		quit(1)
		return
	var game = Main.instantiate()
	game.intro = false
	game.muted = true
	root.add_child(game)
	game.valley.set_graphics("fast")
	game.valley.set_handheld(true)
	game.valley.controller_aim = true
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join("overview.png")
	if root.get_texture().get_image().save_png(path) != OK:
		quit(1)
		return
	game._select(0)
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("inspector.png"))
	game.hud.show_controls()
	game.controller_active = true
	game.hud.focus_sheet()
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("controls.png"))
	print(
		(
			"GLES RENDER: renderer=%s, people=%d, viewport=%s"
			% [
				RenderingServer.get_current_rendering_method(),
				game.valley.people.size(),
				game.valley.viewport.size
			]
		)
	)
	game.queue_free()
	await process_frame
	quit(0)
