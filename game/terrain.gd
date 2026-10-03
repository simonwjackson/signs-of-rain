extends Node3D
# gdlint: disable=max-file-lines
# This is one authored procedural scene asset, not a general runtime subsystem.
## Authored, deterministic landscape. X/Z are meters; simulation remains untouched.
## height_at() is pure and safe directly after new(), including before _ready().
## Resource inputs use simulation ranges: crop 0..100, well_water 0..300.

const GROUND_SHADER = preload("res://game/materials/terrain.gdshader")
const SURFACE_SHADER = preload("res://game/materials/environment.gdshader")
const FOLIAGE_SHADER = preload("res://game/materials/foliage.gdshader")
const WATER_SHADER = preload("res://game/materials/water.gdshader")
const GRID_STEP = 0.75
const GRID_X = 321
const GRID_Z = 241
const POOLS = [
	Vector3(-24, 12, 0.08), Vector3(22, 10, 0.06), Vector3(45, 8, 0.08), Vector3(-51, 7, 0.08)
]

var _decor := RandomNumberGenerator.new()
var _relief_noise := _make_relief_noise()
var _ground_material: ShaderMaterial
var _water_material: ShaderMaterial
var _crop_materials: Array[ShaderMaterial] = []
var _well_surface: MeshInstance3D
var _well_base_y := 0.0
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _box_mesh: BoxMesh
var _stone_mesh: ArrayMesh
var _pending_villages: Array = []
var _pending_water := 160.0
var _wet_point := Vector2.ZERO
var _wet_strength := 0.0
var _built := false


func height_at(point: Vector2) -> float:
	var ground := _base_height_at(point)
	for pool: Vector3 in POOLS:
		var along := (point.y - pool.x) / (pool.y * 0.5)
		if absf(along) > 1.3:
			continue
		var across := (point.x - _river_x(point.y)) / 1.8
		var radius_squared := along * along + across * across
		if radius_squared < 1.6:
			var level := _base_height_at(Vector2(_river_x(pool.x), pool.x)) + pool.z
			var basin := level - 0.28 + radius_squared * radius_squared * 0.6
			ground = lerpf(ground, basin, 1.0 - smoothstep(0.8, 1.6, radius_squared))
	return ground


func _base_height_at(point: Vector2) -> float:
	var x := point.x
	var z := point.y
	# Relief levels out beyond the detailed valley instead of becoming a bowl.
	var far_x := maxf(absf(x) - 110.0, 0.0)
	var far_z := maxf(absf(z) - 80.0, 0.0)
	var hill_x := minf(absf(x), 110.0) + far_x / (1.0 + far_x / 65.0)
	var hill_z := minf(absf(z), 80.0) + far_z / (1.0 + far_z / 65.0)
	var edge_x := maxf(hill_x - 39.0, 0.0)
	var edge_z := maxf(hill_z - 25.0, 0.0)
	var hills := edge_x * edge_x * 0.0042 + edge_z * edge_z * 0.0048
	hills *= 0.79 + 0.48 * _relief_noise.get_noise_2d(x, z)
	hills += 13.0 * exp(-((x + 65.0) * (x + 65.0) / 650.0 + (z + 46.0) * (z + 46.0) / 380.0))
	hills += 18.0 * exp(-((x - 63.0) * (x - 63.0) / 580.0 + (z + 54.0) * (z + 54.0) / 410.0))
	var undulation := sin(x * 0.084 + z * 0.039) * 0.75 + cos(z * 0.11 - x * 0.027) * 0.48
	var detail := sin(x * 0.63 + z * 0.31) * 0.075 + sin(x * 1.71 - z * 0.94) * 0.025
	var village_distance := minf(
		point.distance_to(Vector2(-26, 2)), point.distance_to(Vector2(26, 2))
	)
	var clearing := 1.0 - smoothstep(9.0, 18.0, village_distance)
	var ground := lerpf(hills + undulation, 0.35, clearing * 0.94) + detail
	var river_distance := absf(x - _river_x(z))
	ground -= exp(-river_distance * river_distance / 7.5) * 0.85
	return ground


func update_resources(villages: Array, well_water: float) -> void:
	_pending_villages = villages.duplicate(true)
	_pending_water = clampf(well_water, 0.0, 300.0)
	if not _built:
		return
	for i in range(mini(2, villages.size())):
		var crop := clampf(float(villages[i].get("crop", 76.0)) / 100.0, 0.0, 1.0)
		_crop_materials[i].set_shader_parameter("vitality", crop)
	if is_instance_valid(_well_surface):
		_well_surface.position.y = _well_base_y + 0.12 + 0.62 * _pending_water / 300.0
		_well_surface.visible = _pending_water > 0.01


func set_wetness(point: Vector2, strength: float) -> void:
	_wet_point = point
	_wet_strength = clampf(strength, 0.0, 1.0)
	if _ground_material:
		_ground_material.set_shader_parameter("rain_center", point)
		_ground_material.set_shader_parameter("rain_strength", _wet_strength)


func _ready() -> void:
	_decor.seed = 0x56414C4C4559  # Decor RNG never shares state with the model.
	_make_materials()
	_build_ground()
	_build_horizon()
	_build_watercourse()
	_build_villages()
	_build_shrine()
	_build_well()
	_build_fields()
	_build_vegetation()
	_build_stones()
	_flush_batches()
	_built = true
	update_resources(_pending_villages, _pending_water)
	set_wetness(_wet_point, _wet_strength)


