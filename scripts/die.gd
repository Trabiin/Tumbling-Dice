extends RigidBody3D
## A physical die whose mesh, collision shape and face labels are all generated in code.
##
## Spec keys (see dice_catalog.gd):
##   name         display name
##   sides        4, 6, 8, 10, 12 or 20
##   style        look: colours a/b, swirl, scale, metal, rough, sparkle, ink, ink_outline
##   labels       optional Array[String] of length `sides` (custom faces, in value order 1..n)
##   loaded_face  optional value (1..n) that the die is weighted to roll
##   load         0..1, how far the centre of mass is pushed away from that face (default 0.45)
##   radius       optional circumradius in world units
##   bevel        optional edge rounding multiplier (default 1, 0 = sharp)

const Geo := preload("res://scripts/dice_geometry.gd")
const Mats := preload("res://scripts/materials.gd")
const Sfx := preload("res://scripts/sfx.gd")
const FLAT_THRESHOLD := 0.97  # cos(~14°): below this the die is resting "cocked"

var spec: Dictionary
var sides: int
var labels: PackedStringArray            # labels[value - 1]
var face_normals: Array[Vector3] = []    # local space, one per value slot (value = index + 1)
var face_ups: Array[Vector3] = []        # local "up" direction of each face's text
var vertex_mode := false                 # d4: result is read from the vertex pointing up
var _radius := 0.6
var _audio: AudioStreamPlayer3D
var _last_hit := 0
signal hit(strength: float)   # a hard knock, so the scene can react (flames flicker)
static var _font: FontVariation


static func label_font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = load("res://fonts/Cinzel.ttf")
		_font.variation_opentype = {"wght": 900}  # Cinzel is a variable font: use its heaviest cut
	return _font


func setup(p_spec: Dictionary) -> void:
	spec = p_spec
	sides = spec.sides
	name = spec.get("name", "d%d" % sides).validate_node_name()
	_radius = spec.get("radius", _default_radius(sides))
	vertex_mode = sides == 4

	labels = PackedStringArray()
	if spec.has("labels"):
		labels = PackedStringArray(spec.labels)
	else:
		for v in range(1, sides + 1):
			labels.append(str(v))

	var shape := Geo.build(sides, _radius)
	var verts: PackedVector3Array = shape.verts
	var faces: Array = shape.faces

	# Value per face (or per vertex for the d4), opposite sides summing to n + 1.
	var slots := _assign_values(verts, faces)

	var hull := _build_mesh(verts, faces, slots)
	_build_collision(hull)
	_build_physics()


func _default_radius(n: int) -> float:
	return {4: 0.8, 6: 0.62, 8: 0.68, 10: 0.66, 12: 0.68, 20: 0.72}[n] * 1.3


# ------------------------------------------------------------------ values

## Returns, per face, the value slot (0-based) printed on it. For the d4 the
## slots belong to vertices and the returned array maps vertex index -> slot.
func _assign_values(verts: PackedVector3Array, faces: Array) -> PackedInt32Array:
	face_normals.resize(sides)
	face_ups.resize(sides)
	var slot := PackedInt32Array()
	if vertex_mode:
		slot.resize(verts.size())
		for i in verts.size():
			slot[i] = i
			face_normals[i] = verts[i].normalized()
		return slot

	slot.resize(faces.size())
	slot.fill(-1)
	var normals: Array[Vector3] = []
	for f in faces:
		normals.append(Geo.face_normal(verts, f))
	var low := 0
	var high := sides - 1
	for i in faces.size():
		if slot[i] != -1:
			continue
		slot[i] = low
		low += 1
		var best := -1  # the opposite face
		for j in faces.size():
			if j != i and slot[j] == -1 and normals[i].dot(normals[j]) < -0.999:
				best = j
		if best != -1:
			slot[best] = high
			high -= 1
	for i in faces.size():
		face_normals[slot[i]] = normals[i]
	return slot


# -------------------------------------------------------------------- mesh

## Builds the rounded-edge mesh (see Geo.chamfer) and the face labels.
## Returns the chamfered points, which double as the collision hull.
func _build_mesh(verts: PackedVector3Array, faces: Array, slots: PackedInt32Array) -> PackedVector3Array:
	var min_in := INF
	for f in faces:
		min_in = minf(min_in, Geo.face_inradius(verts, f))
	var bevel: float = min_in * 0.2 * spec.get("bevel", 1.0)

	var ch := Geo.chamfer(verts, faces, bevel)
	var inset: Array = ch.inset
	var normals: Array[Vector3] = ch.normals
	var hull: PackedVector3Array = ch.hull

	var style: Dictionary = spec.get("style", {})
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = ch.mesh
	mi.material_override = Mats.dice(style, randf() * 100.0)
	add_child(mi)

	var ink: Color = style.get("ink", Color.WHITE)
	var ink_outline: Color = style.get("ink_outline", Color.BLACK)
	if vertex_mode:
		for i in faces.size():
			var f: PackedInt32Array = faces[i]
			var c := Geo.face_center(verts, f)
			var r := Geo.face_inradius(verts, f) - bevel
			for k in f.size():
				var toward: Vector3 = inset[i][k] - c
				_add_label(labels[slots[f[k]]], c + toward * 0.56, normals[i], toward.normalized(), r * 0.62, ink, ink_outline)
	else:
		for i in faces.size():
			var f: PackedInt32Array = faces[i]
			var c := Geo.face_center(verts, f)
			var up := _label_up(verts, f, c)
			face_ups[slots[i]] = up
			var text := labels[slots[i]]
			if text == "6" or text == "9":
				text += "."  # tell 6 from 9
			var size := (Geo.face_inradius(verts, f) - bevel) * 1.3
			if sides == 10:
				size *= 1.1  # kites are narrow but tall
			_add_label(text, c, normals[i], up, size, ink, ink_outline)
	return hull


