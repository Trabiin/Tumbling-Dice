extends RefCounted
## CC0 model kits (see assets/kits/README.md), repainted to match the code-built inn.
##
## Every imported surface loses its PBR material and gets KIT below: the kit's colour map,
## our toon light bands (spliced in by Mats._shader), a touch of brush noise, and optionally a
## colour wash (tint) or a fade toward the parchment for remembered board tiles. An inverted
## shell draws the ink outline wherever the painterly screen pass does not: on the Low preset,
## and always on the tale board's miniatures, the same as the code-built figurines.
##
## Kits.enabled = false (or --kits=off on the command line) brings back the code-built props,
## which stay in the code as fallbacks and for before/after comparisons.

const Mats := preload("res://scripts/materials.gd")

const ROOT := "res://assets/kits/"

static var enabled := true

const KIT := """
shader_type spatial;
render_mode CULL;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vcol = false;
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform vec4 wash : source_color = vec4(1.0, 1.0, 1.0, 0.0);   // a = how much of the wash
uniform float fade = 0.0;
uniform vec3 paper : source_color = vec3(0.86, 0.76, 0.56);
uniform float brush_scale = 40.0;
uniform float sat = 1.12;
uniform float glow = 0.0;   // glass catches the lamplight even in the dim corners
void fragment() {
#ifdef LITE
	vec4 t = texture(albedo_tex, UV, 1.0);   // one mip down: half the texture bandwidth on Low
#else
	vec4 t = texture(albedo_tex, UV);
#endif
	vec3 c = t.rgb * albedo.rgb * 1.15;   // the kits are painted a little darker than our props
	if (use_vcol) {
		c *= COLOR.rgb;
	}
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, wash.rgb * (0.35 + lum * 1.3), wash.a);
	// Pull the hand-painted texture toward our palette: a little richer, a little brushier.
	c = mix(vec3(lum), c, sat);
	c *= 0.94 + 0.1 * vnoise(vec3(UV * brush_scale, 1.0));
	ALBEDO = mix(c, paper * 0.95, fade);
	EMISSION = c * glow * (1.0 - fade);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.3;
#ifdef CUTOUT
	ALPHA = t.a * albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
}
"""

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

static var _scenes := {}
static var _meshes := {}
static var _mats := {}


static func _shader(cutout: bool) -> Shader:
	var body := KIT.replace("CULL", "cull_disabled" if cutout else "cull_back")
	if cutout:
		body = body.replace("render_mode", "#define CUTOUT\nrender_mode")
	return Mats._shader("kit_cutout" if cutout else "kit", body)


## A kit model as a node, repainted. path is relative to assets/kits, without ".gltf",
## e.g. "fantasy_props/Barrel". opts:
##   fit     scale so the model is this tall (in our units); or
##   scale   a plain uniform scale (default 1)
##   tint    Color, and wash (0..1): wash the colours toward tint
##   outline world-space ink outline width; default: only on the Low preset
##   sat     colour saturation (default 1.12; the bright KayKit palette wants less)
##   fade    0..1 toward the parchment
##   shadows false to cast none
static func model(path: String, opts := {}) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(ROOT + path + ".gltf")
	var ps: PackedScene = _scenes[path]
	var inst := ps.instantiate()
	var root := Node3D.new()
	root.name = path.get_file()
	root.add_child(inst)
	var s := float(opts.get("scale", 1.0))
	if opts.has("fit"):
		var box := aabb(inst)
		s = float(opts.fit) / maxf(box.size.y, 0.001)
	root.scale = Vector3.ONE * s
	# Room props are seen from a metre or two away: about 4 mm of ink, only where the
	# screen pass is off (the Low preset builds its materials with Mats.lite set).
	var width: float = opts.get("outline", 0.35 if Mats.lite else 0.0)
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	if inst is MeshInstance3D:
		meshes.append(inst)
	for mi: MeshInstance3D in meshes:
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			mi.set_surface_override_material(i, paint(src, opts, width / s))
		if opts.get("shadows", true) == false:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## The KIT material for one imported material (cached).
static func paint(src: Material, opts := {}, outline_local := 0.0) -> ShaderMaterial:
	var tint: Color = opts.get("tint", Color.WHITE)
	var wash: float = opts.get("wash", 0.0)
	var fade: float = opts.get("fade", 0.0)
	var sat: float = opts.get("sat", 1.12)
	var key := "%d|%s|%.2f|%.2f|%.2f|%.4f|%s" % [src.get_instance_id() if src else 0, tint.to_html(), wash, fade, sat, outline_local, Mats.lite]
	if _mats.has(key):
		return _mats[key]
	var tex: Texture2D = null
	var col := Color.WHITE
	var vcol := false
	var cutout := false
	var rough := 0.8
	var metal := 0.0
	var glass := false
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		tex = b.albedo_texture
		col = b.albedo_color
		# The props kit tints glass, potions and coins by vertex colour ("..._Vertex" materials).
		vcol = b.vertex_color_use_as_albedo or String(b.resource_name).contains("Vertex")
		cutout = b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH \
			or (b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and tex != null)
		rough = clampf(b.roughness, 0.45, 1.0)
		if String(b.resource_name).begins_with("MI_Trim_Props_Vertex"):
			rough = 0.25   # glass and glazed pots: a crisp toon highlight and a little glow
			glass = true
		metal = b.metallic * 0.6
	var m := _new_mat(tex, col, vcol, cutout, rough, metal, Color(tint, wash), fade)
	m.set_shader_parameter("sat", sat)
	m.set_shader_parameter("glow", 0.35 if glass else 0.0)
	if outline_local > 0.0 and not cutout:
		var o := ShaderMaterial.new()
		o.shader = Mats._shader("kit_outline", OUTLINE)
		o.set_shader_parameter("width", outline_local)
		o.set_shader_parameter("fade", fade)
		m.next_pass = o
	_mats[key] = m
	return m


