extends Node3D
## The inn: table, dice tray, fireplace, candles and clutter. The room shell, table, tray,
## fireplace, flames and dice are built from primitives and procedural materials; furniture
## and clutter come from CC0 kits (scripts/kits.gd), with the code-built versions kept as
## fallbacks (Kits.enabled = false). Scale: 1 unit is about 1.2 cm, so a d20 is roughly 2 cm.

const Mats := preload("res://scripts/materials.gd")
const Geo := preload("res://scripts/dice_geometry.gd")
const Props := preload("res://scripts/props.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Kits := preload("res://scripts/kits.gd")

const TRAY := Vector2(18.0, 12.0)   # inner size of the dice tray
const TABLE_TOP := -0.3            # table surface; the velvet tray floor sits at y = 0
const FLOOR_Y := -62.0             # the inn floor (a 75 cm table)
const BACK_WALL_Z := -150.0
## Where the hub puts things: the top of Hollis's lower shelf, and Brannoc's bench.
const SHELF_TOP := Vector3(-62.0, FLOOR_Y + 53.5, BACK_WALL_Z + 9.0)
const BENCH_TOP := Vector3(-178.0, FLOOR_Y + 58.0, BACK_WALL_Z + 22.0)

var _flickers: Array = []          # [light, base_energy, speed, phase]
var _time := 0.0
var _noise := FastNoiseLite.new()


var _gust := 0.0
static var _gust_added := false
var environment: Environment
var particles: Array = []          # dust and embers, switched off at low quality
var map_space := false             # the game puts the tale board where the loose parchment lies


func _ready() -> void:
	# Flames read this to lean and flutter when dice slam into the tray.
	# (global_shader_parameter_get_list() is editor-only, so remember it ourselves.)
	if not _gust_added:
		RenderingServer.global_shader_parameter_add("gust", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
		_gust_added = true
	_noise.frequency = 1.0
	_build_environment()
	_build_table()
	_build_tray()
	_build_props()
	_build_room()
	_build_fireplace(Vector3(25, FLOOR_Y + 34, BACK_WALL_Z))
	_build_post()
	_build_dust()


## A knock on the table: flames lean and flutter for a moment.
func gust(strength: float) -> void:
	_gust = clampf(maxf(_gust, strength / 12.0), 0.0, 1.0)


## Dust motes drifting slowly through the lantern light above the tray.
func _build_dust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 160
	p.lifetime = 14.0
	p.preprocess = 14.0
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	p.mesh = q
	p.material_override = Mats.flame_particle()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(26, 12, 10)
	p.position = Vector3(0, 18, -10)
	p.direction = Vector3(0.3, 0.1, 0.2)
	p.spread = 180
	p.gravity = Vector3(0, -0.03, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.85, 0.6, 0), Color(1, 0.85, 0.6, 0.55), Color(1, 0.85, 0.6, 0.55), Color(1, 0.85, 0.6, 0)])
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	particles.append(p)


## The painterly screen pass (brush smear + ink outlines). Needs Forward+ for the
## depth and normal buffers; the Compatibility renderer just shows the toon lighting.
var post: MeshInstance3D
func _build_post() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus" or not Mats.toon:
		return
	post = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	post.mesh = q
	post.material_override = Mats.post()
	post.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(post)


## Graphics quality (see scripts/game/settings.gd). Screen-space effects only exist in Forward+.
func apply_quality(q: Dictionary) -> void:
	var fwd := RenderingServer.get_current_rendering_method() == "forward_plus"
	if environment != null:
		environment.ssao_enabled = fwd and q.ssao
		environment.ssil_enabled = fwd and q.ssil
		environment.volumetric_fog_enabled = fwd and q.vfog
		environment.glow_enabled = q.glow
	if post != null:
		post.visible = q.post
	for p in particles:
		p.emitting = q.particles
		p.visible = q.particles


func _process(delta: float) -> void:
	_time += delta
	_gust = move_toward(_gust, 0.0, delta * 0.8)
	RenderingServer.global_shader_parameter_set("gust", _gust)
	for f in _flickers:
		var light: Light3D = f[0]
		var n := _noise.get_noise_2d(_time * f[2], f[3])
		light.light_energy = f[1] * (0.85 + 0.3 * n)


# ------------------------------------------------------------------ helpers