## Which way is "up" for the text on a face.
func _label_up(verts: PackedVector3Array, f: PackedInt32Array, c: Vector3) -> Vector3:
	if sides == 6:
		return ((verts[f[0]] + verts[f[1]]) * 0.5 - c).normalized()  # square to the edges
	# Triangles, pentagons and d10 kites: point at the farthest corner.
	var far := f[0]
	for i in f:
		if verts[i].distance_to(c) > verts[far].distance_to(c) + 1e-4:
			far = i
	return (verts[far] - c).normalized()


func _add_label(text: String, pos: Vector3, normal: Vector3, up: Vector3, size: float, color: Color, outline: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = label_font()
	l.font_size = 96
	# A darker outline reads like ink pressed into an engraved number.
	l.outline_size = 10
	l.outline_modulate = outline
	# Shrink long words so they still fit on the face.
	var chars := text.length()
	var height := size
	if chars == 2:
		height = size * 0.8
	elif chars > 2:
		height = size * (1.3 / chars + 0.2)
	l.pixel_size = height / l.font_size
	l.modulate = color
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.shaded = false  # painted numbers stay readable even on the shadowed side
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var z := normal.normalized()
	var y := (up - z * up.dot(z)).normalized()
	var x := y.cross(z)
	l.transform = Transform3D(Basis(x, y, z), pos + z * 0.004)
	add_child(l)


# ----------------------------------------------------------------- physics

func _build_collision(points: PackedVector3Array) -> void:
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	cs.shape = shape
	add_child(cs)


func _build_physics() -> void:
	mass = spec.get("mass", 1.0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	pm.bounce = 0.25
	physics_material_override = pm
	angular_damp = 0.4
	linear_damp = 0.1
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_audio = AudioStreamPlayer3D.new()
	_audio.max_polyphony = 3
	_audio.unit_size = 25.0
	add_child(_audio)

	if spec.has("loaded_face"):
		# Pull the centre of mass toward the face OPPOSITE the favoured one, so the
		# heavy side tends to end up on the bottom and the favoured face on top.
		var slot: int = spec.loaded_face - 1
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = -face_normals[slot] * _radius * spec.get("load", 0.45)


# ----------------------------------------------------------------- reading

## Which face ended up on top. Works at any time, but is only meaningful once settled.
func read_result() -> Dictionary:
	var best := -INF
	var best_slot := 0
	for i in sides:
		var d := (global_transform.basis * face_normals[i]).normalized().dot(Vector3.UP)
		if d > best:
			best = d
			best_slot = i
	return {
		"value": best_slot + 1,
		"label": labels[best_slot],
		"flatness": best,
		"cocked": best < FLAT_THRESHOLD,
	}


## Clack, thump or click, by what we hit and how hard.
func _on_body_entered(body: Node) -> void:
	var now := Time.get_ticks_msec()
	var speed := linear_velocity.length() + angular_velocity.length() * _radius * 0.3
	if speed < 1.2 or now - _last_hit < 45:
		return
	_last_hit = now
	var kind := "dice" if body is RigidBody3D else String(body.get_meta("surface", "wood"))
	_audio.stream = Sfx.get_sound(kind)
	_audio.volume_db = -4.0 + linear_to_db(clampf(speed / 14.0, 0.04, 1.0)) + (4.0 if kind == "felt" else 0.0)
	_audio.pitch_scale = randf_range(0.9, 1.12) * (1.15 if sides <= 6 else 1.0)
	_audio.play()
	hit.emit(speed)


func is_settled() -> bool:
	return linear_velocity.length() < 0.05 and angular_velocity.length() < 0.08


## Give the die a random throw from `from`, heading roughly along `dir`.
func throw_from(from: Vector3, dir: Vector3, rng: RandomNumberGenerator, power := 1.0) -> void:
	freeze = false
	sleeping = false
	# Four gaussians normalised = a uniformly random orientation (axis+angle is not uniform).
	var q := Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn()).normalized()
	global_transform = Transform3D(Basis(q), from)
	linear_velocity = dir.normalized() * rng.randf_range(9.0, 14.0) * power + Vector3(0, rng.randf_range(0, 3), 0)
	angular_velocity = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * rng.randf_range(12.0, 28.0)
