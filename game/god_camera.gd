extends Node3D
## Continuous person-to-landscape camera. The camera never changes model state.
const MIN_DISTANCE := 0.85
const MAX_DISTANCE := 180.0
const MIN_PITCH := 8.0
const MAX_PITCH := 82.0
var camera := Camera3D.new()
var height_at: Callable
var target := Vector3(0, 1.5, 0)
var wanted_target := Vector3(0, 1.5, 0)
var distance := 110.0
var wanted_distance := 110.0
var yaw := 0.38
var wanted_yaw := 0.38
var pitch := 35.5
var wanted_pitch := 35.5
var pitch_offset := 0.0
var input_enabled := true
var following := false


func _init(surface_height: Callable = Callable()) -> void:
	height_at = surface_height


func _ready() -> void:
	camera.name = "GodCamera"
	camera.near = 0.06
	camera.far = 650.0
	camera.fov = 52.0
	camera.current = true
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = false
	attributes.dof_blur_near_enabled = false
	camera.attributes = attributes
	add_child(camera)
	if height_at.is_valid():
		wanted_target.y = height_at.call(Vector2.ZERO) + 1.0
		target = wanted_target
	_apply()


func advance(delta: float) -> void:
	if input_enabled:
		var direction := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W):
			direction.y -= 1
		if Input.is_physical_key_pressed(KEY_S):
			direction.y += 1
		if Input.is_physical_key_pressed(KEY_A):
			direction.x -= 1
		if Input.is_physical_key_pressed(KEY_D):
			direction.x += 1
		if direction != Vector2.ZERO:
			pan(direction.normalized() * delta * maxf(2.0, distance * 0.38))
		if Input.is_physical_key_pressed(KEY_Q):
			wanted_yaw += delta * .8
		if Input.is_physical_key_pressed(KEY_E):
			wanted_yaw -= delta * .8
	var blend := 1.0 - exp(-delta * 9.0)
	target = target.lerp(wanted_target, blend)
	distance = lerpf(distance, wanted_distance, blend)
	yaw = lerp_angle(yaw, wanted_yaw, blend)
	pitch = lerpf(pitch, wanted_pitch, blend)
	_apply()


func _apply() -> void:
	var vertical := deg_to_rad(pitch)
	camera.position = (
		target
		+ Vector3(sin(yaw) * cos(vertical), sin(vertical), cos(yaw) * cos(vertical)) * distance
	)
	if height_at.is_valid():
		camera.position.y = maxf(
			camera.position.y, height_at.call(Vector2(camera.position.x, camera.position.z)) + .5
		)
	camera.look_at(target, Vector3.UP)
	var attributes: CameraAttributesPractical = camera.attributes
	attributes.dof_blur_far_enabled = distance < 9.0
	attributes.dof_blur_far_distance = distance + 5.0
	attributes.dof_blur_far_transition = 16.0
	attributes.dof_blur_amount = .18


func overview() -> void:
	following = false
	pitch_offset = 0.0
	wanted_target = Vector3(
		0, height_at.call(Vector2.ZERO) + 1.0 if height_at.is_valid() else 1.5, 0
	)
	wanted_distance = 110.0
	wanted_yaw = .28
	wanted_pitch = _zoom_pitch(wanted_distance)


func focus_person(at: Vector3, facing: float) -> void:
	following = true
	pitch_offset = 0.0
	wanted_target = at
	wanted_distance = 1.6
	wanted_pitch = 12.0
	wanted_yaw = facing + PI


func follow(at: Vector3) -> void:
	if following:
		wanted_target = at


func zoom(steps: float, anchor: Vector3) -> void:
	var previous := wanted_distance
	wanted_distance = clampf(wanted_distance * pow(1.17, steps), MIN_DISTANCE, MAX_DISTANCE)
	if not following and steps < 0:
		wanted_target = wanted_target.lerp(
			anchor + Vector3(0, .7, 0), clampf(1 - wanted_distance / previous, 0, .8)
		)
	wanted_pitch = clampf(_zoom_pitch(wanted_distance) + pitch_offset, MIN_PITCH, MAX_PITCH)


func orbit(pixels: Vector2) -> void:
	wanted_yaw -= pixels.x * .006
	wanted_pitch = clampf(wanted_pitch + pixels.y * .16, MIN_PITCH, MAX_PITCH)
	pitch_offset = wanted_pitch - _zoom_pitch(wanted_distance)


func _zoom_pitch(at_distance: float) -> float:
	return lerpf(12, 48, smoothstep(4, 180, at_distance))


func pan(direction: Vector2) -> void:
	following = false
	var lift := .7
	if height_at.is_valid():
		lift = maxf(
			.7, wanted_target.y - float(height_at.call(Vector2(wanted_target.x, wanted_target.z)))
		)
	var right := Vector3(cos(wanted_yaw), 0, -sin(wanted_yaw))
	var backwards := Vector3(sin(wanted_yaw), 0, cos(wanted_yaw))
	wanted_target += right * direction.x + backwards * direction.y
	wanted_target.x = clampf(wanted_target.x, -65, 65)
	wanted_target.z = clampf(wanted_target.z, -45, 45)
	if height_at.is_valid():
		wanted_target.y = height_at.call(Vector2(wanted_target.x, wanted_target.z)) + lift


func drag_pan(pixels: Vector2, viewport_height: float) -> void:
	pan(-pixels * wanted_distance * 1.15 / maxf(viewport_height, 1))


func ground_under(pixel: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	# A bounded heightfield intersection also works before physics sync and headlessly.
	var previous := origin
	for index in range(1, 401):
		var step := float(index) * 1.25
		var point := origin + direction * step
		var ground: float = (
			height_at.call(Vector2(point.x, point.z)) if height_at.is_valid() else 0.0
		)
		if point.y <= ground:
			var low := previous
			var high := point
			for refinement in range(14):
				var middle := (low + high) * .5
				var y: float = (
					height_at.call(Vector2(middle.x, middle.z)) if height_at.is_valid() else 0.0
				)
				if middle.y > y:
					low = middle
				else:
					high = middle
			return (low + high) * .5
		previous = point
	# Sky clicks map outside the playable simulation, so casts reject instead of teleporting.
	return Vector3(10000, 0, 10000)


func evidence() -> Dictionary:
	return {
		"distance": distance,
		"target_distance": wanted_distance,
		"pitch": pitch,
		"yaw": yaw,
		"position": camera.global_position,
		"target": target,
		"following": following,
		"near": camera.near,
		"far": camera.far
	}