## A box with softly rounded edges (bevel scales with the smallest side).
func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := Geo.box(size)
	var bevel := minf(minf(size.x, size.y), size.z) * 0.12
	mi.mesh = Geo.chamfer(b.verts, b.faces, minf(bevel, 1.5)).mesh
	mi.material_override = mat
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(r_top: float, r_bottom: float, h: float, pos: Vector3, mat: Material, segments := 48, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = segments
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A kit model (path under assets/kits, no extension), k units per kit metre, turned by
## rot_y degrees, standing on pos. The kits are modelled close to real size; 1 m is 83 of
## our units, but the furniture reads better a little smaller than life next to the table.
func _kit(path: String, pos: Vector3, rot_y := 0.0, k := 66.0, parent: Node = self) -> Node3D:
	var n := Kits.model(path, {"scale": k})
	n.position = pos
	n.rotation_degrees.y = rot_y
	parent.add_child(n)
	return n


func _collider(size: Vector3, pos: Vector3, surface := "wood") -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", surface)
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.2
	body.physics_material_override = pm
	add_child(body)


func _rng(at: Vector3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(at)
	return r


func _flicker(light: Light3D, speed := 6.0) -> void:
	_flickers.append([light, light.light_energy, speed, randf() * 100.0])


# ------------------------------------------------------------------ scene

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()  # only used for reflections on metal and resin
	sky_mat.sky_top_color = Color("#2a1a10")
	sky_mat.sky_horizon_color = Color("#6a3c1c")
	sky_mat.ground_horizon_color = Color("#3a2010")
	sky_mat.energy_multiplier = 0.45
	sky_mat.ground_bottom_color = Color("#140a05")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5e5078")  # dusky violet shadows against warm firelight
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	# Forward+ extras (ignored by the Compatibility renderer): contact shadows in
	# crevices, bounced light, and a warm haze that the fire and candles glow through.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 1.5
		env.ssao_intensity = 2.0
		env.ssil_enabled = true
		env.ssil_radius = 4.0
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.002
		env.volumetric_fog_albedo = Color("#b89070")
		env.volumetric_fog_length = 260.0
		env.volumetric_fog_detail_spread = 1.5
		env.volumetric_fog_ambient_inject = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color("#3a2a20")
	env.fog_density = 0.0005
	env.fog_sky_affect = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.95
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	environment = env

	# Lantern overhead: a warm pool of light on the tray.
	var spot := SpotLight3D.new()
	spot.position = Vector3(2, 45, 8)
	spot.look_at_from_position(spot.position, Vector3(0, 0, -1))
	spot.spot_range = 90
	spot.spot_angle = 28
	spot.spot_angle_attenuation = 1.3
	spot.light_color = Color("#fff0dc")
	spot.light_energy = 5.5
	spot.shadow_enabled = false
	add_child(spot)
	_flicker(spot, 1.5)
	# Soft high light from the same lantern direction, only for the dice shadows
	# (directional shadows are steadier than spot shadows in the Compatibility renderer).
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-72, 12, 0)
	key.light_color = Color("#ffd9a8")
	key.light_energy = 0.38
	key.shadow_enabled = true
	key.shadow_opacity = 0.85
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 45.0
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # no sun disk reflected in shiny dice
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(key)


func _build_table() -> void:
	var top := Mats.wood({"col_light": Color("#74513a"), "col_dark": Color("#2e1d12"),
		"plank_width": 11.0, "plank_length": 90.0, "axis": 2, "gap": 0.1, "rough": 0.6, "seed": 1.0})
	# separate planks with small gaps, each slightly uneven, with worn rounded edges
	var rng := _rng(Vector3(1, 2, 3))
	for i in 4:
		var m: ShaderMaterial = top.duplicate()
		m.set_shader_parameter("seed", 1.0 + i * 5.0)
		var pz := -22.0 + 5.5 + i * 11.0
		var p := _box(Vector3(90, 5, 10.8), Vector3(rng.randf_range(-0.6, 0.6), TABLE_TOP - 2.5 - rng.randf_range(0.0, 0.08), pz), m)
		p.rotation_degrees.x = rng.randf_range(-0.15, 0.15)
	# cleats underneath tie the planks together
	for x in [-36, 36]:
		_box(Vector3(6, 3, 42), Vector3(x, TABLE_TOP - 6.5, 0), top)
	# legs, seen in the background
	var leg := Mats.wood({"col_light": Color("#5a3a20"), "col_dark": Color("#2a160a"), "axis": 1, "plank_width": 100.0})
	for x in [-40, 40]:
		for z in [-28, 20]:
			_box(Vector3(5, 56, 5), Vector3(x, FLOOR_Y + 28, z * 0.7), leg)
	_collider(Vector3(90, 5, 44), Vector3(0, TABLE_TOP - 2.5, 0))


func _build_tray() -> void:
	var hx := TRAY.x / 2.0
	var hz := TRAY.y / 2.0
	var wall_t := 0.9
	var wall_h := 1.6
	# velvet bed
	_box(Vector3(TRAY.x, 0.3, TRAY.y), Vector3(0, -0.15, 0), Mats.velvet(Color("#163c3e")))
	_collider(Vector3(TRAY.x + 4, 1, TRAY.y + 4), Vector3(0, -0.5, 0), "felt")

	var frame := Mats.wood({"col_light": Color("#7a4a26"), "col_dark": Color("#3a1e0c"),
		"plank_width": 30.0, "axis": 2, "rough": 0.58, "seed": 5.0, "ring_density": 3.0, "knots": 0.0})
	var cap := Mats.wood({"col_light": Color("#8a5a30"), "col_dark": Color("#4a2810"),
		"plank_width": 30.0, "axis": 2, "rough": 0.55, "seed": 9.0, "ring_density": 3.0, "knots": 0.0})
	var brass := Mats.metal(Color("#c9a14a"), 0.3)
	var sides := [
		[Vector3(0, 0, -hz - wall_t / 2), Vector3(TRAY.x + 2 * wall_t, 0, wall_t)],
		[Vector3(0, 0, hz + wall_t / 2), Vector3(TRAY.x + 2 * wall_t, 0, wall_t)],
		[Vector3(-hx - wall_t / 2, 0, 0), Vector3(wall_t, 0, TRAY.y)],
		[Vector3(hx + wall_t / 2, 0, 0), Vector3(wall_t, 0, TRAY.y)]]
	var frame_z := frame.duplicate()
	frame_z.set_shader_parameter("axis", 0)
	var cap_z := cap.duplicate()
	cap_z.set_shader_parameter("axis", 0)
	for s in sides:
		var pos: Vector3 = s[0]
		var size: Vector3 = s[1]
		var along_z := size.z > size.x
		_box(size + Vector3(0, wall_h, 0), pos + Vector3(0, wall_h / 2 + TABLE_TOP / 2, 0), frame_z if along_z else frame)
		_box(size + Vector3(0.25, 0.18, 0.25), pos + Vector3(0, wall_h + 0.05, 0), cap_z if along_z else cap)
		# tall invisible collider keeps dice in
		_collider(size + Vector3(0, 30, 0), pos + Vector3(0, 15, 0))
	for x in [-hx - wall_t / 2, hx + wall_t / 2]:
		for z in [-hz - wall_t / 2, hz + wall_t / 2]:
			var stud := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.42
			sm.height = 0.5
			stud.mesh = sm
			stud.material_override = brass
			stud.position = Vector3(x, wall_h + 0.2, z)
			add_child(stud)


func _build_props() -> void:
	if Kits.enabled:
		_kit_props()
		return
	_candle(Vector3(15.0, TABLE_TOP, -12.0), 6.0, false)
	_candle(Vector3(-13.0, TABLE_TOP, -15.0), 3.8, false)
	_tankard(Vector3(-23.0, TABLE_TOP, -12.0))
	_coins(Vector3(16.0, TABLE_TOP, -1.0))
	if not map_space:
		_parchment(Vector3(-17.5, TABLE_TOP, 4.0))
	_jug(Vector3(25.0, TABLE_TOP, -13.0))
	var pouch := Props.pouch(_rng(Vector3(9, 9, 9)))
	pouch.position = Vector3(20.5, TABLE_TOP + 2.6, 1.5)
	pouch.rotation_degrees = Vector3(0, -30, 72)   # tipped over, coins spilling out
	add_child(pouch)
	_tome(Vector3(-24.0, TABLE_TOP, -17.0))


## Table clutter from the props kit. The candles keep their code-built wax and flames (they
## light the dice), and the jug stays code: the kit has no pitcher.
func _kit_props() -> void:
	_candle(Vector3(15.0, TABLE_TOP, -12.0), 6.0, false)
	_candle(Vector3(-13.0, TABLE_TOP, -15.0), 3.8, false)
	_kit("fantasy_props/Mug", Vector3(-23.0, TABLE_TOP, -12.0), 200.0, 52.0)
	_kit("fantasy_props/Coin_Pile_2", Vector3(16.5, TABLE_TOP, -1.0), 25.0, 30.0)
	_kit("fantasy_props/Coin_Pile", Vector3(18.5, TABLE_TOP, 3.0), -40.0, 28.0)
	if not map_space:
		_parchment(Vector3(-17.5, TABLE_TOP, 4.0))
	_jug(Vector3(25.0, TABLE_TOP, -13.0))
	_kit("fantasy_props/Pouch_Large", Vector3(21.5, TABLE_TOP, -4.0), -60.0, 34.0)
	_kit("fantasy_props/Book_Stack_1", Vector3(-25.0, TABLE_TOP, -19.0), 25.0, 34.0)
	_kit("fantasy_props/Chalice", Vector3(29.0, TABLE_TOP, -5.0), 0.0, 34.0)


## A thick leather-bound book with brass corners and a clasp.
func _tome(base: Vector3) -> void:
	var leather := Mats.dice({"a": Color("#6a1e18"), "b": Color("#3a0e0a"), "swirl": 0.5, "scale": 0.5, "contrast": 0.5, "rough": 0.7, "depth": 0.0}, 4.0)
	var pages := Mats.parchment({"lines": 0.0})
	var brass := Mats.metal(Color("#c9a04a"), 0.3)
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees.y = 25
	add_child(root)
	_box(Vector3(8, 0.5, 11), Vector3(0, 0.25, 0), leather, root)
	_box(Vector3(7.6, 2.2, 10.4), Vector3(0.15, 1.6, 0), pages, root)
	_box(Vector3(8, 0.5, 11), Vector3(0, 2.95, 0), leather, root)
	_box(Vector3(0.8, 3.4, 11.2), Vector3(-3.9, 1.6, 0), leather, root)   # spine
	for z in [-5.2, 5.2]:
		_box(Vector3(1.6, 3.5, 0.9), Vector3(3.5, 1.6, z * 0.98), brass, root)
	_box(Vector3(1.2, 3.6, 2.0), Vector3(4.0, 1.6, 0), brass, root)          # clasp


func _candle(base: Vector3, height: float, shadows: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.x * 13.0 + height)
	var dish := Props.candle_dish(2.6)
	dish.position = base
	add_child(dish)
	var c := Props.candle(1.25, height, rng)
	var node: Node3D = c.node
	node.position = base + Vector3(0, 2.6 * 0.62, 0)
	node.rotation.y = rng.randf() * TAU
	add_child(node)
	var fy: float = node.position.y + c.flame_y
	add_child(Props.flame(Vector3(base.x, fy, base.z), 3.0, {"base_amount": 1.0, "speed": 0.7, "wild": 0.45, "seed": base.x, "glow": 2.6}))
	var light := OmniLight3D.new()
	light.position = Vector3(base.x, fy + 1.4, base.z)
	light.light_color = Color("#ffae5c")
	light.light_energy = 2.2
	light.omni_range = 45.0
	light.omni_attenuation = 1.4
	# Candle shadows off by default: the low flame behind the tray would throw the tray
	# wall's shadow across the velvet. The overhead lantern provides the dice shadows.
	light.shadow_enabled = shadows
	add_child(light)
	_flicker(light, 9.0)


func _tankard(base: Vector3) -> void:
	var t := Props.tankard(_rng(base))
	t.position = base
	t.rotation_degrees.y = 200
	add_child(t)


func _coins(center: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var stack_h := 0.0
	for i in 7:  # a short stack
		var c := _cyl(1.25, 1.25, 0.28, center + Vector3(rng.randf_range(-0.08, 0.08), 0.15 + stack_h, rng.randf_range(-0.08, 0.08)), Mats.coin(1.25, 0.14, rng.randf() * 6.0))
		stack_h += 0.3
	for i in 9:  # a few loose ones
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, 4.5)
		var c := _cyl(1.25, 1.25, 0.28, center + Vector3(cos(a) * r, 0.15, sin(a) * r), Mats.coin(1.25, 0.14, rng.randf() * 6.0))
		c.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))


