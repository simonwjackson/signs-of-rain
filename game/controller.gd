extends RefCounted
## Event-owned controller state. Modal/focus changes clear held camera input.
const DEADZONE := 0.2
const BUTTONS := {
	JOY_BUTTON_A: "activate",
	JOY_BUTTON_B: "back",
	JOY_BUTTON_X: "rain",
	JOY_BUTTON_Y: "food",
	JOY_BUTTON_START: "pause",
	JOY_BUTTON_BACK: "menu",
	JOY_BUTTON_DPAD_RIGHT: "next",
	JOY_BUTTON_DPAD_LEFT: "previous",
	JOY_BUTTON_DPAD_UP: "focus",
	JOY_BUTTON_DPAD_DOWN: "overview",
}
var device := -1
var axes: Dictionary = {}
var held: Dictionary = {}


func consume(event: InputEvent) -> String:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return ""
	if device >= 0 and event.device != device:
		return ""
	device = event.device
	if event is InputEventJoypadMotion:
		axes[event.axis] = event.axis_value
		return ""
	held[event.button_index] = event.pressed
	return str(BUTTONS.get(event.button_index, "")) if event.pressed else ""


func clear() -> void:
	axes.clear()
	held.clear()


func release_device(id: int) -> void:
	if device == id:
		clear()
		device = -1


func stick(x: int, y: int) -> Vector2:
	var raw := Vector2(float(axes.get(x, 0)), float(axes.get(y, 0))).limit_length()
	var length := raw.length()
	return (
		raw.normalized() * ((length - DEADZONE) / (1 - DEADZONE))
		if length > DEADZONE
		else Vector2.ZERO
	)


func movement() -> Dictionary:
	return {
		"scrolling": bool(held.get(JOY_BUTTON_RIGHT_STICK, false)),
		"pan": stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y),
		"orbit": stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y),
		"zoom":
		(
			int(held.get(JOY_BUTTON_RIGHT_SHOULDER, false))
			- int(held.get(JOY_BUTTON_LEFT_SHOULDER, false))
		),
	}
