extends Control
## A real 3D world inside an intrinsically sized viewport. Model state is read-only.
signal chosen(point: Vector2, button: int)
const Terrain = preload("res://game/terrain.gd")
const Villager = preload("res://game/villager.gd")
const GodCamera = preload("res://game/god_camera.gd")
const TouchCamera = preload("res://game/touch_camera.gd")
const S = preload("res://ui/style.gd")
const FAST_PIXEL_BUDGET := 1400000.0
var state: Dictionary = {}
var selected := -1
var mode := "observe"
var motion := true
var effects_static := false
var camera_input_enabled := true:
	set(value):
		camera_input_enabled = value
		if not value:
			cancel_camera_input()
var touch = TouchCamera.new()
var scale_factor := 1.0
var viewport := SubViewport.new()
var world := Node3D.new()
var terrain: Node3D
var rig: Node3D
var people: Dictionary = {}
var pick_shapes: Dictionary = {}
var caches: Dictionary = {}
var village_labels: Array[Label3D] = []
var selected_ring: MeshInstance3D
var cursor_ring: MeshInstance3D
var cursor_mesh := ImmediateMesh.new()
var cursor := Vector2(-1000, -1000)
var cursor_world := Vector3(10000, 0, 10000)
var last_ring := Vector3(10000, 0, 10000)
var last_ring_mode := ""
var dragging := 0
var drag_travel := 0.0
var follow_id := -1
var last_tick := -1
var clock := 0.0
var effects: Array[Dictionary] = []
var environment := Environment.new()
var sunlight := DirectionalLight3D.new()
var graphics := "high"


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	viewport.name = "ValleyViewport"
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	var image := TextureRect.new()
	image.texture = viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.name = "Valley"
	viewport.add_child(world)
	terrain = Terrain.new()
	world.add_child(terrain)
	_lighting()
	rig = GodCamera.new(terrain.height_at)
	world.add_child(rig)
	selected_ring = _ring(.53, Color("ddc875"))
	world.add_child(selected_ring)
	selected_ring.hide()
	cursor_ring = MeshInstance3D.new()
	cursor_ring.mesh = cursor_mesh
	cursor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(cursor_ring)
	for id in range(2):
		var label := Label3D.new()
		label.name = "VillageLabel%d" % id
		label.font = S.DISPLAY
		label.font_size = 54
		label.pixel_size = .017
		label.outline_size = 8
		label.outline_modulate = Color(.055, .09, .07, .75)
		label.modulate = Color("fff3d3")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		world.add_child(label)
		village_labels.append(label)
	resized.connect(_resize)
	mouse_exited.connect(func(): cursor = Vector2(-1000, -1000))
	_resize()


func _resize() -> void:
	cancel_camera_input()
	var to_screen := get_viewport().get_screen_transform() * get_global_transform_with_canvas()
	var pixels := size * to_screen.get_scale().abs()
	viewport.size = Vector2i(maxi(2, roundi(pixels.x)), maxi(2, roundi(pixels.y)))
	_apply_render_scale()


## Faster graphics caps 3D work at about 1.4 megapixels, so a large HiDPI
## window does not quadruple the cost of an integrated GPU's frame.
func _apply_render_scale() -> void:
	if graphics != "fast":
		viewport.scaling_3d_scale = 1.0
		return
	var pixels := maxf(1.0, float(viewport.size.x) * float(viewport.size.y))
	viewport.scaling_3d_scale = clampf(sqrt(FAST_PIXEL_BUDGET / pixels), .45, .67)


func _lighting() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("427996")
	sky_material.sky_horizon_color = Color("cbd5c5")
	sky_material.ground_bottom_color = Color("586342")
	sky_material.ground_horizon_color = Color("cbd5c5")
	sky_material.sky_curve = .2
	sky_material.sun_angle_max = 12
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = .7
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 5.0
	var renderer := RenderingServer.get_current_rendering_method()
	environment.ssao_enabled = renderer != "mobile"
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.7
	environment.ssil_enabled = renderer == "forward_plus"
	environment.ssil_intensity = .6
	environment.glow_enabled = true
	environment.glow_intensity = .28
	environment.glow_bloom = .035
	environment.fog_enabled = true
	environment.fog_light_color = Color("b8c8be")
	environment.fog_density = .0007
	environment.fog_aerial_perspective = .25
	environment.volumetric_fog_enabled = renderer == "forward_plus"
	environment.volumetric_fog_density = .0007
	environment.volumetric_fog_albedo = Color("d1d8bf")
	environment.volumetric_fog_length = 220
	environment.volumetric_fog_anisotropy = .35
	var sky_node := WorldEnvironment.new()
	sky_node.environment = environment
	world.add_child(sky_node)
	sunlight.name = "AfternoonSun"
	sunlight.rotation_degrees = Vector3(-43, -38, 0)
	sunlight.light_color = Color("fff0cf")
	sunlight.light_energy = 1.8
	sunlight.light_angular_distance = .8
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sunlight.directional_shadow_max_distance = 210
	sunlight.shadow_bias = .1
	sunlight.shadow_normal_bias = 1.5
	world.add_child(sunlight)