func _parchment(center: Vector3) -> void:
	var sheet := MeshInstance3D.new()
	sheet.mesh = Props.curled_sheet(9.0, 12.0, _rng(center))
	sheet.material_override = Mats.parchment()
	sheet.position = center
	sheet.rotation_degrees = Vector3(0, 18, 0)
	add_child(sheet)
	# a quill resting on it
	var quill := MeshInstance3D.new()
	quill.mesh = Props.tube(PackedVector3Array([Vector3(-4, 0.2, 0), Vector3(-1, 0.5, 0.2), Vector3(2, 1.2, 0.5), Vector3(5, 2.2, 0.6)]),
		PackedFloat32Array([0.05, 0.08, 0.08, 0.06]), 6)
	quill.material_override = Mats.plain(Color("#e8e0d0"), 0.6)
	quill.position = center + Vector3(0.5, 0.1, 1.0)
	quill.rotation_degrees.y = -30
	add_child(quill)
	var vane := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.45
	vm.height = 0.15
	vane.mesh = vm
	vane.scale = Vector3(3.2, 1.0, 1.0)
	vane.material_override = Mats.plain(Color("#b8a890"), 0.8)
	vane.position = center + Vector3(0.5, 0.1, 1.0) + Basis.from_euler(Vector3(0, deg_to_rad(-30), 0)) * Vector3(2.8, 1.5, 0.5)
	vane.rotation_degrees = Vector3(0, -30, 18)
	add_child(vane)


