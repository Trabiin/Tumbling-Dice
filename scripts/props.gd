extends RefCounted
## Code-built prop shapes with real silhouettes: lathed candles and dishes, wax drips,
## and bent, knobbly firewood. Everything returns meshes; materials come from materials.gd.

const Mats := preload("res://scripts/materials.gd")


## Spins a profile (x = radius, y = height) around the Y axis. `wobble(angle, y) -> float`
## scales the radius per vertex for hand-made unevenness. Smooth normals throughout; repeat
## a profile point to get a hard crease there.
static func lathe(profile: PackedVector2Array, segments := 48, wobble := Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := profile.size()
	for j in rows:
		for i in segments + 1:
			var a := TAU * i / segments
			var r := profile[j].x
			if wobble.is_valid():
				r *= wobble.call(a, profile[j].y)
			st.set_uv(Vector2(float(i) / segments, profile[j].y))
			st.add_vertex(Vector3(cos(a) * r, profile[j].y, sin(a) * r))
	for j in rows - 1:
		for i in segments:
			var a := j * (segments + 1) + i
			var b := a + segments + 1
			# clockwise seen from outside = front face in Godot
			st.add_index(a); st.add_index(a + 1); st.add_index(b)
			st.add_index(a + 1); st.add_index(b + 1); st.add_index(b)
	st.generate_normals()
	return st.commit()


## A tube along a spine with per-point radius, capped at both ends. UV.x runs along the
## tube in world units, UV.y around it. Caps carry vertex colour r = 1 and UV2 = position
## on the cut face (-1..1), for end-grain shading. `bumps(along, angle) -> float` scales
## the radius (bark ridges, knots).
static func tube(spine: PackedVector3Array, radii: PackedFloat32Array, segments := 20, bumps := Callable()) -> ArrayMesh:
	var n := spine.size()
	# parallel-transport frames so the rings don't twist
	var tangents: Array[Vector3] = []
	for i in n:
		var t: Vector3
		if i == 0: t = spine[1] - spine[0]
		elif i == n - 1: t = spine[i] - spine[i - 1]
		else: t = spine[i + 1] - spine[i - 1]
		tangents.append(t.normalized())
	var side := tangents[0].cross(Vector3.UP)
	if side.length() < 0.1:
		side = tangents[0].cross(Vector3.RIGHT)
	side = side.normalized()
	var sides: Array[Vector3] = []
	for i in n:
		if i > 0:
			side = (side - tangents[i] * side.dot(tangents[i])).normalized()
		sides.append(side)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var rings: Array = []
	for i in n:
		if i > 0:
			along += spine[i].distance_to(spine[i - 1])
		var up := tangents[i].cross(sides[i])
		var ring := PackedVector3Array()
		for k in segments + 1:
			var a := TAU * k / segments
			var r := radii[i]
			if bumps.is_valid():
				r *= bumps.call(along, a)
			var p := spine[i] + (sides[i] * cos(a) + up * sin(a)) * r
			ring.append(p)
			st.set_color(Color(0, 0, 0))
			st.set_uv(Vector2(along, float(k) / segments))
			st.set_uv2(Vector2.ZERO)
			st.add_vertex(p)
		rings.append(ring)
	for i in n - 1:
		for k in segments:
			var a := i * (segments + 1) + k
			var b := a + segments + 1
			st.add_index(a); st.add_index(b); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(b); st.add_index(b + 1)
	# end caps (separate vertices so they get flat normals and end-grain colouring)
	var base := n * (segments + 1)
	for end in [0, n - 1]:
		var ring: PackedVector3Array = rings[end]
		var c := spine[end]
		var outward := -tangents[0] if end == 0 else tangents[n - 1]
		var up := tangents[end].cross(sides[end])
		var start := base
		st.set_color(Color(1, 0, 0)); st.set_uv(Vector2.ZERO); st.set_uv2(Vector2.ZERO)
		st.add_vertex(c + outward * radii[end] * 0.08)  # slightly domed saw cut
		base += 1
		for k in segments + 1:
			var a := TAU * k / segments
			st.set_color(Color(1, 0, 0))
			st.set_uv(Vector2.ZERO)
			st.set_uv2(Vector2(cos(a), sin(a)))
			st.add_vertex(ring[k])
			base += 1
		for k in segments:
			if end == 0:
				st.add_index(start); st.add_index(start + 1 + k); st.add_index(start + 2 + k)
			else:
				st.add_index(start); st.add_index(start + 2 + k); st.add_index(start + 1 + k)
	st.generate_normals()
	var mesh := st.commit()
	_fix_winding(mesh)
	return mesh


## Tubes are built without caring which way round the triangles go; flip them all if
## most face inward (Godot culls counter-clockwise faces).
static func _fix_winding(mesh: ArrayMesh) -> void:
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var score := 0.0
	for t in range(0, idx.size(), 3):
		var face := (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]])
		score += face.dot(nrm[idx[t]])
	if score > 0.0:  # Godot front faces are clockwise: their cross product points inward
		for t in range(0, idx.size(), 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.clear_surfaces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


# ------------------------------------------------------------------- candle

## A burning candle standing at the origin: lathed body with a melted crater and uneven lip,
## wax drips running down, a wick, and a pool of spilled wax. Returns the node and the
## height of the flame base.
static func candle(radius: float, height: float, rng: RandomNumberGenerator, color := Color("#efe2c2")) -> Dictionary:
	var root := Node3D.new()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.3
	var lip := height + radius * 0.12
	var wax := Mats.wax(color, height)
	var prof := PackedVector2Array([
		Vector2(0.001, 0), Vector2(radius * 1.02, 0), Vector2(radius, radius * 0.3),
		Vector2(radius * 0.99, height * 0.6), Vector2(radius * 0.97, height - radius * 0.2),
		Vector2(radius * 0.93, lip), Vector2(radius * 0.8, lip + radius * 0.02),  # rounded, raised lip
		Vector2(radius * 0.62, height - radius * 0.12), Vector2(radius * 0.3, height - radius * 0.32),
		Vector2(0.001, height - radius * 0.36)])                                       # melted crater
	var body := MeshInstance3D.new()
	body.mesh = lathe(prof, 40, func(a: float, y: float) -> float:
		var top := smoothstep(height - radius, lip, y)
		return 1.0 + noise.get_noise_2d(cos(a) * 1.5, sin(a) * 1.5 + y * 0.05) * (0.04 + 0.12 * top))
	body.material_override = wax
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)

	# Drips: fat runs of wax from the lip, each ending in a blob.
	var drips := rng.randi_range(4, 7)
	for i in drips:
		var a := rng.randf() * TAU
		var length := rng.randf_range(0.15, 0.75) * height
		var w := radius * rng.randf_range(0.2, 0.32)
		var dir := Vector3(cos(a), 0, sin(a))
		var spine := PackedVector3Array()
		var radii := PackedFloat32Array()
		var steps := 10
		for k in steps + 1:
			var t := float(k) / steps
			var y := lip - radius * 0.05 - t * length
			var sway := sin(t * 5.0 + a * 3.0) * radius * 0.08
			var r_out := radius * 0.95 + w * 0.55
			spine.append(dir * r_out + dir.cross(Vector3.UP) * sway + Vector3(0, y, 0))
			# thin at the top, swelling to a drop at the bottom
			radii.append(w * (0.55 + 0.45 * t + 0.6 * smoothstep(0.75, 0.95, t) - 0.9 * smoothstep(0.96, 1.0, t)))
		var d := MeshInstance3D.new()
		d.mesh = tube(spine, radii, 10)
		d.material_override = wax
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(d)

	# A puddle of wax that ran all the way down.
	var pool := MeshInstance3D.new()
	pool.mesh = lathe(PackedVector2Array([Vector2(0.001, radius * 0.25), Vector2(radius * 1.25, radius * 0.22),
		Vector2(radius * 1.55, radius * 0.1), Vector2(radius * 1.6, 0.0)]), 32,
		func(a: float, _y: float) -> float: return 1.0 + noise.get_noise_2d(cos(a) * 3.0 + 9.0, sin(a) * 3.0) * 0.35)
	pool.material_override = wax
	root.add_child(pool)

	# Wick: bent, black, glowing at the tip.
	var wick := MeshInstance3D.new()
	var base_y := height - radius * 0.36
	var wh := radius * 0.55
	wick.mesh = tube(PackedVector3Array([Vector3(0, base_y - 0.05, 0), Vector3(0.0, base_y + wh * 0.6, 0),
		Vector3(wh * 0.25, base_y + wh, 0)]), PackedFloat32Array([0.06, 0.055, 0.04]), 6)
	wick.material_override = Mats.plain(Color("#1a1210"), 0.9)
	root.add_child(wick)
	var tip := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.06
	tm.height = 0.12
	tip.mesh = tm
	tip.material_override = Mats.glow(Color("#ff5a1a"), 4.0)
	tip.position = Vector3(wh * 0.25, base_y + wh, 0)
	root.add_child(tip)
	return {"node": root, "flame_y": base_y + wh * 0.35}


