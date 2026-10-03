extends Node3D
## Presentation only. The world owns this node's position and heading.

const MALE = preload("res://assets/characters/male_villager.gltf")
const FEMALE = preload("res://assets/characters/female_villager.gltf")
const CLOTH = [Color("a5a892"), Color("8598a2"), Color("b6a381"), Color("9b8678")]
const HAIR = [Color("493125"), Color("302b27"), Color("87705a"), Color("a39881")]

var person_id: int
var village: int
var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _food: Node3D
var _water: Node3D
var _clip := ""
var _cue_clip := ""
var _cue_time := 0.0
var _last_position := Vector3.ZERO
var _motion_speed := 0.0


func _init(id: int = 0, settlement: int = 0) -> void:
	person_id = id
	village = settlement


func _ready() -> void:
	var female := person_id % 2 == 1
	_model = (FEMALE if female else MALE).instantiate()
	add_child(_model)
	# The source faces +Z. Only the model turns; the parent owns root heading.
	_model.rotation.y = PI
	var body_scale := (1.70 if female else 1.74) / (1.77 if female else 1.81)
	body_scale *= 0.97 + float(person_id % 4) * 0.02
	_model.scale = Vector3.ONE * body_scale
	_model.position.y = 0.012
	_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in _player.get_animation_list():
		var anim := _player.get_animation(clip)
		anim.loop_mode = Animation.LOOP_LINEAR
	_style(_model, female)
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	var hand := BoneAttachment3D.new()
	hand.bone_name = "hand_r"
	_skeleton.add_child(hand)
	_food = _make_supplies(false)
	_water = _make_supplies(true)
	hand.add_child(_food)
	hand.add_child(_water)
	_food.visible = false
	_water.visible = false
	_play("Idle")
	_player.advance(float(person_id % 11) * 0.13)


func _style(node: Node, female: bool) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var label := str(mesh.name)
		if label.begins_with("Hair_"):
			if female:
				mesh.visible = label == ("Hair_Buns" if person_id % 4 == 1 else "Hair_Long")
			else:
				mesh.visible = (
					label == ("Hair_SimpleParted" if person_id % 4 == 0 else "Hair_Buzzed")
					or (label == "Hair_Beard" and person_id % 6 == 0)
				)
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				var material_name := str(source.resource_name)
				if "Peasant" in material_name:
					material.albedo_color = CLOTH[(person_id / 2 + village) % CLOTH.size()]
					material.roughness = 0.94
				elif "Hair" in material_name:
					material.albedo_color = HAIR[(person_id / 3) % HAIR.size()]
					material.roughness = 0.82
				elif "Superhero" in material_name or "Regular" in material_name:
					material.albedo_color = Color(
						1.0, 0.88 + float(person_id % 3) * 0.055, 0.82 + float(person_id % 4) * 0.05
					)
					material.roughness = 0.82
				mesh.set_surface_override_material(surface, material)
	for child in node.get_children():
		_style(child, female)


func _make_supplies(water: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = "CarriedWater" if water else "CarriedFood"
	holder.position = Vector3(0.02, 0.04, 0.0)
	var vessel := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 0.10 if water else 0.14
	shape.bottom_radius = 0.085 if water else 0.10
	shape.height = 0.25 if water else 0.20
	shape.radial_segments = 16
	vessel.mesh = shape
	vessel.position.y = -0.16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("7c6950") if water else Color("9a794c")
	mat.roughness = 0.92
	vessel.material_override = mat
	holder.add_child(vessel)
	var handle := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.095
	ring.outer_radius = 0.11
	ring.rings = 16
	ring.ring_segments = 6
	handle.mesh = ring
	handle.rotation.x = PI * 0.5
	handle.position.y = -0.025
	handle.material_override = mat
	holder.add_child(handle)
	if water:
		var surface := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = 0.09
		disk.bottom_radius = 0.09
		disk.height = 0.005
		surface.mesh = disk
		surface.position.y = -0.031
		var liquid := StandardMaterial3D.new()
		liquid.albedo_color = Color("426d7d")
		liquid.roughness = 0.18
		liquid.metallic = 0.15
		surface.material_override = liquid
		holder.add_child(surface)
	else:
		for i in 3:
			var loaf := MeshInstance3D.new()
			var bread := SphereMesh.new()
			bread.radius = 0.052
			bread.height = 0.09
			loaf.mesh = bread
			loaf.position = Vector3(float(i - 1) * 0.065, -0.065, 0)
			var crust := StandardMaterial3D.new()
			crust.albedo_color = Color("c49b5e")
			crust.roughness = 1.0
			loaf.material_override = crust
			holder.add_child(loaf)
	return holder


func focus_point() -> Vector3:
	if is_instance_valid(_skeleton):
		var head := _skeleton.find_bone("head")
		if head >= 0:
			return (
				_skeleton.global_transform * _skeleton.get_bone_global_pose(head).origin
				+ Vector3(0, .08, 0)
			)
	return global_position + Vector3(0, 1.45, 0)


func _play(clip: String) -> void:
	if _clip == clip:
		return
	_clip = clip
	_player.play(clip, 0.22)


func cue(action: String) -> void:
	_cue_clip = "Interact" if action == "share" else "Idle_Talking"
	_cue_time = .7


func present(person: Dictionary, moving: bool, delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_food.visible = float(person.get("carried_food", 0.0)) > 0.001
	_water.visible = float(person.get("carried_water", 0.0)) > 0.001
	_water.position.x = 0.17 if _food.visible else 0.02
	var clip := "Walk" if moving else "Idle"
	if not moving:
		match str(person.get("action", "")):
			"ritual":
				clip = "Spell_Simple_Idle"
			"tell", "telling":
				clip = "Idle_Talking"
			"share", "sharing":
				clip = "Interact"
			"work", "working":
				clip = "Fixing_Kneeling"
	if delta > 0:
		var speed := position.distance_to(_last_position) / delta
		_motion_speed = lerpf(_motion_speed, minf(speed, 4), 1 - exp(-delta * 3))
	_last_position = position
	if _cue_time > 0:
		clip = _cue_clip
		_cue_time = maxf(0, _cue_time - maxf(delta, 0))
	_play(clip)
	var cadence := clampf(_motion_speed / .8, .4, 2.6) if clip == "Walk" else 1.0
	_player.advance(maxf(delta, 0.0) * cadence)
	# A bucket hangs upright even as the animated hand rotates.
	_food.global_basis = _model.global_basis
	_water.global_basis = _model.global_basis