func _jug(center: Vector3) -> void:
	var j := Props.jug(_rng(center))
	j.position = center
	j.rotation_degrees.y = 150
	add_child(j)


func _build_room() -> void:
	var stone := Mats.stone({"axis": 0})
	var stone_side := Mats.stone({"axis": 1})
	var boards := Mats.wood({"col_light": Color("#5a3a22"), "col_dark": Color("#24140a"),
		"plank_width": 14.0, "plank_length": 400.0, "axis": 1, "gap": 0.2, "seed": 11.0})
	var floor_boards := Mats.wood({"col_light": Color("#4a3020"), "col_dark": Color("#1e1008"),
		"plank_width": 16.0, "plank_length": 160.0, "axis": 0, "gap": 0.2, "seed": 13.0})
	var beam := Mats.wood({"col_light": Color("#3a2414"), "col_dark": Color("#140a04"),
		"plank_width": 400.0, "axis": 2, "seed": 17.0})

	var w := 460.0
	var h := 300.0
	# floor
	_box(Vector3(w, 2, 400), Vector3(0, FLOOR_Y - 1, BACK_WALL_Z + 200), floor_boards)
	# back wall: stone below, timber above
	_box(Vector3(w, 110, 4), Vector3(0, FLOOR_Y + 55, BACK_WALL_Z - 2), stone)
	_box(Vector3(w, h - 110, 4), Vector3(0, FLOOR_Y + 110 + (h - 110) / 2, BACK_WALL_Z - 2), boards)
	_box(Vector3(w, 10, 8), Vector3(0, FLOOR_Y + 112, BACK_WALL_Z + 2), beam)  # rail between
	for x in [-150, -40, 100, 200]:
		_box(Vector3(14, h, 10), Vector3(x, FLOOR_Y + h / 2, BACK_WALL_Z + 3), beam)
	# side walls
	for sx in [-1, 1]:
		_box(Vector3(4, h, 400), Vector3(sx * w / 2, FLOOR_Y + h / 2, BACK_WALL_Z + 200), stone_side)
	# ceiling beams
	for z in [-120, -60, 0]:
		_box(Vector3(w, 12, 12), Vector3(0, FLOOR_Y + 230, z), beam)

	if Kits.enabled:
		_kit_room()
		return
	_shelf(Vector3(-62, FLOOR_Y + 52, BACK_WALL_Z), not map_space)   # the lower shelf holds your dice
	_shelf(Vector3(-62, FLOOR_Y + 80, BACK_WALL_Z))
	if map_space:
		_dicewright_bench(BENCH_TOP)
	_window(Vector3(-118, FLOOR_Y + 62, BACK_WALL_Z))
	_barrel(Vector3(150, FLOOR_Y, BACK_WALL_Z + 30), true)
	_barrel(Vector3(178, FLOOR_Y, BACK_WALL_Z + 40))
	_barrel(Vector3(164, FLOOR_Y + 46, BACK_WALL_Z + 34))
	_wall_lantern(Vector3(-146, FLOOR_Y + 72, BACK_WALL_Z + 8))
	_wall_lantern(Vector3(110, FLOOR_Y + 72, BACK_WALL_Z + 8))
	# a distant table and stools, to suggest a busy room
	var dark := Mats.wood({"col_light": Color("#4a2e1a"), "col_dark": Color("#1c0e06"), "axis": 0, "plank_width": 12.0, "seed": 21.0})
	_box(Vector3(80, 5, 45), Vector3(110, FLOOR_Y + 55, BACK_WALL_Z + 80), dark)
	for x in [80, 140]:
		_box(Vector3(5, 52, 5), Vector3(x, FLOOR_Y + 26, BACK_WALL_Z + 80), dark)
		_cyl(10, 10, 3, Vector3(x, FLOOR_Y + 30, BACK_WALL_Z + 112), dark, 16)
		_cyl(2, 2, 28, Vector3(x, FLOOR_Y + 14, BACK_WALL_Z + 112), dark, 8)