## A cartoon flame card of the given height, its base at `pos`.
static func flame(pos: Vector3, h: float, params := {}, width := 0.62) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(h * width, h)
	q.center_offset = Vector3(0, h * 0.5, 0)
	mi.mesh = q
	mi.material_override = Mats.flame(params)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.extra_cull_margin = h
	return mi


## A brass candle dish with a raised rim and a ring handle.
static func candle_dish(radius: float) -> Node3D:
	var root := Node3D.new()
	var brass := Mats.metal(Color("#c08f3c"), 0.3)
	var r := radius
	var dish := MeshInstance3D.new()
	dish.mesh = lathe(PackedVector2Array([
		Vector2(0.001, 0), Vector2(r * 0.85, 0), Vector2(r, r * 0.08), Vector2(r * 1.02, r * 0.2),
		Vector2(r * 0.96, r * 0.24), Vector2(r * 0.9, r * 0.12), Vector2(r * 0.42, r * 0.12),
		Vector2(r * 0.4, r * 0.22), Vector2(r * 0.36, r * 0.55), Vector2(r * 0.42, r * 0.62),
		Vector2(r * 0.34, r * 0.64), Vector2(0.001, r * 0.6)]), 48)
	dish.material_override = brass
	root.add_child(dish)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.22
	tm.outer_radius = r * 0.32
	ring.mesh = tm
	ring.material_override = brass
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(r * 1.2, r * 0.15, 0)
	root.add_child(ring)
	return root


