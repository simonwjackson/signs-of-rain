extends Control
## World presentation. State is supplied by the composition root; never mutated here.
signal chosen(point: Vector2, button: int)
const S = preload("res://ui/style.gd")
const WORLD := Vector2(1000, 640)
var state: Dictionary = {}
var selected := -1
var mode := "observe"
var motion := true
var effects_static := false
var clock := 0.0
var scale_factor := 1.0
var origin := Vector2.ZERO
var cursor := Vector2(-1000, -1000)
var displayed: Dictionary = {}
var decor: Array[Dictionary] = []
var flashes: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	var rng := RandomNumberGenerator.new()
	rng.seed = 621
	for i in range(150):
		var point := Vector2(rng.randf_range(20, 980), rng.randf_range(30, 610))
		decor.append({"pos": point, "size": rng.randf_range(2, 9), "kind": i % 4})
	mouse_exited.connect(func(): cursor = Vector2(-1000, -1000))


func _process(delta: float) -> void:
	clock += delta if motion else 0.0
	for person in state.get("people", []):
		var id: int = person.id
		var at: Vector2 = displayed.get(id, person.pos)
		displayed[id] = at.lerp(person.pos, minf(1, delta * 9)) if motion else person.pos
	for effect in flashes:
		effect.age += delta
	flashes = flashes.filter(func(effect): return effect.age < effect.life)
	queue_redraw()


func set_state(value: Dictionary) -> void:
	state = value


func reset() -> void:
	displayed.clear()
	flashes.clear()


func miracle(kind: String, point: Vector2) -> void:
	flashes.append({"kind": kind, "pos": point, "age": 0.0, "life": 4.0})


func action_mark(action: String, point: Vector2) -> void:
	if flashes.size() < 14:
		flashes.append({"kind": action, "pos": point, "age": 0.0, "life": 2.5})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		cursor = (event.position - origin) / scale_factor
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = (event.position - origin) / scale_factor
		if Rect2(Vector2.ZERO, WORLD).has_point(point):
			chosen.emit(point, event.button_index)
		accept_event()


func to_screen(point: Vector2) -> Vector2:
	return global_position + origin + point * scale_factor


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), S.INK.lightened(0.025))
	scale_factor = minf(size.x / WORLD.x, size.y / WORLD.y)
	origin = (size - WORLD * scale_factor) / 2
	draw_set_transform(origin, 0, Vector2.ONE * scale_factor)
	draw_rect(Rect2(Vector2.ZERO, WORLD), S.GRASS)
	# Broad strata make a dry valley rather than an empty board.
	_blob(Vector2(190, 130), Vector2(280, 190), Color("b8b17b"), 3)
	_blob(Vector2(875, 160), Vector2(240, 190), Color("b6ae7b"), 5)
	_blob(Vector2(790, 625), Vector2(430, 130), Color("9a9e6e"), 7)
	_blob(Vector2(120, 615), Vector2(210, 145), Color("939868"), 11)
	var river := PackedVector2Array(
		[
			Vector2(569, 0),
			Vector2(563, 91),
			Vector2(602, 174),
			Vector2(570, 217),
			Vector2(473, 367),
			Vector2(458, 434),
			Vector2(498, 506),
			Vector2(521, 640)
		]
	)
	draw_polyline(river, Color("898d70"), 58, true)
	draw_polyline(river, Color("b8b491"), 45, true)
	draw_polyline(river, Color("cac5a3"), 23, true)
	for i in range(12):
		var y := 28.0 + i * 49
		var x := 526.0 + sin(y * 0.013) * 42
		draw_line(Vector2(x, y), Vector2(x + 10, y + 11), Color("a6a47f"), 1.5, true)
	var road := PackedVector2Array(
		[
			Vector2(200, 359),
			Vector2(319, 380),
			Vector2(450, 432),
			Vector2(575, 415),
			Vector2(745, 356),
			Vector2(800, 363)
		]
	)
	draw_polyline(road, Color("c8bd8d"), 23, true)
	draw_polyline(
		PackedVector2Array(
			[
				Vector2(250, 343),
				Vector2(365, 289),
				Vector2(500, 280),
				Vector2(640, 280),
				Vector2(760, 340)
			]
		),
		Color("c6ba87"),
		15,
		true
	)
	# A stone ford makes exchange between the two settlements visible.
	for i in range(7):
		draw_style_box(
			S.box(Color("b7b297"), Color("8f947d"), 2),
			Rect2(445 + i * 9, 412 + sin(i * .5) * 4, 7, 27)
		)
	for item in decor:
		var p: Vector2 = item.pos
		if (
			p.distance_to(Vector2(500, 300)) < 210
			or p.distance_to(Vector2(240, 340)) < 155
			or p.distance_to(Vector2(760, 340)) < 155
		):
			continue
		if item.kind == 0 and (p.y < 165 or p.y > 520):
			_tree(p, item.size * .07 + .5)
		else:
			_grass(p, item.size)
	for village in state.get("villages", []):
		_village(village)
	_shrine()
	_common_well()
	# Resources, if represented as ground caches by the simulation.
	for cache in state.get("caches", []):
		if cache.get("food", cache.get("amount", 0)) > 0:
			_basket(cache.pos, 1.3)
	for event in state.get("events", []):
		if event.kind == "rain":
			var age := int(state.get("tick", 0)) - int(event.tick)
			if age < 100:
				var wet := Color("799d78")
				wet.a = maxf(0, .20 * (1 - age / 100.0))
				draw_circle(event.pos, 150, wet)
		elif int(state.get("tick", 0)) - int(event.tick) < 35:
			_basket(event.pos, 1.1)
	_draw_cause()
	var sorted: Array = state.get("people", []).duplicate()
	sorted.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for person in sorted:
		_person(person)
	for effect in flashes:
		_effect(effect)
	if (
		cursor.x >= 0
		and cursor.y >= 0
		and cursor.x <= WORLD.x
		and cursor.y <= WORLD.y
		and mode != "observe"
	):
		var color := S.RAIN if mode == "rain" else S.WHEAT
		draw_circle(cursor, 150, Color(color, .09))
		draw_arc(cursor, 150, 0, TAU, 64, Color(color, .8), 2.5, true)
		draw_line(cursor - Vector2(10, 0), cursor + Vector2(10, 0), color, 2)
		draw_line(cursor - Vector2(0, 10), cursor + Vector2(0, 10), color, 2)
		draw_circle(cursor, 4, color)
	_text(Vector2(32, 42), "The dry valley", 23, Color("4b5b47"), S.DISPLAY)
	_text(Vector2(32, 62), "Two villages. One last week without rain.", 13, Color("576048"))
	_text(Vector2(880, 38), "N", 15, Color("5d674e"))
	draw_line(Vector2(887, 47), Vector2(887, 73), Color("677358"), 1.5)
	draw_colored_polygon(
		PackedVector2Array([Vector2(887, 45), Vector2(882, 56), Vector2(892, 56)]), Color("677358")
	)
	draw_set_transform(Vector2.ZERO)