static func _make_relief_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = 572903
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.014
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.42
	return noise


func _river_x(z: float) -> float:
	return 7.0 + sin(z * 0.061) * 7.0 + sin(z * 0.14) * 1.8


func _surface(
	color: Color, texture_scale: float = 8.0, variation: float = 0.3, grain: float = 0.0
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("texture_scale", texture_scale)
	material.set_shader_parameter("variation", variation)
	material.set_shader_parameter("grain_direction", grain)
	return material


func _make_materials() -> void:
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GROUND_SHADER
	_water_material = ShaderMaterial.new()
	_water_material.shader = WATER_SHADER
	_materials["stone"] = _surface(Color("8d8c79"), 6.0, 0.48)
	_materials["chalk"] = _surface(Color("c2baa0"), 9.0, 0.3)
	_materials["plaster"] = _surface(Color("cec4a8"), 12.0, 0.19)
	_materials["plaster_warm"] = _surface(Color("bdb299"), 12.0, 0.22)
	_materials["wood"] = _surface(Color("62523b"), 5.0, 0.52, 0.85)
	_materials["wood_dark"] = _surface(Color("3c392c"), 6.0, 0.45, 0.85)
	_materials["roof"] = _surface(Color("80634d"), 16.0, 0.32)
	_materials["roof_slate"] = _surface(Color("606d69"), 18.0, 0.32)
	_materials["soil"] = _surface(Color("5f5239"), 12.0, 0.55)
	_materials["dark"] = _surface(Color("252c26"), 4.0, 0.2)
	_materials["cloth"] = _surface(Color("627c77"), 18.0, 0.12)
	_materials["clay"] = _surface(Color("947453"), 12.0, 0.3)
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_stone_mesh = _make_stone_mesh()


func _build_ground() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var heights := PackedFloat32Array()
	vertices.resize(GRID_X * GRID_Z)
	normals.resize(GRID_X * GRID_Z)
	uvs.resize(GRID_X * GRID_Z)
	heights.resize(GRID_X * GRID_Z)
	for iz in range(GRID_Z):
		for ix in range(GRID_X):
			var p := Vector2(ix * GRID_STEP - 120.0, iz * GRID_STEP - 90.0)
			var index := iz * GRID_X + ix
			var y := height_at(p)
			vertices[index] = Vector3(p.x, y, p.y)
			heights[index] = y
			normals[index] = (
				Vector3(
					height_at(p - Vector2(0.15, 0)) - height_at(p + Vector2(0.15, 0)),
					0.3,
					height_at(p - Vector2(0, 0.15)) - height_at(p + Vector2(0, 0.15))
				)
				. normalized()
			)
			uvs[index] = p * 0.1
			if ix < GRID_X - 1 and iz < GRID_Z - 1:
				indices.append_array(
					PackedInt32Array(
						[
							index,
							index + 1,
							index + GRID_X,
							index + 1,
							index + GRID_X + 1,
							index + GRID_X
						]
					)
				)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_add_mesh(mesh, _ground_material, self, "ValleyHeightfield")
	var body := StaticBody3D.new()
	body.name = "TerrainPickingLayer1"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = GRID_X
	shape.map_depth = GRID_Z
	shape.map_data = heights
	collider.shape = shape
	collider.scale = Vector3(GRID_STEP, 1.0, GRID_STEP)
	body.add_child(collider)
	add_child(body)


func _build_horizon() -> void:
	# A coarse, continuous outer apron hides the rectangular valley mesh edge.
	# Only the central 240 x 180 m has the detailed layer-1 picking collider.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(192):
		for ix in range(240):
			var x := ix * 3.0 - 360.0
			var z := iz * 3.0 - 288.0
			if x >= -120 and x < 120 and z >= -90 and z < 90:
				continue
			var a := Vector3(x, height_at(Vector2(x, z)), z)
			var b := Vector3(x + 3, height_at(Vector2(x + 3, z)), z)
			var c := Vector3(x, height_at(Vector2(x, z + 3)), z + 3)
			var d := Vector3(x + 3, height_at(Vector2(x + 3, z + 3)), z + 3)
			_triangle(st, a, c, b)
			_triangle(st, b, c, d)
	st.generate_normals()
	_add_mesh(st.commit(), _ground_material, self, "DistantValleyHorizon")


func _build_watercourse() -> void:
	# Separate shallow pools leave most of the drought channel exposed. Each pool
	# has a horizontal free surface and a bank-conforming, irregular shoreline.
	for spec: Vector3 in POOLS:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var center := Vector2(_river_x(spec.x), spec.x)
		var level: float = _base_height_at(center) + spec.z
		for row in range(64):
			var z0: float = spec.x - spec.y * 0.5 + spec.y * row / 64.0
			var z1: float = spec.x - spec.y * 0.5 + spec.y * (row + 1) / 64.0
			var w0 := sin(PI * float(row) / 64.0) * 1.72
			var w1 := sin(PI * float(row + 1) / 64.0) * 1.72
			var a := Vector3(_river_x(z0) - w0, level, z0)
			var b := Vector3(_river_x(z0) + w0, level, z0)
			var c := Vector3(_river_x(z1) - w1, level, z1)
			var d := Vector3(_river_x(z1) + w1, level, z1)
			_triangle(st, a, c, b)
			_triangle(st, b, c, d)
		st.generate_normals()
		_add_mesh(st.commit(), _water_material, self, "RemainingStreamPool")
	# Low ford stones are outside the villagers' main east/west walking line.
	for i in range(8):
		var p := Vector2(_river_x(15.0) - 2.4 + i * 0.65, 15.0)
		_stone(
			Vector3(p.x, height_at(p) + 0.03, p.y), Vector3(0.48, 0.16, 0.36), _materials["stone"]
		)


func _build_villages() -> void:
	for village in range(2):
		var cx := -26.0 if village == 0 else 26.0
		for i in range(3):
			var p := Vector2(cx + (i - 1) * 7.8, -11.5 - (1.5 if i == 1 else 0.0))
			_cottage(p, 0.04 * (i - 1), village, 0.91 + i * 0.07)
		var outer_x := cx + (-15.0 if village == 0 else 15.0)
		_cottage(Vector2(outer_x, -3.7), -0.14 if village == 0 else 0.14, village, 0.85)
		# Low dry-stone garden walls live behind houses, never across home routes.
		for i in range(32):
			var p := Vector2(cx - 12.0 + i * 0.77, -17.1)
			for course in range(2):
				_stone(
					Vector3(p.x, height_at(p) + 0.18 + course * 0.30, p.y),
					Vector3(0.42, 0.22, 0.34),
					_materials["stone"]
				)


func _cottage(point: Vector2, angle: float, village: int, size_factor: float) -> void:
	var root := Node3D.new()
	root.name = "LimestoneCottage"
	root.position = Vector3(point.x, height_at(point) - 0.08, point.y)
	root.rotation.y = angle
	root.scale = Vector3.ONE * size_factor
	add_child(root)
	var w := 2.6
	var d := 2.15
	# Slightly battered plaster wall surfaces, true gable ends, overhanging tiled roof.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_quad(
		st,
		Vector3(-w, 0.35, d),
		Vector3(w, 0.35, d),
		Vector3(w - 0.06, 3.0, d - 0.05),
		Vector3(-w + 0.06, 3.0, d - 0.05)
	)
	_quad(
		st,
		Vector3(w, 0.35, -d),
		Vector3(-w, 0.35, -d),
		Vector3(-w + 0.06, 3.0, -d + 0.05),
		Vector3(w - 0.06, 3.0, -d + 0.05)
	)
	_quad(
		st,
		Vector3(-w, 0.35, -d),
		Vector3(-w, 0.35, d),
		Vector3(-w + 0.06, 3.0, d),
		Vector3(-w + 0.06, 3.0, -d)
	)
	_quad(
		st,
		Vector3(w, 0.35, d),
		Vector3(w, 0.35, -d),
		Vector3(w - 0.06, 3.0, -d),
		Vector3(w - 0.06, 3.0, d)
	)
	_triangle(st, Vector3(-w + 0.06, 3.0, d), Vector3(w - 0.06, 3.0, d), Vector3(0, 4.65, d))
	_triangle(st, Vector3(w - 0.06, 3.0, -d), Vector3(-w + 0.06, 3.0, -d), Vector3(0, 4.65, -d))
	st.generate_normals()
	_add_mesh(
		st.commit(),
		_materials["plaster" if village == 0 else "plaster_warm"],
		root,
		"LimewashedGables"
	)
	for side in [-1.0, 1.0]:
		for i in range(11):
			if side > 0.0 and absf(-2.4 + i * 0.48 - 0.1) < 0.75:
				continue
			for course in range(2):
				_local_stone(
					root,
					Vector3(-2.4 + i * 0.48, 0.19 + course * 0.26, side * d),
					Vector3(0.29, 0.18, 0.22)
				)
		for i in range(8):
			_local_stone(root, Vector3(side * w, 0.25, -1.8 + i * 0.51), Vector3(0.24, 0.27, 0.30))
		_beam(
			root,
			Vector3(side * 2.53, 0.50, 2.18),
			Vector3(side * 2.53, 3.08, 2.18),
			0.16,
			"wood_dark"
		)
		_beam(root, Vector3(0, 4.6, 2.2), Vector3(side * 2.87, 2.9, 2.2), 0.15, "wood_dark")
		_beam(
			root,
			Vector3(side * 2.77, 2.92, -2.4),
			Vector3(side * 2.77, 2.92, 2.4),
			0.18,
			"wood_dark"
		)
	_beam(root, Vector3(-2.58, 3.02, 2.2), Vector3(2.58, 3.02, 2.2), 0.16, "wood_dark")
	_beam(root, Vector3(0, 3.02, 2.21), Vector3(0, 4.6, 2.21), 0.13, "wood_dark")
	var roof_material: ShaderMaterial = _materials["roof" if village == 0 else "roof_slate"]
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		# Roof thickness and a continuous substrate prevent pinholes between tiles.
		var a := Vector3(0, 4.68, -2.47)
		var b := Vector3(side * 2.91, 2.92, -2.47)
		var c := Vector3(side * 2.91, 2.92, 2.47)
		var e := Vector3(0, 4.68, 2.47)
		if side > 0:
			_quad(roof, a, e, c, b)
		else:
			_quad(roof, a, b, c, e)
	roof.generate_normals()
	_add_mesh(roof.commit(), roof_material, root, "RoofUnderlay")
	# Selection-only occlusion. These bodies never participate in model movement.
	var occluder := StaticBody3D.new()
	occluder.name = "SolidBuildingPickOccluder"
	occluder.collision_layer = 4
	occluder.collision_mask = 0
	for surface in ["LimewashedGables", "RoofUnderlay"]:
		var collision := CollisionShape3D.new()
		collision.shape = root.get_node(surface).mesh.create_trimesh_shape()
		occluder.add_child(collision)
	root.add_child(occluder)
	var tile_mesh := _roof_tile()
	var tile_transforms: Array[Transform3D] = []
	var tile_colors: Array[Color] = []
	for side in [-1.0, 1.0]:
		for row in range(11):
			for column in range(17):
				var x: float = side * (0.05 + row * 0.267)
				var y := 4.72 - absf(x) * 0.605 + 0.018 * sin(column * 2.5 + row)
				# Tile local X runs down the roof; local Z is the gutter direction.
				var basis := Basis(Vector3(0, 0, 1), -side * atan(0.605))
				tile_transforms.append(Transform3D(basis, Vector3(x, y, -2.38 + column * 0.291)))
				tile_colors.append(Color.WHITE * _decor.randf_range(0.83, 1.13))
	_batch(tile_mesh, tile_transforms, tile_colors, roof_material, root, "OverlappingFiredTiles")
	var ridge_transforms: Array[Transform3D] = []
	var ridge_colors: Array[Color] = []
	for i in range(17):
		ridge_transforms.append(Transform3D(Basis.IDENTITY, Vector3(0, 4.76, -2.36 + i * 0.294)))
		ridge_colors.append(Color.WHITE * _decor.randf_range(0.9, 1.1))
	_batch(_roof_ridge_tile(), ridge_transforms, ridge_colors, roof_material, root, "ClayRidgeCaps")
	# A real recess, separate jambs, lintel, door boards and shutter boards read at person scale.
	_local_box(root, Vector3(0.1, 1.28, 2.19), Vector3(1.13, 2.0, 0.13), "dark")
	for i in range(6):
		_local_box(root, Vector3(-0.35 + i * 0.18, 1.23, 2.28), Vector3(0.165, 1.86, 0.055), "wood")
	_local_box(root, Vector3(0.46, 1.22, 2.325), Vector3(0.065, 0.13, 0.04), "dark")
	for x in [-0.52, 0.71]:
		_local_box(root, Vector3(x, 1.28, 2.24), Vector3(0.16, 2.13, 0.22), "chalk")
	_local_box(root, Vector3(0.1, 2.38, 2.24), Vector3(1.45, 0.21, 0.28), "chalk")
	_local_box(root, Vector3(0.1, 0.19, 2.54), Vector3(1.65, 0.20, 0.78), "stone")
	for x in [-1.63, 1.65]:
		_local_box(root, Vector3(x, 1.85, 2.16), Vector3(0.87, 1.01, 0.18), "dark")
		for edge in [-0.49, 0.49]:
			_local_box(root, Vector3(x + edge, 1.85, 2.24), Vector3(0.12, 1.19, 0.19), "wood")
		for y in [1.28, 2.4]:
			_local_box(root, Vector3(x, y, 2.28), Vector3(1.12, 0.13, 0.3), "chalk")
		for board in range(4):
			_local_box(
				root,
				Vector3(x - 0.83 + board * 0.145, 1.84, 2.32),
				Vector3(0.135, 1.05, 0.085),
				"wood"
			)
		_local_box(root, Vector3(x, 1.85, 2.24), Vector3(0.045, 0.93, 0.12), "wood_dark")
	_local_box(root, Vector3(1.43, 4.25, -0.94), Vector3(0.63, 1.57, 0.64), "stone")
	_local_box(root, Vector3(1.43, 5.04, -0.94), Vector3(0.81, 0.16, 0.83), "chalk")
	_local_box(root, Vector3(1.43, 5.13, -0.94), Vector3(0.49, 0.035, 0.47), "dark")
	# Frontage objects stay on the building side of z=-7.5.
	_barrel(root, Vector3(-2.13, 0.52, 2.89), 0.42)
	_barrel(root, Vector3(-1.27, 0.37, 2.93), 0.30)
	_beam(root, Vector3(1.25, 0.52, 2.87), Vector3(2.46, 0.52, 2.87), 0.28, "wood")
	for x in [1.35, 2.34]:
		_local_box(root, Vector3(x, 0.24, 2.87), Vector3(0.16, 0.5, 0.31), "wood_dark")