## The back wall dressed from the props kit: Hollis's shelves, barrels on a rack, wall
## lanterns, a long table, a cabinet and a few things hung on the beams. The window, the
## lantern lights and the dice shelf's top stay where the code-built room had them.
func _kit_room() -> void:
	var wall := BACK_WALL_Z
	# Hollis's shelves: the lower one holds your dice, so its top is SHELF_TOP.
	var lower := _kit("fantasy_props/Shelf_Simple", Vector3(-62, 0, wall), 0.0, 51.0)
	lower.position.y = SHELF_TOP.y - Kits.aabb(lower).end.y * 51.0
	if not map_space:
		_shelf_bottles(Vector3(-62, SHELF_TOP.y, wall + 9))
	var upper := _kit("fantasy_props/Shelf_Simple", Vector3(-62, 0, wall), 0.0, 51.0)
	upper.position.y = FLOOR_Y + 81.5 - Kits.aabb(upper).end.y * 51.0
	_shelf_bottles(Vector3(-62, FLOOR_Y + 81.5, wall + 9), 1)
	if map_space:
		_dicewright_bench(BENCH_TOP)
		_kit("fantasy_props/Anvil", Vector3(-214, FLOOR_Y, wall + 40), 80.0, 40.0)
	_window(Vector3(-118, FLOOR_Y + 62, wall))
	# Barrels on a rack, with more stacked about
	_kit("fantasy_props/Barrel_Holder", Vector3(160, FLOOR_Y, wall + 26), 0.0, 52.0)
	_kit("fantasy_props/Barrel", Vector3(196, FLOOR_Y, wall + 44), 40.0, 50.0)
	_kit("fantasy_props/Barrel_Apples", Vector3(130, FLOOR_Y, wall + 52), 10.0, 46.0)
	_kit("fantasy_props/Crate_Wooden", Vector3(205, FLOOR_Y, wall + 92), -15.0, 46.0)
	_kit("fantasy_props/Bag", Vector3(178, FLOOR_Y, wall + 90), 30.0, 44.0)
	for x in [-146.0, 110.0]:
		_kit_lantern(Vector3(x, FLOOR_Y + 72, wall))
	# A long table and stools across the room, to suggest a busy inn
	_kit("fantasy_props/Table_Large", Vector3(120, FLOOR_Y, wall + 78), 0.0, 56.0)
	_kit("fantasy_props/Stool", Vector3(92, FLOOR_Y, wall + 112), 20.0, 60.0)
	_kit("fantasy_props/Stool", Vector3(148, FLOOR_Y, wall + 114), -10.0, 60.0)
	_kit("fantasy_props/Chair_1", Vector3(36, FLOOR_Y, wall + 80), 90.0, 58.0)
	_kit("fantasy_props/Mug", Vector3(104, FLOOR_Y + 45.4, wall + 76), 30.0, 56.0)
	_kit("fantasy_props/Table_Plate", Vector3(138, FLOOR_Y + 45.4, wall + 82), 0.0, 56.0)
	# On the hearth and the mantel
	_kit("fantasy_props/Pot_1", Vector3(-20, FLOOR_Y + 34, wall + 22), 30.0, 44.0)
	_kit("fantasy_props/Bucket_Wooden_1", Vector3(78, FLOOR_Y + 34, wall + 20), 0.0, 48.0)
	_kit("fantasy_props/CandleStick_Triple", Vector3(-10, FLOOR_Y + 112, wall + 14), 0.0, 40.0)
	_kit("fantasy_props/Vase_2", Vector3(62, FLOOR_Y + 112, wall + 14), 0.0, 22.0)
	# Hung on the wall and beams
	_kit("fantasy_props/Shield_Wooden", Vector3(-40, FLOOR_Y + 150, wall + 8), 0.0, 50.0)
	if not map_space:
		_kit("fantasy_props/Cabinet", Vector3(-205, FLOOR_Y, wall), 0.0, 56.0)