func _blob(center: Vector2, extent: Vector2, color: Color, phase: float) -> void:
	var points := PackedVector2Array()
	for i in range(48):
		var angle := i * TAU / 48
		var length := .93 + .07 * sin(i * 1.6 + phase)
		points.append(center + Vector2(cos(angle), sin(angle)) * extent * length)
	draw_colored_polygon(points, color)


func _grass(p: Vector2, length: float) -> void:
	var color := Color("83885b")
	for i in range(3):
		draw_line(p + Vector2(i * 3, 0), p + Vector2(i * 3 - 2, -length), color, 1, true)


func _tree(p: Vector2, s: float) -> void:
	draw_set_transform(origin + p * scale_factor, 0, Vector2.ONE * scale_factor * s)
	draw_circle(Vector2(7, 8), 22, Color(0.18, .26, .2, .16))
	draw_line(Vector2.ZERO, Vector2(0, -31), Color("59644b"), 5, true)
	draw_circle(Vector2(-12, -23), 17, Color("6e8053"))
	draw_circle(Vector2(10, -31), 18, Color("819459"))
	draw_circle(Vector2(-5, -40), 17, Color("93a064"))
	draw_circle(Vector2(1, -46), 12, Color("a3ac6f"))
	draw_set_transform(origin, 0, Vector2.ONE * scale_factor)


func _village(v: Dictionary) -> void:
	var p: Vector2 = v.pos
	var color := S.ALDER if int(v.id) == 0 else S.SEDGE
	var field := p + Vector2(-60, 115)
	var growth: float = clampf(float(v.get("crop", 0)) / 100, 0, 1)
	draw_style_box(
		S.box(Color("929367"), Color("777f56"), 4), Rect2(field - Vector2(7, 7), Vector2(136, 68))
	)
	for row in range(5):
		for col in range(12):
			var stalk := field + Vector2(col * 10, row * 11)
			draw_line(
				stalk,
				stalk - Vector2(2, 4 + growth * 9),
				Color("e1d092").lerp(Color("84ae77"), growth),
				2,
				true
			)
	for i in range(6):
		var angle := -PI + i * PI / 5
		var home := p + Vector2(cos(angle) * 100, sin(angle) * 77 - 15)
		_house(home, color, i)
	# Central well; its water height is a direct resource readout.
	draw_circle(p + Vector2(5, 7), 24, Color(.15, .2, .14, .18))
	draw_circle(p, 22, Color("e1d5af"))
	draw_circle(p, 15, Color("656c59"))
	draw_circle(p, 4 + clampf(float(v.water) / 100, 0, 1) * 10, S.RAIN.darkened(.2))
	_basket(p + Vector2(-42, 16), .75 + clampf(float(v.food) / 100, 0, 1) * .7)
	_text(p + Vector2(-30, 213), str(v.name), 31, S.INK, S.DISPLAY)
	var supplies := "Food %d  /  Water %d" % [roundi(float(v.food)), roundi(float(v.water))]
	_text(p + Vector2(-75, 233), supplies, 15, Color("3e5245"))
	draw_line(p + Vector2(-71, 242), p + Vector2(71, 242), Color(color, .7), 2)