## The render method decides which effects exist. Graphics only changes cost.
func set_graphics(preset: String, renderer: String = "") -> void:
	graphics = "fast" if preset == "fast" else "high"
	var method := RenderingServer.get_current_rendering_method() if renderer == "" else renderer
	var forward := method == "forward_plus"
	var fast := graphics == "fast"
	viewport.msaa_3d = Viewport.MSAA_DISABLED if fast else Viewport.MSAA_4X
	viewport.scaling_3d_mode = (
		Viewport.SCALING_3D_MODE_FSR if fast and forward else Viewport.SCALING_3D_MODE_BILINEAR
	)
	_apply_render_scale()
	environment.ssao_enabled = method != "mobile"
	environment.ssil_enabled = not fast and forward
	environment.volumetric_fog_enabled = not fast and forward
	sunlight.directional_shadow_mode = (
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		if fast
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	)
	sunlight.directional_shadow_max_distance = 140 if fast else 210


func set_state(value: Dictionary) -> void:
	state = value


func reset() -> void:
	last_tick = -1
	follow_id = -1
	cancel_camera_input()
	if is_instance_valid(terrain):
		terrain.set_wetness(Vector2.ZERO, 0.0)
	for person in people.values():
		person.queue_free()
	people.clear()
	pick_shapes.clear()
	for cache in caches.values():
		cache.queue_free()
	caches.clear()
	for effect in effects:
		effect.node.queue_free()
	effects.clear()
	if is_instance_valid(rig):
		rig.overview()


func _process(delta: float) -> void:
	if not is_instance_valid(rig):
		return
	clock += delta
	for person in state.get("people", []):
		var id: int = person.id
		var at := world_position(person.pos)
		if not people.has(id):
			var actor := Villager.new(id, int(person.village))
			world.add_child(actor)
			actor.position = at
			people[id] = actor
			var body := Area3D.new()
			body.name = "PickingBody"
			body.collision_layer = 2
			body.collision_mask = 0
			body.monitoring = false
			body.set_meta("person_id", id)
			var shape := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = .4
			capsule.height = 1.85
			shape.shape = capsule
			shape.position.y = .925
			body.add_child(shape)
			actor.add_child(body)
			pick_shapes[id] = shape
		var actor: Node3D = people[id]
		var travel := at - actor.position
		var moving := travel.length() > .007 and motion
		actor.position = actor.position.lerp(at, minf(1, delta * 9)) if motion else at
		if moving:
			var heading := atan2(-travel.x, -travel.z)
			actor.rotation.y = lerp_angle(actor.rotation.y, heading, minf(1, delta * 7))
		actor.present(person, moving, delta if motion else 0.0)
		var head: Vector3 = actor.to_local(actor.focus_point())
		var shape: CollisionShape3D = pick_shapes[id]
		var body_height := maxf(1.0, head.y + .22)
		shape.shape.height = body_height
		shape.position = Vector3(head.x * .5, body_height * .5, head.z * .5)
		if selected == id:
			selected_ring.position = actor.position + Vector3(0, .025, 0)
	selected_ring.visible = selected >= 0
	if follow_id >= 0 and people.has(follow_id):
		rig.follow(people[follow_id].focus_point())
	rig.input_enabled = camera_input_enabled
	if camera_input_enabled:
		rig.advance(delta)
	scale_factor = maxf(.2, 50.0 / maxf(rig.distance, .1))
	if int(state.get("tick", 0)) != last_tick:
		last_tick = int(state.get("tick", 0))
		terrain.update_resources(state.get("villages", []), float(state.get("well_water", 0)))
		var history: Array = state.get("events", [])
		for index in range(history.size() - 1, -1, -1):
			var event: Dictionary = history[index]
			if event.kind == "rain":
				var wet_at := world_position(event.pos)
				terrain.set_wetness(
					Vector2(wet_at.x, wet_at.z), maxf(0, 1 - (last_tick - int(event.tick)) / 100.0)
				)
				break
		_refresh_caches()
	for village in state.get("villages", []):
		var label := village_labels[int(village.id)]
		label.text = (
			"%s\nFood %d   Water %d" % [village.name, roundi(village.food), roundi(village.water)]
		)
		label.position = world_position(village.pos) + Vector3(0, 4.2, 0)
		label.visible = rig.distance > 23
		label.pixel_size = clampf(rig.distance * .00046, .014, .085)
	_update_cursor()
	_update_effects(delta)


