extends RefCounted
## One policy for width and height. Actions survive in a window-level menu.
const WIDE := 1050.0
const SHORT := 500.0
const HEADER := 76.0
const COMPACT_HEADER := 56.0
const BAR := 82.0
const COMPACT_BAR := 58.0
const PANEL := 330.0


static func plan(size: Vector2, has_panel: bool) -> Dictionary:
	var compact := size.y < SHORT or size.x < 620.0
	var header := COMPACT_HEADER if compact else HEADER
	var bar := COMPACT_BAR if compact else BAR
	var docked := has_panel and size.x >= WIDE and size.y >= SHORT
	var side := PANEL if docked else 0.0
	var world := Rect2(0, header, size.x - side, maxf(1.0, size.y - header - bar))
	var panel := Rect2(size.x - PANEL, header, PANEL, size.y - header - bar)
	if not docked:
		panel = Rect2(
			maxf(0.0, size.x - PANEL), header, minf(PANEL, size.x), maxf(1.0, size.y - header - bar)
		)
	return {
		"compact": compact,
		"docked": docked,
		"header": Rect2(0, 0, size.x, header),
		"world": world,
		"panel": panel,
		"bar": Rect2(0, size.y - bar, size.x, bar),
		"extra_inline": size.x >= 860.0,
	}
