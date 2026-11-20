extends Node3D
## Dice at the inn. Builds the tavern, a themed dice set, and the UI in code.
##
## Controls: Space / left click = throw all, 1-9 = throw one die, T = next dice set,
##           E = add/remove the special dice, G = gallery view, Esc = quit.
## Command-line (after `--`):
##   --capture          throw once automatically and quit after the dice settle
##   --shot=<file.png>  save a screenshot when the dice settle (or of the gallery)
##   --gallery          lay all dice out for inspection instead of throwing
##   --seed=<int>       make throws repeatable
##   --theme=<n>        start with dice set n (0-4)
##   --extras           include the loaded and combat dice

const Die := preload("res://scripts/die.gd")
const Catalog := preload("res://scripts/dice_catalog.gd")
const Tavern := preload("res://scripts/tavern.gd")

const INK := Color("#3a2210")
const GOLD := Color("#f2c75c")

var rng := RandomNumberGenerator.new()
var tavern: Node3D
var camera: Camera3D
var dice: Array = []
var result_tags: Dictionary = {}
var theme_index := 0
var with_extras := false

var title_label: Label
var result_label: Label
var banner: Label
var font_ui: Font
var font_title: Font

var rolling := false
var roll_time := 0.0
var settle_frames := 0
var in_gallery := false
var has_rolled := false

var opt_capture := false
var opt_still := false   # --still: render the scene as it is, no throw, no UI
var opt_shot := ""
var debug_cam := PackedFloat64Array()   # --cam=x,y,z,tx,ty,tz for inspecting the scene


func _ready() -> void:
	var start_gallery := _parse_args()
	font_ui = _font("res://fonts/Cinzel.ttf", 700)
	font_title = load("res://fonts/CinzelDecorative-Bold.ttf")
	tavern = Tavern.new()
	add_child(tavern)
	camera = Camera3D.new()
	add_child(camera)
	# Painterly depth of field: the room behind the tray softens (Forward+ only).
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 75.0
	attr.dof_blur_far_transition = 90.0
	attr.dof_blur_amount = 0.05
	camera.attributes = attr
	_camera_tray()
	_build_ui()
	_spawn_dice()

	if start_gallery:
		_gallery()
		await _wait_frames(30)
		_finish()
		return
	if opt_still:
		for c in get_children():
			if c is CanvasLayer:
				c.visible = false
		await _wait_frames(45)
		_finish()
		return
	if opt_capture:
		await get_tree().create_timer(0.5).timeout
		throw_dice(dice)


func _parse_args() -> bool:
	var gallery := false
	var seeded := false
	for a in OS.get_cmdline_user_args():
		if a == "--capture": opt_capture = true
		elif a == "--still": opt_still = true
		elif a == "--gallery": gallery = true
		elif a == "--extras": with_extras = true
		elif a.begins_with("--shot="): opt_shot = a.substr(7)
		elif a.begins_with("--theme="): theme_index = int(a.substr(8))
		elif a.begins_with("--cam="): debug_cam = PackedFloat64Array(Array(a.substr(6).split(",")).map(func(v): return float(v)))
		elif a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
			seed(int(a.substr(7)))
			seeded = true
	if not seeded:
		rng.randomize()
	return gallery


func _font(path: String, weight: int) -> Font:
	var f := FontVariation.new()
	f.base_font = load(path)
	f.variation_opentype = {"wght": weight}
	return f


func _camera_tray() -> void:
	if result_label:
		result_label.get_parent().get_parent().visible = true
		for d in result_tags: result_tags[d].pixel_size = 0.016
	camera.fov = 52
	camera.position = Vector3(0, 9.5, 17.0)
	camera.look_at(Vector3(0, 0.0, -6.0))
	_apply_debug_cam()
	_cam_rest = camera.transform


var _cam_rest := Transform3D()
var _breath := 0.0


## The camera drifts very slightly, like someone leaning over the table.
func _process(delta: float) -> void:
	if in_gallery or debug_cam.size() == 6:
		return
	_breath += delta
	var off := Vector3(sin(_breath * 0.37) * 0.18, sin(_breath * 0.29 + 1.0) * 0.1, sin(_breath * 0.21) * 0.12)
	camera.transform = _cam_rest.translated(off).rotated_local(Vector3.FORWARD, sin(_breath * 0.17) * 0.004)