static func _new_mat(tex: Texture2D, col: Color, vcol: bool, cutout: bool, rough: float, metal: float, tint: Color, fade: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(cutout)
	if tex == null:
		tex = _white()
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("use_vcol", vcol)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("wash", tint)
	m.set_shader_parameter("fade", fade)
	return m


static var _white_tex: ImageTexture
static func _white() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


## The bounds of everything visible under a node, in that node's space.
static func aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var node: Node = e[0]
		var xf: Transform3D = e[1]
		if node is VisualInstance3D and node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var b: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in node.get_children():
			var cx := xf
			if c is Node3D:
				cx = xf * (c as Node3D).transform
			stack.append([c, cx])
	return box


# ------------------------------------------------------------------ miniatures

## Which atlas each baked miniature (tools/bake_minis.gd) is painted with.
const MINI_TEX := {
	"hero": "rogue_texture", "smuggler": "rogue_texture", "innkeeper": "barbarian_texture",
	"drowned": "skeleton_texture", "abbess": "skeleton_texture", "hooded": "skeleton_texture",
}
## Colour washes that turn stock characters into ours.
const MINI_TINT := {
	"drowned": [Color("#5f9a86"), 0.55],   # lake-green bones and weed-dark rags
	"abbess": [Color("#8fb6c4"), 0.4],     # pale, drowned blue
	"hooded": [Color("#5a5468"), 0.35],
}
const MINI_HEIGHT := 1.55                  # the figure itself, standing on its 0.2 base
const GLOW := Color("#9ef0d8")


static func has_mini(kind: String) -> bool:
	return enabled and MINI_TEX.has(kind)


## A baked KayKit character standing at the origin, facing +z, MINI_HEIGHT tall.
## carved: a foe figurine, washed toward carved wood like the code-built ones.
static func mini(kind: String, carved := false, fade := 0.0, outline := 0.035) -> Node3D:
	if not _meshes.has(kind):
		_meshes[kind] = load(ROOT + "minis/" + kind + ".res")
	var mesh: ArrayMesh = _meshes[kind]
	var tex: Texture2D = load(ROOT + "minis/" + MINI_TEX[kind] + ".png")
	var s := MINI_HEIGHT / maxf(mesh.get_aabb().size.y, 0.001)
	var mi := MeshInstance3D.new()
	mi.name = "Kit"
	mi.mesh = mesh
	mi.scale = Vector3.ONE * s
	var t: Array = MINI_TINT.get(kind, [Color.WHITE, 0.0])
	var tint: Color = t[0]
	var wash: float = t[1]
	if carved:
		tint = tint.lerp(Color("#8e5c32"), 0.6) if wash > 0.0 else Color("#8e5c32")
		wash = maxf(wash, 0.35)
	var key := "mini|%s|%s|%.2f|%.2f|%.3f|%s" % [MINI_TEX[kind], tint.to_html(), wash, fade, outline / s, Mats.lite]
	if not _mats.has(key):
		var m := _new_mat(tex, Color.WHITE, false, false, 0.75, 0.0, Color(tint, wash), fade)
		m.set_shader_parameter("brush_scale", 6.0)
		if outline > 0.0:
			var o := ShaderMaterial.new()
			o.shader = Mats._shader("kit_outline", OUTLINE)
			o.set_shader_parameter("width", outline / s)
			o.set_shader_parameter("fade", fade)
			m.next_pass = o
		_mats[key] = m
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == "glow":
			var g := StandardMaterial3D.new()
			g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			g.albedo_color = GLOW
			mi.set_surface_override_material(i, g)
		else:
			mi.set_surface_override_material(i, _mats[key])
	return mi


## Repaint a board piece made by model() or mini() toward the parchment (remembered tiles).
static func set_fade(root: Node, fade: float) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var meta := "kit_base_%d" % i
			if not mi.has_meta(meta):
				mi.set_meta(meta, mi.get_surface_override_material(i))
			var base = mi.get_meta(meta)
			if not (base is ShaderMaterial) or base.get_shader_parameter("fade") == null:
				continue
			var key := "fade|%d|%.2f" % [base.get_instance_id(), fade]
			if not _mats.has(key):
				var c: ShaderMaterial = base.duplicate()
				c.set_shader_parameter("fade", fade)
				if base.next_pass != null:
					var o: ShaderMaterial = base.next_pass.duplicate()
					o.set_shader_parameter("fade", fade)
					c.next_pass = o
				_mats[key] = c
			mi.set_surface_override_material(i, base if fade == 0.0 else _mats[key])
