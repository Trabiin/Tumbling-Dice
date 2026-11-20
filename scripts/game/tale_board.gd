extends Node3D
## The tale board: a parchment map on the table, left of the dice tray. Each scene is a painted
## tile, roads are inked in as you walk them, fog lifts where you arrive, roads not taken stay
## sketched and faded, and your choices leave tokens behind (a lit beacon, Kettle's flag, a
## grave for Aldous, the toppled figurine of a foe you beat). Your figurine hops from tile to
## tile like someone moving it by hand.
##
## The board only draws what scripts/rules/board.gd says; everything it shows comes from the
## tale and the saved tale state, so it comes back exactly as it was after Continue.

const Board := preload("res://scripts/rules/board.gd")
const Kits := preload("res://scripts/kits.gd")
const Fig := preload("res://scripts/figures.gd")
const Mats := preload("res://scripts/materials.gd")

const SCALE := 2.5          # world units per grid unit
const MARGIN := Vector2(2.4, 2.2)
const HERO_OFFSET := Vector3(0.5, 0.0, 0.8)   # where the figurine stands on a tile
const TOKEN_SCALE := 1.7
const TOKEN_SPOTS := [Vector3(1.05, 0, 0.45), Vector3(-1.0, 0, 0.5), Vector3(1.1, 0, -0.5), Vector3(-1.1, 0, -0.45),
	Vector3(-0.45, 0, 1.15), Vector3(0.0, 0, -1.2), Vector3(0.8, 0, 1.15)]

const ROAD := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec3 ink : source_color = vec3(0.22, 0.11, 0.05);
uniform float alpha = 1.0;
uniform float dash = 0.0;       // dashes per unit of length (0 = solid)
uniform float progress = 1.0;   // how much of the road is inked so far, 0 to 1
uniform float length = 1.0;
uniform float reverse = 0.0;    // 1: ink from the far end
void fragment() {
	float along = mix(UV.x, length - UV.x, reverse);
	if (along > progress * length) { discard; }
	float d = dash > 0.0 ? step(0.45, fract(along * dash)) : 1.0;
	float edge = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);
	float wobble = 0.85 + 0.15 * sin(along * 7.0 + UV.y * 3.0);
	ALBEDO = ink;
	ALPHA = alpha * d * edge * wobble;
}
"""

## Mist over the parts of the map you don't know yet: soft, drifting, a shade darker than
## the parchment.
const FOG := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.6, 0.54, 0.44);
uniform float alpha = 0.92;
uniform float seed = 0.0;
uniform float fade = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = fbm(vec3(UV * 2.5 + vec2(TIME * 0.02, seed), seed));
	float a = smoothstep(1.0, 0.35, length(p) + (n - 0.5) * 0.7);
	ALBEDO = tint * (0.88 + 0.24 * n);
	ALPHA = a * alpha * (1.0 - fade);
}
"""

signal hopped(scene_id: String)

var lite := false
var tale: Dictionary = {}
var lay: Dictionary = {}
var paper: MeshInstance3D
var tiles := {}             # id -> {root, icon, ring, label, state}
var roads := {}             # key -> {mesh, mat, state, a, b}
var fog := {}               # id -> Array of puffs
var tokens := {}            # token key -> {node, label, scene}
var hero: Node3D
var hero_at := ""
var shown_path: Array = []
var _queue: Array = []      # views waiting while the figurine is moving
var _moving := false
var _fog_mat: ShaderMaterial
var _road_shader: Shader
var _font: Font


func setup(p_tale: Dictionary, font: Font = null) -> void:
	clear()
	tale = p_tale
	_font = font
	lite = Mats.lite
	lay = Board.layout(tale)
	if lay.tiles.is_empty():
		return
	var b: Rect2 = lay.bounds
	var size := b.size * SCALE + MARGIN * 2.0
	var center := (b.position + b.size * 0.5) * SCALE
	# The parchment, a little larger than the tiles, with burnt edges.
	paper = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 2
	pm.subdivide_depth = 2
	paper.mesh = pm
	paper.material_override = Mats.parchment({"lines": 0.0})
	paper.position = Vector3(center.x, 0.02, center.y)
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paper)
	_weights(Vector3(center.x, 0, center.y), size)
	_title(Vector3(center.x, 0.04, center.y - size.y * 0.5 + 0.9), String(tale.get("title", "")))
	_road_shader = Shader.new()
	_road_shader.code = ROAD
	for r in lay.roads:
		_build_road(r)
	for t in lay.tiles:
		_build_tile(t)
	hero = Fig.figurine("hero")
	hero.scale = Vector3.ONE * 1.1
	hero.visible = false
	add_child(hero)


