extends RefCounted
## Painted miniatures built from primitives: the traveller's figurine, carved foe figurines,
## the tale board's scene tiles and the tokens your choices leave on it.
##
## Every piece is merged into one vertex-coloured mesh (one draw call, plus one for an ink
## outline shell), so a whole board costs about as much as a handful of dice. Glowing bits
## (flames, lamp light) go in a second small mesh with an unshaded material.
## Scale: 1 unit is about 1.2 cm, as in the tavern. A figurine is about 2.2 units tall.

const Mats := preload("res://scripts/materials.gd")
const Kits := preload("res://scripts/kits.gd")

## Painted wood in soft toon bands. COLOR comes from the merged mesh; fade washes it toward
## the parchment, for tiles you remember from an earlier telling.
const FIGURE := """
shader_type spatial;
uniform vec3 paper : source_color = vec3(0.86, 0.76, 0.56);
uniform float fade = 0.0;
uniform float rough = 0.75;
void fragment() {
	// Vertex colours are written in sRGB; Forward+ lights in linear. (The Compatibility
	// renderer already hands them over converted.)
	vec3 c = COLOR.rgb;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	c = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
#endif
	float n = vnoise(vec3(UV * 40.0, 1.0));
	c *= 0.93 + 0.12 * n;   // a little brush texture in the paint
	ALBEDO = mix(c, paper * 0.95, fade);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
"""

