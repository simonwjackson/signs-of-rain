extends SceneTree
## Run against the actual exported main pack from outside the source checkout.
var paths: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	walk("res://")
	for path in paths:
		var parts := path.trim_prefix("res://").split("/")
		if parts[0] not in ["game", "ui", "sim", "assets", ".godot", "project.binary"]:
			failures.append("Unexpected pack member: " + path)
		if path.ends_with(".py") or path.ends_with(".json") or path.ends_with(".mp4"):
			failures.append("Development/capture data in pack: " + path)
	for required in [
		"res://game/main.tscn",
		"res://game/god_camera.gd",
		"res://sim/simulation.gd",
		"res://assets/characters/male_villager.gltf",
		"res://assets/characters/female_villager.gltf"
	]:
		if not ResourceLoader.exists(required):
			failures.append("Missing runtime resource: " + required)
	for path in failures:
		printerr("FAIL: " + path)
	print("PACK: %d members, %d boundary failures" % [paths.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


func walk(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		failures.append("Cannot inspect pack directory: " + path)
		return
	for file in dir.get_files():
		paths.append(path.path_join(file))
	for child in dir.get_directories():
		walk(path.path_join(child))