func _apply_debug_cam() -> void:
	if debug_cam.size() == 6:
		camera.position = Vector3(debug_cam[0], debug_cam[1], debug_cam[2])
		camera.look_at(Vector3(debug_cam[3], debug_cam[4], debug_cam[5]))


# ------------------------------------------------------------------ dice

func _spawn_dice() -> void:
	for d in dice:
		result_tags[d].queue_free()
		d.queue_free()
	dice.clear()
	result_tags.clear()
	var themes := Catalog.themes()
	theme_index = posmod(theme_index, themes.size())
	var specs := Catalog.make_set(themes[theme_index])
	if with_extras:
		specs.append_array(Catalog.extras())
	for spec in specs:
		var d := Die.new()
		d.setup(spec)
		d.hit.connect(tavern.gust)
		add_child(d)
		dice.append(d)
		var tag := Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.font = font_ui
		tag.font_size = 48
		tag.outline_size = 14
		tag.outline_modulate = Color("#1a0e05")
		tag.modulate = GOLD
		tag.pixel_size = 0.016
		tag.visible = false
		add_child(tag)
		result_tags[d] = tag
	title_label.text = themes[theme_index].name
	_park_dice()
	_refresh_ui()


func _park_dice() -> void:
	# Lined up along the back wall of the tray.
	var n := dice.size()
	for i in n:
		var d: RigidBody3D = dice[i]
		d.freeze = true
		d.global_transform = Transform3D(Basis(), Vector3(lerpf(-7.2, 7.2, (i + 0.5) / n), 1.1, -4.3))
		d.freeze = false
		d.sleeping = false


func throw_dice(which: Array) -> void:
	if in_gallery:
		in_gallery = false
		_camera_tray()
	for t in result_tags.values():
		t.visible = false
	for i in which.size():
		var d = which[i]
		var z := lerpf(-4.0, 4.0, (i + 0.5) / which.size()) + rng.randf_range(-0.3, 0.3)
		var from := Vector3(-Tavern.TRAY.x / 2 + 1.4, rng.randf_range(2.5, 4.5), z)
		d.throw_from(from, Vector3(1, 0, rng.randf_range(-0.35, 0.35)), rng)
	banner.modulate.a = 0.0
	rolling = true
	has_rolled = true
	roll_time = 0.0
	settle_frames = 0
	_refresh_ui()


func _physics_process(delta: float) -> void:
	if not rolling:
		return
	roll_time += delta
	var all_still := dice.all(func(d): return d.is_settled() or d.sleeping)
	settle_frames = settle_frames + 1 if all_still else 0
	if settle_frames > 30 or roll_time > 10.0:
		rolling = false
		_on_settled()


func _on_settled() -> void:
	var parts: Array[String] = []
	for d in dice:
		var r: Dictionary = d.read_result()
		var tag: Label3D = result_tags[d]
		tag.text = ("%s ?" % r.label) if r.cocked else r.label
		tag.modulate = Color("#ff7a6a") if r.cocked else GOLD
		tag.global_position = d.global_position + Vector3(0, 1.7, 0)
		tag.visible = true
		parts.append("%s=%s" % [d.spec.name, r.label])
		if d.spec.name == "d20" and not r.cocked:
			if r.value == 20:
				_show_banner("Natural 20!", GOLD)
			elif r.value == 1:
				_show_banner("Critical Fail", Color("#ff6a50"))
	print("ROLL: ", ", ".join(parts))
	_refresh_ui()
	if opt_capture:
		await _wait_frames(50)
		_finish()