func world_position(point: Vector2) -> Vector3:
	var xz := point * .1 - Vector2(50, 32)
	return Vector3(xz.x, terrain.height_at(xz), xz.y)


func simulation_position(point: Vector3) -> Vector2:
	return (Vector2(point.x, point.z) + Vector2(50, 32)) * 10


func to_screen(point: Vector2) -> Vector2:
	var pixel: Vector2 = rig.camera.unproject_position(world_position(point) + Vector3(0, .08, 0))
	return get_global_transform_with_canvas() * (pixel * size / Vector2(viewport.size))


## Input stays in canvas units; only camera projection reads physical viewport pixels.
func viewport_point(at: Vector2) -> Vector2:
	return at * Vector2(viewport.size) / size.max(Vector2.ONE)


func ground_at(at: Vector2) -> Vector3:
	return rig.ground_under(viewport_point(at))


func person_at_pointer() -> int:
	var pixel := viewport_point(cursor)
	var start: Vector3 = rig.camera.project_ray_origin(pixel)
	var direction: Vector3 = rig.camera.project_ray_normal(pixel)
	var ray := PhysicsRayQueryParameters3D.create(start, start + direction * 650, 1 | 2 | 4)
	ray.collide_with_areas = true
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return -1
	return int(hit.collider.get_meta("person_id", -1))


func is_following_person() -> bool:
	return is_instance_valid(rig) and rig.following


func focus_person(id: int) -> void:
	if people.has(id):
		follow_id = id
		rig.focus_person(people[id].focus_point(), people[id].rotation.y)


func overview() -> void:
	follow_id = -1
	rig.overview()


func cancel_camera_input() -> void:
	dragging = 0
	drag_travel = 0.0
	touch.reset()
	cursor = Vector2(-1000, -1000)


## The game binding supplies valley-local coordinates after checking HUD occlusion.
func touch_input(event: InputEvent, at: Vector2) -> bool:
	if not camera_input_enabled:
		cancel_camera_input()
		return false
	var result: Dictionary = touch.handle(event, at, size)
	match result.kind:
		"ignored":
			return false
		"held":
			cursor = (
				at if touch.fingers.size() == 1 and not touch.gesturing else Vector2(-1000, -1000)
			)
		"tap":
			cursor = result.at
			chosen.emit(simulation_position(ground_at(cursor)), MOUSE_BUTTON_LEFT)
		"orbit":
			cursor = Vector2(-1000, -1000)
			rig.orbit(result.delta)
		"pan_zoom":
			cursor = Vector2(-1000, -1000)
			rig.drag_pan(result.delta, size.y)
			var anchor: Vector3 = ground_at(result.at)
			if absf(anchor.x) > 1000:
				anchor = rig.target
			rig.zoom(result.zoom, anchor)
	return true


func _gui_input(event: InputEvent) -> void:
	if not camera_input_enabled:
		cancel_camera_input()
		return
	# Godot still emulates a mouse for ordinary GUI buttons on Android. The world
	# handles real touch once, on release, instead of casting on the emulated press.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		cursor = event.position
		if dragging != 0:
			var required := (
				MOUSE_BUTTON_MASK_MIDDLE
				if dragging == MOUSE_BUTTON_MIDDLE
				else MOUSE_BUTTON_MASK_RIGHT
			)
			if (event.button_mask & required) == 0:
				dragging = 0
				drag_travel = 0.0
				return
			drag_travel += event.relative.length()
			if dragging == MOUSE_BUTTON_MIDDLE:
				rig.orbit(event.relative)
			else:
				rig.drag_pan(event.relative, size.y)
			accept_event()
	if event is InputEventMouseButton:
		cursor = event.position
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var amount := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			var anchor: Vector3 = ground_at(cursor)
			if absf(anchor.x) > 1000:
				anchor = rig.target
			rig.zoom(amount * maxf(event.factor, 1), anchor)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				dragging = event.button_index
				drag_travel = 0
			else:
				if dragging == MOUSE_BUTTON_RIGHT and drag_travel < 4:
					chosen.emit(simulation_position(ground_at(cursor)), MOUSE_BUTTON_RIGHT)
				dragging = 0
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			chosen.emit(simulation_position(ground_at(cursor)), MOUSE_BUTTON_LEFT)
			accept_event()