func _kit_lantern(pos: Vector3) -> void:
	var lan := _kit("fantasy_props/Lantern_Wall", Vector3(pos.x, pos.y - 10, BACK_WALL_Z), 0.0, 24.0)
	var box := Kits.aabb(lan)
	var l := OmniLight3D.new()
	# The cage hangs from the end of the arm, in the lower part of the model.
	l.position = Vector3(pos.x, pos.y - 10 + (box.position.y + box.size.y * 0.2) * 24.0, BACK_WALL_Z + (box.end.z - box.size.z * 0.12) * 24.0)
	l.light_color = Color("#ffa04a")
	l.light_energy = 3.0
	l.omni_range = 120
	add_child(l)
	_flicker(l, 4.0)
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 4.4
	glow.mesh = sm
	glow.material_override = Mats.glow(Color("#ffb060"), 2.5)
	glow.position = l.position
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


func _shelf_bottles(pos: Vector3, variant := 0) -> void:
	var names := ["Bottle_1", "Potion_2", "Vase_4", "Potion_1", "Bottle_1", "Potion_4", "SmallBottles_1"]
	if variant == 1:
		names = ["Potion_4", "Bottle_1", "Potion_2", "Potion_1", "Potion_2", "Bottle_1", "Potion_4"]
	var x := -25.0
	for n in names:
		var k := 30.0 if n == "Vase_4" else 56.0
		_kit("fantasy_props/" + n, pos + Vector3(x, 0, 0), x * 7.0 + variant * 40.0, k)
		x += 8.3


## Leaded window with bullseye panes looking out on a moonlit night, and the cool
## light it lets in.
func _window(c: Vector3) -> void:
	var frame := Mats.wood({"col_light": Color("#5a3a20"), "col_dark": Color("#24140a"), "axis": 1, "plank_width": 100.0, "seed": 61.0})
	var w := 30.0
	var h := 40.0
	var pane := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	pane.mesh = q
	pane.material_override = Mats.night_window()
	pane.position = c + Vector3(0, h / 2, 1.0)
	add_child(pane)
	_box(Vector3(w + 6, 3, 8), c + Vector3(0, -1.5, 3), frame)          # sill
	_box(Vector3(w + 6, 3, 6), c + Vector3(0, h + 1.5, 2.5), frame)     # lintel
	for sx in [-1, 1]:
		_box(Vector3(3, h, 6), c + Vector3(sx * (w / 2 + 1.5), h / 2, 2.5), frame)
	_box(Vector3(1.4, h, 3), c + Vector3(0, h / 2, 2), frame)            # mullion
	_box(Vector3(w, 1.4, 3), c + Vector3(0, h * 0.55, 2), frame)        # transom
	# a few things on the sill
	var rng := _rng(c)
	var b := Props.bottle(rng, Color("#34507a"))
	b.position = c + Vector3(-9, 0, 4)
	add_child(b)
	var cnd := Props.candle(1.4, 3.0, rng)
	cnd.node.position = c + Vector3(8, 0, 4)
	add_child(cnd.node)          # burnt out, unlit
	# cool moonlight spilling in around the window: blue against the warm room
	var moon := OmniLight3D.new()
	moon.position = c + Vector3(0, h * 0.5, 14)
	moon.light_color = Color("#7f9cff")
	moon.light_energy = 2.5
	moon.omni_range = 45.0
	moon.omni_attenuation = 1.5
	add_child(moon)


func _shelf(pos: Vector3, bottles := true) -> void:
	var plank := Mats.wood({"col_light": Color("#6a4426"), "col_dark": Color("#2e180a"), "axis": 2, "plank_width": 100.0, "seed": 31.0})
	_box(Vector3(60, 3, 16), pos + Vector3(0, 0, 9), plank)
	for x in [-24, 24]:  # brackets
		_box(Vector3(2, 8, 12), pos + Vector3(x, -5, 7), plank)
	if not bottles:
		return
	var rng := _rng(pos)
	var glass_colors := [Color("#3f7d3a"), Color("#7a3a1c"), Color("#34507a"), Color("#8a7a30"), Color("#5a2850")]
	var x := -26.0
	while x < 24.0:
		var b := Props.bottle(rng, glass_colors[rng.randi() % glass_colors.size()])
		b.position = pos + Vector3(x, 1.5, 8 + rng.randf_range(-2, 2))
		b.rotation.y = rng.randf() * TAU
		add_child(b)
		x += rng.randf_range(7.0, 11.0)