func _house(p: Vector2, color: Color, index: int) -> void:
	draw_style_box(
		S.box(Color(.14, .22, .16, .17), Color.TRANSPARENT, 8),
		Rect2(p + Vector2(-13, -4), Vector2(52, 29))
	)
	draw_rect(Rect2(p + Vector2(-20, -17), Vector2(40, 32)), Color("ded6ae"))
	draw_rect(Rect2(p + Vector2(4, -17), Vector2(16, 32)), Color("c8c39e"))
	var roof := PackedVector2Array(
		[p + Vector2(-29, -13), p + Vector2(-5, -39), p + Vector2(29, -15), p + Vector2(5, -20)]
	)
	draw_colored_polygon(roof, color.darkened(.12 if index % 2 else .02))
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2]]), color.lightened(.2), 2, true)
	draw_rect(Rect2(p + Vector2(-6, -3), Vector2(10, 18)), Color("6a7360"))
	draw_line(p + Vector2(-21, 15), p + Vector2(22, 15), Color("a4a784"), 3)


func _shrine() -> void:
	var p := Vector2(500, 280)
	draw_circle(p + Vector2(0, 4), 38, Color("a8a581"))
	draw_arc(p, 33, 0, TAU, 32, Color("d5d0ad"), 7, true)
	draw_colored_polygon(
		PackedVector2Array(
			[
				p + Vector2(-13, 3),
				p + Vector2(-9, -45),
				p + Vector2(0, -53),
				p + Vector2(13, -39),
				p + Vector2(16, 3)
			]
		),
		Color("d9d6b7")
	)
	draw_colored_polygon(
		PackedVector2Array(
			[p + Vector2(0, -53), p + Vector2(13, -39), p + Vector2(16, 3), p + Vector2(4, 3)]
		),
		Color("bbbea2")
	)
	draw_arc(p + Vector2(0, -24), 6, 0, TAU, 20, Color("768975"), 2, true)
	_text(p + Vector2(-43, 58), "The old shrine", 17, Color("4d5e4c"), S.DISPLAY)


func _common_well() -> void:
	var at := Vector2(500, 405)
	draw_circle(at + Vector2(3, 4), 18, Color(.15, .2, .14, .18))
	draw_circle(at, 16, Color("d2cfad"))
	draw_circle(at, 11, Color("656c59"))
	draw_circle(at, maxf(2, 10 * float(state.get("well_water", 0)) / 160), S.RAIN.darkened(.25))
	_text(
		at + Vector2(30, 25),
		"Shared spring · %d" % roundi(float(state.get("well_water", 0))),
		14,
		Color("4d5e4c")
	)


func _basket(p: Vector2, s: float) -> void:
	draw_circle(p + Vector2(4, 4), 11 * s, Color(.2, .22, .12, .16))
	draw_style_box(
		S.box(Color("a78950"), Color("786b44"), 3),
		Rect2(p - Vector2(10, 5) * s, Vector2(20, 13) * s)
	)
	for i in range(4):
		draw_circle(p + Vector2(-6 + i * 4, -4 + sin(i) * 2) * s, 3.5 * s, S.WHEAT)


