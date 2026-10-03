extends Control
## Controls and causal account. All state arrives from the game binding.
signal command(name: String)
signal person_chosen(id: int)
const S = preload("res://ui/style.gd")
const Layout = preload("res://ui/layout.gd")
var header: PanelContainer
var bar: PanelContainer
var inspector: PanelContainer
var inspector_title: Label
var inspector_next: Button
var inspector_scroll: ScrollContainer
var account: RichTextLabel
var title: Label
var readout: Label
var hint: Label
var status: Label
var status_time := 0.0
var buttons: Dictionary = {}
var menu: MenuButton
var secondary: HBoxContainer
var action_row: HBoxContainer
var sheet: Control
var sheet_box: PanelContainer
var selected := -1
var snapshot: Dictionary = {}
var last_account := ""
var layout_plan: Dictionary = {}
var muted := false
var reduced_motion := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = S.theme()
	_build_header()
	_build_bar()
	_build_inspector()
	resized.connect(arrange)
	arrange()


func _process(delta: float) -> void:
	if status_time > 0:
		status_time -= delta
		if status_time <= 0:
			status.text = ""


func _panel() -> PanelContainer:
	var result := PanelContainer.new()
	add_child(result)
	return result


func _build_header() -> void:
	header = _panel()
	var padding := S.margin(12)
	header.add_child(padding)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	padding.add_child(row)
	title = S.heading("Signs of Rain", 32)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	readout = S.label("Day 1 / 7", 18)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)
	var info := S.button("?", func(): command.emit("help"))
	info.tooltip_text = "Controls and the story"
	info.custom_minimum_size.x = 44
	row.add_child(info)


func _build_bar() -> void:
	bar = _panel()
	var padding := S.margin(8)
	bar.add_child(padding)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	padding.add_child(column)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row = row
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	for item in [
		["observe", "Look", "1 · Select a person to inspect what they know"],
		["rain", "Rain · 2", "2 · Give water and help crops within the circle"],
		["food", "Food · 1", "3 · Leave food in the valley"]
	]:
		var name: String = item[0]
		var button := S.button(item[1], func(): command.emit(name))
		button.toggle_mode = true
		button.tooltip_text = item[2]
		row.add_child(button)
		buttons[name] = button
	var play := S.button("▶", func(): command.emit("pause"))
	play.custom_minimum_size.x = 44
	play.tooltip_text = "Space · Pause or resume time"
	row.add_child(play)
	buttons.pause = play
	secondary = HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 6)
	row.add_child(secondary)
	for item in [["people", "People"], ["speed", "1×"], ["restart", "Restart"]]:
		var name: String = item[0]
		var button := S.button(item[1], func(): command.emit(name))
		secondary.add_child(button)
		buttons[name] = button
	menu = MenuButton.new()
	menu.text = "…"
	menu.tooltip_text = "People, time, replay, sound, and controls"
	menu.custom_minimum_size = Vector2(44, 44)
	row.add_child(menu)
	var popup := menu.get_popup()
	popup.add_item("People", 0)
	popup.add_item("Next person     Tab", 9)
	popup.add_item("Change speed     F", 1)
	popup.add_item("Restart same seed     R", 2)
	popup.add_item("Replay my last attempt     P", 3)
	popup.add_item("Save replay", 4)
	popup.add_separator()
	popup.add_check_item("Mute sound     M", 5)
	popup.add_check_item("Reduce motion", 6)
	popup.add_item("Controls and story     H", 7)
	popup.add_item("Quit", 8)
	popup.id_pressed.connect(_menu_command)
	hint = S.label("Look at a person. Learn what they believe.", 14, S.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	status = S.label("", 17, S.WHEAT)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	status.z_index = 20


func _menu_command(id: int) -> void:
	var names := [
		"people", "speed", "restart", "replay", "save", "mute", "motion", "help", "quit", "next"
	]
	command.emit(names[id])


func _build_inspector() -> void:
	inspector = _panel()
	inspector.z_index = 10
	var padding := S.margin(16)
	inspector.add_child(padding)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	padding.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	inspector_title = S.heading("A person", 31)
	inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inspector_title)
	row.add_child(S.button("×", func(): person_chosen.emit(-1)))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	account = S.prose("")
	account.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(account)
	inspector_scroll = scroll
	inspector_next = S.button(
		"Next person     Tab", func(): person_chosen.emit((selected + 1) % 24)
	)
	column.add_child(inspector_next)
	inspector.hide()