## Old Brannoc's workbench: a heavy top on trestles, a vice, chisels and a mallet, a lamp to
## carve by and a scatter of shavings. The die being worked sits in the middle.
func _dicewright_bench(top: Vector3) -> void:
	var oak := Mats.wood({"col_light": Color("#7a5232"), "col_dark": Color("#3a2210"), "axis": 0, "plank_width": 14.0, "seed": 71.0})
	var dark := Mats.wood({"col_light": Color("#4a2e1a"), "col_dark": Color("#1c0e06"), "axis": 1, "plank_width": 100.0, "seed": 73.0})
	var iron := Mats.metal(Color("#3a3632"), 0.45)
	_box(Vector3(56, 4, 26), top + Vector3(0, -2, 0), oak)
	for x in [-24, 24]:
		_box(Vector3(4, 54, 20), Vector3(top.x + x, FLOOR_Y + 27, top.z), dark)
	_box(Vector3(50, 3, 3), Vector3(top.x, FLOOR_Y + 12, top.z), dark)                  # stretcher
	# the vice at the right end
	_box(Vector3(6, 5, 6), top + Vector3(20, 2.5, 6), iron)
	_box(Vector3(6, 5, 1.5), top + Vector3(20, 2.5, 10), iron)
	_cyl(0.5, 0.5, 9, top + Vector3(20, 2.5, 12), iron, 8).rotation_degrees.x = 90
	# chisels and a mallet laid out
	for i in 4:
		var c := _box(Vector3(0.7, 0.5, 9), top + Vector3(-18 + i * 2.2, 0.25, 4), iron)
		c.rotation_degrees.y = -8 + i * 4
		var h := _box(Vector3(1.0, 1.0, 4), top + Vector3(-18 + i * 2.2, 0.5, 9.5), dark)
		h.rotation_degrees.y = -8 + i * 4
	var mallet := _cyl(2.2, 2.2, 6, top + Vector3(-6, 2.2, -6), dark, 16)
	mallet.rotation_degrees.z = 90
	_box(Vector3(1, 1, 10), top + Vector3(-6, 1.2, -0.5), oak)
	# shavings and dust
	var rng := _rng(top)
	var shav := Mats.plain(Color("#c8a070"), 0.9)
	for i in 14:
		var b := _box(Vector3(rng.randf_range(0.6, 1.4), 0.12, rng.randf_range(0.3, 0.6)), top + Vector3(rng.randf_range(-10, 10), 0.06, rng.randf_range(-6, 8)), shav)
		b.rotation_degrees.y = rng.randf() * 180
	# a stub of candle to carve by
	_candle(top + Vector3(14, 0, -7), 3.0, false)
	# a rack of finished dice blanks on the wall above
	_box(Vector3(30, 2, 6), top + Vector3(0, 28, -14), oak)


func _barrel(base: Vector3, tap := false) -> void:
	var b := Props.barrel(_rng(base), tap)
	b.position = base
	b.rotation.y = base.x
	add_child(b)


func _wall_lantern(pos: Vector3) -> void:
	var iron := Mats.metal(Color("#26221e"), 0.5)
	_box(Vector3(1.6, 1.6, 14), pos + Vector3(0, 14, -3), iron)   # bracket arm
	_box(Vector3(1.6, 10, 1.6), pos + Vector3(0, 10, -9), iron)
	var chain := Props.tube(PackedVector3Array([pos + Vector3(0, 14, 3), pos + Vector3(0, 11, 3.1)]), PackedFloat32Array([0.3, 0.3]), 6)
	add_child(Props._mesh(chain, iron))
	var lan := Props.lantern(_rng(pos))
	lan.position = pos + Vector3(0, 0, 3)
	add_child(lan)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 0, 10)
	l.light_color = Color("#ffa04a")
	l.light_energy = 3.0
	l.omni_range = 120
	add_child(l)
	_flicker(l, 4.0)


func _build_fireplace(base: Vector3) -> void:
	var stone := Mats.stone({"axis": 0, "col_a": Color("#55504a"), "col_b": Color("#36322e"), "block": Vector2(18, 10), "soot": 0.6, "soot_height": 120.0})
	var soot := Mats.plain(Color("#0c0907"), 1.0)
	var mantle := Mats.wood({"col_light": Color("#5a3416"), "col_dark": Color("#1e0e04"), "axis": 2, "plank_width": 200.0, "seed": 41.0})
	var z := 14.0  # depth of the fire inside the hearth, relative to the wall
	_box(Vector3(122, base.y - FLOOR_Y, 30), Vector3(base.x, (base.y + FLOOR_Y) / 2, base.z + 14), stone)  # raised hearth
	_box(Vector3(22, 72, 24), base + Vector3(-50, 36, 12), stone)
	_box(Vector3(22, 72, 24), base + Vector3(50, 36, 12), stone)
	_box(Vector3(122, 26, 24), base + Vector3(0, 85, 12), stone)
	_box(Vector3(130, 6, 30), base + Vector3(0, 75, 14), mantle)
	_box(Vector3(80, 70, 4), base + Vector3(0, 36, 2), soot)                       # back of the hearth
	_box(Vector3(120, 4, 30), base + Vector3(0, 2, 14), stone)                      # hearth stone
	# chimney breast up to the ceiling
	_box(Vector3(110, 200, 20), base + Vector3(0, 198, 6), stone)
	_build_fire(base + Vector3(0, 4, z))

	var embers := CPUParticles3D.new()
	particles.append(embers)
	embers.amount = 24
	embers.lifetime = 2.5
	var eq := QuadMesh.new()
	eq.size = Vector2(0.8, 0.8)
	embers.mesh = eq
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.0
	embers.material_override = Mats.flame_particle()
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(20, 2, 4)
	embers.direction = Vector3.UP
	embers.spread = 25
	embers.gravity = Vector3(0, 8, 0)
	embers.initial_velocity_min = 10
	embers.initial_velocity_max = 25
	embers.color = Color(1.0, 0.55, 0.15)
	embers.position = base + Vector3(0, 10, z)
	embers.preprocess = 2.0
	add_child(embers)

	var light := OmniLight3D.new()
	light.position = base + Vector3(0, 25, z + 25)
	light.light_color = Color("#ff8a3a")
	light.light_energy = 14.0
	light.omni_range = 300
	light.omni_attenuation = 1.2
	light.light_cull_mask = 0xFFFFF & ~2
	add_child(light)
	_flicker(light, 7.0)

	# candles on the mantelpiece
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for x in [-45, 40]:
		var b := base + Vector3(x, 78, 16)
		var c := Props.candle(2.0, 12.0 + rng.randf() * 4.0, rng, Color("#e8dcc0"))
		c.node.position = b
		add_child(c.node)
		add_child(Props.flame(b + Vector3(0, c.flame_y, 0), 5.5, {"base_amount": 1.0, "speed": 0.7, "wild": 0.45, "seed": x, "glow": 2.6}))