func _build_shrine() -> void:
	# Simulation destination (0,-4) is the open approach, not inside the altar.
	for ring in range(2):
		for i in range(22):
			var angle := TAU * i / 22.0
			var p := Vector2(cos(angle), sin(angle)) * (1.65 + ring * 0.42) + Vector2(0, -4)
			_stone(
				Vector3(p.x, height_at(p) - 0.04, p.y),
				Vector3(0.31, 0.1, 0.28),
				_materials["chalk"]
			)
	var root := Node3D.new()
	root.name = "OpenShrineApproach"
	root.position = Vector3(0, height_at(Vector2(0, -6.3)), -6.3)
	add_child(root)
	_local_box(root, Vector3(0, 0.24, 0), Vector3(2.4, 0.38, 1.15), "stone")
	_local_box(root, Vector3(0, 0.49, 0), Vector3(2.1, 0.16, 1.03), "chalk")
	for side in [-1.0, 1.0]:
		var column := CylinderMesh.new()
		column.top_radius = 0.20
		column.bottom_radius = 0.25
		column.height = 2.15
		column.radial_segments = 16
		var node := _add_mesh(column, _materials["chalk"], root, "WeatheredShrineColumn")
		node.position = Vector3(side * 0.83, 1.6, -0.18)
		_local_box(root, Vector3(side * 0.83, 2.75, -0.18), Vector3(0.62, 0.18, 0.63), "stone")
	_local_box(root, Vector3(0, 2.97, -0.18), Vector3(2.66, 0.29, 0.77), "chalk")
	_local_box(root, Vector3(0, 3.17, -0.18), Vector3(2.85, 0.12, 0.88), "stone")
	# Carved stone votive, not a glowing UI marker.
	_local_stone(root, Vector3(0, 1.08, 0), Vector3(0.24, 0.56, 0.23))
	_local_stone(root, Vector3(0, 1.73, 0), Vector3(0.18, 0.22, 0.17))
	var bowl := TorusMesh.new()
	bowl.inner_radius = 0.19
	bowl.outer_radius = 0.30
	bowl.rings = 24
	bowl.ring_segments = 10
	var bowl_node := _add_mesh(bowl, _materials["clay"], root, "OfferingBowl")
	bowl_node.position = Vector3(0, 0.68, 0.37)


