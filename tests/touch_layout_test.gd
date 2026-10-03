extends SceneTree
## Pure layout boundaries plus the actual HUD containers and control targets.
const Main = preload("res://game/main.tscn")
const Layout = preload("res://ui/layout.gd")
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
	for width in [619, 620, 859, 860, 1049, 1050]:
		for height in [499, 500]:
			var extent := Vector2(width, height)
			var plan := Layout.plan(extent, true)
			check(plan.compact == (height < 500 or width < 620), "compact boundary %s" % extent)
			check(plan.extra_inline == (width >= 860), "action overflow boundary %s" % extent)
			check(
				plan.docked == (width >= 1050 and height >= 500),
				"inspector docking boundary %s" % extent
			)
			check(
				Rect2(Vector2.ZERO, extent).encloses(plan.world),
				"world fits at boundary %s" % extent
			)
	var scaled := Transform2D.IDENTITY.scaled(Vector2(3, 3))
	var safe := Layout.safe_rect(Vector2(360, 800), Rect2i(60, 120, 960, 2220), scaled)
	check(
		safe.is_equal_approx(Rect2(20, 40, 320, 740)),
		"safe area converts physical pixels into logical canvas coordinates"
	)
	var translated := scaled
	translated.origin = Vector2(30, 60)
	check(
		Layout.safe_rect(Vector2(360, 800), Rect2i(60, 120, 960, 2220), translated).is_equal_approx(
			Rect2(10, 20, 320, 740)
		),
		"safe area also accounts for the canvas origin"
	)
	check(
		Layout.safe_rect(Vector2(360, 800), Rect2i(), scaled) == Rect2(0, 0, 360, 800),
		"an unavailable safe area preserves the full container"
	)
	check(
		(
			Layout.safe_rect(Vector2(360, 800), Rect2i(-100, -100, 2000, 4000), scaled)
			== Rect2(0, 0, 360, 800)
		),
		"a safe area cannot exceed the container"
	)
	var game = Main.instantiate()
	game.intro = false
	game.muted = true
	root.add_child(game)
	await process_frame
	for extent in [
		Vector2i(380, 860),
		Vector2i(740, 980),
		Vector2i(980, 740),
		Vector2i(320, 240),
		Vector2i(1280, 300)
	]:
		root.size = extent
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(extent))
		var last := Rect2()
		for button in [
			game.hud.buttons.observe,
			game.hud.buttons.rain,
			game.hud.buttons.food,
			game.hud.buttons.pause,
			game.hud.menu
		]:
			var hit: Rect2 = button.get_global_rect()
			check(
				hit.size.x >= 48 and hit.size.y >= 48,
				"%s keeps a 48-pixel target at %s" % [button.text, extent]
			)
			check(bounds.encloses(hit), "%s stays in the container at %s" % [button.text, extent])
			check(not last.intersects(hit), "adjacent targets do not overlap at %s" % extent)
			last = hit
		game.hud.show_controls()
		await process_frame
		await process_frame
		check(
			bounds.encloses(game.hud.sheet_box.get_global_rect()),
			"controls sheet fits at %s" % extent
		)
		var scrolls: Array[Node] = game.hud.sheet_box.find_children(
			"*", "ScrollContainer", true, false
		)
		check(
			scrolls.size() == 1 and scrolls[0].size.y >= 48,
			"overflow actions have a readable scroll area at %s" % extent
		)
		var close: Button = game.hud.sheet_box.get_child(0).get_child(0).get_child(0).get_child(1)
		check(
			bounds.encloses(close.get_global_rect()),
			"the controls close target fits at %s" % extent
		)
		game.hud.command.emit("close")
	game.queue_free()
	await process_frame
	print("TOUCH LAYOUT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