## An inverted shell drawn behind the figure: the ink outline, without the screen pass.
const OUTLINE := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec3 ink : source_color = vec3(0.12, 0.06, 0.03);
uniform vec3 paper : source_color = vec3(0.86, 0.76, 0.56);
uniform float fade = 0.0;
uniform float width = 0.035;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = mix(ink, paper * 0.8, fade);
}
"""

static var _mats := {}

# Palette
const SKIN := Color("#e8b48a")
const INK := Color("#2a160a")
const WOOD_L := Color("#c08a54")
const WOOD_M := Color("#8e5c32")
const WOOD_D := Color("#5a361c")
const STONE := Color("#8a8478")
const STONE_D := Color("#5e5a52")
const WATER := Color("#3f7484")
const WATER_D := Color("#2a5260")
const GRASS := Color("#6f7d42")
const SAND := Color("#c9a86a")
const GOLD := Color("#e8b830")
const ROOF := Color("#9a3a22")
const WHITE := Color("#efe6d2")
const LIGHT := Color("#ffc860")


static func material(fade := 0.0) -> ShaderMaterial:
	var key := "f%.2f%s" % [fade, "l" if Mats.lite else ""]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = Mats._shader("figure", FIGURE)
		m.set_shader_parameter("fade", fade)
		var o := ShaderMaterial.new()
		o.shader = Mats._shader("figure_outline", OUTLINE)
		o.set_shader_parameter("fade", fade)
		m.next_pass = o
		_mats[key] = m
	return _mats[key]


static func outline_width(m: ShaderMaterial, w: float) -> ShaderMaterial:
	var c: ShaderMaterial = m.duplicate()
	var o: ShaderMaterial = m.next_pass.duplicate()
	o.set_shader_parameter("width", w)
	c.next_pass = o
	return c


## Collects primitives with colours into one mesh.
class Kit:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var glow_kit: Kit = null
	## CC0 kit pieces placed alongside the primitives: [kind, name, Transform3D, carved].
	## kind "mini" is a baked KayKit character, "model" a kit model (scripts/kits.gd).
	var pieces: Array = []

	func piece(kind: String, name: String, xf: Transform3D, carved := false, opts := {}) -> void:
		pieces.append([kind, name, xf, carved, opts])

	func add(mesh: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arr := mesh.get_mesh_arrays()
		var mv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var mn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var muv = arr[Mesh.ARRAY_TEX_UV]
		var mi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := v.size()
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		for i in mv.size():
			v.append(xf * mv[i])
			n.append((nb * mn[i]).normalized())
			c.append(col)
			uv.append(muv[i] if muv != null and i < muv.size() else Vector2.ZERO)
		if flip:
			for i in range(0, mi.size(), 3):
				idx.append(base + mi[i])
				idx.append(base + mi[i + 2])
				idx.append(base + mi[i + 1])
		else:
			for i in mi:
				idx.append(base + i)

	func glow() -> Kit:
		if glow_kit == null:
			glow_kit = Kit.new()
		return glow_kit

	func empty() -> bool:
		return v.is_empty() and pieces.is_empty()

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	## The finished piece: a node with the painted mesh and, if any, the glowing one.
	func node(fade := 0.0, shadows := true) -> Node3D:
		var root := Node3D.new()
		if not v.is_empty():
			var mi := MeshInstance3D.new()
			mi.name = "Paint"
			mi.mesh = mesh()
			mi.material_override = Figures.material(fade)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		if glow_kit != null and not glow_kit.empty():
			var g := MeshInstance3D.new()
			g.name = "Glow"
			g.mesh = glow_kit.mesh()
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.vertex_color_use_as_albedo = true
			gm.vertex_color_is_srgb = true
			gm.emission_enabled = true
			gm.emission = LIGHT
			gm.emission_energy_multiplier = 1.6
			g.material_override = gm
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(g)
		for p in pieces:
			var xf: Transform3D = p[2]
			var sc := xf.basis.get_scale().x
			var n: Node3D
			if p[0] == "mini":
				n = Kits.mini(p[1], p[3], fade, 0.035 / sc)
			else:
				var o: Dictionary = {"outline": 0.03 / sc, "fade": fade, "shadows": shadows}
				if String(p[1]).begins_with("hexagon/"):
					o.sat = 0.9   # KayKit's toy-bright palette, toned a little toward our painted wood
				o.merge(p[4], true)
				n = Kits.model(p[1], o)
			if not shadows:
				for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
					m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var holder := Node3D.new()
			holder.name = "Kit_" + String(p[1]).get_file()
			holder.transform = xf
			holder.add_child(n)
			root.add_child(holder)
		return root


const Figures := preload("res://scripts/figures.gd")

# ------------------------------------------------------------------ primitives

static func _sph(r: float, segs := 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


static func _cyl(rt: float, rb: float, h: float, segs := 14) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func _prism(s: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = s
	return m


static func _torus(inner: float, outer: float, segs := 16) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = segs
	m.ring_segments = 6
	return m


static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 10
	m.rings = 3
	return m


static func T(pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl)
	return Transform3D(b, pos)


## A Transform3D relative to a parent transform.
static func _at(parent: Transform3D, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return parent * T(pos, rot_deg, scl)


# ------------------------------------------------------------------ figurines

const FIGURES := ["hero", "wolf", "drowned", "smuggler", "abbess", "innkeeper", "kettle", "hooded", "knight", "mage", "warrior"]
const OPPONENT_FIGURE := {"odile": "innkeeper", "kettle": "kettle", "kettle_threat": "kettle", "abbess_name": "abbess",
	"pell": "smuggler", "ormond_bid": "mage", "court_judge": "abbess", "drowned_court": "warrior", "brask": "innkeeper",
	"magistrate": "hooded", "harrow_parley": "knight", "holloway_council": "innkeeper", "ashgrove": "knight"}
## Figures that only exist as kit miniatures stand in as the nearest code-built figure when the
## kits are off (-- --kits=off).
const CODE_FALLBACK := {"knight": "smuggler", "mage": "abbess", "warrior": "drowned", "hooded": "abbess"}


## A figurine on its round base, facing +z (toward the player). carved: foe figurines are
## carved wood with only a touch of paint; the traveller is fully painted.
static func figurine(kind: String, carved := false, scale := 1.0) -> Node3D:
	var k := Kit.new()
	add_figure(k, kind, T(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * scale), carved)
	var node := k.node()
	node.name = kind.capitalize()
	return node


static func add_figure(k: Kit, kind: String, at: Transform3D, carved := false) -> void:
	var tint := func(col: Color) -> Color:
		return col.lerp(WOOD_M, 0.3) if carved else col
	var base_col: Color = WOOD_D if carved else Color("#3a3a40")
	k.add(_cyl(0.56, 0.62, 0.16, 18), _at(at, Vector3(0, 0.08, 0)), base_col)
	k.add(_cyl(0.5, 0.56, 0.04, 18), _at(at, Vector3(0, 0.18, 0)), base_col.lightened(0.18))
	var y := 0.2
	if Kits.has_mini(kind):
		k.piece("mini", kind, _at(at, Vector3(0, y, 0)), carved)
		return
	kind = CODE_FALLBACK.get(kind, kind)
	match kind:
		"hero":
			k.add(_cyl(0.2, 0.46, 1.0), _at(at, Vector3(0, y + 0.5, -0.02)), tint.call(Color("#8a2a22")))     # cloak
			k.add(_cyl(0.2, 0.27, 0.5), _at(at, Vector3(0, y + 0.82, 0.04)), tint.call(Color("#3c5a7a")))     # tunic
			k.add(_cyl(0.28, 0.28, 0.07), _at(at, Vector3(0, y + 0.7, 0.04)), tint.call(Color("#5a3418")))     # belt
			k.add(_box(Vector3(0.1, 0.08, 0.04)), _at(at, Vector3(0, y + 0.7, 0.31)), GOLD)                       # buckle
			k.add(_sph(0.2), _at(at, Vector3(0, y + 1.22, 0.05)), tint.call(SKIN))                              # head
			k.add(_sph(0.25), _at(at, Vector3(0, y + 1.27, -0.06), Vector3.ZERO, Vector3(1.0, 1.05, 1.0)), tint.call(Color("#7a241e")))  # hood
			k.add(_cyl(0.0, 0.14, 0.32), _at(at, Vector3(0, y + 1.38, -0.28), Vector3(-60, 0, 0)), tint.call(Color("#7a241e")))  # hood tip
			k.add(_sph(0.03, 6), _at(at, Vector3(-0.07, y + 1.24, 0.24)), INK)                                  # eyes
			k.add(_sph(0.03, 6), _at(at, Vector3(0.07, y + 1.24, 0.24)), INK)
			k.add(_cyl(0.035, 0.04, 1.75), _at(at, Vector3(0.36, y + 0.86, 0.12)), tint.call(WOOD_M))           # staff
			k.add(_sph(0.08), _at(at, Vector3(0.3, y + 0.86, 0.16)), tint.call(SKIN))                           # hand
			k.add(_cap(0.07, 0.4), _at(at, Vector3(0.24, y + 0.98, 0.12), Vector3(0, 0, 35)), tint.call(Color("#3c5a7a")))  # arm
			k.add(_box(Vector3(0.16, 0.2, 0.16)), _at(at, Vector3(0.36, y + 1.8, 0.12)), Color("#3a3028"))      # lantern
			k.glow().add(_box(Vector3(0.11, 0.15, 0.17)), _at(at, Vector3(0.36, y + 1.8, 0.12)), LIGHT)
			k.add(_cyl(0.0, 0.11, 0.1, 8), _at(at, Vector3(0.36, y + 1.95, 0.12)), Color("#3a3028"))
			k.add(_cap(0.13, 0.5), _at(at, Vector3(0, y + 0.8, -0.32), Vector3(10, 0, 0)), tint.call(Color("#6a4a2a")))  # pack
		"wolf":
			var fur: Color = tint.call(Color("#6a6a70"))
			k.add(_cap(0.22, 0.95), _at(at, Vector3(0, y + 0.52, -0.05), Vector3(90, 0, 0)), fur)               # body
			k.add(_sph(0.24), _at(at, Vector3(0, y + 0.66, 0.24)), fur)                                         # chest
			k.add(_sph(0.18), _at(at, Vector3(0, y + 0.86, 0.42)), fur)                                         # head
			k.add(_cyl(0.05, 0.11, 0.26), _at(at, Vector3(0, y + 0.8, 0.6), Vector3(90, 0, 0)), fur)            # snout
			k.add(_sph(0.035, 6), _at(at, Vector3(0, y + 0.81, 0.73)), INK)
			for sx in [-1, 1]:
				k.add(_cyl(0.0, 0.06, 0.16, 6), _at(at, Vector3(sx * 0.09, y + 1.04, 0.38)), fur)               # ears
				k.add(_sph(0.03, 6), _at(at, Vector3(sx * 0.08, y + 0.9, 0.57)), Color("#e8c040"))             # eyes
				for z in [-0.35, 0.25]:
					k.add(_cyl(0.05, 0.06, 0.42), _at(at, Vector3(sx * 0.12, y + 0.21, z)), fur)                 # legs
			k.add(_cyl(0.02, 0.09, 0.5), _at(at, Vector3(0, y + 0.5, -0.62), Vector3(-120, 0, 0)), fur)         # tail
		"drowned":
			var cloth: Color = tint.call(Color("#5e6e66"))
			var flesh: Color = tint.call(Color("#9aa89a"))
			k.add(_cyl(0.18, 0.34, 0.95), _at(at, Vector3(0, y + 0.5, 0), Vector3(12, 0, 0)), cloth)            # hunched body
			k.add(_sph(0.18), _at(at, Vector3(0, y + 1.05, 0.18)), flesh)                                       # head
			k.add(_sph(0.035, 6), _at(at, Vector3(-0.06, y + 1.07, 0.34)), Color("#d8e8e0"))
			k.add(_sph(0.035, 6), _at(at, Vector3(0.06, y + 1.07, 0.34)), Color("#d8e8e0"))
			for sx in [-1, 1]:
				k.add(_cap(0.06, 0.62), _at(at, Vector3(sx * 0.24, y + 0.72, 0.22), Vector3(-55, 0, sx * 8)), cloth)  # reaching arms
				k.add(_sph(0.07), _at(at, Vector3(sx * 0.26, y + 0.62, 0.48)), flesh)
			for i in 4:  # lake weed
				k.add(_cyl(0.015, 0.025, 0.4, 5), _at(at, Vector3(-0.2 + i * 0.13, y + 0.75, -0.12), Vector3(0, 0, -10 + i * 7)), tint.call(Color("#3e6a3a")))
		"smuggler":
			k.add(_cyl(0.2, 0.32, 0.95), _at(at, Vector3(0, y + 0.48, 0)), tint.call(Color("#4a4a3a")))         # coat
			k.add(_cyl(0.23, 0.23, 0.08), _at(at, Vector3(0, y + 0.85, 0)), tint.call(Color("#a83020")))        # scarf
			k.add(_sph(0.18), _at(at, Vector3(0, y + 1.08, 0.02)), tint.call(SKIN))
			k.add(_cyl(0.36, 0.36, 0.04, 16), _at(at, Vector3(0, y + 1.2, 0), Vector3(-6, 0, 0)), tint.call(Color("#2e2620")))  # brim
			k.add(_cyl(0.15, 0.18, 0.2), _at(at, Vector3(0, y + 1.32, 0)), tint.call(Color("#2e2620")))
			k.add(_cap(0.06, 0.45), _at(at, Vector3(0.24, y + 0.72, 0.14), Vector3(-40, 0, 20)), tint.call(Color("#4a4a3a")))
			k.add(_box(Vector3(0.04, 0.04, 0.32)), _at(at, Vector3(0.3, y + 0.62, 0.38), Vector3(-20, 0, 0)), Color("#c8ccd0"))  # knife
			k.add(_sph(0.03, 6), _at(at, Vector3(-0.06, y + 1.1, 0.18)), INK)
			k.add(_box(Vector3(0.12, 0.03, 0.02)), _at(at, Vector3(0.05, y + 1.12, 0.18)), INK)                 # eyepatch
		"abbess":
			var habit: Color = tint.call(Color("#2c3448"))
			k.add(_cyl(0.18, 0.48, 1.35), _at(at, Vector3(0, y + 0.68, 0)), habit)
			k.add(_sph(0.17), _at(at, Vector3(0, y + 1.45, 0.03)), tint.call(Color("#b8c4bc")))                  # pale face
			k.add(_cyl(0.2, 0.2, 0.1), _at(at, Vector3(0, y + 1.3, 0.0)), tint.call(WHITE))                       # wimple
			k.add(_sph(0.23), _at(at, Vector3(0, y + 1.5, -0.07)), habit)                                         # veil
			k.add(_cyl(0.04, 0.3, 0.9), _at(at, Vector3(0, y + 1.0, -0.2), Vector3(14, 0, 0)), habit)            # veil drape
			k.add(_sph(0.03, 6), _at(at, Vector3(-0.06, y + 1.47, 0.18)), Color("#e0f0e8"))
			k.add(_sph(0.03, 6), _at(at, Vector3(0.06, y + 1.47, 0.18)), Color("#e0f0e8"))
			k.add(_cyl(0.04, 0.12, 0.16), _at(at, Vector3(0.26, y + 0.82, 0.26)), tint.call(Color("#b08a3a")))   # hand-bell
			k.add(_cap(0.06, 0.5), _at(at, Vector3(0.22, y + 1.02, 0.15), Vector3(-30, 0, 18)), habit)
			for i in 5:
				k.add(_cyl(0.012, 0.02, 0.5, 5), _at(at, Vector3(-0.3 + i * 0.15, y + 0.3, 0.22 + absf(i - 2) * -0.04), Vector3(10, 0, -8 + i * 4)), tint.call(Color("#3e6a3a")))
		"innkeeper":
			k.add(_cyl(0.22, 0.4, 1.0), _at(at, Vector3(0, y + 0.5, 0)), tint.call(Color("#7a4a2a")))
			k.add(_box(Vector3(0.36, 0.6, 0.06)), _at(at, Vector3(0, y + 0.45, 0.33), Vector3(-12, 0, 0)), tint.call(WHITE))  # apron
			k.add(_sph(0.18), _at(at, Vector3(0, y + 1.15, 0.02)), tint.call(SKIN))
			k.add(_sph(0.13), _at(at, Vector3(0, y + 1.3, -0.12)), tint.call(Color("#5a2a14")))                  # bun
			k.add(_cyl(0.08, 0.08, 0.16), _at(at, Vector3(0.3, y + 0.75, 0.2)), tint.call(Color("#9a7a52")))     # mug
			k.add(_sph(0.03, 6), _at(at, Vector3(-0.06, y + 1.17, 0.18)), INK)
			k.add(_sph(0.03, 6), _at(at, Vector3(0.06, y + 1.17, 0.18)), INK)
		"kettle":
			k.add(_sph(0.42), _at(at, Vector3(0, y + 0.5, 0), Vector3.ZERO, Vector3(1.0, 1.15, 0.9)), tint.call(Color("#4a3a5a")))
			k.add(_cyl(0.3, 0.42, 0.25), _at(at, Vector3(0, y + 0.85, 0)), tint.call(Color("#8a2a3a")))          # shawl
			k.add(_sph(0.2), _at(at, Vector3(0, y + 1.15, 0.02)), tint.call(SKIN))
			k.add(_cyl(0.16, 0.26, 0.18), _at(at, Vector3(0, y + 1.32, -0.03)), tint.call(Color("#2e2620")))     # bonnet
			k.add(_box(Vector3(0.03, 0.03, 0.22)), _at(at, Vector3(0.08, y + 1.06, 0.28), Vector3(10, 0, 0)), WOOD_D)  # pipe
			k.add(_cyl(0.04, 0.03, 0.06), _at(at, Vector3(0.08, y + 1.1, 0.4)), WOOD_D)
			k.add(_sph(0.03, 6), _at(at, Vector3(-0.07, y + 1.18, 0.18)), INK)
			k.add(_sph(0.03, 6), _at(at, Vector3(0.07, y + 1.18, 0.18)), INK)
		_:
			k.add(_cyl(0.2, 0.42, 1.2), _at(at, Vector3(0, y + 0.6, 0)), tint.call(Color("#3a3a3a")))
			k.add(_sph(0.24), _at(at, Vector3(0, y + 1.32, 0)), tint.call(Color("#2a2a2a")))
			k.add(_sph(0.03, 6), _at(at, Vector3(-0.07, y + 1.32, 0.21)), Color("#e8c040"))
			k.add(_sph(0.03, 6), _at(at, Vector3(0.07, y + 1.32, 0.21)), Color("#e8c040"))


# ------------------------------------------------------------------ board tiles

## The ground colour under each tile icon.
static func terrain(icon: String) -> Color:
	match icon:
		"dive", "bell": return WATER
		"shore", "drowned", "jetty", "cove", "chest": return SAND
		"abbey", "shrine", "tower", "cave": return Color("#8a8a6a")
	return GRASS


## A scene tile: a painted hex of ground with a little scene on it, about 2 units across.
static func tile(icon: String, fade := 0.0, rng_seed := 0) -> Node3D:
	var k := Kit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var g := terrain(icon)
	if Kits.enabled:
		# A KayKit hex, pressed flat: its top sits at 0.2 like the painted one.
		k.piece("model", "hexagon/" + hex_ground(icon), T(Vector3.ZERO, Vector3(0, 30, 0), Vector3(0.98, 0.2, 0.98)), false,
			{"tint": g, "wash": 0.7, "sat": 1.0})
	else:
		k.add(_cyl(0.98, 1.02, 0.16, 6), T(Vector3(0, 0.08, 0), Vector3(0, 30, 0)), g.darkened(0.25))
		k.add(_cyl(0.92, 0.98, 0.04, 6), T(Vector3(0, 0.18, 0), Vector3(0, 30, 0)), g)
	var at := T(Vector3(0, 0.2, -0.2), Vector3.ZERO, Vector3.ONE * 1.3)
	if not (Kits.enabled and kit_icon(k, icon, at, rng)):
		add_icon(k, icon, at, rng)
	var node := k.node(fade)
	node.name = "Tile_" + icon
	return node


## Which KayKit hex goes under a tile icon.
static func hex_ground(icon: String) -> String:
	match icon:
		"dive", "bell", "bridge": return "hex_water"
		"shore", "drowned", "jetty": return "hex_coast_A"
		"cove", "chest": return "hex_coast_B"
	return "hex_grass"


## Tile scenes from kit pieces (KayKit buildings, Quaternius trees and rocks), keeping the
## code-built boats, bells, jetty and water rings that no kit has. False: use add_icon.
static func kit_icon(k: Kit, icon: String, at: Transform3D, rng: RandomNumberGenerator) -> bool:
	var hex := func(name: String, pos: Vector3, rot := 0.0, s := 0.62) -> void:
		k.piece("model", "hexagon/" + name, _at(at, pos, Vector3(0, rot, 0), Vector3.ONE * s * 1.2))
	var nat := func(name: String, pos: Vector3, rot := 0.0, s := 0.6) -> void:
		k.piece("model", "nature/" + name, _at(at, pos, Vector3(0, rot, 0), Vector3.ONE * s))
	match icon:
		"inn":
			hex.call("building_tavern_red", Vector3(-0.05, 0, 0.05), 200.0, 0.7)
			hex.call("barrel", Vector3(0.45, 0, 0.45), 0.0, 0.5)
		"village":
			hex.call("building_home_A_red", Vector3(-0.35, 0, 0.05), 195.0, 0.55)
			hex.call("building_home_B_red", Vector3(0.3, 0, -0.15), 170.0, 0.55)
			hex.call("building_well_red", Vector3(0.25, 0, 0.5), 0.0, 0.45)
		"drowned":
			_water(k, _at(at, Vector3(0.1, 0, 0.25)), 0.62)
			add_figure(k, "drowned", _at(at, Vector3(-0.15, -0.05, 0.25), Vector3.ZERO, Vector3.ONE * 0.5), true)
			add_figure(k, "drowned", _at(at, Vector3(0.32, -0.05, 0.05), Vector3(0, -20, 0), Vector3.ONE * 0.45), true)
			hex.call("building_home_B_red", Vector3(-0.45, 0, -0.35), 160.0, 0.4)
		"jetty":
			_water(k, _at(at, Vector3(0.15, 0, 0.25)), 0.66)
			for i in 5:
				k.add(_box(Vector3(0.34, 0.04, 0.12)), _at(at, Vector3(-0.3 + i * 0.13, 0.12, -0.3 + i * 0.15), Vector3(0, -40, 0)), WOOD_L)
			for i in 3:
				k.add(_cyl(0.035, 0.04, 0.3, 6), _at(at, Vector3(-0.2 + i * 0.2, 0.1, -0.12 + i * 0.22)), WOOD_D)
			_boat(k, _at(at, Vector3(0.45, 0.02, 0.0), Vector3(0, 70, 0)), 0.6)
			hex.call("crate_A_small", Vector3(-0.45, 0, -0.35), 20.0, 0.5)
		"abbey":
			hex.call("building_church_red", Vector3(0.0, 0, -0.05), 190.0, 0.62)
			_water(k, _at(at, Vector3(-0.4, 0, 0.55)), 0.3)
		"cove":
			nat.call("Rock_Medium_1", Vector3(-0.4, 0, -0.05), 0.0, 0.32)
			nat.call("Rock_Medium_2", Vector3(0.35, 0, -0.1), 60.0, 0.3)
			_boat(k, _at(at, Vector3(0.0, 0.03, 0.48), Vector3(0, 10, 0)), 0.55)
			hex.call("crate_A_small", Vector3(-0.1, 0, -0.05), 10.0, 0.45)
			hex.call("sack", Vector3(0.12, 0, -0.1), 0.0, 0.45)
		"camp":
			hex.call("tent", Vector3(-0.3, 0, -0.05), 30.0, 1.2)
			hex.call("resource_lumber", Vector3(0.45, 0, -0.3), 70.0, 0.5)
			for i in 3:
				k.add(_cyl(0.04, 0.04, 0.36, 6), _at(at, Vector3(0.3, 0.05, 0.25), Vector3(90, i * 60, 0)), WOOD_D)
			k.glow().add(_cyl(0.0, 0.1, 0.28, 8), _at(at, Vector3(0.3, 0.2, 0.25)), Color("#ff9a3a"))
			add_figure(k, "smuggler", _at(at, Vector3(0.1, 0, -0.25), Vector3(0, 20, 0), Vector3.ONE * 0.42), true)
		"chest":
			k.piece("model", "fantasy_props/Chest_Wood", _at(at, Vector3(0, 0, 0), Vector3(0, 10, 0), Vector3.ONE * 0.5))
			k.piece("model", "fantasy_props/Coin_Pile_2", _at(at, Vector3(0.3, 0, 0.45), Vector3(0, 40, 0), Vector3.ONE * 1.2))
			k.piece("model", "fantasy_props/Coin_Pile", _at(at, Vector3(-0.35, 0, 0.4), Vector3(0, -20, 0), Vector3.ONE * 1.2))
		"shrine":
			for p in [Vector3(-0.35, 0, 0), Vector3(0.35, 0, 0)]:
				k.add(_box(Vector3(0.18, 0.62, 0.18)), _at(at, p + Vector3(0, 0.31, 0)), STONE)
			k.add(_box(Vector3(0.95, 0.15, 0.24)), _at(at, Vector3(0, 0.69, 0)), STONE_D)
			k.add(_prism(Vector3(1.05, 0.2, 0.34)), _at(at, Vector3(0, 0.86, 0)), Color("#5a6a32"))
			k.add(_cyl(0.18, 0.2, 0.06, 10), _at(at, Vector3(0, 0.03, 0.4)), STONE_D)
			k.glow().add(_cyl(0.0, 0.09, 0.22, 8), _at(at, Vector3(0, 0.16, 0.4)), Color("#ff9a3a"))
			nat.call("Pine_1", Vector3(-0.55, 0, -0.35), 0.0, 0.11)
			nat.call("Bush_Common", Vector3(0.55, 0, 0.45), 0.0, 0.25)
		"tower":
			hex.call("building_tower_A_red", Vector3(0, 0, 0), 0.0, 0.6)
		"forest":
			nat.call("CommonTree_1", Vector3(-0.3, 0, 0), 0.0, 0.12)
			nat.call("Pine_2", Vector3(0.28, 0, -0.1), 40.0, 0.12)
			nat.call("CommonTree_2", Vector3(0.0, 0, 0.38), 80.0, 0.1)
		"bridge":
			hex.call("building_bridge_A", Vector3(0, 0, 0), 90.0, 0.6)
		"market":
			hex.call("tent", Vector3(-0.35, 0, -0.1), 20.0, 1.0)
			hex.call("tent", Vector3(0.3, 0, -0.25), -30.0, 0.9)
			hex.call("crate_A_small", Vector3(0.35, 0, 0.35), 15.0, 0.5)
			hex.call("barrel", Vector3(-0.05, 0, 0.4), 0.0, 0.45)
			hex.call("sack", Vector3(-0.4, 0, 0.4), 0.0, 0.45)
		"keep":
			hex.call("building_tower_A_red", Vector3(-0.25, 0, -0.1), 0.0, 0.55)
			hex.call("building_home_B_red", Vector3(0.35, 0, 0.05), 200.0, 0.45)
			for i in 3:
				hex.call("fence_wood_straight", Vector3(-0.45 + i * 0.42, 0, 0.5), 0.0, 0.5)
			hex.call("flag_red", Vector3(0.45, 0, -0.4), 0.0, 0.5)
		"road":
			hex.call("tree_single_A", Vector3(-0.45, 0, -0.2), 0.0, 0.5)
			hex.call("rock_single_B", Vector3(0.4, 0, 0.35), 40.0, 0.5)
			hex.call("hill_single_A", Vector3(0.35, 0, -0.35), 0.0, 0.45)
			for i in 4:
				k.add(_box(Vector3(0.16, 0.02, 0.1)), _at(at, Vector3(-0.3 + i * 0.2, 0.06, 0.15 - i * 0.08), Vector3(0, 20, 0)), STONE)
		_:
			return false
	return true


static func _house(k: Kit, at: Transform3D, w: float, roof_col := ROOF, lit := true) -> void:
	k.add(_box(Vector3(w, w * 0.75, w * 0.8)), _at(at, Vector3(0, w * 0.375, 0)), Color("#d8c8a0"))
	k.add(_prism(Vector3(w * 1.15, w * 0.55, w * 0.9)), _at(at, Vector3(0, w * 0.75 + w * 0.27, 0)), roof_col)
	k.add(_box(Vector3(w * 0.22, w * 0.3, 0.02)), _at(at, Vector3(0, w * 0.15, w * 0.41)), WOOD_D)    # door
	if lit:
		k.glow().add(_box(Vector3(w * 0.18, w * 0.16, 0.02)), _at(at, Vector3(w * 0.3, w * 0.45, w * 0.41)), LIGHT)


static func _water(k: Kit, at: Transform3D, r: float) -> void:
	k.add(_cyl(r, r, 0.03, 18), _at(at, Vector3(0, 0.0, 0)), WATER)
	k.add(_torus(r * 0.45, r * 0.5, 18), _at(at, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.2, 1)), WATER.lightened(0.25))


static func _bell(k: Kit, at: Transform3D, s: float, col := Color("#b08a3a")) -> void:
	k.add(_cyl(0.18 * s, 0.42 * s, 0.6 * s, 16), _at(at, Vector3(0, 0.3 * s, 0)), col)
	k.add(_sph(0.18 * s), _at(at, Vector3(0, 0.6 * s, 0)), col)
	k.add(_torus(0.38 * s, 0.46 * s), _at(at, Vector3(0, 0.03 * s, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), col.darkened(0.2))
	k.add(_torus(0.04 * s, 0.09 * s), _at(at, Vector3(0, 0.8 * s, 0), Vector3(90, 0, 0)), col.darkened(0.3))


static func _stone(k: Kit, at: Transform3D, h: float, rng: RandomNumberGenerator) -> void:
	k.add(_box(Vector3(0.22, h, 0.16)), _at(at, Vector3(0, h * 0.5, 0), Vector3(rng.randf_range(-6, 6), rng.randf_range(-20, 20), rng.randf_range(-6, 6))), STONE.darkened(rng.randf() * 0.15))


static func add_icon(k: Kit, icon: String, at: Transform3D, rng: RandomNumberGenerator) -> void:
	match icon:
		"inn":
			_house(k, at, 0.8, ROOF)
			k.add(_box(Vector3(0.14, 0.4, 0.14)), _at(at, Vector3(0.22, 0.95, -0.1)), STONE_D)               # chimney
			k.add(_box(Vector3(0.04, 0.4, 0.04)), _at(at, Vector3(-0.5, 0.2, 0.38)), WOOD_D)                   # sign post
			k.add(_box(Vector3(0.24, 0.16, 0.03)), _at(at, Vector3(-0.5, 0.38, 0.4)), Color("#c08a30"))
		"village":
			_house(k, _at(at, Vector3(-0.35, 0, 0.1), Vector3(0, 15, 0)), 0.5, ROOF)
			_house(k, _at(at, Vector3(0.3, 0, -0.1), Vector3(0, -10, 0)), 0.56, Color("#6a4a3a"))
			_house(k, _at(at, Vector3(0.05, 0, 0.5), Vector3(0, 5, 0)), 0.4, ROOF.darkened(0.2), false)
			_water(k, _at(at, Vector3(0.45, 0, 0.62)), 0.32)
		"shore":
			_water(k, _at(at, Vector3(0.2, 0, 0.2)), 0.6)
			for i in 3:
				_stone(k, _at(at, Vector3(-0.4 + i * 0.25, 0, -0.1 - i * 0.05)), 0.25 + rng.randf() * 0.2, rng)
		"drowned":
			_water(k, _at(at, Vector3(0.1, 0, 0.25)), 0.62)
			add_figure(k, "drowned", _at(at, Vector3(-0.15, -0.05, 0.25), Vector3.ZERO, Vector3.ONE * 0.5), true)
			add_figure(k, "drowned", _at(at, Vector3(0.32, -0.05, 0.05), Vector3(0, -20, 0), Vector3.ONE * 0.45), true)
			_house(k, _at(at, Vector3(-0.45, 0, -0.35)), 0.38, ROOF.darkened(0.3))
		"jetty":
			_water(k, _at(at, Vector3(0.15, 0, 0.25)), 0.66)
			for i in 5:
				k.add(_box(Vector3(0.34, 0.04, 0.12)), _at(at, Vector3(-0.3 + i * 0.13, 0.12, -0.3 + i * 0.15), Vector3(0, -40, 0)), WOOD_L)
			for i in 3:
				k.add(_cyl(0.035, 0.04, 0.3, 6), _at(at, Vector3(-0.2 + i * 0.2, 0.1, -0.12 + i * 0.22)), WOOD_D)
			_boat(k, _at(at, Vector3(0.45, 0.02, 0.0), Vector3(0, 70, 0)), 0.6)
		"abbey":
			k.add(_box(Vector3(0.95, 0.5, 0.5)), _at(at, Vector3(-0.1, 0.25, 0)), STONE)
			k.add(_prism(Vector3(1.0, 0.32, 0.55)), _at(at, Vector3(-0.1, 0.66, 0)), STONE_D)
			k.add(_box(Vector3(0.32, 1.0, 0.32)), _at(at, Vector3(0.48, 0.5, 0.0)), STONE.lightened(0.05))   # bell tower
			k.add(_cyl(0.0, 0.26, 0.42, 4), _at(at, Vector3(0.48, 1.21, 0.0), Vector3(0, 45, 0)), STONE_D)
			k.add(_box(Vector3(0.14, 0.24, 0.02)), _at(at, Vector3(0.48, 0.75, 0.17)), INK)                    # belfry window
			k.add(_box(Vector3(0.2, 0.3, 0.02)), _at(at, Vector3(-0.1, 0.15, 0.26)), WOOD_D)                   # door
			_water(k, _at(at, Vector3(-0.3, 0, 0.55)), 0.35)
		"cove":
			k.add(_box(Vector3(0.3, 0.7, 0.5)), _at(at, Vector3(-0.4, 0.35, 0), Vector3(0, 0, 6)), STONE_D)
			k.add(_box(Vector3(0.3, 0.6, 0.5)), _at(at, Vector3(0.35, 0.3, 0), Vector3(0, 0, -6)), STONE_D)
			k.add(_box(Vector3(1.05, 0.25, 0.55)), _at(at, Vector3(0, 0.78, 0), Vector3(0, 0, 3)), STONE)
			_water(k, _at(at, Vector3(0, 0, 0.45)), 0.45)
			_boat(k, _at(at, Vector3(0.0, 0.03, 0.48), Vector3(0, 10, 0)), 0.55)
			k.add(_box(Vector3(0.22, 0.16, 0.16)), _at(at, Vector3(-0.1, 0.08, -0.05)), WOOD_M)                 # crates
			k.add(_box(Vector3(0.16, 0.14, 0.16)), _at(at, Vector3(0.12, 0.07, -0.08)), WOOD_L)
		"camp":
			k.add(_prism(Vector3(0.6, 0.5, 0.7)), _at(at, Vector3(-0.3, 0.25, 0), Vector3(0, 30, 0)), Color("#8a7a5a"))  # tent
			for i in 3:
				k.add(_cyl(0.04, 0.04, 0.36, 6), _at(at, Vector3(0.3, 0.05, 0.25), Vector3(90, i * 60, 0)), WOOD_D)
			k.glow().add(_cyl(0.0, 0.1, 0.28, 8), _at(at, Vector3(0.3, 0.2, 0.25)), Color("#ff9a3a"))
			add_figure(k, "smuggler", _at(at, Vector3(0.1, 0, -0.25), Vector3(0, 20, 0), Vector3.ONE * 0.42), true)
		"dive":
			_water(k, at, 0.85)
			k.add(_torus(0.25, 0.3, 18), _at(at, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.2, 1)), WHITE)
			k.add(_torus(0.5, 0.54, 18), _at(at, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.2, 1)), WATER.lightened(0.4))
			_bell(k, _at(at, Vector3(0, -0.12, 0)), 0.42, Color("#9a7a3a"))
			_boat(k, _at(at, Vector3(-0.45, 0.02, 0.35), Vector3(0, -30, 0)), 0.5)
		"chest":
			k.add(_box(Vector3(0.6, 0.32, 0.4)), _at(at, Vector3(0, 0.16, 0)), WOOD_M)
			k.add(_box(Vector3(0.62, 0.06, 0.42)), _at(at, Vector3(0, 0.08, 0)), Color("#5a4a30"))
			k.add(_box(Vector3(0.62, 0.14, 0.42)), _at(at, Vector3(0, 0.42, -0.14), Vector3(-50, 0, 0)), WOOD_L)  # open lid
			for i in 7:
				k.add(_cyl(0.07, 0.07, 0.03, 10), _at(at, Vector3(rng.randf_range(-0.22, 0.22), 0.33 + rng.randf() * 0.04, rng.randf_range(-0.12, 0.12)), Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20))), GOLD)
			for i in 4:
				k.add(_cyl(0.07, 0.07, 0.03, 10), _at(at, Vector3(rng.randf_range(-0.5, 0.5), 0.02, rng.randf_range(0.25, 0.5))), GOLD)
		"shrine":
			for p in [Vector3(-0.35, 0, 0), Vector3(0.35, 0, 0)]:
				k.add(_box(Vector3(0.18, 0.62, 0.18)), _at(at, p + Vector3(0, 0.31, 0)), STONE)
			k.add(_box(Vector3(0.95, 0.15, 0.24)), _at(at, Vector3(0, 0.69, 0)), STONE_D)                      # lintel
			k.add(_prism(Vector3(1.05, 0.2, 0.34)), _at(at, Vector3(0, 0.86, 0)), Color("#5a6a32"))              # turf roof
			k.add(_cyl(0.18, 0.2, 0.06, 10), _at(at, Vector3(0, 0.03, 0.4)), STONE_D)                           # fire pit
			k.glow().add(_cyl(0.0, 0.09, 0.22, 8), _at(at, Vector3(0, 0.16, 0.4)), Color("#ff9a3a"))
			_water(k, _at(at, Vector3(0.45, 0, 0.6)), 0.3)
		"bell":
			_water(k, at, 0.85)
			k.add(_cyl(0.55, 0.65, 0.12, 8), _at(at, Vector3(0, 0.06, -0.05)), Color("#4a6a5a"))              # green stone floor
			_bell(k, _at(at, Vector3(0, 0.12, -0.05)), 1.0)
			k.add(_cyl(0.015, 0.015, 0.5, 5), _at(at, Vector3(0.0, 1.15, -0.05)), WOOD_D)                       # rope
		"tower":
			k.add(_cyl(0.22, 0.3, 1.1, 10), _at(at, Vector3(0, 0.55, 0)), STONE)
			k.add(_cyl(0.0, 0.32, 0.4, 10), _at(at, Vector3(0, 1.3, 0)), ROOF)
		"forest":
			for p in [Vector3(-0.3, 0, 0), Vector3(0.25, 0, -0.1), Vector3(0, 0, 0.35)]:
				k.add(_cyl(0.04, 0.05, 0.25, 6), _at(at, p + Vector3(0, 0.12, 0)), WOOD_D)
				k.add(_cyl(0.0, 0.28, 0.6, 8), _at(at, p + Vector3(0, 0.5, 0)), Color("#3e5a2a"))
		"cave":
			k.add(_sph(0.55, 10), _at(at, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.2, 1.0, 0.9)), STONE_D)
			k.add(_sph(0.25, 10), _at(at, Vector3(0, 0.1, 0.32), Vector3.ZERO, Vector3(1, 1.1, 0.6)), Color("#14100c"))
		"bridge":
			_water(k, at, 0.8)
			for i in 6:
				k.add(_box(Vector3(0.14, 0.05, 0.4)), _at(at, Vector3(-0.42 + i * 0.17, 0.12 + sin(i / 5.0 * PI) * 0.15, 0)), WOOD_L)
		"market":
			for p in [Vector3(-0.35, 0, -0.1), Vector3(0.3, 0, -0.2)]:
				k.add(_box(Vector3(0.45, 0.3, 0.35)), _at(at, p + Vector3(0, 0.15, 0)), WOOD_M)
				k.add(_prism(Vector3(0.55, 0.22, 0.42)), _at(at, p + Vector3(0, 0.41, 0)), Color("#a83a2a"))
			k.add(_box(Vector3(0.22, 0.16, 0.16)), _at(at, Vector3(0.3, 0.08, 0.4)), WOOD_L)
		"keep":
			k.add(_box(Vector3(0.38, 1.0, 0.38)), _at(at, Vector3(-0.25, 0.5, -0.1)), STONE)
			k.add(_cyl(0.0, 0.3, 0.4, 4), _at(at, Vector3(-0.25, 1.2, -0.1), Vector3(0, 45, 0)), ROOF)
			k.add(_box(Vector3(1.0, 0.35, 0.12)), _at(at, Vector3(0.05, 0.18, 0.45)), STONE_D)
			_house(k, _at(at, Vector3(0.32, 0, 0.0)), 0.42, ROOF)
		"road":
			for i in 5:
				k.add(_box(Vector3(0.18, 0.03, 0.12)), _at(at, Vector3(-0.4 + i * 0.2, 0.05, 0.2 - i * 0.1), Vector3(0, 25, 0)), STONE)
			k.add(_cyl(0.0, 0.25, 0.55, 8), _at(at, Vector3(-0.4, 0.3, -0.3)), Color("#3e5a2a"))
		_:
			k.add(_box(Vector3(0.06, 0.7, 0.06)), _at(at, Vector3(0, 0.35, 0)), WOOD_D)
			k.add(_box(Vector3(0.42, 0.12, 0.04)), _at(at, Vector3(0.12, 0.58, 0.04), Vector3(0, 0, 6)), WOOD_L)
			k.add(_box(Vector3(0.38, 0.12, 0.04)), _at(at, Vector3(-0.1, 0.42, 0.04), Vector3(0, 0, -8)), WOOD_L)


static func _boat(k: Kit, at: Transform3D, s: float) -> void:
	k.add(_cyl(0.18 * s, 0.1 * s, 0.9 * s, 10), _at(at, Vector3(0, 0.06 * s, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.55)), WOOD_M)
	k.add(_box(Vector3(0.7 * s, 0.03 * s, 0.14 * s)), _at(at, Vector3(0, 0.15 * s, 0)), WOOD_L)


# ------------------------------------------------------------------ tokens

## A small token that sits on a tile's rim, about 0.6 units tall.
static func token(icon: String, figure := "") -> Node3D:
	var k := Kit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(icon)
	var at := Transform3D()
	match icon:
		"coins":
			for i in 5:
				k.add(_cyl(0.13, 0.13, 0.05, 12), _at(at, Vector3(rng.randf_range(-0.02, 0.02), 0.03 + i * 0.055, rng.randf_range(-0.02, 0.02))), GOLD)
			k.add(_cyl(0.13, 0.13, 0.05, 12), _at(at, Vector3(0.24, 0.03, 0.06), Vector3(0, 0, 8)), GOLD)
		"chest":
			k.add(_box(Vector3(0.36, 0.2, 0.24)), _at(at, Vector3(0, 0.1, 0)), WOOD_M)
			k.add(_cyl(0.12, 0.12, 0.36, 10), _at(at, Vector3(0, 0.2, 0), Vector3(0, 0, 90), Vector3(1, 1, 1.0)), WOOD_L)
			k.add(_box(Vector3(0.06, 0.08, 0.02)), _at(at, Vector3(0, 0.16, 0.125)), GOLD)
		"grave":
			k.add(_sph(0.22, 10), _at(at, Vector3(0, 0.0, 0.1), Vector3.ZERO, Vector3(1.0, 0.4, 1.4)), Color("#6a5a3a"))
			k.add(_box(Vector3(0.24, 0.34, 0.07)), _at(at, Vector3(0, 0.17, -0.18), Vector3(-6, 0, 3)), STONE)
		"lamp":
			k.add(_cyl(0.025, 0.03, 0.55, 6), _at(at, Vector3(0, 0.27, 0)), Color("#3a3028"))
			k.add(_box(Vector3(0.16, 0.2, 0.16)), _at(at, Vector3(0, 0.6, 0)), Color("#3a3028"))
			k.glow().add(_box(Vector3(0.12, 0.15, 0.17)), _at(at, Vector3(0, 0.6, 0)), LIGHT)
			k.glow().add(_box(Vector3(0.17, 0.15, 0.12)), _at(at, Vector3(0, 0.6, 0)), LIGHT)
		"beacon":
			for i in 3:
				k.add(_cyl(0.02, 0.025, 0.5, 5), _at(at, Vector3(0, 0.22, 0), Vector3(16, i * 120, 0)), WOOD_D)
			k.add(_cyl(0.16, 0.1, 0.12, 10), _at(at, Vector3(0, 0.48, 0)), Color("#3a3028"))
			k.glow().add(_cyl(0.0, 0.14, 0.34, 8), _at(at, Vector3(0, 0.68, 0)), Color("#ffb040"))
			k.glow().add(_cyl(0.0, 0.08, 0.22, 8), _at(at, Vector3(0.05, 0.82, 0.02)), Color("#fff0a0"))
		"flag":
			k.add(_cyl(0.02, 0.02, 0.7, 6), _at(at, Vector3(0, 0.35, 0)), WOOD_D)
			k.add(_box(Vector3(0.3, 0.18, 0.02)), _at(at, Vector3(0.16, 0.6, 0), Vector3(0, 0, -4)), Color("#2a2a2a"))
			k.add(_sph(0.04, 6), _at(at, Vector3(0.16, 0.6, 0.02)), WHITE)
		"knife":
			k.add(_box(Vector3(0.05, 0.03, 0.34)), _at(at, Vector3(0, 0.12, 0.08), Vector3(-30, 25, 0)), Color("#c8ccd0"))
			k.add(_box(Vector3(0.06, 0.06, 0.14)), _at(at, Vector3(0, 0.03, -0.12), Vector3(-30, 25, 0)), WOOD_D)
		"rune":
			k.add(_box(Vector3(0.3, 0.12, 0.24)), _at(at, Vector3(0, 0.06, 0), Vector3(0, 15, 4)), STONE)
			k.glow().add(_box(Vector3(0.16, 0.01, 0.03)), _at(at, Vector3(0, 0.125, 0), Vector3(0, 60, 0)), Color("#60e0d0"))
			k.glow().add(_box(Vector3(0.12, 0.01, 0.03)), _at(at, Vector3(0.02, 0.125, 0.0), Vector3(0, -30, 0)), Color("#60e0d0"))
		"boat":
			_boat(k, _at(at, Vector3(0, 0.0, 0)), 0.9)
		"footprints":
			for i in 4:
				k.add(_sph(0.06, 8), _at(at, Vector3((i % 2) * 0.1 - 0.05, 0.0, -0.25 + i * 0.16), Vector3.ZERO, Vector3(0.7, 0.15, 1.2)), Color("#3a5a62"))
		"handbell":
			_bell(k, _at(at, Vector3(0, 0, 0)), 0.32, Color("#c8a040"))
			k.add(_cyl(0.025, 0.03, 0.2, 6), _at(at, Vector3(0, 0.3, 0)), WOOD_D)
		"candle":
			k.add(_cyl(0.12, 0.14, 0.04, 10), _at(at, Vector3(0, 0.02, 0)), Color("#b08a3a"))
			k.add(_cyl(0.06, 0.06, 0.3, 8), _at(at, Vector3(0, 0.19, 0)), WHITE)
			k.glow().add(_cyl(0.0, 0.04, 0.12, 6), _at(at, Vector3(0, 0.4, 0)), Color("#ffc050"))
		"broken_bell":
			k.add(_cyl(0.08, 0.2, 0.3, 10), _at(at, Vector3(-0.08, 0.1, 0), Vector3(0, 0, 70)), Color("#9a7a3a"))
			k.add(_cyl(0.06, 0.16, 0.22, 8), _at(at, Vector3(0.15, 0.06, 0.05), Vector3(80, 30, 0)), Color("#9a7a3a"))
		"wave":
			k.add(_torus(0.2, 0.28, 14), _at(at, Vector3(0, 0.12, 0), Vector3(90, 0, 0), Vector3(1, 1, 0.6)), WATER)
			k.add(_sph(0.1, 8), _at(at, Vector3(0.18, 0.25, 0), Vector3.ZERO, Vector3(1.2, 0.8, 0.8)), WHITE)
		"dove":
			k.add(_sph(0.1, 10), _at(at, Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.5)), WHITE)
			k.add(_sph(0.06, 8), _at(at, Vector3(0, 0.47, 0.13)), WHITE)
			for sx in [-1, 1]:
				k.add(_box(Vector3(0.24, 0.02, 0.1)), _at(at, Vector3(sx * 0.14, 0.46, -0.02), Vector3(0, 0, sx * 30)), WHITE)
			k.add(_cyl(0.015, 0.015, 0.3, 5), _at(at, Vector3(0, 0.15, 0)), WOOD_D)
		"foe":
			# The beaten foe's own figurine, toppled on its side.
			add_figure(k, figure if figure != "" else "hooded", _at(at, Vector3(0.0, 0.14, 0), Vector3(0, 30, 88), Vector3.ONE * 0.36), true)
		"skull":
			k.add(_sph(0.13, 10), _at(at, Vector3(0, 0.13, 0)), WHITE)
			k.add(_box(Vector3(0.12, 0.06, 0.08)), _at(at, Vector3(0, 0.03, 0.06)), WHITE)
			k.add(_sph(0.03, 6), _at(at, Vector3(-0.045, 0.14, 0.11)), INK)
			k.add(_sph(0.03, 6), _at(at, Vector3(0.045, 0.14, 0.11)), INK)
		"fire":
			k.add(_cyl(0.16, 0.18, 0.05, 10), _at(at, Vector3(0, 0.02, 0)), STONE_D)
			k.glow().add(_cyl(0.0, 0.12, 0.32, 8), _at(at, Vector3(0, 0.2, 0)), Color("#ff9a3a"))
		_:  # seal
			k.add(_cyl(0.14, 0.15, 0.05, 14), _at(at, Vector3(0, 0.025, 0)), Color("#9a1a1a"))
			k.add(_cyl(0.08, 0.08, 0.02, 10), _at(at, Vector3(0, 0.055, 0)), Color("#7a1010"))
	var node := k.node(0.0, false)
	node.name = "Token_" + icon
	return node