func _update_cursor() -> void:
	cursor_ring.visible = (
		mode != "observe" and Rect2(Vector2.ZERO, size).has_point(cursor) and camera_input_enabled
	)
	if not cursor_ring.visible:
		return
	cursor_world = ground_at(cursor)
	if absf(cursor_world.x) > 55 or absf(cursor_world.z) > 37:
		cursor_ring.hide()
		return
	if cursor_world.distance_to(last_ring) < .05 and last_ring_mode == mode:
		return
	last_ring = cursor_world
	last_ring_mode = mode
	cursor_mesh.clear_surfaces()
	var material := _material(S.RAIN if mode == "rain" else S.WHEAT, true)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cursor_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in range(128):
		var a := i * TAU / 128
		var b := (i + 1) * TAU / 128
		var vertices: Array[Vector3] = []
		for pair in [[a, 14.92], [a, 15.08], [b, 14.92], [b, 15.08]]:
			var p: Vector2 = (
				Vector2(cursor_world.x, cursor_world.z)
				+ Vector2(cos(pair[0]), sin(pair[0])) * pair[1]
			)
			vertices.append(Vector3(p.x, terrain.height_at(p) + .08, p.y))
		for index in [0, 2, 1, 1, 2, 3]:
			cursor_mesh.surface_add_vertex(vertices[index])
	cursor_mesh.surface_end()


func miracle(kind: String, point: Vector2) -> void:
	last_tick = -1  # Casts also change visible resources while simulation time is paused.
	var node := Node3D.new()
	node.position = world_position(point)
	world.add_child(node)
	if kind == "rain" and not effects_static:
		var rain := MultiMeshInstance3D.new()
		var drops := MultiMesh.new()
		drops.transform_format = MultiMesh.TRANSFORM_3D
		var drop := CylinderMesh.new()
		drop.top_radius = .032
		drop.bottom_radius = .032
		drop.height = 1.2
		drop.radial_segments = 4
		drop.rings = 1
		drop.material = _material(Color(.65, .83, .88, .62), true)
		drops.mesh = drop
		drops.instance_count = 260
		rain.multimesh = drops
		rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(rain)
		effects.append({"node": node, "kind": kind, "age": 0.0, "life": 5.0, "rain": drops})
	else:
		var ring := _ring(.5, S.WHEAT if kind == "food" else S.RAIN)
		node.add_child(ring)
		effects.append({"node": node, "kind": kind, "age": 0.0, "life": 2.5, "ring": ring})
	if kind == "rain" and terrain.has_method("set_wetness"):
		terrain.set_wetness(Vector2(node.position.x, node.position.z), 1.0)


func _update_effects(delta: float) -> void:
	for effect in effects:
		effect.age += delta
		if effect.has("rain"):
			for i in range(260):
				var angle := i * 2.39996
				var radius := sqrt(float(i) / 260) * 15
				var at := Vector3(
					cos(angle) * radius,
					13 - fmod(effect.age * 17 + i * .43, 13),
					sin(angle) * radius
				)
				effect.rain.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		if effect.has("ring"):
			effect.ring.scale = Vector3.ONE * (1 + effect.age * 5)
		if effect.age >= effect.life:
			effect.node.queue_free()
	effects = effects.filter(func(effect): return effect.age < effect.life)


func action_mark(action: String, person_id: int) -> void:
	if people.has(person_id):
		people[person_id].cue(action)


func _refresh_caches() -> void:
	for cache in state.get("caches", []):
		var id: int = cache.event_id
		if not caches.has(id):
			var basket := Node3D.new()
			basket.position = world_position(cache.pos)
			var body := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .48
			cylinder.bottom_radius = .36
			cylinder.height = .5
			cylinder.radial_segments = 24
			cylinder.material = _material(Color("967044"))
			body.mesh = cylinder
			body.position.y = .25
			basket.add_child(body)
			for i in range(10):
				var band := _ring(.4 + i * .008, Color("61492d"))
				band.position.y = i * .052
				basket.add_child(band)
			var grain := MeshInstance3D.new()
			grain.name = "Grain"
			var pile := SphereMesh.new()
			pile.radius = .39
			pile.height = .19
			pile.material = _material(Color("d0b46d"))
			grain.mesh = pile
			grain.position.y = .48
			basket.add_child(grain)
			world.add_child(basket)
			caches[id] = basket
		caches[id].visible = cache.food > .1
		caches[id].get_node("Grain").position.y = .18 + .30 * clampf(cache.food / 38.0, 0, 1)


func _ring(radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = radius
	ring.outer_radius = radius + .026
	ring.rings = 32
	ring.ring_segments = 6
	ring.material = _material(color)
	node.mesh = ring
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .75
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func camera_evidence() -> Dictionary:
	var result: Dictionary = rig.evidence()
	result["followed_person"] = follow_id if rig.following else -1
	return result