func _build_well() -> void:
	# Collection point is (0,8.5). Basin is beside it so villagers never enter stone.
	var point := Vector2(0, 10.5)
	_well_base_y = height_at(point)
	for course in range(4):
		for i in range(18):
			var angle := TAU * (i + 0.5 * (course % 2)) / 18.0
			var p := point + Vector2(cos(angle), sin(angle)) * 0.93
			var basis := Basis(Vector3.UP, -angle).scaled(Vector3(0.30, 0.16, 0.22))
			_queue_mesh(
				_stone_mesh,
				_materials["chalk" if course == 3 else "stone"],
				Transform3D(basis, Vector3(p.x, _well_base_y + 0.13 + course * 0.23, p.y))
			)
	var disk := CylinderMesh.new()
	disk.top_radius = 0.73
	disk.bottom_radius = 0.73
	disk.height = 0.018
	disk.radial_segments = 48
	_well_surface = _add_mesh(disk, _water_material, self, "FiniteWellWaterLevel")
	_well_surface.position = Vector3(point.x, _well_base_y + 0.45, point.y)
	var root := Node3D.new()
	root.name = "SharedWellWindlass"
	root.position = Vector3(point.x, _well_base_y, point.y)
	add_child(root)
	for side in [-1.0, 1.0]:
		_beam(root, Vector3(side * 1.19, 0, 0), Vector3(side * 1.19, 2.45, 0), 0.15, "wood_dark")
	_beam(root, Vector3(-1.39, 2.4, 0), Vector3(1.39, 2.4, 0), 0.17, "wood")
	_beam(root, Vector3(0, 0.65, 0), Vector3(0, 2.42, 0), 0.023, "wood")
	_barrel(root, Vector3(1.53, 0.23, -0.44), 0.21)


