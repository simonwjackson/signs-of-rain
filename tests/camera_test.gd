extends SceneTree
const GodCamera = preload("res://game/god_camera.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func height_at(point: Vector2) -> float:
	return 1.0 + sin(point.x * .04) * .3 + cos(point.y * .03) * .2


func settle(rig: Node3D) -> void:
	for i in range(120):
		rig.advance(1.0 / 60.0)


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var rig := GodCamera.new(height_at)
	viewport.add_child(rig)
	rig.input_enabled = false
	await process_frame
	check(
		rig.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "world uses a perspective camera"
	)
	var initial := rig.distance
	rig.focus_person(Vector3(20, height_at(Vector2(20, 0)) + 1.45, 0), 0)
	rig.advance(.016)
	check(
		rig.distance < initial and rig.distance > 1.6,
		"close-view motion interpolates instead of teleporting"
	)
	settle(rig)
	check(absf(rig.distance - 1.6) < .001, "close view frames a human-scale portrait")
	check(
		absf(rig.target.y - height_at(Vector2(20, 0)) - 1.45) < .001,
		"close focus follows the person's head height"
	)
	rig.orbit(Vector2(0, 1000))
	var high_tilt: float = rig.wanted_pitch
	rig.zoom(1, rig.target)
	check(absf(rig.wanted_pitch - high_tilt) < 1, "one zoom step preserves the maximum manual tilt")
	rig.orbit(Vector2(0, -1000))
	var low_tilt: float = rig.wanted_pitch
	rig.zoom(-1, rig.target)
	check(absf(rig.wanted_pitch - low_tilt) < 1, "one zoom step preserves the minimum manual tilt")
	rig.focus_person(Vector3(20, height_at(Vector2(20, 0)) + 1.45, 0), 0)
	rig.zoom(-100, rig.target)
	settle(rig)
	check(absf(rig.distance - .85) < .001, "wheel zoom reaches face-scale viewing")
	check(
		(
			rig.camera.position.y
			>= height_at(Vector2(rig.camera.position.x, rig.camera.position.z)) + .49
		),
		"camera remains above the terrain"
	)
	rig.zoom(100, rig.target)
	settle(rig)
	check(absf(rig.distance - 180.0) < .001, "wheel zoom reaches the entire landscape")
	rig.orbit(Vector2(240, 240))
	settle(rig)
	check(rig.pitch <= 82.0 and rig.pitch >= 8.0, "orbit tilt stays within safe bounds")
	check(absf(rig.yaw - .38) > .1, "orbit changes the real camera azimuth")
	rig.pan(Vector2(1000, -1000))
	settle(rig)
	check(
		absf(rig.target.x) <= 65 and absf(rig.target.z) <= 45,
		"panning stays within reachable terrain"
	)
	check(not rig.following, "panning releases person-follow mode")
	rig.overview()
	settle(rig)
	for point in [Vector2(-26, 2), Vector2(26, 2), Vector2(0, -4)]:
		var world := Vector3(point.x, height_at(point), point.y)
		var pixel := rig.camera.unproject_position(world)
		var hit: Vector3 = rig.ground_under(pixel)
		check(
			hit.distance_to(world) < .025,
			"camera-ray picking returns the real ground at %s" % point
		)
	viewport.queue_free()
	await process_frame
	print("CAMERA: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
