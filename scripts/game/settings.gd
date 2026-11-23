extends RefCounted
## Graphics quality presets, saved to user://settings.cfg.
##
##   low     for tablets and Chromebooks (Lenovo Duet class: ARM, Mali GPU, Compatibility renderer).
##           Lower 3D resolution, no MSAA, no screen-space effects, no particles, no painterly
##           screen pass, cheap shaders (no per-pixel relief), small shadow map, 30 fps cap.
##           Physics stays at 120 Hz on every preset: at 60 Hz the dice measurably favour some
##           faces (tests/physics_check.gd -- --hz=60 fails its chi-square test), and a handful
##           of dice cost little next to rendering.
##   medium  a mid laptop: most of the look, without bounced light, volumetric haze or 8x MSAA.
##   high    the full look.
##
## The first run picks low on mobile or under the Compatibility renderer, high otherwise.

const Mats := preload("res://scripts/materials.gd")

const PATH := "user://settings.cfg"
const PRESETS := ["low", "medium", "high"]
const NAMES := {"low": "Low", "medium": "Medium", "high": "High"}

const QUALITY := {
	"low": {"scale": 0.6, "msaa": Viewport.MSAA_DISABLED, "ssao": false, "ssil": false, "vfog": false,
		"glow": false, "dof": false, "post": false, "particles": false, "shadow_size": 2048,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_HARD, "max_fps": 30, "physics_hz": 120, "lite": true},
	"medium": {"scale": 0.85, "msaa": Viewport.MSAA_2X, "ssao": true, "ssil": false, "vfog": false,
		"glow": true, "dof": true, "post": true, "particles": true, "shadow_size": 4096,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "max_fps": 60, "physics_hz": 120, "lite": false},
	"high": {"scale": 1.0, "msaa": Viewport.MSAA_8X, "ssao": true, "ssil": true, "vfog": true,
		"glow": true, "dof": true, "post": true, "particles": true, "shadow_size": 8192,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_ULTRA, "max_fps": 0, "physics_hz": 120, "lite": false},
}

static var preset := ""
static var show_fps := false

## Accessibility. Text speed is how fast the Teller's lines are written out; reduced motion stills
## the camera's breathing, makes camera moves and banners instant, and drops the tray's shake.
## Text size scales every panel. None of these touch the dice or the odds.
const TEXT_SPEEDS := ["slow", "normal", "fast", "instant"]
const TEXT_SPEED_NAMES := {"slow": "Slow", "normal": "Normal", "fast": "Fast", "instant": "At once"}
const TEXT_CPS := {"slow": 40.0, "normal": 90.0, "fast": 220.0, "instant": 0.0}
const TEXT_SIZES := [1.0, 1.15, 1.3]
static var text_speed := "normal"
static var reduced_motion := false
static var text_size := 1.0
## The language: "" follows the system; otherwise a locale code with a translation in res://locale.
static var locale := ""
## Remapped controls: action name -> Array of serialized events (see controls.gd). Empty = defaults.
static var bindings := {}


static func default_preset() -> String:
	if OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"] \
			or RenderingServer.get_current_rendering_method() != "forward_plus":
		return "low"
	return "high"


static func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		preset = str(cf.get_value("graphics", "preset", ""))
		show_fps = bool(cf.get_value("graphics", "show_fps", false))
		text_speed = str(cf.get_value("access", "text_speed", "normal"))
		reduced_motion = bool(cf.get_value("access", "reduced_motion", false))
		text_size = float(cf.get_value("access", "text_size", 1.0))
		locale = str(cf.get_value("language", "locale", ""))
		var b = cf.get_value("controls", "bindings", {})
		bindings = b if b is Dictionary else {}
	if not text_speed in TEXT_SPEEDS:
		text_speed = "normal"
	if not text_size in TEXT_SIZES:
		text_size = 1.0
	if not preset in PRESETS:
		preset = default_preset()


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "preset", preset)
	cf.set_value("graphics", "show_fps", show_fps)
	cf.set_value("access", "text_speed", text_speed)
	cf.set_value("access", "reduced_motion", reduced_motion)
	cf.set_value("access", "text_size", text_size)
	cf.set_value("language", "locale", locale)
	cf.set_value("controls", "bindings", bindings)
	cf.save(PATH)


static func q() -> Dictionary:
	return QUALITY.get(preset, QUALITY.high)


static func cycle(list: Array, cur):
	return list[(list.find(cur) + 1) % list.size()]


## Seconds to write out n characters of the Teller's lines at the chosen speed.
static func type_seconds(n: int) -> float:
	var cps: float = TEXT_CPS.get(text_speed, 90.0)
	if cps <= 0.0:
		return 0.0
	return clampf(n / cps, 0.05, 6.0)


static func next_preset() -> String:
	return PRESETS[(PRESETS.find(preset) + 1) % PRESETS.size()]


## Engine-wide parts. Call before the scene is built (shader quality is baked in at build time).
static func apply_engine() -> void:
	var qq := q()
	Mats.lite = qq.lite
	Engine.max_fps = qq.max_fps
	Engine.physics_ticks_per_second = qq.physics_hz
	# At a 30 fps cap that is 4 physics steps per frame; allow enough to keep up.
	Engine.max_physics_steps_per_frame = 8
	RenderingServer.directional_shadow_atlas_set_size(qq.shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(qq.shadow_filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(qq.shadow_filter)


## Per-scene parts: the viewport, the inn's environment and effects, the camera's depth of field.
static func apply_scene(vp: Viewport, tavern, camera: Camera3D) -> void:
	var qq := q()
	vp.msaa_3d = qq.msaa
	vp.scaling_3d_scale = qq.scale
	var fwd := RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (fwd and qq.scale < 1.0) else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = 0.8   # softer than the 0.2 default: upscaled noise otherwise looks crunchy
	vp.positional_shadow_atlas_size = qq.shadow_size
	if tavern != null and tavern.has_method("apply_quality"):
		tavern.apply_quality(qq)
	if camera != null and camera.attributes is CameraAttributesPractical:
		camera.attributes.dof_blur_far_enabled = qq.dof
