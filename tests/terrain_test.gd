extends SceneTree
const Terrain = preload("res://game/terrain.gd")
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
	seed(8181)
	var expected := randf()
	seed(8181)
	var terrain := Terrain.new()
	check(randf() == expected, "terrain construction does not consume global randomness")
	var other := Terrain.new()
	var stable := true
	for x in range(-120, 121, 6):
		for z in range(-90, 91, 6):
			var point := Vector2(x, z)
			stable = (
				stable
				and is_finite(terrain.height_at(point))
				and terrain.height_at(point) == other.height_at(point)
			)
	check(stable, "terrain height is finite and deterministic before entering a scene")
	other.free()
	var villages := [{"crop": 25.0}, {"crop": 100.0}]
	var saved := villages.duplicate(true)
	terrain.update_resources(villages, 0.0)
	terrain.set_wetness(Vector2(-26, 2), .7)
	root.add_child(terrain)
	await process_frame
	check(villages == saved, "terrain resource display does not mutate model dictionaries")
	var water := terrain.get_node("FiniteWellWaterLevel") as MeshInstance3D
	check(not water.visible, "an empty well has no rendered water surface")
	var crop := terrain.get_node("LivingCropAlder") as MultiMeshInstance3D
	check(
		is_equal_approx(crop.material_override.get_shader_parameter("vitality"), .25),
		"crop display reflects actual model vitality"
	)
	var ground := terrain.get_node("ValleyHeightfield") as MeshInstance3D
	check(
		is_equal_approx(ground.material_override.get_shader_parameter("rain_strength"), .7),
		"rain changes the actual ground material"
	)
	terrain.set_wetness(Vector2.ZERO, 0.0)
	check(
		is_equal_approx(ground.material_override.get_shader_parameter("rain_strength"), 0),
		"reset removes the previous rain's wet appearance"
	)
	terrain.update_resources(villages, 300.0)
	check(water.visible, "a refilled well has a visible water surface")
	check(
		terrain.get_node("TerrainPickingLayer1").collision_layer == 1,
		"terrain provides the declared ground collision layer"
	)
	await physics_frame
	await physics_frame
	for point in [
		Vector2(0, -4), Vector2(-26, 2), Vector2(26, 2), Vector2(0, 8.5), Vector2(42, 20)
	]:
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(point.x, 100, point.y), Vector3(point.x, -20, point.y), 1
		)
		var hit := terrain.get_world_3d().direct_space_state.intersect_ray(ray)
		check(
			not hit.is_empty() and absf(hit.position.y - terrain.height_at(point)) < .1,
			"real ground collision agrees with actor height at %s" % point
		)
	terrain.queue_free()
	await process_frame
	print("TERRAIN: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