func arrange() -> void:
	if not is_instance_valid(header):
		return
	layout_plan = Layout.plan(size, selected >= 0)
	_place(header, layout_plan.header)
	_place(bar, layout_plan.bar)
	_place(inspector, layout_plan.panel)
	secondary.visible = layout_plan.extra_inline
	inspector_next.visible = size.y >= Layout.SHORT
	var inspector_margin: MarginContainer = inspector.get_child(0)
	var inspector_column: VBoxContainer = inspector_margin.get_child(0)
	inspector_column.add_theme_constant_override("separation", 4 if size.y < Layout.SHORT else 10)
	for side in ["left", "right", "top", "bottom"]:
		inspector_margin.add_theme_constant_override(
			"margin_" + side, 4 if size.y < Layout.SHORT else 16
		)
	action_row.add_theme_constant_override("separation", 3 if size.x < 420 else 6)
	var header_margin: MarginContainer = header.get_child(0)
	var bar_margin: MarginContainer = bar.get_child(0)
	for side in ["left", "right", "top", "bottom"]:
		header_margin.add_theme_constant_override(
			"margin_" + side, 4 if layout_plan.compact else 12
		)
		bar_margin.add_theme_constant_override("margin_" + side, 4 if layout_plan.compact else 8)
	buttons.rain.text = "Rain 2" if size.x < 420 else "Rain · 2"
	buttons.food.text = "Food 1" if size.x < 420 else "Food · 1"
	hint.visible = not layout_plan.compact
	title.visible = size.x >= 480
	title.add_theme_font_size_override("font_size", 25 if layout_plan.compact else 32)
	status.position = Vector2(8, layout_plan.bar.position.y - 32)
	status.size = Vector2(maxf(1, size.x - 16), 28)
	if is_instance_valid(sheet_box):
		var width := minf(620, size.x - 20)
		var height := minf(600, size.y - 20)
		_place(sheet_box, Rect2((size - Vector2(width, height)) / 2, Vector2(width, height)))


func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func refresh(
	value: Dictionary, person: int, mode: String, paused: bool, speed: int, replaying: bool
) -> void:
	snapshot = value
	if selected != person:
		selected = person
		last_account = ""
		inspector.visible = selected >= 0
		arrange()
	var tick: int = value.get("tick", 0)
	var day := mini(7, tick / 80 + 1)
	var prefix := "Replay · " if replaying else ""
	readout.text = "%sDay %d / 7   ·   %d power" % [prefix, day, value.get("power", 0)]
	if value.get("ended", false):
		readout.text = "The drought is over   ·   Seed %d" % value.get("seed", 2401)
	buttons.pause.text = "▶" if paused else "Ⅱ"
	buttons.speed.text = "%d×" % speed
	for name in ["observe", "rain", "food"]:
		buttons[name].set_pressed_no_signal(mode == name)
	buttons.rain.disabled = int(value.get("power", 0)) < 2 or replaying or value.get("ended", false)
	buttons.food.disabled = int(value.get("power", 0)) < 1 or replaying or value.get("ended", false)
	var hints := {
		"observe": "Click a person to follow their story. Tab visits everyone.",
		"rain":
		"Rain · 2 power. Put a village well inside the circle to restore its water and crops.",
		"food": "Click to leave food. It costs 1 power. A gift can mean different things."
	}
	hint.text = hints[mode]
	if selected >= 0 and selected < value.get("people", []).size():
		_refresh_account(value.people[selected])


func _refresh_account(person: Dictionary) -> void:
	inspector_title.text = person.name
	var village_name: String = snapshot.villages[int(person.village)].name
	var belief_names := {
		"uncertain": "Still making sense of it",
		"care": "The giver cares for us",
		"ritual": "Our rituals bring gifts",
		"favoritism": "The giver chooses favorites"
	}
	var text := (
		"[color=#acc1b3]%s  ·  Hunger %d%%  ·  Thirst %d%%[/color]\n\n"
		% [village_name, roundi(person.hunger * 100), roundi(person.thirst * 100)]
	)
	text += "[font_size=22]" + belief_names.get(person.belief, person.belief) + "[/font_size]\n"
	text += "Conviction %d%%\n\n" % roundi(float(person.conviction) * 100)
	var current_action: String = (
		"considering a new sign"
		if person.get("goal", "") == "idle" and not person.memories.is_empty()
		else person.action
	)
	text += "[color=#89c6d0]Now: %s[/color]\n%s\n\n" % [current_action, person.cause]
	text += "[font_size=22]What led here[/font_size]\n"
	if person.memories.is_empty():
		text += "No miracle has reached them yet. They follow their needs and earlier habits.\n"
	else:
		var first := maxi(0, person.memories.size() - 6)
		for i in range(person.memories.size() - 1, first - 1, -1):
			var memory: Dictionary = person.memories[i]
			var event_kind := "an event"
			var event_day := 1
			for event in snapshot.events:
				if event.id == memory.event_id:
					event_kind = event.kind
					event_day = int(event.tick) / 80 + 1
			var source := "Saw it directly"
			if memory.source == "report":
				var sender := (
					str(snapshot.people[int(memory.via)].name)
					if int(memory.via) >= 0
					else "someone"
				)
				source = "Heard it from " + sender
			text += (
				"\n[color=#ddc875]Day %d · %s #%d[/color]\n%s on day %d.\n"
				% [event_day, event_kind, memory.event_id, source, int(memory.tick) / 80 + 1]
			)
			text += (
				"%s\n%s\n"
				% [belief_names.get(memory.interpretation, memory.interpretation), memory.reason]
			)
			if memory.source == "report":
				var names: PackedStringArray = []
				for id in memory.chain:
					if int(id) >= 0 and int(id) < snapshot.people.size():
						names.append(str(snapshot.people[int(id)].name))
				if not names.is_empty():
					text += "[color=#acc1b3]Story route: %s[/color]\n" % " > ".join(names)
	text += "\n[font_size=22]Choices made[/font_size]\n"
	var count := 0
	var logs: Array = snapshot.get("action_log", [])
	for i in range(logs.size() - 1, -1, -1):
		var entry: Dictionary = logs[i]
		if int(entry.person) != selected:
			continue
		text += "\nDay %d · %s\n%s\n" % [int(entry.tick) / 80 + 1, entry.action, entry.cause]
		count += 1
		if count == 4:
			break
	if text != last_account:
		account.text = text
		last_account = text


