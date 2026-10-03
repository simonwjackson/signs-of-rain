extends RefCounted
## Owns one touch sequence. Camera gestures can never finish as a world tap.
const TAP_SLOP := 12.0
# The existing camera takes pixel deltas. Normalize touch travel to the pane:
# a full width turns 180 degrees; a full height tilts 60 degrees.
const ORBIT_RANGE := Vector2(PI / .006, 60.0 / .16)
var fingers: Dictionary = {}
var travel := 0.0
var gesturing := false


func reset() -> void:
	fingers.clear()
	travel = 0.0
	gesturing = false


func handle(event: InputEvent, at: Vector2, canvas: Vector2) -> Dictionary:
	if event is InputEventScreenTouch:
		return _contact(event, at, canvas)
	if event is InputEventScreenDrag and fingers.has(event.index):
		return _drag(event, at, canvas)
	return {"kind": "ignored"}


func _contact(event: InputEventScreenTouch, at: Vector2, canvas: Vector2) -> Dictionary:
	if event.pressed:
		if fingers.is_empty():
			travel = 0.0
			gesturing = false
		fingers[event.index] = at
		if fingers.size() > 1:
			gesturing = true
		return {"kind": "held"}
	if not fingers.has(event.index):
		return {"kind": "ignored"}
	travel += at.distance_to(fingers[event.index])
	var tap := (
		fingers.size() == 1
		and not gesturing
		and not event.canceled
		and travel < TAP_SLOP
		and Rect2(Vector2.ZERO, canvas).has_point(at)
	)
	fingers.erase(event.index)
	if fingers.is_empty():
		reset()
	return {"kind": "tap", "at": at} if tap else {"kind": "held"}


func _drag(event: InputEventScreenDrag, at: Vector2, canvas: Vector2) -> Dictionary:
	var previous: Vector2 = fingers[event.index]
	if fingers.size() == 1:
		fingers[event.index] = at
		travel += previous.distance_to(at)
		if travel >= TAP_SLOP:
			gesturing = true
		if not gesturing:
			return {"kind": "held"}
		var extent := Vector2(maxf(1, canvas.x), maxf(1, canvas.y))
		return {"kind": "orbit", "delta": (at - previous) / extent * ORBIT_RANGE}
	if fingers.size() == 2:
		var pair := fingers.keys()
		var first: Vector2 = fingers[pair[0]]
		var second: Vector2 = fingers[pair[1]]
		var center := (first + second) * .5
		var span := first.distance_to(second)
		fingers[event.index] = at
		first = fingers[pair[0]]
		second = fingers[pair[1]]
		var next_center := (first + second) * .5
		var next_span := first.distance_to(second)
		var zoom := 0.0
		if span >= TAP_SLOP and next_span >= TAP_SLOP:
			zoom = log(span / next_span) / log(1.17)
		return {"kind": "pan_zoom", "delta": next_center - center, "zoom": zoom, "at": next_center}
	# Three fingers block taps but do not choose an arbitrary moving pair.
	fingers[event.index] = at
	return {"kind": "held"}