func _build_fields() -> void:
	var crop_mesh := _make_grass_mesh(true)
	for village in range(2):
		var cx := -26.0 if village == 0 else 26.0
		var material := ShaderMaterial.new()
		material.shader = FOLIAGE_SHADER
		material.set_shader_parameter("dry_color", Color("a08a50"))
		material.set_shader_parameter("fresh_color", Color("9a9a51"))
		material.set_shader_parameter("vitality", 0.76)
		material.set_shader_parameter("crop_mode", 1.0)
		material.set_shader_parameter("wind_strength", 0.075)
		_crop_materials.append(material)
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		# Southern field per direction; north kitchen beds match actual sim jobs.
		for field_center in [Vector2(cx, 11.6), Vector2(cx, -2.2)]:
			var south: bool = field_center.y > 0
			var rows := 12 if south else 6
			var columns := 29 if south else 20
			for row in range(rows):
				for column in range(columns):
					var p: Vector2 = (
						field_center
						+ Vector2((column - columns * 0.5) * 0.34, (row - rows * 0.5) * 0.51)
					)
					p += Vector2(_decor.randf_range(-0.07, 0.07), _decor.randf_range(-0.055, 0.055))
					var s := _decor.randf_range(0.75, 1.12)
					var basis := Basis(Vector3.UP, _decor.randf_range(0, TAU)).scaled(
						Vector3(s, s, s)
					)
					transforms.append(Transform3D(basis, Vector3(p.x, height_at(p) + 0.025, p.y)))
					colors.append(Color(_decor.randf_range(0.3, 0.95), 1, 1))
				# Low furrows follow the terrain, with no raised fence across movement.
				for segment in range(columns / 2):
					var p: Vector2 = (
						field_center
						+ Vector2((segment * 2 - columns * 0.5) * 0.34, (row - rows * 0.5) * 0.51)
					)
					_queue_mesh(
						_stone_mesh,
						_materials["soil"],
						Transform3D(
							Basis.IDENTITY.scaled(Vector3(0.41, 0.035, 0.18)),
							Vector3(p.x, height_at(p), p.y)
						)
					)
		_batch(
			crop_mesh,
			transforms,
			colors,
			material,
			self,
			"LivingCropAlder" if village == 0 else "LivingCropSedge"
		)