# ------------------------------------------------------------------- firewood

## A split log: gently bent, thicker at one end, with bark ridges and a knot or two.
static func log_mesh(length: float, radius: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.08
	var spine := PackedVector3Array()
	var radii := PackedFloat32Array()
	var bend := rng.randf_range(-0.12, 0.12) * length
	var bend2 := rng.randf_range(-0.06, 0.06) * length
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		var x := (t - 0.5) * length
		var arch := sin(t * PI)
		spine.append(Vector3(x, arch * bend * 0.4, arch * bend2))
		radii.append(radius * (1.08 - 0.18 * t) * (1.0 + 0.08 * noise.get_noise_1d(t * 40.0)))
	var knot_at := rng.randf_range(0.2, 0.8) * length
	var knot_a := rng.randf() * TAU
	return tube(spine, radii, 22, func(along: float, a: float) -> float:
		var ridges := 0.06 * absf(noise.get_noise_2d(along * 0.4, a * 6.0)) + 0.03 * sin(a * 9.0 + along * 0.1)
		var dk := Vector2(along - knot_at, angle_difference(a, knot_a) * radius).length()
		return 1.0 + ridges + 0.25 * exp(-dk * dk / (radius * radius * 0.3)))


# ------------------------------------------------------------------- table clutter

## Profile helper: a hoop/band hugging radius `r` between heights y0 and y1.
static func _band(r: float, y0: float, y1: float, t := 0.18) -> PackedVector2Array:
	var e := (y1 - y0) * 0.15
	return PackedVector2Array([Vector2(r - 0.02, y0), Vector2(r + t, y0 + e), Vector2(r + t, y1 - e), Vector2(r - 0.02, y1)])


static func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A run of liquid (wax, foam) down the outside of a round object.
static func drip_mesh(angle: float, top_y: float, surface_r: float, length: float, w: float) -> ArrayMesh:
	var dir := Vector3(cos(angle), 0, sin(angle))
	var spine := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in 11:
		var t := k / 10.0
		var sway := sin(t * 5.0 + angle * 3.0) * w * 0.3
		spine.append(dir * (surface_r + w * 0.4) + dir.cross(Vector3.UP) * sway + Vector3(0, top_y - t * length, 0))
		radii.append(w * (0.6 + 0.4 * t + 0.5 * smoothstep(0.75, 0.95, t) - 0.9 * smoothstep(0.96, 1.0, t)))
	return tube(spine, radii, 10)


## Wooden tankard: tapered staves, iron hoops, a C-shaped handle, and ale foam spilling over.
static func tankard(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var R := 3.7
	var H := 10.0
	var staves := Mats.wood({"col_light": Color("#9a6436"), "col_dark": Color("#4a2810"), "uv_mode": 1,
		"uv_scale": Vector2(TAU * R, 1.0), "plank_width": 1.9, "gap": 0.07, "seed": rng.randf() * 50.0, "rough": 0.7})
	var iron := Mats.metal(Color("#3a3634"), 0.5, 0.7)
	var rr := func(y: float) -> float: return lerpf(R + 0.25, R, y / H)
	root.add_child(_mesh(lathe(PackedVector2Array([
		Vector2(0.001, 0), Vector2(rr.call(0) - 0.15, 0), Vector2(rr.call(0), 0.25), Vector2(rr.call(H), H),
		Vector2(rr.call(H) - 0.1, H + 0.12), Vector2(rr.call(H) - 0.4, H), Vector2(R - 0.45, 1.0), Vector2(0.001, 1.0)]), 40), staves))
	for y in [0.9, H - 2.0]:
		root.add_child(_mesh(lathe(_band(rr.call(y + 0.5), y, y + 1.0, 0.16), 40), iron))
	var foam := Mats.foam()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.5
	root.add_child(_mesh(lathe(PackedVector2Array([Vector2(0.001, H + 1.3), Vector2(1.8, H + 1.15), Vector2(3.0, H + 0.75),
		Vector2(R + 0.1, H + 0.25), Vector2(R + 0.05, H - 0.15), Vector2(R - 0.2, H - 0.3)]), 36,
		func(a: float, y: float) -> float: return 1.0 + noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0 + y) * 0.07), foam))
	for i in 2:
		root.add_child(_mesh(drip_mesh(rng.randf_range(2.0, 4.0) + i * 1.3, H, R, rng.randf_range(1.5, 3.5), 0.45), foam))
	var handle := PackedVector3Array()
	for k in 13:
		var t := k / 12.0
		var a := lerpf(-1.25, 1.25, t)
		handle.append(Vector3(R + 0.2 + cos(a) * 2.4 - 0.4, H * 0.5 + sin(a) * 3.4, 0))
	var hr := PackedFloat32Array()
	hr.resize(13)
	hr.fill(0.6)
	root.add_child(_mesh(tube(handle, hr, 12), Mats.wood({"col_light": Color("#8a5a32"), "col_dark": Color("#40220e"), "axis": 1, "plank_width": 100.0})))
	return root


## Glazed clay jug with a narrow neck, flared lip, handle and cork.
static func jug(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var clay := Mats.dice({"a": Color("#b0603a"), "b": Color("#6a2c16"), "swirl": 0.8, "scale": 0.25,
		"contrast": 0.6, "rough": 0.35, "depth": 0.0}, rng.randf() * 9.0)
	root.add_child(_mesh(lathe(PackedVector2Array([
		Vector2(0.001, 0), Vector2(2.0, 0), Vector2(2.15, 0.3), Vector2(2.0, 0.55), Vector2(2.9, 1.8),
		Vector2(3.4, 3.4), Vector2(3.2, 5.0), Vector2(2.3, 6.5), Vector2(1.15, 7.6), Vector2(1.0, 8.6),
		Vector2(1.4, 9.3), Vector2(1.45, 9.6), Vector2(1.1, 9.65), Vector2(0.9, 9.2), Vector2(0.001, 8.9)]), 48), clay))
	var spine := PackedVector3Array([Vector3(1.0, 8.5, 0), Vector3(2.4, 8.9, 0), Vector3(3.6, 8.2, 0),
		Vector3(4.0, 6.6, 0), Vector3(3.6, 5.0, 0), Vector3(3.0, 4.2, 0)])
	root.add_child(_mesh(tube(spine, PackedFloat32Array([0.42, 0.42, 0.42, 0.42, 0.42, 0.45]), 10), clay))
	root.add_child(_mesh(lathe(PackedVector2Array([Vector2(0.001, 8.9), Vector2(0.88, 8.9), Vector2(1.0, 10.4),
		Vector2(0.9, 10.6), Vector2(0.001, 10.6)]), 20), Mats.plain(Color("#b08a5a"), 0.95)))
	return root


## A glass bottle, flask or jar with cork, label and sometimes a wax seal.
static func bottle(rng: RandomNumberGenerator, color: Color) -> Node3D:
	var root := Node3D.new()
	var glass := Mats.glass(color)
	var R := rng.randf_range(2.6, 3.6)
	var kind := rng.randi() % 3
	var prof: PackedVector2Array
	var neck_top: float
	var neck_r := R * 0.33
	match kind:
		0:  # tall wine bottle
			var H := rng.randf_range(12.0, 17.0)
			neck_top = H + R * 1.2 + 5.0
			prof = PackedVector2Array([Vector2(0.001, 0), Vector2(R * 0.95, 0), Vector2(R, 0.4), Vector2(R, H),
				Vector2(R * 0.85, H + R * 0.6), Vector2(neck_r * 1.1, H + R * 1.2), Vector2(neck_r, neck_top)])
		1:  # round flask
			neck_top = R * 2.0 + 6.0
			prof = PackedVector2Array([Vector2(0.001, 0), Vector2(R * 0.6, 0), Vector2(R * 1.15, R * 0.5),
				Vector2(R * 1.3, R * 1.1), Vector2(R * 1.1, R * 1.7), Vector2(neck_r, R * 2.1), Vector2(neck_r, neck_top)])
		_:  # squat jar
			neck_r = R * 0.7
			neck_top = R * 2.4
			prof = PackedVector2Array([Vector2(0.001, 0), Vector2(R * 1.1, 0), Vector2(R * 1.2, 0.4),
				Vector2(R * 1.2, R * 1.9), Vector2(neck_r * 1.05, R * 2.1), Vector2(neck_r, neck_top)])
	prof.append(Vector2(neck_r * 1.25, neck_top + 0.2))
	prof.append(Vector2(neck_r * 1.25, neck_top + 0.7))
	prof.append(Vector2(0.001, neck_top + 0.7))
	root.add_child(_mesh(lathe(prof, 28), glass, Vector3.ZERO, false))
	var cork_r := neck_r * 0.95
	root.add_child(_mesh(lathe(PackedVector2Array([Vector2(0.001, neck_top), Vector2(cork_r, neck_top),
		Vector2(cork_r * 1.08, neck_top + 2.2), Vector2(cork_r * 0.9, neck_top + 2.5), Vector2(0.001, neck_top + 2.5)]), 16),
		Mats.plain(Color("#b8925e"), 0.95)))
	if rng.randf() < 0.4:
		root.add_child(_mesh(lathe(PackedVector2Array([Vector2(0.001, neck_top + 2.9), Vector2(cork_r * 1.2, neck_top + 2.4),
			Vector2(neck_r * 1.45, neck_top + 0.6), Vector2(neck_r * 1.4, neck_top - 0.2)]), 16,
			func(a: float, _y: float) -> float: return 1.0 + 0.12 * sin(a * 5.0)), Mats.plain(Color("#8a1a14"), 0.4)))
	if kind != 1 and rng.randf() < 0.7:
		var ly := R * 0.8
		root.add_child(_mesh(lathe(PackedVector2Array([Vector2(R * (1.2 if kind == 2 else 1.0) + 0.04, ly),
			Vector2(R * (1.2 if kind == 2 else 1.0) + 0.04, ly + R * 1.1)]), 28), Mats.parchment({"lines": 0.0}), Vector3.ZERO, false))
	return root


## Oak barrel: bulging staves, four iron hoops, a planked lid, and optionally a tap.
static func barrel(rng: RandomNumberGenerator, tap := false) -> Node3D:
	var root := Node3D.new()
	var H := 46.0
	var Rm := 16.0
	var Re := 13.5
	var r := func(y: float) -> float: return Re + (Rm - Re) * sin(PI * y / H)
	var staves := Mats.wood({"col_light": Color("#8a5428"), "col_dark": Color("#3a1c08"), "uv_mode": 1,
		"uv_scale": Vector2(TAU * Rm, 1.0), "plank_width": 7.0, "gap": 0.3, "seed": rng.randf() * 50.0, "plank_length": 400.0})
	var prof := PackedVector2Array([Vector2(0.001, 0.8), Vector2(Re - 1.0, 0.8), Vector2(Re - 1.0, 0.0)])
	for k in 13:
		var y := H * k / 12.0
		prof.append(Vector2(r.call(y), y))
	prof.append_array(PackedVector2Array([Vector2(Re - 1.0, H), Vector2(Re - 1.0, H - 1.0), Vector2(0.001, H - 1.0)]))
	root.add_child(_mesh(lathe(prof, 36), staves))
	var iron := Mats.metal(Color("#2e2c2a"), 0.5, 0.8)
	for y in [2.5, 12.0, H - 14.0, H - 4.5]:
		root.add_child(_mesh(lathe(_band(r.call(y + 1.0), y, y + 2.2, 0.3), 36), iron))
	var lid := Mats.wood({"col_light": Color("#7a4a24"), "col_dark": Color("#341a08"), "axis": 0, "plank_width": 6.0, "gap": 0.25, "seed": rng.randf() * 50.0})
	var lm := CylinderMesh.new()
	lm.top_radius = Re - 1.0
	lm.bottom_radius = Re - 1.0
	lm.height = 0.4
	root.add_child(_mesh(lm, lid, Vector3(0, H - 1.0, 0)))
	if tap:
		var brass := Mats.metal(Color("#b8893a"), 0.3)
		var spout := tube(PackedVector3Array([Vector3(0, 9, Re + 1.5), Vector3(0, 9, Re + 4.5), Vector3(0, 8, Re + 5.5), Vector3(0, 6.5, Re + 5.6)]),
			PackedFloat32Array([0.9, 0.8, 0.7, 0.6]), 12)
		root.add_child(_mesh(spout, brass))
		var key := BoxMesh.new()
		key.size = Vector3(3.0, 0.6, 0.6)
		root.add_child(_mesh(key, brass, Vector3(0, 10.2, Re + 4.0)))
	return root


## Leather coin pouch: a lumpy cinched sack with a cord.
static func pouch(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var leather := Mats.dice({"a": Color("#8a5430"), "b": Color("#4a2812"), "swirl": 0.5, "scale": 0.6,
		"contrast": 0.5, "rough": 0.75, "depth": 0.0}, rng.randf() * 9.0)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.9
	root.add_child(_mesh(lathe(PackedVector2Array([Vector2(0.001, 0), Vector2(2.2, 0.1), Vector2(3.0, 1.0),
		Vector2(3.15, 2.2), Vector2(2.6, 3.4), Vector2(1.1, 4.2), Vector2(0.9, 4.45), Vector2(1.5, 5.0),
		Vector2(1.9, 5.6), Vector2(1.3, 5.75), Vector2(0.001, 5.5)]), 32,
		func(a: float, y: float) -> float: return 1.0 + noise.get_noise_3d(cos(a) * 2.0, sin(a) * 2.0, y * 0.6) * 0.22), leather))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.15
	root.add_child(_mesh(tm, Mats.plain(Color("#c9a060")), Vector3(0, 4.4, 0)))
	return root


## A parchment sheet that curls up at both ends.
static func curled_sheet(w: float, l: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 12
	var nz := 48
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.15
	for j in nz + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / nz
			var x := (u - 0.5) * w
			var s := (v - 0.5) * l       # distance along the sheet
			var p := Vector3(x, 0.03 + noise.get_noise_2d(x, s) * 0.12, s)
			var top := l * 0.5 - 1.6     # curl start near the far end, rolled tightly
			if s < -top:
				var rr := 0.6 + 0.04 * x
				var th := minf((-top - s) / rr, TAU * 0.9)
				p = Vector3(x, rr * (1.0 - cos(th)) + 0.03, -top - rr * sin(th))
			var near := l * 0.5 - 1.2    # the near end lifts gently
			if s > near:
				var rr2 := 1.6
				var th2 := (s - near) / rr2
				p = Vector3(x, rr2 * (1.0 - cos(th2)) + 0.03, near + rr2 * sin(th2))
			st.set_uv(Vector2(u, v))
			st.add_vertex(p)
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + nx + 1
			st.add_index(a); st.add_index(a + 1); st.add_index(b)
			st.add_index(a + 1); st.add_index(b + 1); st.add_index(b)
	st.generate_normals()
	return st.commit()


## Hanging iron lantern with amber glass, a candle stub and a flame. Centre at the origin.
static func lantern(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var iron := Mats.metal(Color("#2a2622"), 0.5, 0.8)
	root.add_child(_mesh(lathe(PackedVector2Array([Vector2(0.001, 9.5), Vector2(1.0, 9.2), Vector2(4.6, 6.4),
		Vector2(5.4, 6.0), Vector2(5.4, 5.3), Vector2(4.2, 5.3), Vector2(0.001, 5.3)]), 8), iron))
	root.add_child(_mesh(lathe(PackedVector2Array([Vector2(0.001, -6.5), Vector2(4.8, -6.5), Vector2(5.4, -5.8),
		Vector2(5.4, -5.0), Vector2(0.001, -5.0)]), 8), iron))
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var bar := BoxMesh.new()
		bar.size = Vector3(0.5, 10.5, 0.5)
		var b := _mesh(bar, iron, Vector3(cos(a) * 4.6, 0.15, sin(a) * 4.6))
		b.rotation.y = -a
		root.add_child(b)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.4
	var ring := _mesh(tm, iron, Vector3(0, 10.5, 0))
	ring.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(ring)
	var pane := lathe(PackedVector2Array([Vector2(4.4, -5.0), Vector2(4.4, 5.3)]), 8)
	var gm := Mats.glass(Color("#ffb45a"))
	gm.emission_enabled = true
	gm.emission = Color("#ff9a3a")
	gm.emission_energy_multiplier = 0.6
	root.add_child(_mesh(pane, gm, Vector3.ZERO, false))
	var c := candle(1.0, 3.0, rng)
	c.node.position = Vector3(0, -5.0, 0)
	root.add_child(c.node)
	root.add_child(flame(Vector3(0, -5.0 + c.flame_y, 0), 2.6, {"base_amount": 1.0, "speed": 0.7, "wild": 0.45, "seed": rng.randf() * 9.0, "glow": 2.6}))
	return root
