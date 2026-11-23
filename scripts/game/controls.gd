extends RefCounted
## The game's controls: named actions with keyboard and controller defaults, remapping saved to
## settings.cfg, and readable names for the Options screen.
##
## Menus and cards use Godot's own ui_* actions (arrows, d-pad or left stick to move, Enter or the
## bottom face button to choose, Escape or the right face button to go back). The actions here are
## the game's own. On a controller, dice are thrown with a flick of the right stick (see
## game.gd, _pad_stick), or with the Throw button.

const Settings := preload("res://scripts/game/settings.gd")

## [action, label, default events]. Events are written as "key:<keycode>", "pad:<button>" or
## "axis:<axis>:<+1|-1>", so they can be saved as plain text.
const ACTIONS := [
	["throw", "Throw the dice", ["key:%d" % KEY_SPACE, "pad:%d" % JOY_BUTTON_Y]],
	["confirm", "Continue or confirm", ["key:%d" % KEY_ENTER, "key:%d" % KEY_KP_ENTER, "pad:%d" % JOY_BUTTON_START]],
	["best", "Place dice for the most good", ["key:%d" % KEY_B, "pad:%d" % JOY_BUTTON_X]],
	["magnify", "Hold to look closer at the tray", ["key:%d" % KEY_Z, "pad:%d" % JOY_BUTTON_RIGHT_SHOULDER]],
	["view", "Look between the tray and the board", ["key:%d" % KEY_V, "pad:%d" % JOY_BUTTON_LEFT_SHOULDER]],
	["fast_dice", "Fast dice on or off", ["key:%d" % KEY_F, "pad:%d" % JOY_BUTTON_BACK]],
	["log_up", "Scroll the Teller's lines up", ["key:%d" % KEY_PAGEUP, "axis:%d:1" % JOY_AXIS_TRIGGER_LEFT]],
	["log_down", "Scroll the Teller's lines down", ["key:%d" % KEY_PAGEDOWN, "axis:%d:1" % JOY_AXIS_TRIGGER_RIGHT]],
	["quit", "Quit the game", ["key:%d" % KEY_ESCAPE]],
]

const STICK_DEADZONE := 0.25


static func labels() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[a[0]] = a[1]
	return out


static func defaults(action: String) -> Array:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return []


static func bound(action: String) -> Array:
	var b = Settings.bindings.get(action)
	return b if b is Array and not b.is_empty() else defaults(action)


## Build the InputMap from the defaults and any saved remapping. Call once at start and after
## each change.
static func apply() -> void:
	for a in ACTIONS:
		var name: String = a[0]
		if InputMap.has_action(name):
			InputMap.erase_action(name)
		InputMap.add_action(name, 0.5)
		for code in bound(name):
			var e := parse(str(code))
			if e != null:
				InputMap.action_add_event(name, e)


static func parse(code: String) -> InputEvent:
	var p := code.split(":")
	match p[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(p[1]) as Key
			k.keycode = int(p[1]) as Key
			return k
		"pad":
			var b := InputEventJoypadButton.new()
			b.button_index = int(p[1]) as JoyButton
			return b
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(p[1]) as JoyAxis
			m.axis_value = float(p[2]) if p.size() > 2 else 1.0
			return m
	return null


## The saveable code for an event pressed on the remap screen, or "" if it can't be bound.
static func code_of(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return "key:%d" % k
	if e is InputEventJoypadButton:
		return "pad:%d" % e.button_index
	if e is InputEventJoypadMotion and absf(e.axis_value) > 0.6 \
			and e.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		return "axis:%d:1" % e.axis
	return ""


const PAD_NAMES := {
	JOY_BUTTON_A: "A / Cross", JOY_BUTTON_B: "B / Circle", JOY_BUTTON_X: "X / Square", JOY_BUTTON_Y: "Y / Triangle",
	JOY_BUTTON_BACK: "Back / Select", JOY_BUTTON_START: "Start / Options", JOY_BUTTON_LEFT_SHOULDER: "Left bumper",
	JOY_BUTTON_RIGHT_SHOULDER: "Right bumper", JOY_BUTTON_LEFT_STICK: "Left stick press",
	JOY_BUTTON_RIGHT_STICK: "Right stick press", JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}


static func describe(code: String) -> String:
	var p := code.split(":")
	match p[0]:
		"key": return OS.get_keycode_string(int(p[1]))
		"pad": return PAD_NAMES.get(int(p[1]), "Button %s" % p[1])
		"axis": return "Left trigger" if int(p[1]) == JOY_AXIS_TRIGGER_LEFT else "Right trigger"
	return code


## Every binding of an action, readable: "Space, Y / Triangle".
static func describe_action(action: String) -> String:
	return ", ".join(bound(action).map(func(c): return describe(str(c))))


## Rebind: a key replaces the action's keys, a controller input its controller inputs.
static func rebind(action: String, code: String) -> void:
	var is_key := code.begins_with("key:")
	var keep: Array = bound(action).filter(func(c): return str(c).begins_with("key:") != is_key)
	keep.append(code)
	Settings.bindings[action] = keep
	Settings.save_settings()
	apply()


static func reset() -> void:
	Settings.bindings = {}
	Settings.save_settings()
	apply()


## A throw velocity from the right stick at its furthest push in a flick. The stick's direction is
## taken on screen (up is away from you, across the tray) using the camera's view, and how far it
## was pushed sets the speed, up to the tray's hardest throw.
static func stick_velocity(peak: Vector2, cam: Basis, max_speed: float) -> Vector3:
	var strength := clampf((peak.length() - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
	var right := Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	var away := Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var dir := (right * peak.x - away * peak.y).normalized()
	return dir * lerpf(max_speed * 0.3, max_speed, strength)
