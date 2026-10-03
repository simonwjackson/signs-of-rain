extends SceneTree
const Villager = preload("res://game/villager.gd")
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
	var actors: Array[Node3D] = []
	for id in range(24):
		var actor := Villager.new(id, id / 12)
		actor.position = Vector3(id * .5, 2, -3)
		actor.rotation.y = id * .1
		root.add_child(actor)
		actors.append(actor)
	await process_frame
	for id in range(24):
		var actor := actors[id]
		var original := actor.transform
		var untouched := true
		var visible_supplies := true
		var focus_valid := true
		var first_hand := Vector3.ZERO
		var hand_moved := false
		for frame in range(240):
			var actions := ["rest", "ritual", "tell", "share", "work"]
			var person := {
				"action": actions[(frame / 40) % 5],
				"carried_food": 2.0 if frame % 2 else 0.0,
				"carried_water": 0.0 if frame % 2 else 2.0
			}
			var saved := person.duplicate(true)
			actor.present(person, id < 12, 1.0 / 60.0)
			# BoneAttachment transforms publish with the next scene frame.
			await process_frame
			untouched = untouched and person == saved and actor.transform == original
			var food := actor.find_child("CarriedFood", true, false) as Node3D
			var water := actor.find_child("CarriedWater", true, false) as Node3D
			visible_supplies = (
				visible_supplies
				and food.visible == (frame % 2 == 1)
				and water.visible == (frame % 2 == 0)
			)
			var focus: Vector3 = actor.focus_point()
			focus_valid = (
				focus_valid
				and focus.is_finite()
				and focus.y > actor.position.y + .5
				and focus.y < actor.position.y + 2.1
			)
			if frame == 1:
				first_hand = food.global_position
			if frame == 30:
				hand_moved = food.global_position.distance_to(first_hand) > .01
		check(untouched, "person %d presentation preserves input and world transform" % id)
		check(visible_supplies, "person %d shows only actual carried supplies" % id)
		check(focus_valid, "person %d exposes a usable animated head focus" % id)
		if id < 12:
			check(hand_moved, "person %d has visibly moving carried geometry during Walk" % id)
	for actor in actors:
		actor.queue_free()
	await process_frame
	print("CHARACTERS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