func clear() -> void:
	for c in get_children():
		c.queue_free()
	tiles.clear()
	roads.clear()
	fog.clear()
	tokens.clear()
	hero = null
	hero_at = ""
	shown_path = []
	_queue.clear()
	_moving = false
	paper = null


func has_board() -> bool:
	return paper != null


## Where a grid position sits on the board (local space).
func at(p: Vector2) -> Vector3:
	return Vector3(p.x * SCALE, 0.04, p.y * SCALE)


func tile_pos(id: String) -> Vector3:
	return at(lay.pos.get(id, Vector2.ZERO))


## The point a camera should look at: the middle of the parchment, in world space.
func focus() -> Vector3:
	return paper.global_position if paper != null else global_position


func size() -> Vector2:
	return (paper.mesh as PlaneMesh).size if paper != null else Vector2.ZERO


# ------------------------------------------------------------------ building

func _build_tile(t: Dictionary) -> void:
	var root := Node3D.new()
	root.name = t.id
	root.position = at(t.pos)
	add_child(root)
	var icon := Fig.tile(t.icon, 0.0, hash(t.id))
	icon.rotation.y = deg_to_rad(float(hash(t.id) % 13) - 6.0)
	icon.visible = false
	root.add_child(icon)
	if lite:
		# On Low the board casts no shadows: the dice keep the shadow map to themselves.
		for c: GeometryInstance3D in icon.find_children("*", "GeometryInstance3D", true, false):
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A faint inked ring, for a place you know of but have not been.
	var ring := MeshInstance3D.new()
	var pts := PackedVector2Array()
	for i in 41:
		var a := i / 40.0 * TAU
		pts.append(Vector2(cos(a), sin(a)) * (0.92 + 0.04 * sin(a * 5.0 + t.pos.x)))
	ring.mesh = _ribbon(pts, 0.09)
	var rm := _road_mat(pts)
	rm.set_shader_parameter("dash", 3.0)
	ring.material_override = rm
	ring.visible = false
	root.add_child(ring)
	var label: Label3D = null
	if _font != null:
		label = Label3D.new()
		label.text = String(t.title).replace("The ", "")
		label.font = _font
		# Low renders the 3D at 60%, so the names get bigger to stay readable.
		label.font_size = 64 if lite else 48
		label.pixel_size = 0.0068 if lite else 0.0072
		label.modulate = Color("#3a1e0c")
		label.outline_size = 0
		label.shaded = false
		label.double_sided = true
		label.rotation_degrees.x = -90
		label.position = Vector3(0, 0.03, 1.4)
		label.width = 340
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.visible = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		root.add_child(label)
	tiles[t.id] = {"root": root, "icon": icon, "ring": ring, "label": label, "state": Board.FOG, "faded": -1.0}
	fog[t.id] = _make_fog(root.position, hash(t.id))


func _build_road(r: Dictionary) -> void:
	var pa: Vector2 = lay.pos[r.a]
	var pb: Vector2 = lay.pos[r.b]
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var p := Board.road_point(pa, pb, r.bend, i / float(n)) * SCALE
		pts.append(p)
	# Trim the ends so roads stop at the tile edges.
	pts = _trim(pts, 1.05)
	var mi := MeshInstance3D.new()
	mi.mesh = _ribbon(pts, 0.16)
	mi.position.y = 0.035
	var mat := _road_mat(pts)
	mi.material_override = mat
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	roads[Board.road_key(r.a, r.b)] = {"mesh": mi, "mat": mat, "state": Board.FOG, "a": r.a, "b": r.b, "pts": pts}


func _road_mat(pts: PackedVector2Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _road_shader
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i].distance_to(pts[i - 1])
	m.set_shader_parameter("length", length)
	return m


