extends SceneTree
const Valley = preload("res://game/valley.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func person(id: int, pos: Vector2) -> Dictionary:
	return {
		"id": id,
		"village": 0,
		"pos": pos,
		"action": "rest",
		"carried_food": 0.0,
		"carried_water": 0.0
	}


func point_camera(view: Control, from: Vector3, target: Vector3) -> void:
	view.rig.camera.global_position = from
	view.rig.camera.look_at(target)
	view.cursor = view.rig.camera.unproject_position(target)


func run() -> void:
	root.size = Vector2i(960, 640)
	var view := Valley.new()
	root.add_child(view)
	view.size = Vector2(960, 640)
	view.motion = false
	view.camera_input_enabled = false
	var people := [person(0, Vector2(500, 500)), person(1, Vector2(700, 500))]
	view.set_state(
		{
			"tick": 0,
			"people": people,
			"villages": [],
			"caches": [],
			"events": [],
			"well_water": 160.0
		}
	)
	await process_frame
	await process_frame
	await physics_frame
	await physics_frame
	var target: Vector3 = view.people[0].focus_point()
	point_camera(view, target + Vector3(0, .1, 5), target)
	check(view.person_at_pointer() == 0, "visible person is picked by a real 3D ray")
	people[1].pos = Vector2(500, 520)
	await process_frame
	await physics_frame
	await physics_frame
	target = view.people[0].focus_point()
	point_camera(view, target + Vector3(0, .1, 5), target)
	check(view.person_at_pointer() == 1, "overlapping people pick the nearest visible body")
	people[1].pos = Vector2(700, 500)
	var cottage: Node3D = view.terrain.get_node("LimestoneCottage")
	var hidden: Vector3 = cottage.global_transform * Vector3(0, 0, -3.5)
	people[0].pos = view.simulation_position(hidden)
	await process_frame
	await physics_frame
	await physics_frame
	target = view.people[0].focus_point()
	var front: Vector3 = cottage.global_transform * Vector3(0, 2, 8)
	point_camera(view, front, target)
	check(view.person_at_pointer() == -1, "an opaque cottage blocks selection of the hidden person")
	people[0].pos = Vector2(500, 320)
	await process_frame
	await physics_frame
	await physics_frame
	target = view.people[0].focus_point()
	var terrain_case := false
	for xz in [
		Vector2(-80, -50), Vector2(70, -55), Vector2(0, -80), Vector2(65, 35), Vector2(-65, 40)
	]:
		var from := Vector3(xz.x, view.terrain.height_at(xz) + .65, xz.y)
		var blocked := false
		for index in range(1, 60):
			var sample := from.lerp(target, index / 60.0)
			if sample.y + .2 < view.terrain.height_at(Vector2(sample.x, sample.z)):
				blocked = true
		if not blocked:
			continue
		terrain_case = true
		point_camera(view, from, target)
		check(
			view.person_at_pointer() == -1,
			"real intervening terrain blocks a hidden person's capsule"
		)
		break
	check(terrain_case, "the terrain occlusion fixture actually has an intervening ridge")
	view.queue_free()
	await process_frame
	print("PICKING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