## Numeric value of a die for sums: d10 "0" counts as 10.
func _numeric(d, r: Dictionary) -> int:
	if d.spec.get("percentile", false) or (d.spec.has("labels") and not d.spec.get("numeric", false)):
		return 0
	return r.value


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#e6d2a6")
	sb.border_color = Color("#5a3a1c")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	title_label = Label.new()
	title_label.add_theme_font_override("font", font_title)
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("#6a1010"))
	vb.add_child(title_label)
	var rule := ColorRect.new()
	rule.color = Color("#5a3a1c")
	rule.custom_minimum_size = Vector2(0, 2)
	vb.add_child(rule)
	result_label = Label.new()
	result_label.add_theme_font_override("font", font_ui)
	result_label.add_theme_font_size_override("font_size", 17)
	result_label.add_theme_color_override("font_color", INK)
	vb.add_child(result_label)

	var hint := Label.new()
	hint.text = "Space: throw    1-9: one die    T: next dice set    E: special dice    G: gallery"
	hint.add_theme_font_override("font", font_ui)
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("#f0dcb0"))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	layer.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)

	banner = Label.new()
	banner.add_theme_font_override("font", font_title)
	banner.add_theme_font_size_override("font_size", 64)
	banner.add_theme_color_override("font_outline_color", Color("#1a0a02"))
	banner.add_theme_constant_override("outline_size", 18)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	layer.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_WIDTH, 40)
	banner.size.x = 900
	banner.position.x = (1280 - 900) / 2.0


func _show_banner(text: String, color: Color) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.modulate.a = 0.0
	banner.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.5)
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)


func _refresh_ui() -> void:
	var lines: Array[String] = []
	var total := 0
	var d10 := -1
	var pct := -1
	for d in dice:
		var r: Dictionary = d.read_result()
		var val: String = ("..." if rolling else "-") if (rolling or not has_rolled) else r.label + ("  (cocked)" if r.cocked else "")
		lines.append("%s   %s" % [d.spec.name.rpad(10), val])
		total += _numeric(d, r)
		if d.spec.name == "d10": d10 = r.value % 10
		if d.spec.name == "d%": pct = (r.value % 10) * 10
	if not rolling and has_rolled:
		lines.append("")
		lines.append("Total   %d" % total)
		if d10 >= 0 and pct >= 0:
			var p := pct + d10
			lines.append("Percentile   %d" % (100 if p == 0 else p))
	result_label.text = "\n".join(lines)


func _gallery() -> void:
	in_gallery = true
	result_label.get_parent().get_parent().visible = false
	camera.fov = 40
	camera.position = Vector3(0, 9.0, 11.5)
	camera.look_at(Vector3(0, 0.2, 0.2))
	_apply_debug_cam()
	var n := dice.size()
	var per_row := 4 if n <= 8 else 5
	for i in n:
		var d = dice[i]
		d.freeze = true
		var row := i / per_row
		var in_row := mini(per_row, n - row * per_row)
		var col := i % per_row
		var pos := Vector3((col - (in_row - 1) / 2.0) * 3.6, 1.1, -1.9 + row * 3.6)
		# Show the highest face toward the camera, text upright.
		var slot: int = 3 if d.sides == 4 else d.sides - 1
		var n_local: Vector3 = d.face_normals[slot]
		var target := (camera.position - pos).normalized()  # facing the camera, away from the lantern's glare
		var basis := Basis(Quaternion(n_local, target))
		if d.sides != 4:
			var u: Vector3 = basis * d.face_ups[slot]
			var want := camera.global_basis.y
			u = (u - target * u.dot(target)).normalized()
			want = (want - target * want.dot(target)).normalized()
			basis = Basis(target, u.signed_angle_to(want, target)) * basis
		d.global_transform = Transform3D(basis, pos)
		var tag: Label3D = result_tags[d]
		tag.text = d.spec.name
		tag.modulate = Color("#f0dcb0")
		tag.pixel_size = 0.016 * clampf(5.0 / d.spec.name.length(), 0.55, 1.0)
		tag.global_position = pos + Vector3(0, -0.6, 1.5)
		tag.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: throw_dice(dice)
			KEY_T:
				theme_index += 1
				_respawn()
			KEY_E:
				with_extras = not with_extras
				_respawn()
			KEY_G:
				if in_gallery:
					in_gallery = false
					_camera_tray()
					_park_dice()
					for t in result_tags.values(): t.visible = false
				else:
					_gallery()
			KEY_ESCAPE: get_tree().quit()
			_:
				var k: int = event.keycode - KEY_1
				if k >= 0 and k < dice.size():
					throw_dice([dice[k]])
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		throw_dice(dice)


func _respawn() -> void:
	var was_gallery := in_gallery
	rolling = false
	has_rolled = false
	_spawn_dice()
	if was_gallery:
		_gallery()
	else:
		_camera_tray()


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _finish() -> void:
	if opt_shot != "":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(opt_shot)
		print("Saved ", opt_shot)
	get_tree().quit()