func _trim(pts: PackedVector2Array, r: float) -> PackedVector2Array:
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var out := PackedVector2Array()
	for p in pts:
		if p.distance_to(a) >= r and p.distance_to(b) >= r:
			out.append(p)
	if out.size() < 2:
		return pts
	return out


## A flat strip along a 2D path on the board: UV.x is the distance along it, UV.y across.
func _ribbon(pts: PackedVector2Array, width: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	var dist := 0.0
	for i in pts.size():
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == pts.size() - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		var side := Vector2(-dir.y, dir.x).normalized() * width * 0.5
		var w := 1.0 + 0.25 * sin(dist * 2.3)
		v.append(Vector3(pts[i].x + side.x * w, 0, pts[i].y + side.y * w))
		v.append(Vector3(pts[i].x - side.x * w, 0, pts[i].y - side.y * w))
		uv.append(Vector2(dist, 0))
		uv.append(Vector2(dist, 1))
		nrm.append(Vector3.UP)
		nrm.append(Vector3.UP)
		if i > 0:
			var k := i * 2
			idx.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _make_fog(center: Vector3, seed_value: int) -> Array:
	if _fog_mat == null:
		_fog_mat = ShaderMaterial.new()
		_fog_mat.shader = Mats._shader("board_fog", FOG)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	var count := 2 if lite else 3
	for i in count:
		var q := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		qm.size = Vector2.ONE
		q.mesh = qm
		var m: ShaderMaterial = _fog_mat.duplicate()
		m.set_shader_parameter("seed", rng.randf() * 50.0)
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(2.6, 3.4)
		q.scale = Vector3(s * 1.2, 1, s)
		q.rotation.y = rng.randf() * TAU
		q.position = center + Vector3(rng.randf_range(-0.5, 0.5), 0.35 + i * 0.12, rng.randf_range(-0.4, 0.4))
		add_child(q)
		out.append(q)
	return out


## Coins and a die hold the corners of the map down.
func _weights(center: Vector3, size: Vector2) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	for c in [Vector3(-hx + 0.6, 0, -hz + 0.6), Vector3(hx - 0.7, 0, hz - 0.6)]:
		var k := Fig.Kit.new()
		for i in 3:
			k.add(Fig._cyl(0.55, 0.55, 0.12, 14), Fig.T(Vector3(i * 0.05, 0.06 + i * 0.12, 0)), Fig.GOLD.darkened(0.08 * i))
		var n := k.node()
		n.position = center + c
		add_child(n)


func _title(pos: Vector3, text: String) -> void:
	if _font == null or text == "":
		return
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = 64
	l.pixel_size = 0.009
	l.modulate = Color("#5a1a0c")
	l.outline_size = 0
	l.shaded = false
	l.double_sided = true
	l.rotation_degrees.x = -90
	l.position = pos
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	add_child(l)


# ------------------------------------------------------------------ showing state

## Bring the board up to date. animate: walk the figurine, ink the roads and lift the fog;
## otherwise (a resumed tale) everything snaps into place.
func show_view(view: Dictionary, animate := true) -> void:
	if paper == null:
		return
	if _moving:
		_queue = [view]
		return
	var path: Array = view.path
	var new_steps: Array = []
	if animate and hero_at != "" and path.size() > shown_path.size() and path.slice(0, shown_path.size()) == shown_path:
		new_steps = path.slice(shown_path.size())
	if not animate or hero_at == "" or (new_steps.is_empty() and path != shown_path):
		_snap(view)
		return
	if new_steps.is_empty():
		_apply(view, true)
		return
	_moving = true
	for id in new_steps:
		await _hop(hero_at, id, view)
		if not is_inside_tree():
			return
		hero_at = id
		_lift_fog(id)
		hopped.emit(id)
	shown_path = path.duplicate()
	_apply(view, true)
	_moving = false
	if not _queue.is_empty():
		var nv: Dictionary = _queue.pop_back()
		_queue.clear()
		show_view(nv, true)


func _snap(view: Dictionary) -> void:
	shown_path = view.path.duplicate()
	hero_at = view.here
	_apply(view, false)
	if hero != null and hero_at != "":
		hero.visible = true
		hero.position = tile_pos(hero_at) + HERO_OFFSET
		hero.rotation = Vector3.ZERO


func _apply(view: Dictionary, animate: bool) -> void:
	for id in tiles:
		_set_tile(id, view.tiles.get(id, Board.FOG), animate)
	for key in roads:
		_set_road(key, view.roads.get(key, Board.FOG), animate)
	_set_tokens(view.tokens, animate)


func _set_tile(id: String, s: String, animate: bool) -> void:
	var t: Dictionary = tiles[id]
	if t.state == s:
		return
	t.state = s
	var known := s == Board.VISITED or s == Board.CURRENT
	var sketched := s == Board.OPEN or s == Board.PASSED
	t.icon.visible = known or s == Board.REMEMBERED
	if t.icon.visible:
		var fade := 0.0 if known else 0.6
		if t.faded != fade:
			t.faded = fade
			for c in t.icon.get_children():
				if c.name == "Paint":
					c.material_override = Fig.material(fade)
			Kits.set_fade(t.icon, fade)
		if animate and known and t.icon.scale.y < 0.99:
			pass
	t.ring.visible = sketched
	if sketched:
		(t.ring.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.55 if s == Board.OPEN else 0.28)
	if t.label != null:
		t.label.visible = known or s == Board.REMEMBERED
		t.label.modulate.a = 1.0 if known else 0.45
	if s != Board.FOG:
		_lift_fog(id, animate)
	if animate and known and not t.get("popped", false):
		t.popped = true
		t.icon.scale = Vector3(1, 0.05, 1)
		var tw := create_tween()
		tw.tween_property(t.icon, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif known:
		t.popped = true


func _set_road(key: String, s: String, animate: bool) -> void:
	var r: Dictionary = roads[key]
	if r.state == s:
		return
	var was: String = r.state
	r.state = s
	var mat: ShaderMaterial = r.mat
	r.mesh.visible = s != Board.FOG
	match s:
		Board.VISITED:
			mat.set_shader_parameter("dash", 0.0)
			mat.set_shader_parameter("alpha", 0.9)
		Board.OPEN:
			mat.set_shader_parameter("dash", 2.2)
			mat.set_shader_parameter("alpha", 0.6)
		Board.PASSED:
			mat.set_shader_parameter("dash", 2.2)
			mat.set_shader_parameter("alpha", 0.25)
		Board.REMEMBERED:
			mat.set_shader_parameter("dash", 4.0)
			mat.set_shader_parameter("alpha", 0.3)
	if animate and s != Board.FOG and was == Board.FOG:
		mat.set_shader_parameter("progress", 0.0)
		var tw := create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.6)
	elif s != Board.FOG:
		mat.set_shader_parameter("progress", 1.0)


func _lift_fog(id: String, animate := true) -> void:
	var puffs: Array = fog.get(id, [])
	if puffs.is_empty():
		return
	fog[id] = []
	for q in puffs:
		if not animate:
			q.queue_free()
			continue
		var tw := create_tween().set_parallel()
		var m: ShaderMaterial = q.material_override
		tw.tween_property(q, "scale", q.scale * 1.6, 1.0).set_ease(Tween.EASE_OUT)
		tw.tween_property(q, "position", q.position + Vector3(randf_range(-1.2, 1.2), 0.8, randf_range(-0.8, 0.4)), 1.0)
		tw.tween_method(func(v): m.set_shader_parameter("fade", v), 0.0, 1.0, 1.0)
		tw.chain().tween_callback(q.queue_free)


func _token_key(tok: Dictionary) -> String:
	return "%s|%s|%s" % [tok.get("scene", ""), tok.get("icon", ""), tok.get("label", "")]


func _set_tokens(list: Array, animate: bool) -> void:
	var want := {}
	var per_scene := {}
	for tok in list:
		var key := _token_key(tok)
		want[key] = true
		var n: int = per_scene.get(tok.scene, 0)
		per_scene[tok.scene] = n + 1
		if tokens.has(key):
			continue
		var node := Fig.token(tok.icon, tok.get("figure", ""))
		node.position = tile_pos(tok.scene) + TOKEN_SPOTS[n % TOKEN_SPOTS.size()] * Vector3(1, 0, 1) + Vector3(0, 0.02, 0)
		node.rotation.y = deg_to_rad(float(hash(key) % 40) - 20.0)
		add_child(node)
		tokens[key] = {"node": node, "label": tok.get("label", ""), "scene": tok.scene}
		node.scale = Vector3.ONE * TOKEN_SCALE
		if animate:
			node.scale = Vector3.ONE * 0.01
			var tw := create_tween()
			tw.tween_interval(0.15 * n)
			tw.tween_property(node, "scale", Vector3.ONE * TOKEN_SCALE * 1.3, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "scale", Vector3.ONE * TOKEN_SCALE, 0.15)
	for key in tokens.keys():
		if not want.has(key):
			tokens[key].node.queue_free()
			tokens.erase(key)


## The figurine is picked up, carried along the road and set down with a little wobble.
func _hop(from_id: String, to_id: String, view: Dictionary) -> void:
	if hero == null:
		return
	hero.visible = true
	var key := Board.road_key(from_id, to_id)
	var pts := PackedVector3Array()
	var a := tile_pos(from_id) + HERO_OFFSET
	var b := tile_pos(to_id) + HERO_OFFSET
	if roads.has(key):
		var r: Dictionary = roads[key]
		var road_pts: PackedVector2Array = r.pts
		if r.a != from_id:
			road_pts.reverse()
		pts.append(a)
		for i in range(0, road_pts.size(), 4):
			pts.append(Vector3(road_pts[i].x, 0.04, road_pts[i].y) + HERO_OFFSET * 0.4)
		pts.append(b)
		# Ink the road as the figurine goes.
		if r.state == Board.FOG or r.state != Board.VISITED:
			r.mesh.visible = true
			r.state = Board.VISITED
			var mat: ShaderMaterial = r.mat
			mat.set_shader_parameter("dash", 0.0)
			mat.set_shader_parameter("alpha", 0.9)
			mat.set_shader_parameter("reverse", 1.0 if r.a != from_id else 0.0)
			mat.set_shader_parameter("progress", 0.0)
			var tw0 := create_tween()
			tw0.tween_method(func(v): mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.9)
	else:
		pts.append(a)
		pts.append(b)
	var lift := 1.1
	var dur := clampf(a.distance_to(b) * 0.12, 0.6, 1.4)
	var tw := create_tween()
	tw.tween_property(hero, "position", a + Vector3(0, lift, 0), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(hero, "rotation", Vector3(0.12, 0, -0.08), 0.18)
	var curve := Curve3D.new()
	for p in pts:
		curve.add_point(p + Vector3(0, lift, 0))
	tw.tween_method(func(t):
		var p := curve.sample_baked(t * curve.get_baked_length())
		p.y += sin(t * PI) * 0.6
		hero.position = p, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(hero, "position", b, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(hero, "rotation", Vector3.ZERO, 0.16)
	tw.tween_property(hero, "rotation", Vector3(0, 0, 0.09), 0.07)
	tw.tween_property(hero, "rotation", Vector3(0, 0, -0.05), 0.07)
	tw.tween_property(hero, "rotation", Vector3.ZERO, 0.06)
	_lift_fog(to_id)
	await tw.finished


## The label of the token or tile under the mouse, if any.
func hover_text(screen: Vector2, cam: Camera3D) -> String:
	if paper == null or not visible:
		return ""
	var best := ""
	var best_d := 26.0
	for key in tokens:
		var n: Node3D = tokens[key].node
		if cam.is_position_behind(n.global_position):
			continue
		var d := cam.unproject_position(n.global_position + Vector3(0, 0.3, 0)).distance_to(screen)
		if d < best_d:
			best_d = d
			best = tokens[key].label
	if best != "":
		return best
	best_d = 40.0
	for id in tiles:
		var t: Dictionary = tiles[id]
		if t.state == Board.FOG:
			continue
		var d := cam.unproject_position(t.root.global_position + Vector3(0, 0.5, 0)).distance_to(screen)
		if d < best_d:
			best_d = d
			var title := ""
			for tt in lay.tiles:
				if tt.id == id:
					title = tt.title
			best = title + {Board.OPEN: " (a road you could take)", Board.PASSED: " (a road not taken)",
				Board.REMEMBERED: " (from an earlier telling)"}.get(t.state, "")
	return best