func _person(p: Dictionary) -> void:
	var at: Vector2 = displayed.get(p.id, p.pos)
	var walking: bool = at.distance_to(p.target) > 3
	var bob := sin(clock * 9 + int(p.id)) * 1.4 if walking and motion else 0.0
	var color := S.ALDER if int(p.village) == 0 else S.SEDGE
	if selected == int(p.id):
		draw_circle(at, 19, Color(S.PAPER, .3))
		draw_arc(at, 19, 0, TAU, 30, S.PAPER, 2, true)
	draw_circle(at + Vector2(4, 3), 8, Color(.16, .22, .15, .25))
	var foot := sin(clock * 9 + int(p.id)) * 2.8 if walking and motion else 1.0
	draw_line(at + Vector2(-2, 0), at + Vector2(-3, 5 + foot), S.INK, 2, true)
	draw_line(at + Vector2(2, 0), at + Vector2(3, 5 - foot), S.INK, 2, true)
	var body := PackedVector2Array(
		[
			at + Vector2(-4, -11 + bob),
			at + Vector2(4, -11 + bob),
			at + Vector2(7, 1),
			at + Vector2(-7, 1)
		]
	)
	draw_colored_polygon(body, color)
	draw_line(at + Vector2(-3, -8 + bob), at + Vector2(-5, -1), color.lightened(.35), 2, true)
	var skin := Color("e7c49b").lerp(Color("94744f"), (int(p.id) % 5) / 5.0)
	draw_circle(at + Vector2(0, -15 + bob), 4.5, skin)
	draw_arc(at + Vector2(0, -16 + bob), 4.5, PI, TAU, 12, Color("525b42"), 2.5, true)
	var action: String = p.action
	var icon := at + Vector2(13, -20)
	if action == "tell":
		draw_style_box(S.box(S.PAPER, Color.TRANSPARENT, 4), Rect2(icon, Vector2(18, 12)))
		for i in range(3):
			draw_circle(icon + Vector2(4 + i * 5, 6), 1, S.SLATE)
	elif action == "ritual":
		draw_arc(at + Vector2(0, -22), 8, PI, TAU, 16, S.WHEAT, 2, true)
		if motion:
			draw_circle(
				at + Vector2(sin(clock * 2 + int(p.id)) * 4, -28 - fmod(clock * 9 + int(p.id), 12)),
				1.5,
				S.PAPER
			)
	elif action == "share":
		_basket(at + Vector2(12, -2), .55)
		draw_line(at + Vector2(9, -9), at + Vector2(17, -9), S.PAPER, 2, true)
	elif action == "fetch":
		_basket(at + Vector2(10, -2), .45)
	elif action == "avoid":
		draw_line(icon, icon + Vector2(8, 6), S.SEDGE.darkened(.25), 2)
		draw_line(icon + Vector2(8, 0), icon + Vector2(0, 6), S.SEDGE.darkened(.25), 2)
	if selected == int(p.id):
		var caption: String = str(p.name) + " · " + action
		var width := S.BODY.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_style_box(
			S.box(Color(S.INK, .94), Color.TRANSPARENT, 4),
			Rect2(at + Vector2(-width / 2 - 7, 16), Vector2(width + 14, 26))
		)
		_text(at + Vector2(-width / 2, 34), caption, 15, S.PAPER)


func _draw_cause() -> void:
	var people: Array = state.get("people", [])
	if selected < 0 or selected >= people.size():
		return
	var person: Dictionary = people[selected]
	if person.memories.is_empty():
		return
	var memory: Dictionary = person.memories.back()
	var destination: Vector2 = person.pos
	var found := false
	if memory.source == "report" and int(memory.via) >= 0 and int(memory.via) < people.size():
		destination = people[int(memory.via)].pos
		found = true
	else:
		for event in state.get("events", []):
			if event.id == memory.event_id:
				destination = event.pos
				found = true
	if found:
		draw_dashed_line(person.pos, destination, Color(S.PAPER, .55), 1.5, 7, true)


func _effect(effect: Dictionary) -> void:
	var p: Vector2 = effect.pos
	var age: float = effect.age
	var fade: float = clampf(1 - age / float(effect.life), 0, 1)
	if effects_static:
		if effect.kind in ["rain", "food"]:
			draw_circle(p, 150, Color(S.RAIN if effect.kind == "rain" else S.WHEAT, .14 * fade))
		return
	if effect.kind == "rain":
		draw_circle(p, 150, Color(S.RAIN, .12 * fade))
		for i in range(70):
			var angle := i * 2.39996
			var spread := sqrt(float(i) / 70.0) * 140
			var drop := p + Vector2(cos(angle), sin(angle)) * spread
			drop.y -= fmod(age * 95 + i * 7, 52)
			draw_line(drop, drop + Vector2(-3, 13), Color(S.RAIN.lightened(.35), fade), 1.7, true)
		draw_arc(p, 40 + age * 25, 0, TAU, 50, Color(S.RAIN, fade * .6), 2, true)
	elif effect.kind == "food":
		draw_arc(p, age * 32 + 10, 0, TAU, 50, Color(S.WHEAT, fade), 3, true)
		for i in range(8):
			var angle := i * TAU / 8
			draw_circle(
				p + Vector2(cos(angle), sin(angle)) * (age * 18 + 12) - Vector2(0, age * 5),
				2.5,
				Color(S.PAPER, fade)
			)
	else:
		var captions := {
			"share": "shared food", "ritual": "a ritual", "tell": "a story", "avoid": "turned away"
		}
		var text: String = captions.get(effect.kind, "")
		if text != "":
			_text(p + Vector2(-20, -35 - age * 9), text, 13, Color(S.INK, fade))


func _text(at: Vector2, text: String, font_size: int, color: Color, font: Font = S.BODY) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