func _build_vegetation() -> void:
	var grass_material := ShaderMaterial.new()
	grass_material.shader = FOLIAGE_SHADER
	grass_material.set_shader_parameter("dry_color", Color("958555"))
	grass_material.set_shader_parameter("fresh_color", Color("727e47"))
	grass_material.set_shader_parameter("vitality", 0.28)
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in range(42000):
		var p := Vector2(_decor.randf_range(-104, 104), _decor.randf_range(-77, 77))
		if i > 21000:
			p = Vector2(_decor.randf_range(-54, 54), _decor.randf_range(-33, 35))
		if _is_corridor(p, 1.6) or absf(p.x - _river_x(p.y)) < 3.0:
			continue
		if _near_building(p) or _is_field(p):
			continue
		var density := (sin(p.x * 0.29) * cos(p.y * 0.33) + 1.0) * 0.5
		if _decor.randf() > 0.32 + density * 0.64:
			continue
		var s := _decor.randf_range(0.6, 1.35)
		var basis := Basis(Vector3.UP, _decor.randf_range(0, TAU)).scaled(
			Vector3(s, s * _decor.randf_range(0.6, 1.0), s)
		)
		transforms.append(Transform3D(basis, Vector3(p.x, height_at(p), p.y)))
		colors.append(Color(_decor.randf_range(0.25, 1.0), 1, 1))
	_spatial_batch(
		_make_grass_mesh(false), transforms, colors, grass_material, "InstancedDryMeadow", false
	)
	var leaf_material := ShaderMaterial.new()
	leaf_material.shader = FOLIAGE_SHADER
	leaf_material.set_shader_parameter("dry_color", Color("687148"))
	leaf_material.set_shader_parameter("fresh_color", Color("768566"))
	leaf_material.set_shader_parameter("vitality", 0.8)
	leaf_material.set_shader_parameter("wind_strength", 0.035)
	var leaf_transforms: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var trunk_transforms: Array[Transform3D] = []
	var trunk_colors: Array[Color] = []
	var trees: Array[Vector2] = [
		Vector2(-41, -19),
		Vector2(-12, -17),
		Vector2(13, -19),
		Vector2(41, -20),
		Vector2(-43, 17),
		Vector2(46, 15),
		Vector2(-15, 27),
		Vector2(26, 28)
	]
	for i in range(105):
		var p := Vector2(_decor.randf_range(-105, 105), _decor.randf_range(-77, 77))
		if absf(p.x) < 48.0 and p.y > -28.0 and p.y < 35.0:
			continue
		if absf(p.x - _river_x(p.y)) < 4.0:
			continue
		trees.append(p)
	for p in trees:
		var s := _decor.randf_range(0.8, 1.5)
		var rotation_y := _decor.randf_range(0, TAU)
		var base := Transform3D(
			Basis(Vector3.UP, rotation_y).scaled(Vector3.ONE * s),
			Vector3(p.x, height_at(p) - 0.07, p.y)
		)
		trunk_transforms.append(base)
		trunk_colors.append(Color.WHITE)
		# Irregular flattened olive crowns; each sprig is seven curved pointed leaves.
		for i in range(330):
			var azimuth := _decor.randf_range(0, TAU)
			var radial := sqrt(_decor.randf()) * 2.65
			var branch := int(i % 5)
			var branch_angle := TAU * branch / 5.0
			var center := Vector3(
				cos(branch_angle) * 0.85,
				3.6 + sin(branch_angle * 2.0) * 0.45,
				sin(branch_angle) * 0.85
			)
			var offset := Vector3(
				cos(azimuth) * radial,
				_decor.randf_range(-0.65, 0.75) * sqrt(maxf(0.0, 1.0 - radial / 3.0)),
				sin(azimuth) * radial
			)
			var leaf_basis := (
				Basis
				. from_euler(
					Vector3(_decor.randf_range(-0.65, 0.65), azimuth, _decor.randf_range(-0.6, 0.6))
				)
				. scaled(Vector3.ONE * _decor.randf_range(0.85, 1.6))
			)
			leaf_transforms.append(base * Transform3D(leaf_basis, center + offset))
			leaf_colors.append(Color(_decor.randf_range(0.3, 1.0), 1, 1))
	_spatial_batch(
		_make_tree_trunk(), trunk_transforms, trunk_colors, _materials["wood"], "GnarledOliveTrunks"
	)
	_spatial_batch(
		_make_leaf_sprig(), leaf_transforms, leaf_colors, leaf_material, "SilverOliveCanopies"
	)


func _build_stones() -> void:
	for i in range(950):
		var p := Vector2(_decor.randf_range(-113, 113), _decor.randf_range(-84, 84))
		var river_bank := absf(p.x - _river_x(p.y))
		if _is_corridor(p, 2.0) or _near_building(p) or _is_field(p):
			continue
		if absf(p.x) < 43.0 and absf(p.y) < 28.0 and river_bank > 4.5:
			continue
		var s := _decor.randf_range(0.2, 1.35)
		if river_bank < 4.5:
			s *= 0.45
		_stone(
			Vector3(p.x, height_at(p) - s * 0.12, p.y),
			Vector3(s, s * 0.68, s * 0.85),
			_materials["stone"]
		)
	# Pebbles add scale at foot height but do not block paths.
	for i in range(1700):
		var p := Vector2(_decor.randf_range(-48, 48), _decor.randf_range(-26, 29))
		if _near_building(p):
			continue
		var s := _decor.randf_range(0.025, 0.095)
		_stone(Vector3(p.x, height_at(p), p.y), Vector3(s * 1.3, s * 0.55, s), _materials["chalk"])