## Logs on a bed of embers, with cartoon flames licking up between them.
func _build_fire(floor_c: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var bed := MeshInstance3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 2.0
	bed.mesh = Props.lathe(PackedVector2Array([Vector2(0.001, 3.2), Vector2(8, 2.6), Vector2(14, 1.2), Vector2(17, 0.0)]), 40,
		func(a: float, _y: float) -> float: return 1.0 + noise.get_noise_2d(cos(a), sin(a)) * 0.25)
	bed.scale = Vector3(1.9, 1.0, 0.75)
	bed.position = floor_c
	bed.material_override = Mats.embers()
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed)

	var wood := func(seed_v: float) -> ShaderMaterial:
		return Mats.firewood({"char_top": floor_c.y + 6.0, "char_soft": 3.0, "seed": seed_v})
	# [length, radius, position offset, rotation degrees]
	var logs := [
		[44.0, 4.6, Vector3(-3, 4.2, 3), Vector3(0, 12, 4)],
		[42.0, 4.2, Vector3(4, 4.0, -5), Vector3(0, -9, -3)],
		[40.0, 4.0, Vector3(0, 11.5, 0), Vector3(0, 62, 6)],
		[30.0, 2.2, Vector3(-12, 9, -2), Vector3(10, 25, 38)],
		[28.0, 2.0, Vector3(13, 9, 1), Vector3(-8, -30, -40)],
	]
	for i in logs.size():
		var L: Array = logs[i]
		var mi := MeshInstance3D.new()
		mi.mesh = Props.log_mesh(L[0], L[1], rng)
		mi.material_override = wood.call(float(i) * 7.3)
		mi.layers = 2  # the fire's own lights skip the logs, or they'd bleach the bark
		mi.position = floor_c + L[2]
		mi.rotation_degrees = L[3]
		add_child(mi)

	# Flames: tall ones in the middle, smaller tongues along the logs.
	var fl := [
		[Vector3(0, 6, -2), 36.0], [Vector3(-9, 5, -3), 28.0], [Vector3(9, 5, -3), 30.0],
		[Vector3(-17, 4, -1), 18.0], [Vector3(18, 4, -1), 17.0], [Vector3(-4, 12, 3), 20.0],
		[Vector3(6, 12, 2), 16.0], [Vector3(2, 8, 6), 13.0], [Vector3(-12, 8, 5), 11.0],
		[Vector3(13, 9, 5), 10.0],
	]
	# Glowing coals spilled around the logs.
	var coal_mat := Mats.firewood({"char_top": floor_c.y + 40.0, "char_soft": 1.0, "seed": 3.0})
	for i in 14:
		var coal := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 7
		sm.rings = 4
		sm.radius = rng.randf_range(1.2, 2.4)
		sm.height = sm.radius * 1.2
		coal.mesh = sm
		coal.material_override = coal_mat
		coal.layers = 2
		var a := rng.randf() * TAU
		coal.position = floor_c + Vector3(cos(a) * rng.randf_range(10, 26), 0.6, sin(a) * rng.randf_range(4, 10) + 3)
		coal.rotation = Vector3(rng.randf(), rng.randf() * TAU, rng.randf())
		coal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(coal)
	# Two broad, round-topped flames behind everything merge the tongues into one fire.
	add_child(Props.flame(floor_c + Vector3(-6, 3, -6), 26.0, {"seed": 50.0, "speed": 0.5, "top": 0.75, "glow": 1.8}, 1.3))
	add_child(Props.flame(floor_c + Vector3(8, 3, -6), 24.0, {"seed": 61.0, "speed": 0.45, "top": 0.75, "glow": 1.8}, 1.3))
	for i in fl.size():
		var f: Array = fl[i]
		add_child(Props.flame(floor_c + f[0], f[1], {"seed": float(i) * 3.7, "speed": 0.55 + rng.randf() * 0.3, "wild": 1.0, "glow": 2.0, "top": 0.95}, 0.8))
	var crackle := AudioStreamPlayer3D.new()
	crackle.stream = Sfx.get_sound("crackle")
	crackle.position = floor_c + Vector3(0, 10, 0)
	crackle.unit_size = 140.0
	crackle.volume_db = -3.0
	crackle.autoplay = true
	add_child(crackle)
	# Low warm light that paints the hearth stones.
	var glow := OmniLight3D.new()
	glow.position = floor_c + Vector3(0, 10, 12)
	glow.light_color = Color("#ff7a2a")
	glow.light_energy = 3.0
	glow.omni_range = 70.0
	glow.light_cull_mask = 0xFFFFF & ~2
	add_child(glow)
	_flicker(glow, 9.0)
