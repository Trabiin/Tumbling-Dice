extends RefCounted
## Shared look for the table's paper and wax UI: fonts, panels, buttons, and two small
## widgets drawn in code (a die tile and an odds bar). No image files.

const Dice := preload("res://scripts/rules/dice.gd")
const S := preload("res://scripts/rules/scoring.gd")

const INK := Color("#3a2210")
const INK_SOFT := Color("#6a4a2a")
const PAPER := Color("#ead7ab")
const PAPER_DARK := Color("#d4bb86")
const WAX := Color("#8a1e14")
const GOLD := Color("#f2c75c")
const EDGE := Color("#5a3a1c")

static var _fonts := {}


static func font(kind := "ui") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"title":
			f = load("res://fonts/CinzelDecorative-Bold.ttf")
		"body":
			f = load("res://fonts/IMFellEnglish-Regular.woff2")
		"italic":
			f = load("res://fonts/IMFellEnglish-Italic.woff2")
		_:
			var v := FontVariation.new()
			v.base_font = load("res://fonts/Cinzel.ttf")
			v.variation_opentype = {"wght": 700}
			f = v
	_fonts[kind] = f
	return f


static func paper_box(color := PAPER, border := EDGE, radius := 6, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func panel(color := PAPER, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", paper_box(color, EDGE, 6, margin))
	return p


static func label(text: String, size := 16, color := INK, kind := "ui") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap_label(text: String, size := 17, color := INK, kind := "body") -> Label:
	var l := label(text, size, color, kind)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


## A card-like button with a wax-red edge (choices, approaches, costs).
static func card_button(text: String, size := 17, kind := "body") -> Button:
	var b := Button.new()
	b.text = smart_quotes(text)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font(kind))
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, INK)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.45))
	var normal := paper_box(Color("#f2e3bd"), Color("#8a5a2a"), 5, 10)
	var hover := paper_box(Color("#fff2cc"), WAX, 5, 10)
	hover.set_border_width_all(3)
	var pressed := paper_box(Color("#e6cf98"), WAX, 5, 10)
	var disabled := paper_box(Color("#d8c8a0"), Color("#a08a6a"), 5, 10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	return b


## A compact wax-seal button (Throw, Continue, Fate actions).
static func seal_button(text: String, size := 15, color := WAX) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font("ui"))
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, Color("#fbe9c4"))
	b.add_theme_color_override("font_disabled_color", Color("#c8b490"))
	var mk := func(c: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.border_color = c.darkened(0.45)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 3
		return sb
	b.add_theme_stylebox_override("normal", mk.call(color))
	b.add_theme_stylebox_override("hover", mk.call(color.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", mk.call(color.darkened(0.2)))
	b.add_theme_stylebox_override("focus", mk.call(color.lightened(0.1)))
	b.add_theme_stylebox_override("disabled", mk.call(Color("#7a6a58")))
	return b


static func rule(color := EDGE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 2)
	return r


## Curly quotes for the IM Fell face: an opening quote after a space, bracket or line start.
static func smart_quotes(text: String) -> String:
	var out := ""
	var prev := " "
	for ch in text:
		if ch == "\"":
			out += "\u201c" if prev in [" ", "\n", "(", "[", "]", "\u2014"] else "\u201d"
		elif ch == "'":
			out += "\u2018" if prev in [" ", "\n", "(", "["] else "\u2019"
		else:
			out += ch
		prev = ch
	return out


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ===================================================================== widgets

## A die drawn as its silhouette (triangle d4, square d6, diamond d8, kite d10, pentagon d12,
## hexagon d20) in its material colour, with its aspect glyph and number range.
class DieTile extends Control:
	signal pressed(tile)
	var die: Dictionary
	var selected := false
	var dim := false
	var badge := ""         # small text under the tile ("in pouch", a value)
	var big := ""           # a big number drawn on the die (a thrown face)
	var hover := false
	var caption := Color("#f4e4c0")   # caption colour: light on dark trays, ink on paper

	func _init(d: Dictionary, size := 78.0) -> void:
		die = d
		custom_minimum_size = Vector2(size, size + 18)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = Dice.tooltip(d)
		mouse_entered.connect(func(): hover = true; queue_redraw())
		mouse_exited.connect(func(): hover = false; queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(self)
			accept_event()

	func _shape(n: int, c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var k: int = {4: 3, 6: 4, 8: 4, 10: 4, 12: 5, 20: 6}[n]
		var rot: float = {4: -PI / 2, 6: PI / 4, 8: -PI / 2, 10: -PI / 2, 12: -PI / 2, 20: 0.0}[n]
		for i in k:
			var a: float = rot + TAU * i / k
			var rr := r
			if n == 10 and (i == 1 or i == 3):
				rr = r * 0.62
			if n == 8 and (i == 1 or i == 3):
				rr = r * 0.78
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		return pts

	func _draw() -> void:
		var s := custom_minimum_size.x
		var c := Vector2(s / 2, s / 2)
		var r := s * 0.44
		var st: Dictionary = load("res://scripts/game/table.gd").style_for(die.material)
		var col_a: Color = st.a
		var col_b: Color = st.b
		var pts := _shape(die.sides, c, r)
		var alpha := 0.45 if dim else 1.0
		if selected:
			draw_colored_polygon(_shape(die.sides, c, r + 6), Color("#ffd75a", 0.95))
		elif hover and not dim:
			draw_colored_polygon(_shape(die.sides, c, r + 4), Color("#fff2cc", 0.7))
		var cols := PackedColorArray()
		for i in pts.size():
			cols.append(col_a.lerp(col_b, float(i) / pts.size()) * Color(1, 1, 1, alpha))
		draw_polygon(pts, cols)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, Color("#1a0e05", alpha), 2.5, true)
		var ink: Color = st.ink
		var f: Font = load("res://scripts/game/ui_kit.gd").font("ui")
		var text := big if big != "" else "d%d" % die.sides
		var fs := 22 if big != "" else 15
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string_outline(f, c + Vector2(-w / 2, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(st.ink_outline, alpha))
		draw_string(f, c + Vector2(-w / 2, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, alpha))
		# aspect glyph in a little circle at the top-left
		var ac: Color = Dice.ASPECT_COLOR[die.aspect]
		draw_circle(Vector2(12, 12), 10, Color(ac, alpha))
		draw_arc(Vector2(12, 12), 10, 0, TAU, 20, Color("#1a0e05", alpha), 1.5)
		var g: String = Dice.ASPECT_GLYPH[die.aspect]
		var gw := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(12 - gw / 2, 16.5), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE if die.aspect != "grace" else Color("#2a1608"))
		# weight pips at the top-right
		for i in int(die.weight):
			draw_circle(Vector2(s - 8 - i * 7, 8), 2.6, Color("#2a1608", alpha))
		if die.has("loaded_face"):
			draw_string(f, Vector2(s - 20, s - 4), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a01010", alpha))
		if die.cursed:
			draw_string(f, Vector2(4, s - 4), "~", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#a01010", alpha))
		if die.ally:
			draw_string(f, Vector2(4, s - 4), "ally", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#1a5a2a", alpha))
		var cap: String = badge if badge != "" else die.name.get_slice(" ", 0)
		var cw := f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(f, Vector2((s - cw) / 2, s + 13), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(caption, alpha) if not selected else Color("#b07a10"))


## Four coloured segments: Fail / Mixed / Success / Triumph, with percentages.
class OddsBar extends Control:
	var tiers: Array = [0.0, 0.0, 0.0, 0.0]
	var exact := true

	func _init() -> void:
		custom_minimum_size = Vector2(300, 30)

	func set_tiers(t: Array, p_exact := true) -> void:
		tiers = t
		exact = p_exact
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := 16.0
		var x := 0.0
		var f: Font = load("res://scripts/game/ui_kit.gd").font("ui")
		var names := ["Fail", "Mixed", "Success", "Triumph"]
		var cols: Array = load("res://scripts/rules/scoring.gd").TIER_COLORS
		draw_rect(Rect2(0, 0, w, h), Color("#2a1608"))
		for i in 4:
			var seg: float = w * float(tiers[i])
			if seg > 0.5:
				draw_rect(Rect2(x, 0, seg, h), cols[i])
				if seg > 34:
					var t := "%d%%" % roundi(tiers[i] * 100)
					var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
					draw_string(f, Vector2(x + (seg - tw) / 2, 12.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#1a0e05"))
			x += seg
		draw_rect(Rect2(0, 0, w, h), Color("#1a0e05"), false, 1.5)
		var lx := 0.0
		for i in 4:
			draw_rect(Rect2(lx, h + 5, 8, 8), cols[i])
			draw_string(f, Vector2(lx + 11, h + 13), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#3a2210"))
			lx += 66
		if not exact:
			draw_string(f, Vector2(w - 58, h + 13), "simulated", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#6a4a2a"))


## A row of small circles (Fate tokens, Effort sockets, a Danger clock).
class Pips extends Control:
	var filled := 0
	var total := 0
	var col := Color("#d4a13a")
	var empty_col := Color("#3a2a1a")
	var radius := 7.0

	func _init(c := Color("#d4a13a"), r := 7.0) -> void:
		col = c
		radius = r

	func set_count(f: int, t: int) -> void:
		filled = f
		total = t
		custom_minimum_size = Vector2(maxi(t, 1) * (radius * 2 + 4), radius * 2 + 2)
		queue_redraw()

	func _draw() -> void:
		for i in total:
			var c := Vector2(radius + 1 + i * (radius * 2 + 4), radius + 1)
			draw_circle(c, radius, col if i < filled else empty_col)
			draw_arc(c, radius, 0, TAU, 18, Color("#1a0e05"), 1.5)
