extends RefCounted
## Shared presentation tokens and control atoms. No simulation dependencies.
const INK := Color("123333")
const SLATE := Color("416260")
const GRASS := Color("aba578")
const WHEAT := Color("ddd396")
const RAIN := Color("89c6d0")
const PAPER := Color("edf0da")
const MUTED := Color("acc1b3")
const ALDER := Color("417f88")
const SEDGE := Color("9a647a")
const ACCENT := Color("ddc875")
const BODY = preload("res://assets/fonts/Lato-Regular.ttf")
const DISPLAY = preload("res://assets/fonts/Alegreya-Regular.ttf")
const TOUCH := 44.0


static func box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 8) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1 if border.a > 0 else 0)
	result.set_corner_radius_all(radius)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	return result


static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 17
	result.set_color("font_color", "Label", PAPER)
	result.set_color("default_color", "RichTextLabel", PAPER)
	result.set_constant("line_separation", "RichTextLabel", 6)
	result.set_stylebox("normal", "Button", box(SLATE.darkened(0.25)))
	result.set_stylebox("hover", "Button", box(SLATE))
	result.set_stylebox("pressed", "Button", box(ALDER.darkened(0.2), RAIN))
	result.set_stylebox("focus", "Button", box(Color.TRANSPARENT, ACCENT))
	result.set_stylebox("disabled", "Button", box(INK.lightened(0.08)))
	result.set_color("font_color", "Button", PAPER)
	result.set_color("font_disabled_color", "Button", MUTED.darkened(0.35))
	var panel_style := box(INK)
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_bottom = 0
	result.set_stylebox("panel", "PanelContainer", panel_style)
	result.set_stylebox("panel", "PopupMenu", box(INK, SLATE))
	result.set_constant("v_separation", "PopupMenu", 18)
	result.set_font_size("font_size", "PopupMenu", 18)
	result.set_stylebox("normal", "LineEdit", box(INK.lightened(0.1), SLATE))
	result.set_color("font_color", "LineEdit", PAPER)
	return result


static func label(text: String, font_size: int = 17, color: Color = PAPER) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func heading(text: String, font_size: int = 32) -> Label:
	var result := label(text, font_size)
	result.add_theme_font_override("font", DISPLAY)
	return result


static func button(text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = TOUCH
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.pressed.connect(callback)
	return result


static func prose(text: String) -> RichTextLabel:
	var result := RichTextLabel.new()
	result.bbcode_enabled = true
	result.text = text
	result.fit_content = true
	result.scroll_active = false
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


static func margin(padding: int = 16) -> MarginContainer:
	var result := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		result.add_theme_constant_override("margin_" + side, padding)
	return result
