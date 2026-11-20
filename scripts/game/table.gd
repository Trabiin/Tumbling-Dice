extends Node3D
## The physical side of a throw: turns dice data into real rigid-body dice, throws them into
## the tray, waits for them to settle and reads the faces. The foe's dice are thrown from the
## far side and freeze in place, so you see the threat while you choose.

const Die := preload("res://scripts/die.gd")
const Dice := preload("res://scripts/rules/dice.gd")
const Catalog := preload("res://scripts/dice_catalog.gd")
const Tavern := preload("res://scripts/tavern.gd")

const SETTLE_TIMEOUT := 9.0

var rng := RandomNumberGenerator.new()
var tavern: Node3D
var font: Font
var player_nodes: Array = []
var foe_nodes: Array = []
var tags := {}


static func style_for(material: String) -> Dictionary:
	var th := Catalog.themes()
	match material:
		"dragon": return th[0]
		"bone": return th[1]
		"jade": return th[2]
		"brass": return th[3]
		"amethyst": return th[4]
		"oak":
			return {"a": Color("#c08a4e"), "b": Color("#6a4220"), "swirl": 2.2, "scale": 2.6, "contrast": 0.8, "rough": 0.7,
				"ink": Color("#2a1608"), "ink_outline": Color("#d8b884")}
		"bellmetal":
			return {"a": Color("#6f8a5a"), "b": Color("#c9a24a"), "swirl": 0.9, "scale": 2.0, "contrast": 0.7,
				"metal": 0.8, "rough": 0.35, "ink": Color("#1a2410"), "ink_outline": Color("#d8c27a")}
		"driftwood":
			return {"a": Color("#a8a49a"), "b": Color("#5c5a52"), "swirl": 2.5, "scale": 3.0, "contrast": 0.6, "rough": 0.85,
				"ink": Color("#1c1c1a"), "ink_outline": Color("#d4d0c4")}
	return th[1]


## A die spec for die.gd from a rules die. Rune faces get a gold (or red, for Bane) ink.
static func spec_for(d: Dictionary) -> Dictionary:
	var labels: Array = []
	var inks: Array = []
	for f in d.faces:
		labels.append(str(f.n))
		if f.rune == "bane":
			inks.append(Color("#ff4a3a"))
		elif f.rune != "":
			inks.append(Color("#ffd75a"))
		else:
			inks.append(null)
	var ph: Dictionary = Dice.PHYSICS.get(d.material, {})
	var spec := {"name": d.name, "sides": d.sides, "labels": labels, "face_inks": inks,
		"style": style_for(d.material), "mass": ph.get("mass", 1.0), "bounce": ph.get("bounce", 0.25),
		"friction": ph.get("friction", 0.55)}
	if d.has("loaded_face"):
		spec.loaded_face = d.loaded_face
		spec.load = d.get("load", 0.3)
	return spec


static func foe_spec(fd: Dictionary) -> Dictionary:
	return {"name": fd.name, "sides": fd.sides,
		"style": {"a": Color("#3a3a44"), "b": Color("#101016"), "swirl": 1.0, "scale": 2.0, "contrast": 0.8,
			"metal": 0.5, "rough": 0.4, "ink": Color("#e8e0d0"), "ink_outline": Color("#000000")},
		"mass": 1.2, "bounce": 0.15}


func _make(spec: Dictionary) -> RigidBody3D:
	var n := Die.new()
	n.setup(spec)
	if tavern != null:
		n.hit.connect(tavern.gust)
	add_child(n)
	var tag := Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font = font
	tag.font_size = 48
	tag.outline_size = 14
	tag.outline_modulate = Color("#1a0e05")
	tag.pixel_size = 0.014
	tag.visible = false
	add_child(tag)
	tags[n] = tag
	return n


func clear_player() -> void:
	for n in player_nodes:
		_free(n)
	player_nodes.clear()


func clear_foe() -> void:
	for n in foe_nodes:
		_free(n)
	foe_nodes.clear()


func _free(n) -> void:
	if tags.has(n):
		tags[n].queue_free()
		tags.erase(n)
	n.queue_free()