func toast(text: String) -> void:
	status.text = text
	status_time = 4.5


func close_sheet() -> void:
	if is_instance_valid(sheet):
		remove_child(sheet)
		sheet.queue_free()
		sheet = null
		sheet_box = null


func sheet_open() -> bool:
	return is_instance_valid(sheet)


func _sheet(title_text: String) -> VBoxContainer:
	close_sheet()
	sheet = Control.new()
	add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.z_index = 50
	var shade := ColorRect.new()
	shade.color = Color(S.INK, .78)
	sheet.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet_box = PanelContainer.new()
	sheet.add_child(sheet_box)
	sheet_box.add_theme_stylebox_override("panel", S.box(S.INK, S.SLATE, 12))
	var padding := S.margin(20)
	sheet_box.add_child(padding)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	padding.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := S.heading(title_text, 34)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	row.add_child(S.button("×", func(): command.emit("close")))
	arrange()
	return column


func show_help(intro: bool, seed_value: int) -> void:
	var column := _sheet("Signs of Rain" if intro else "Your acts. Their meanings.")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var text := (
		"[font_size=23]Seven days. Two villages. Eight measures of power.[/font_size]\n\n"
		+ "Alder and Sedge face the last week of a drought. You can give rain or food. "
		+ "You cannot tell people what your gifts mean.\n\n"
		+ "Someone hungry can see kindness. Someone who prayed can see an answered ritual. "
		+ "Someone left out can hear a story of favoritism. Watch what they do next.\n\n"
		+ "[color=#89c6d0]Try this[/color]\nWhen people approach the shrine, leave food nearby. "
		+ "Look at a witness. Watch the story travel. "
		+ "Then restart and help both villages, or do nothing.\n\n"
		+ "[color=#89c6d0]Controls[/color]\n1  Look and select a person\n"
		+ "2  Rain, then click a place · costs 2\n3  Food, then click a place · costs 1\n"
		+ "Space  Pause or resume\nTab  Follow the next person\nF  Change time speed\n"
		+ "R  Restart the same seed\nM  Mute sound\nH  Open this guide\n"
		+ "Escape  Close a panel or cancel a miracle\n\n"
		+ "The menu also has People, replay, reduced motion, and Quit. "
		+ "At normal speed the drought lasts 4 minutes 40 seconds. "
		+ "Pausing lets you inspect or act without losing time.\n\n"
		+ "Seed %d. No networks, no language model calls. " % seed_value
		+ "Rules and remembered events drive each person.\n\n"
		+ "There is no single good ending. More food does not guarantee more trust."
	)
	scroll.add_child(S.prose(text))
	column.add_child(
		S.button(
			"Enter the valley" if intro else "Return to the valley",
			func(): command.emit("begin" if intro else "close")
		)
	)


func show_people(people: Array) -> void:
	var column := _sheet("People of the valley")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for person in people:
		var id: int = person.id
		var village := "Alder" if int(person.village) == 0 else "Sedge"
		var button := S.button(
			"%s · %s\n%s" % [person.name, village, person.action],
			func():
				close_sheet()
				person_chosen.emit(id)
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(button)


func show_ending(summary: Dictionary) -> void:
	var column := _sheet(str(summary.get("title", "The drought is over")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var text: String = summary.get("text", "The week ends. Its stories remain.")
	text += "\n\n[color=#89c6d0]What the valley remembers[/color]\n"
	var metrics: Dictionary = summary.get("metrics", {})
	for key in ["shares", "rituals", "reports", "avoidance"]:
		text += "%s: %s\n" % [key.capitalize(), str(metrics.get(key, 0))]
	text += (
		"\nInspect people after closing this account. Try the same seed with different choices, "
		+ "or replay your exact last attempt."
	)
	scroll.add_child(S.prose(text))
	column.add_child(S.button("Try again, same seed", func(): command.emit("restart")))
	column.add_child(S.button("Stay and listen", func(): command.emit("close")))


func update_toggles(sound_muted: bool, still: bool) -> void:
	muted = sound_muted
	reduced_motion = still
	var popup := menu.get_popup()
	popup.set_item_checked(popup.get_item_index(5), muted)
	popup.set_item_checked(popup.get_item_index(6), reduced_motion)