func _is_corridor(p: Vector2, width: float) -> bool:
	for center in [Vector2(-26, 2), Vector2(26, 2)]:
		if p.distance_to(center) < 9.0:
			return true
		for target in [Vector2(0, -4), Vector2(0, 8.5), -center + Vector2(0, 4)]:
			if _segment_distance(p, center, target) < width + 3.3:
				return true
	return p.distance_to(Vector2(0, -4)) < 3.2 or p.distance_to(Vector2(0, 8.5)) < 3.0


func _near_building(p: Vector2) -> bool:
	for cx in [-26.0, 26.0]:
		if absf(p.x - cx) < 12.0 and p.y > -17.5 and p.y < -7.0:
			return true
		if p.distance_to(Vector2(cx + (-15.0 if cx < 0 else 15.0), -3.7)) < 4.3:
			return true
	return false


func _is_field(p: Vector2) -> bool:
	for cx in [-26.0, 26.0]:
		if absf(p.x - cx) < 5.8 and absf(p.y - 11.6) < 3.6:
			return true
	return false


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0))


func _make_grass_mesh(crop: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(8 if crop else 10):
		var angle := blade * 2.399
		var h := (0.64 if crop else 0.45) * _decor.randf_range(0.65, 1.3)
		var base := Vector3(cos(angle) * 0.10, 0, sin(angle) * 0.10)
		var side := Vector3(cos(angle), 0, sin(angle)) * (0.009 if crop else 0.012)
		var bend := Vector3(sin(angle), 0, cos(angle)) * h * 0.23
		var mid := base + Vector3.UP * h * 0.55 + bend * 0.3
		var tip := base + Vector3.UP * h + bend
		_foliage_triangle(st, base - side, base + side, mid + side * 0.6, 0, 0, 0.55)
		_foliage_triangle(st, base - side, mid + side * 0.6, mid - side * 0.6, 0, 0.55, 0.55)
		_foliage_triangle(st, mid - side * 0.6, mid + side * 0.6, tip, 0.55, 0.55, 1)
		if crop:
			for seed in range(4):
				var at := tip + Vector3.UP * seed * 0.033
				var ear_side := side.normalized() * (0.031 - seed * 0.004)
				_foliage_triangle(
					st, at - ear_side, at + ear_side, at + Vector3.UP * 0.055, 0.9, 0.9, 1
				)
	st.generate_normals()
	return st.commit()


func _make_leaf_sprig() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(7):
		var side := -1.0 if i % 2 == 0 else 1.0
		var origin := Vector3(0, float(i) * 0.023, (i - 3) * 0.085)
		var end := origin + Vector3(side * 0.24, 0.04, 0.09)
		var mid := (origin + end) * 0.5 + Vector3(0, 0.025, 0)
		var width := Vector3(-0.018, 0, side * 0.052)
		_foliage_triangle(st, origin, mid + width, mid, 0, 0.6, 0.6)
		_foliage_triangle(st, origin, mid, mid - width, 0, 0.6, 0.6)
		_foliage_triangle(st, mid + width, end, mid, 0.6, 1, 0.6)
		_foliage_triangle(st, mid, end, mid - width, 0.6, 1, 0.6)
	st.generate_normals()
	return st.commit()


func _make_tree_trunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_branch(st, Vector3.ZERO, Vector3(0.18, 1.4, 0.07), 0.32, 0.22)
	_branch(st, Vector3(0.18, 1.4, 0.07), Vector3(-0.15, 2.4, 0), 0.23, 0.16)
	for i in range(5):
		var angle := i * TAU / 5.0
		var start := Vector3(0.05, 1.35 + i * 0.13, 0)
		var elbow := Vector3(cos(angle) * 1.15, 2.5 + i * 0.08, sin(angle) * 1.15)
		var tip := Vector3(cos(angle) * 2.35, 3.3 + sin(angle * 2.0) * 0.35, sin(angle) * 2.35)
		_branch(st, start, elbow, 0.16, 0.095)
		_branch(st, elbow, tip, 0.095, 0.026)
		_branch(st, elbow, tip.rotated(Vector3.UP, 0.4) + Vector3(0, 0.4, 0), 0.065, 0.014)
		_branch(st, Vector3.ZERO, Vector3(cos(angle) * 0.7, 0.05, sin(angle) * 0.7), 0.21, 0.04)
	st.generate_normals()
	return st.commit()


func _branch(st: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float) -> void:
	var direction := (b - a).normalized()
	var tangent := direction.cross(Vector3.FORWARD).normalized()
	if tangent.length_squared() < 0.1:
		tangent = Vector3.RIGHT
	var bitangent := direction.cross(tangent).normalized()
	for i in range(10):
		var t0 := TAU * i / 10.0
		var t1 := TAU * (i + 1) / 10.0
		var n0 := tangent * cos(t0) + bitangent * sin(t0)
		var n1 := tangent * cos(t1) + bitangent * sin(t1)
		_quad(st, a + n1 * radius_a, b + n1 * radius_b, b + n0 * radius_b, a + n0 * radius_a)


func _make_stone_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		var p := vertices[i]
		var wobble := 1.0 + sin(p.x * 9.1 + p.z * 3.7) * 0.085 + cos(p.y * 8.2 - p.x * 3.0) * 0.065
		vertices[i] = p * wobble
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()


func _roof_tile() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(5):
		var z0 := -0.155 + segment * 0.062
		var z1 := z0 + 0.062
		var y0 := sin(PI * float(segment) / 5.0) * 0.037
		var y1 := sin(PI * float(segment + 1) / 5.0) * 0.037
		_quad(
			st,
			Vector3(-0.16, y0, z0),
			Vector3(-0.16, y1, z1),
			Vector3(0.16, y1, z1),
			Vector3(0.16, y0, z0)
		)
	st.generate_normals()
	return st.commit()


func _roof_ridge_tile() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		var a := PI * i / 8.0
		var b := PI * (i + 1) / 8.0
		_quad(
			st,
			Vector3(cos(a) * 0.18, sin(a) * 0.12, -0.16),
			Vector3(cos(b) * 0.18, sin(b) * 0.12, -0.16),
			Vector3(cos(b) * 0.18, sin(b) * 0.12, 0.16),
			Vector3(cos(a) * 0.18, sin(a) * 0.12, 0.16)
		)
	st.generate_normals()
	return st.commit()


func _barrel(parent: Node3D, at: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.85
	mesh.bottom_radius = radius * 0.9
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	var node := _add_mesh(mesh, _materials["wood"], parent, "CooperedBucket")
	node.position = at
	for y in [-0.65, 0.65]:
		var ring := TorusMesh.new()
		ring.inner_radius = radius * 0.83
		ring.outer_radius = radius * 0.95
		ring.rings = 20
		ring.ring_segments = 6
		var hoop := _add_mesh(ring, _materials["wood_dark"], parent, "BarrelBinding")
		hoop.position = at + Vector3(0, y * radius, 0)


func _local_box(parent: Node3D, at: Vector3, size: Vector3, material_name: String) -> void:
	_queue_mesh(
		_box_mesh,
		_materials[material_name],
		parent.transform * Transform3D(Basis.IDENTITY.scaled(size), at)
	)


func _beam(parent: Node3D, a: Vector3, b: Vector3, thickness: float, material_name: String) -> void:
	var direction := (b - a).normalized()
	var basis := (
		Basis(Quaternion(Vector3.UP, direction))
		* Basis.from_scale(Vector3(thickness, a.distance_to(b), thickness))
	)
	_queue_mesh(
		_box_mesh, _materials[material_name], parent.transform * Transform3D(basis, (a + b) * 0.5)
	)


func _local_stone(parent: Node3D, at: Vector3, size: Vector3) -> void:
	_queue_mesh(
		_stone_mesh,
		_materials["stone"],
		parent.transform * Transform3D(Basis.IDENTITY.scaled(size), at)
	)


func _stone(at: Vector3, size: Vector3, material: Material) -> void:
	var basis := (
		Basis
		. from_euler(
			Vector3(
				_decor.randf_range(-0.2, 0.2),
				_decor.randf_range(0, TAU),
				_decor.randf_range(-0.15, 0.15)
			)
		)
		. scaled(size)
	)
	_queue_mesh(_stone_mesh, material, Transform3D(basis, at))


func _queue_mesh(mesh: Mesh, material: Material, transform: Transform3D) -> void:
	var key := str(mesh.get_instance_id()) + ":" + str(material.get_instance_id())
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "material": material, "transforms": [], "colors": []}
	_batches[key].transforms.append(transform)
	_batches[key].colors.append(Color.WHITE)


func _flush_batches() -> void:
	for item in _batches.values():
		if item.mesh == _stone_mesh:
			_spatial_batch(
				item.mesh, item.transforms, item.colors, item.material, "InstancedStoneDetail"
			)
		else:
			_batch(
				item.mesh,
				item.transforms,
				item.colors,
				item.material,
				self,
				"InstancedArchitecturalDetail"
			)
	_batches.clear()


func _spatial_batch(
	mesh: Mesh,
	transforms: Array,
	colors: Array,
	material: Material,
	label: String,
	shadows: bool = true
) -> void:
	# MultiMeshes are culled as a whole. Small spatial buckets keep person-scale
	# views from submitting every leaf and pebble in the entire valley.
	var cells: Dictionary = {}
	for i in range(transforms.size()):
		var origin: Vector3 = transforms[i].origin
		var key := Vector2i(floori(origin.x / 24.0), floori(origin.z / 24.0))
		if not cells.has(key):
			cells[key] = {"transforms": [], "colors": []}
		cells[key].transforms.append(transforms[i])
		cells[key].colors.append(colors[i])
	for cell in cells.values():
		var node := _batch(mesh, cell.transforms, cell.colors, material, self, label)
		if not shadows:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _batch(
	mesh: Mesh, transforms: Array, colors: Array, material: Material, parent: Node3D, label: String
) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	node.material_override = material
	parent.add_child(node)
	return node


func _add_mesh(mesh: Mesh, material: Material, parent: Node3D, label: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	return node


func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# SurfaceTool uses clockwise fronts. Callers describe outward CCW faces.
	for p in [a, c, b]:
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(st, a, b, c)
	_triangle(st, a, c, d)


func _foliage_triangle(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ta: float, tb: float, tc: float
) -> void:
	st.set_uv(Vector2(0, ta))
	st.add_vertex(a)
	st.set_uv(Vector2(1, tb))
	st.add_vertex(b)
	st.set_uv(Vector2(0.5, tc))
	st.add_vertex(c)