## Throw these rules dice into the tray. Returns [{node, value, cocked, alt}] once settled.
func throw_player(dice: Array) -> Array:
	clear_player()
	for d in dice:
		var n := _make(spec_for(d))
		n.set_meta("die", d)
		player_nodes.append(n)
	_launch(player_nodes, -1)
	await _wait_settle(player_nodes)
	return read(player_nodes)


## Throw some of the dice already in the tray again (Reroll, Echo, quakes, Wren's bell).
func rethrow(nodes: Array) -> Array:
	for n in nodes:
		tags[n].visible = false
	_launch(nodes, -1, 0.75)
	await _wait_settle(nodes)
	return read(nodes)


func throw_foe(foe_dice: Array) -> Array:
	clear_foe()
	for fd in foe_dice:
		var n := _make(foe_spec(fd))
		foe_nodes.append(n)
	_launch(foe_nodes, 1)
	await _wait_settle(foe_nodes)
	var vals: Array = []
	for i in foe_nodes.size():
		var n: RigidBody3D = foe_nodes[i]
		var r: Dictionary = n.read_result()
		# A foe die that ends up cocked takes its lower face: no free gifts for monsters.
		var v: int = r.value if not r.cocked else mini(r.value, r.alt_value)
		vals.append(v)
		n.freeze = true
		var tag: Label3D = tags[n]
		tag.text = "%s %d" % [foe_dice[i].name, v]
		tag.modulate = Color("#ff8a6a")
		tag.pixel_size = 0.011
		tag.global_position = n.global_position + Vector3(0, 1.6, 0)
		tag.visible = true
	return vals


func _launch(nodes: Array, side: int, power := 1.0) -> void:
	var count := nodes.size()
	for i in count:
		var n: RigidBody3D = nodes[i]
		n.freeze = false
		var z := lerpf(-3.8, 3.8, (i + 0.5) / count) + rng.randf_range(-0.4, 0.4)
		var from := Vector3(side * (Tavern.TRAY.x / 2 - 1.6), rng.randf_range(2.5, 4.5), z)
		n.throw_from(from, Vector3(-side, 0, rng.randf_range(-0.35, 0.35)), rng, power)


func _wait_settle(nodes: Array) -> void:
	var t := 0.0
	var still := 0
	while true:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var ok := nodes.all(func(n): return not is_instance_valid(n) or n.is_settled() or n.sleeping)
		still = still + 1 if ok else 0
		if still > 30 or t > SETTLE_TIMEOUT:
			break


func read(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		var r: Dictionary = n.read_result()
		var d: Dictionary = n.get_meta("die")
		var cocked: bool = r.cocked and Dice.trait_of(d) != "steadfast"
		out.append({"node": n, "value": r.value, "cocked": cocked, "alt": r.alt_value})
		show_tag(n, Dice.face_n(d, r.value - 1), cocked, d)
	return out


func show_tag(n, number: int, cocked: bool, d: Dictionary) -> void:
	var tag: Label3D = tags[n]
	tag.text = ("%d ?" % number) if cocked else str(number)
	tag.modulate = Color("#ff7a6a") if cocked else Dice.ASPECT_COLOR[d.aspect].lightened(0.35)
	tag.global_position = n.global_position + Vector3(0, 1.7, 0)
	tag.visible = true


## Turn a die in the tray so the given face (1-based value slot) is up: a Nudge, or a Steady.
func turn_to(n, value: int) -> void:
	var nl: Vector3 = n.face_normals[value - 1]
	n.freeze = true
	var basis := Basis(Quaternion(nl.normalized(), Vector3.UP))
	var pos: Vector3 = n.global_position
	pos.y = maxf(pos.y, 0.9)
	var tw := create_tween()
	tw.tween_property(n, "global_transform", Transform3D(basis, pos), 0.25)
	await tw.finished
	var d: Dictionary = n.get_meta("die")
	show_tag(n, Dice.face_n(d, value - 1), false, d)


## Light up a die (selected in the assignment UI).
func highlight(n, on: bool) -> void:
	if tags.has(n):
		tags[n].outline_modulate = Color("#ffd75a") if on else Color("#1a0e05")
		tags[n].pixel_size = 0.018 if on else 0.014
