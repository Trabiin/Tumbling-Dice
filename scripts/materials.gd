extends RefCounted
## Procedural materials. Every surface in the scene is a shader driven by numbers: no image
## textures, so detail holds up at any resolution and any camera distance.
##
## Each shader computes a colour AND a height field. The height is turned into per-pixel
## surface relief (bump mapping) from screen-space derivatives, so wood pores, stone chips,
## velvet fibres and coin embossing catch the light without any normal-map images.

const NOISE_LIB := """
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
	               mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
	               mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < FBM_OCTAVES; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}
float fbm3(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < FBM3_OCTAVES; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec3(4.1, 1.3, 7.7);
		a *= 0.5;
	}
	return s;
}
// Distance to the nearest of a set of jittered points (cellular / Worley noise).
vec2 cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 c = o + vec3(hash3(i + o), hash3(i + o + 17.0), hash3(i + o + 41.0)) - f;
		float d = dot(c, c);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return vec2(sqrt(d1), sqrt(d2));
}
// Per-pixel relief from a height value (Mikkelsen surface-gradient bump mapping).
vec3 bump(vec3 n, vec3 pos, float h, float strength) {
#ifdef LITE
	return n;  // Low quality: no per-pixel relief
#endif
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(h) * strength;
	float dhdy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - g);
}
"""


# ---------------------------------------------------------------- toon light
# Shared painterly lighting, spliced into every lit shader below. Light falls off in a few
# soft bands instead of a smooth gradient, and the band edges wobble with world-space noise
# so they read like brush strokes rather than computer-perfect lines.
const TOON_LIGHT := """
float toon_band(float k) {
	return smoothstep(0.02, 0.09, k) * 0.5 + smoothstep(0.32, 0.40, k) * 0.32 + smoothstep(0.72, 0.80, k) * 0.18;
}
float toon_steps(float a) {
	// Distance falloff in painted rings: four soft-edged steps.
	float s = a * 4.0;
	// plus a little of the smooth falloff, so faint distant light is not lost entirely
	return (floor(s) + smoothstep(0.35, 0.65, fract(s))) * 0.25 * 0.8 + a * 0.2;
}
void light() {
	vec3 wp = toon_wp;
#ifdef LITE
	float brush = vnoise(wp * 0.4) - 0.5;
#else
	float brush = (vnoise(wp * 0.4) * 0.7 + vnoise(wp * 1.4) * 0.3) - 0.5;
#endif
	float ndl = dot(NORMAL, LIGHT);
	float d;
	if (LIGHT_IS_DIRECTIONAL) {
		d = toon_band(clamp(ndl, 0.0, 1.0) * ATTENUATION + brush * 0.14);
	} else {
		d = toon_band(clamp(ndl, 0.0, 1.0) + brush * 0.14) * toon_steps(clamp(ATTENUATION + brush * 0.05 * smoothstep(0.0, 0.08, ATTENUATION), 0.0, 1.0));
	}
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += d * lc * 1.15;
	// Light through thin wax and resin.
	DIFFUSE_LIGHT += BACKLIGHT * clamp(-ndl, 0.0, 1.0) * ATTENUATION * lc;
	// Rim: a bright painted edge on the lit side.
	float rim = smoothstep(0.66, 0.72, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	DIFFUSE_LIGHT += rim * d * lc * 0.45;
	// One crisp highlight shape instead of a soft glossy blob.
	vec3 h = normalize(LIGHT + VIEW);
	float gloss = 1.0 - ROUGHNESS;
	float sp = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(6.0, 260.0, gloss * gloss));
	float spot = smoothstep(0.45, 0.52, sp + brush * 0.08) * gloss * gloss * smoothstep(0.45, 0.6, gloss);  // matte things get no highlight
	vec3 tint = mix(vec3(1.0), ALBEDO, METALLIC);
	float shade = LIGHT_IS_DIRECTIONAL ? ATTENUATION : toon_steps(ATTENUATION);
	SPECULAR_LIGHT += spot * shade * LIGHT_COLOR * tint * (0.35 + SPECULAR_AMOUNT) * 1.4;
}
"""

# ---------------------------------------------------------------- wood
# Planks with growth rings that arch along the board, open pores, occasional knots,
# dark seams between boards and a varnish sheen.
# axis: 0 = grain along world Z, 1 = along Y (vertical boards), 2 = along X.
const WOOD := """
shader_type spatial;
uniform vec3 col_light : source_color = vec3(0.56, 0.36, 0.20);
uniform vec3 col_dark : source_color = vec3(0.24, 0.13, 0.06);
uniform float plank_width = 4.0;
uniform float plank_length = 40.0;
uniform float grain_scale = 1.0;
uniform int axis = 0;
uniform float gap = 0.025;
uniform float rough = 0.7;
uniform float seed = 0.0;
uniform float ring_density = 1.6;
uniform float knots = 0.5;
uniform float relief = 1.0;
uniform int uv_mode = 0;          // 1: staves on lathed shapes (UV.x around, UV.y up)
uniform vec2 uv_scale = vec2(1.0);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 p = wpos * grain_scale;
	vec3 q = axis == 0 ? p.xzy : (axis == 1 ? p.xyz : p.zxy);
	if (uv_mode == 1) q = vec3(UV.x * uv_scale.x, UV.y * uv_scale.y, 0.5) * grain_scale;
	float plank = floor(q.x / plank_width);
	float h = hash3(vec3(plank, seed, 7.7));
	float along = q.y + h * 97.0;
	float joint = floor(along / plank_length);
	float h2 = hash3(vec3(plank, joint, seed + 3.0));
	float h3 = hash3(vec3(plank, joint, seed + 9.0));

	// Growth rings: distance from a log centre that drifts along the board -> arches.
	float local_x = q.x - plank * plank_width;
	vec2 c = vec2(plank_width * (0.2 + 0.6 * h2), -plank_width * (1.5 + 2.0 * h3));
	float warp = fbm(vec3(local_x * 0.25, along * 0.02, h2 * 30.0)) * 2.5;
	float r = length(vec2(local_x - c.x, q.z - c.y + along * 0.035 * (h3 - 0.5))) + warp;
	// knots: rings swirl around a few points
	vec2 kp = vec2(plank_width * hash3(vec3(plank, joint, 2.0)), plank_length * hash3(vec3(plank, joint, 5.0)));
	float fy = mod(along, plank_length);
	float kd = length(vec2(local_x - kp.x, (fy - kp.y) * 0.35));
	float has_knot = step(1.0 - knots * 0.5, hash3(vec3(plank, joint, 11.0)));
	r += has_knot * 3.0 / (kd + 0.6);
	float ring = fract(r * ring_density);
	float late = smoothstep(0.55, 0.95, ring) * (1.0 - smoothstep(0.95, 1.0, ring));

	float streak = vnoise(vec3(local_x * 18.0, along * 0.25, h2 * 9.0));
	float pores = smoothstep(0.62, 0.8, vnoise(vec3(local_x * 70.0, along * 1.2, h3 * 50.0)));
	float big = fbm3(vec3(wpos.xz * 0.03, seed));

	vec3 col = mix(col_light, col_dark, late * 0.75 + streak * 0.25);
	col *= 0.82 + 0.36 * h2;
	col *= 0.9 + 0.2 * big;
	col = mix(col, col_dark * 0.6, has_knot * smoothstep(1.2, 0.0, kd));
	col *= 1.0 - pores * 0.35;

	float fx = local_x / plank_width;
	float fyn = fy / plank_length;
	float e = min(min(fx, 1.0 - fx) * plank_width, min(fyn, 1.0 - fyn) * plank_length);
	float groove = smoothstep(gap * 0.3, gap * 3.0, e);
	col *= mix(0.2, 1.0, groove);

	float height = (groove - 1.0) * 0.08 - pores * 0.012 + late * 0.006 + streak * 0.004;
	NORMAL = bump(NORMAL, VERTEX, height, relief);
	ALBEDO = col;
	ROUGHNESS = clamp(rough + pores * 0.25 + (1.0 - groove) * 0.3 - late * 0.08, 0.05, 1.0);
	SPECULAR = 0.45;
}
"""

# ---------------------------------------------------------------- stone
# Rough-hewn blocks: chiselled bevels, chips and pits, recessed sandy mortar, soot.
const STONE := """
shader_type spatial;
uniform vec3 col_a : source_color = vec3(0.42, 0.40, 0.37);
uniform vec3 col_b : source_color = vec3(0.28, 0.26, 0.24);
uniform vec3 mortar : source_color = vec3(0.16, 0.14, 0.12);
uniform vec2 block = vec2(28.0, 14.0);
uniform int axis = 0;  // 0: wall facing Z (uses x,y), 1: wall facing X (uses z,y), 2: floor (x,z)
uniform float soot = 0.0;
uniform float soot_height = 60.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = axis == 0 ? wpos.xy : (axis == 1 ? wpos.zy : wpos.xz);
	float row = floor(uv.y / block.y);
	float off = hash3(vec3(row, 1.0, 2.0)) * block.x;
	float wscale = 0.7 + 0.6 * hash3(vec3(row, 5.0, 1.0));
	float bx = (uv.x + off) / (block.x * wscale);
	float col = floor(bx);
	vec2 f = vec2(fract(bx), fract(uv.y / block.y));
	float h = hash3(vec3(col, row, 3.0));
	vec3 sp = vec3(uv * 0.2, h * 20.0);
	float grit = fbm(sp);
	float fine = vnoise(vec3(uv * 3.0, h * 7.0));
	vec2 cl = cells(vec3(uv * 0.35, h * 5.0));
	float pits = smoothstep(0.12, 0.0, cl.x) * step(0.7, hash3(vec3(floor(uv * 0.35), h)));
#ifdef LITE
	// Low renders at 0.6 scale without MSAA: the fine grain and hard-edged pits are smaller
	// than a pixel there and alias into blocky purple blotches, so leave them out.
	fine = 0.5;
	pits = 0.0;
#endif

	vec2 d = min(f, 1.0 - f) * vec2(block.x * wscale, block.y);
	float edge = min(d.x, d.y) + (grit - 0.5) * 3.0;
	float m = smoothstep(0.4, 1.6, edge);
	float bevel = smoothstep(0.4, 3.5, edge);

	vec3 c = mix(col_b, col_a, clamp(h * 0.5 + grit * 0.7 - 0.1, 0.0, 1.0));
	c *= 0.85 + 0.3 * fine;
	c = mix(c, c * vec3(0.9, 0.95, 0.85), smoothstep(0.6, 0.8, fbm3(sp * 0.5)));  // lichen-ish variation
	c *= mix(0.65, 1.0, bevel);
	c *= 1.0 - pits * 0.4;
	vec3 mo = mortar * (0.8 + 0.4 * vnoise(vec3(uv * 5.0, 3.0)));
	c = mix(mo, c, m);
	c *= 1.0 - soot * smoothstep(0.0, soot_height, wpos.y - (-30.0)) * 0.8 * (0.7 + 0.3 * grit);

	float height = m * (bevel * 1.2 + grit * 1.5 + fine * 0.15) - pits * 0.4;
	NORMAL = bump(NORMAL, VERTEX, height, 1.0);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
}
"""

# ---------------------------------------------------------------- velvet
# Crushed velvet: fibre noise, patches where the nap lies differently, bright rim sheen.
const VELVET := """
shader_type spatial;
uniform vec3 color : source_color = vec3(0.1, 0.25, 0.25);
uniform float nap = 1.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float crush = fbm(vec3(wpos.xz * 0.35, 1.0));
	float fibres = vnoise(vec3(wpos.xz * 40.0, 2.0)) * 0.6 + vnoise(vec3(wpos.xz * 90.0, 5.0)) * 0.4;
	vec3 c = color * (0.75 + 0.5 * crush) * (0.9 + 0.2 * fibres);
	NORMAL = bump(NORMAL, VERTEX, fibres * 0.01 + crush * 0.03, nap);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
	RIM = 0.9;
	RIM_TINT = 0.75;
}
"""

# ---------------------------------------------------------------- parchment
const PARCHMENT := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 paper : source_color = vec3(0.86, 0.76, 0.56);
uniform vec3 ink : source_color = vec3(0.22, 0.12, 0.06);
uniform float lines = 1.0;
void fragment() {
	vec3 p = vec3(UV * vec2(9.0, 12.0), 1.0);
	float n = fbm(p * 0.8);
	float fibre = vnoise(vec3(UV.x * 300.0, UV.y * 40.0, 3.0)) * 0.5 + vnoise(vec3(UV.x * 50.0, UV.y * 260.0, 7.0)) * 0.5;
	float stain = smoothstep(0.55, 0.75, fbm(vec3(UV * 3.0, 9.0)));
	vec2 e = min(UV, 1.0 - UV);
	float burn = smoothstep(0.0, 0.06 + n * 0.06, min(e.x, e.y));
	vec3 c = paper * (0.85 + 0.25 * n) * (0.94 + 0.12 * fibre) * mix(0.3, 1.0, burn);
	c = mix(c, c * vec3(0.78, 0.62, 0.42), stain * 0.6);
	// handwriting: wobbly lines broken into words, with varying pressure
	float row = floor(UV.y * 20.0);
	float ly = fract(UV.y * 20.0) + (vnoise(vec3(UV.x * 30.0, row, 1.0)) - 0.5) * 0.25;
	float word = step(0.42, vnoise(vec3(UV.x * 22.0, row * 3.1, 2.0)));
	float pressure = 0.5 + 0.5 * vnoise(vec3(UV.x * 160.0, row, 4.0));
	float stroke = 1.0 - smoothstep(0.0, 0.07 * pressure, abs(ly - 0.5));
	float scrib = step(0.45, vnoise(vec3(UV.x * 140.0, UV.y * 90.0, row)));
	float txt = stroke * word * mix(0.6, 1.0, scrib) * lines;
	txt *= step(0.12, UV.x) * step(UV.x, 0.88 - 0.2 * hash3(vec3(row, 1.0, 1.0))) * step(0.12, UV.y) * step(UV.y, 0.9);
	// a title line
	float title = (1.0 - smoothstep(0.0, 0.012, abs(UV.y - 0.08))) * step(0.25, UV.x) * step(UV.x, 0.75) * lines;
	c = mix(c, ink, clamp(txt * 0.8 + title * 0.9, 0.0, 1.0));
	NORMAL = bump(NORMAL, VERTEX, n * 0.05 + fibre * 0.004, 1.0);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""

# ---------------------------------------------------------------- dice
# Resin with swirls suspended at different depths (parallax layers), sparkle flakes,
# a clear-coat sheen and faint scratches. With metal > 0 it becomes brushed metal.
const DICE := """
shader_type spatial;
uniform vec3 color_a : source_color = vec3(0.5, 0.0, 0.0);
uniform vec3 color_b : source_color = vec3(0.05, 0.0, 0.0);
uniform float swirl = 1.0;
uniform float scale = 2.0;
uniform float contrast = 1.0;
uniform float metal = 0.0;
uniform float rough = 0.25;
uniform float sparkle = 0.0;
uniform vec3 sparkle_color : source_color = vec3(1.0, 0.85, 0.5);
uniform float seed = 0.0;
uniform float depth = 0.35;
varying vec3 lpos;
varying vec3 lcam;
void vertex() {
	lpos = VERTEX;
	lcam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}
float marble(vec3 p) {
	vec3 s = p * scale + vec3(seed);
	float w = fbm(s * 1.3);
	float n = fbm(s + vec3(w * swirl * 3.0));
	return clamp((n - 0.5) * 3.0 * contrast + 0.5, 0.0, 1.0);
}
void fragment() {
	vec3 v = normalize(lpos - lcam);
	float layered = 0.0;
	float glint = 0.0;
	if (metal < 0.5) {
		// three layers looked at through the surface: swirls appear to float inside
		// surface layer dominates; deeper layers show through where it is clear
		float top = marble(lpos);
		float mid = marble(lpos + v * depth * 0.5);
		float deep = marble(lpos + v * depth);
		layered = top * 0.65 + mid * 0.25 + deep * 0.1;
		layered = smoothstep(0.1, 0.9, layered);
		for (int i = 0; i < 3; i++) {
			vec3 fp = floor((lpos + v * depth * float(i) * 0.5) * 55.0 + vec3(seed + float(i) * 13.0));
			glint += step(1.0 - sparkle * 0.012, hash3(fp)) * (1.0 - float(i) * 0.3);
		}
	} else {
		layered = marble(lpos);
	}
	vec3 c = mix(color_a, color_b, layered);
	// Brushed lines (metal) or fine scratches (resin) as relief.
	float brushed = vnoise(vec3(lpos.x * 6.0, lpos.y * 6.0, lpos.z * 900.0)) * metal * 0.5;
	float scratch = smoothstep(0.985, 1.0, vnoise(vec3(lpos.xy * 25.0, lpos.z * 2.0 + seed))) * (1.0 - metal);
	float tarnish = fbm3(lpos * 3.0 + vec3(seed)) * metal;
	c *= 1.0 - tarnish * 0.35;
	NORMAL = bump(NORMAL, VERTEX, brushed * 0.004 - scratch * 0.002, 1.0);
	if (metal < 0.5) {
		// candy resin: edges glow brighter and more saturated, light shines through
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
		c = mix(c, color_a * 1.35 + vec3(0.06), fres * 0.55);
		BACKLIGHT = color_a * 0.7;
	}
	ALBEDO = c;
	METALLIC = metal;
	ROUGHNESS = clamp(rough + brushed * 0.08 + tarnish * 0.15 + scratch * 0.2, 0.04, 1.0);
	SPECULAR = 0.5;
	CLEARCOAT = 1.0 - metal;
	CLEARCOAT_ROUGHNESS = 0.08;
	EMISSION = sparkle_color * glint * sparkle * 0.9;
}
"""

# ---------------------------------------------------------------- metal
# Brass and iron fittings: tarnish in the crevices, fine hammer marks.
const METAL := """
shader_type spatial;
uniform vec3 color : source_color = vec3(0.8, 0.6, 0.3);
uniform vec3 tarnish_color : source_color = vec3(0.2, 0.15, 0.08);
uniform float rough = 0.35;
uniform float tarnish = 0.5;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = smoothstep(0.45, 0.75, fbm(wpos * 0.6)) * tarnish;
	float hammer = cells(wpos * 2.5).x;
	vec3 c = mix(color, tarnish_color, t);
	NORMAL = bump(NORMAL, VERTEX, hammer * 0.02, 1.0);
	ALBEDO = c;
	METALLIC = 1.0 - t * 0.7;
	ROUGHNESS = clamp(rough + t * 0.4 + hammer * 0.1, 0.05, 1.0);
}
"""

# ---------------------------------------------------------------- coin
# Gold coin, embossed in local space: raised rim, a star in the centre, reeded edge.
const COIN := """
shader_type spatial;
uniform vec3 color : source_color = vec3(0.95, 0.75, 0.3);
uniform float radius = 1.25;
uniform float half_h = 0.14;
uniform float seed = 0.0;
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	float r = length(lpos.xz) / radius;
	float a = atan(lpos.z, lpos.x) + seed;
	float face = step(half_h * 0.9, abs(lpos.y));
	float rim = smoothstep(0.80, 0.86, r) * face;
	float star = smoothstep(0.02, 0.0, r - (0.32 + 0.14 * cos(a * 5.0))) * face;
	float dots = smoothstep(0.03, 0.0, abs(r - 0.68)) * step(0.5, fract(a * 24.0 / 6.2831)) * face;
	float reed = (1.0 - face) * (0.5 + 0.5 * sin(a * 90.0));
	float wear = fbm3(lpos * 6.0 + vec3(seed));
	float height = rim * 0.03 + star * 0.025 + dots * 0.015 + reed * 0.01;
	NORMAL = bump(NORMAL, VERTEX, height, 1.0);
	ALBEDO = color * (0.85 + 0.25 * wear) * (1.0 - (1.0 - rim) * face * 0.08);
	METALLIC = 0.95;
	ROUGHNESS = 0.25 + wear * 0.2 - (rim + star) * 0.1;
}
"""

# ---------------------------------------------------------------- embers
# Glowing coals: cracked cells that pulse.
const EMBERS := """
shader_type spatial;
render_mode unshaded;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = cells(vec3(wpos.xz * 0.9, TIME * 0.15));
	float crack = smoothstep(0.0, 0.25, c.y - c.x);
	float pulse = 0.7 + 0.3 * vnoise(vec3(wpos.xz * 0.2, TIME * 1.5));
	vec3 hot = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.75, 0.3), pulse * (1.0 - crack));
	float glow = smoothstep(0.3, 0.8, vnoise(vec3(wpos.xz * 0.15, TIME * 0.4)));
	vec3 col = mix(hot * (0.6 + 1.6 * glow) * pulse, vec3(0.03, 0.01, 0.0), crack * 0.9);
	ALBEDO = col;
}
"""

# ---------------------------------------------------------------- wax
const WAX := """
shader_type spatial;
uniform vec3 color : source_color = vec3(0.94, 0.89, 0.76);
uniform float top_y = 1e6;    // world height of the candle top: wax glows just below the flame
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float drip = fbm3(vec3(wpos.x * 3.0, wpos.y * 0.6, wpos.z * 3.0));
	float n = vnoise(wpos * 8.0);
	NORMAL = bump(NORMAL, VERTEX, drip * 0.06 + n * 0.005, 1.0);
	// warmer, more golden toward the flame, cooler and darker at the foot
	float hgt = smoothstep(top_y - 8.0, top_y, wpos.y);
	ALBEDO = color * mix(vec3(0.72, 0.68, 0.66), vec3(0.9, 0.82, 0.62), hgt) * (0.92 + 0.08 * n);
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
	BACKLIGHT = vec3(0.9, 0.55, 0.25) * 0.6;  // flame light glows through the wax
	float near = smoothstep(top_y - 3.0, top_y + 0.2, wpos.y);
	EMISSION = vec3(1.0, 0.5, 0.15) * near * near * 0.55;
}
"""

# ---------------------------------------------------------------- foam
const FOAM := """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 b = cells(wpos * 3.0);
	float bubbles = smoothstep(0.0, 0.5, b.y - b.x);
	NORMAL = bump(NORMAL, VERTEX, bubbles * 0.05, 1.0);
	ALBEDO = vec3(0.95, 0.90, 0.78) * (0.85 + 0.15 * bubbles);
	ROUGHNESS = 0.6;
}
"""


# ---------------------------------------------------------------- painterly post
# A full-screen pass drawn before any transparent effects: it smears the image into
# brush-like patches (a Kuwahara filter: each pixel takes the calmest of four neighbouring
# areas, which flattens fine noise but keeps edges sharp), then inks the outlines of shapes
# wherever depth or surface direction jumps.
const POST := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D nr_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec3 ink : source_color = vec3(0.13, 0.07, 0.05);
uniform float line_px = 1.6;
uniform int brush_px = 3;
uniform float line_strength = 0.85;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}
vec3 nrm(vec2 uv) { return normalize(texture(nr_tex, uv).xyz * 2.0 - 1.0); }
void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	// --- brush (Kuwahara)
	vec3 col = texture(screen_tex, uv).rgb;
	if (brush_px > 0) {
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		for (int q = 0; q < 4; q++) {
			vec2 dir = vec2(q % 2 == 0 ? -1.0 : 1.0, q < 2 ? -1.0 : 1.0);
			vec3 m = vec3(0.0);
			vec3 m2 = vec3(0.0);
			float n = 0.0;
			for (int x = 0; x <= brush_px; x++)
			for (int y = 0; y <= brush_px; y++) {
				vec3 c = texture(screen_tex, uv + dir * (vec2(float(x), float(y)) - 0.5) * px * 1.5).rgb;
				m += c; m2 += c * c; n += 1.0;
			}
			m /= n;
			vec3 var3 = m2 / n - m * m;
			float v = var3.r + var3.g + var3.b;
			// soft choice: calm areas win, but blend so patches don't turn into squares
			float w = 1.0 / pow(1.0 + v * 600.0, 4.0);
			acc += m * w; wsum += w;
		}
		col = acc / wsum;
	}
	// --- ink lines, with a slight hand-drawn wobble
	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	vec3 nc = nrm(uv);
	float wob = sin(uv.y * 310.0 + uv.x * 170.0) * 0.35 + 0.65;
	vec2 o = px * line_px * wob;
	float edge = 0.0;
	vec2 offs[4] = vec2[](vec2(o.x, 0.0), vec2(-o.x, 0.0), vec2(0.0, o.y), vec2(0.0, -o.y));
	for (int i = 0; i < 4; i++) {
		float dn = lin_depth(uv + offs[i], INV_PROJECTION_MATRIX);
		float de = smoothstep(0.012, 0.03, (dn - dc) / dc);   // only the nearer side draws the line
		float ne = smoothstep(0.35, 0.6, 1.0 - dot(nc, nrm(uv + offs[i])));
		edge = max(edge, max(de, ne * step(dc, 250.0)));
	}
	edge *= line_strength * (1.0 - smoothstep(120.0, 420.0, dc) * 0.6);
	ALBEDO = mix(col, col * ink * 1.5, edge);
}
"""

# ---------------------------------------------------------------- cartoon flame
# A camera-facing card with a teardrop flame cut out by rising noise: three crisp colour
# bands (core, body, edge) and tongues that lick upward. HDR colours feed the glow.
const FLAME := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 c_core : source_color = vec3(1.0, 0.95, 0.65);
uniform vec3 c_mid : source_color = vec3(1.0, 0.62, 0.12);
uniform vec3 c_edge : source_color = vec3(0.95, 0.25, 0.05);
uniform vec3 c_base : source_color = vec3(0.3, 0.45, 1.0);
uniform float base_amount = 0.0;
uniform float glow = 2.2;
uniform float speed = 1.0;
uniform float wild = 1.0;
uniform float seed = 0.0;
uniform float top = 1.15;   // lower = blunter, rounder flame top
global uniform float gust;
void vertex() {
	// Turn to face the camera around the vertical axis, keeping the card's scale.
	vec3 x = normalize(INV_VIEW_MATRIX[0].xyz * vec3(1.0, 0.0, 1.0)) * length(MODEL_MATRIX[0].xyz);
	vec3 y = MODEL_MATRIX[1].xyz;
	vec3 z = normalize(cross(x, y));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x, 0.0), vec4(y, 0.0), vec4(z, 0.0), MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);
	float t = TIME * speed + seed * 7.0;
	p.x += gust * (sin(TIME * 13.0 + seed + p.y * 5.0) * 0.12 + 0.08) * p.y * p.y;
	p.x += (sin(t * 2.3 + p.y * 3.0) * 0.06 + (vnoise(vec3(p.y * 2.0 - t, t * 0.7, seed)) - 0.5) * 0.12) * p.y * wild;
	float w = 0.85 * pow(max(p.y, 0.0), 0.4) * pow(max(1.0 - p.y, 0.0), top);
	float f = 1.0 - abs(p.x) / max(w, 1e-3);
	float n = fbm3(vec3(p.x * 5.0, p.y * 3.5 - t * 2.6, seed));
	f -= (n - 0.35) * (0.25 + p.y * 1.2) * wild;
	f = min(f, (p.y - 0.02) * 12.0);
	if (f <= 0.0) discard;
	vec3 c = c_edge;
	c = mix(c, c_mid, smoothstep(0.17, 0.2, f));
	c = mix(c, c_core, smoothstep(0.45, 0.48, f));
	c = mix(c, c_base, base_amount * (1.0 - smoothstep(0.12, 0.22, p.y)) * smoothstep(0.1, 0.13, f));
	ALBEDO = c * glow;
	ALPHA = smoothstep(0.0, 0.05, f);
}
"""

# ---------------------------------------------------------------- firewood
# Bark with deep ridges along the log, end grain on the cut faces (vertex colour r = 1),
# and charring that creeps up from below with glowing cracks.
const LOG := """
shader_type spatial;
uniform vec3 bark_a : source_color = vec3(0.28, 0.16, 0.08);
uniform vec3 bark_b : source_color = vec3(0.11, 0.06, 0.03);
uniform vec3 grain : source_color = vec3(0.78, 0.58, 0.36);
uniform float char_top = 0.0;      // world y below which the wood is charred
uniform float char_soft = 6.0;
uniform float seed = 0.0;
varying vec3 wpos;
varying float cap;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; cap = COLOR.r; }
void fragment() {
	vec2 uv = UV;   // u along the log (world units), v around it (0..1)
	float ridge = fbm3(vec3(uv.x * 0.15, uv.y * 14.0, seed));
	float cracks = smoothstep(0.55, 0.6, vnoise(vec3(uv.x * 0.25, uv.y * 30.0, seed + 3.0)));
	vec3 c = mix(bark_b, bark_a, smoothstep(0.35, 0.65, ridge));
	c = mix(c, bark_b * 0.5, cracks);
	float h = ridge - cracks * 0.3;
	// end grain: rings around the centre
	float r = length(UV2) + fbm3(vec3(UV2 * 2.0, seed)) * 0.15;
	float rings = smoothstep(0.4, 0.6, fract(r * 6.0));
	vec3 endc = mix(grain, grain * 0.75, rings);
	endc = mix(endc, bark_b, smoothstep(0.86, 0.92, r));
	c = mix(c, endc, cap);
	h = mix(h, rings * 0.2, cap);
	// char + embers
	float ch = smoothstep(char_top + char_soft, char_top - char_soft, wpos.y + (fbm3(wpos * 0.15 + seed) - 0.5) * char_soft * 2.0);
	vec2 cl = cells(wpos * 0.35 + vec3(seed));
	float crack = 1.0 - smoothstep(0.0, 0.05, cl.y - cl.x);
	crack *= smoothstep(0.45, 0.6, fbm3(wpos * 0.08 + vec3(seed, 2.0, 0.0)));   // only in patches
	crack = max(crack, smoothstep(char_top - char_soft * 0.5, char_top - char_soft * 2.0, wpos.y) * 0.3);  // undersides glow
	vec3 charc = vec3(0.09, 0.065, 0.06) * (0.7 + 0.6 * ridge);
	c = mix(c, charc, ch);
	float pulse = 0.65 + 0.35 * vnoise(vec3(wpos.xz * 0.2, TIME * 1.3 + seed));
	EMISSION = mix(vec3(1.0, 0.3, 0.04), vec3(1.0, 0.65, 0.2), pulse) * crack * ch * pulse * 2.4;
	NORMAL = bump(NORMAL, VERTEX, h * 0.5, 1.0);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
"""


# ---------------------------------------------------------------- night window
# Diamond leaded panes of wobbly glass, a moon with a halo, stars, a dark treeline, snow
# drifting past outside and a rime of frost creeping in from the frame.
const WINDOW := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec2 size = vec2(30.0, 40.0);
uniform float snow = 1.0;    // the season outside: snow in winter, rain in autumn and spring
uniform float rain = 0.0;
uniform float frost = 1.0;
void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y) * size;
	// diamond leading
	vec2 d = vec2(p.x + p.y, p.x - p.y) / 10.0;
	vec2 f = abs(fract(d) - 0.5);
	float lead = smoothstep(0.44, 0.47, max(f.x, f.y));
	// each pane bends the view a little (old crown glass)
	vec2 cellid = floor(d);
	vec2 wob = (vec2(hash3(vec3(cellid, 1.0)), hash3(vec3(cellid, 2.0))) - 0.5) * 0.6 + (fract(d) - 0.5) * 0.8;
	vec2 q = p + wob;
	vec3 sky = mix(vec3(0.07, 0.11, 0.24), vec3(0.02, 0.03, 0.09), smoothstep(0.0, size.y, q.y));
	vec2 mc = vec2(size.x * 0.3, size.y * 0.72);
	float md = length(q - mc);
	sky += vec3(0.35, 0.45, 0.7) * exp(-md * 0.25) * 0.4;                       // halo
	float moon = smoothstep(4.2, 3.8, md);
	float crater = smoothstep(0.55, 0.7, vnoise(vec3((q - mc) * 0.9, 3.0)));
	sky = mix(sky, vec3(1.0, 0.97, 0.85) * (1.0 - crater * 0.2) * 1.05, moon);   // under 1: no bloom smear
	float star = step(0.985, hash3(vec3(floor(q * 1.6), 5.0))) * (1.0 - moon);
	sky += vec3(0.9, 0.9, 1.0) * star * 0.8;
	// distant treeline and hills
	float hill = size.y * 0.18 + vnoise(vec3(q.x * 0.08, 1.0, 1.0)) * 4.0 + smoothstep(0.4, 0.9, vnoise(vec3(q.x * 0.6, 2.0, 1.0))) * 3.0;
	sky = mix(sky, vec3(0.02, 0.03, 0.06), step(q.y, hill));
	// Snow drifting down past the glass: two layers, the near one bigger and faster.
	for (int l = 0; l < 2; l++) {
		float fl = float(l);
		float cell = 5.0 - fl * 1.6;
		vec2 sp = q / cell + vec2(sin(TIME * 0.35 + q.y * 0.15 + fl * 2.0) * 0.35, TIME * (0.35 + fl * 0.3));
		vec2 id = floor(sp);
		vec2 c = fract(sp) - 0.5 - (vec2(hash3(vec3(id, 7.0 + fl)), hash3(vec3(id, 9.0 + fl))) - 0.5) * 0.6;
		float on = step(0.55, hash3(vec3(id, 11.0 + fl)));
		sky += vec3(0.75, 0.8, 0.95) * on * snow * smoothstep(0.2 + fl * 0.05, 0.06, length(c)) * (0.55 + fl * 0.2);
	}
	// Rain: thin slanted streaks, fast, faint.
	vec2 rp = vec2(q.x + q.y * 0.18, q.y) * vec2(1.4, 0.12) + vec2(0.0, TIME * 2.6);
	vec2 rid = floor(rp);
	float rx = abs(fract(rp.x) - 0.5 - (hash3(vec3(rid, 13.0)) - 0.5) * 0.6);
	float streak = step(0.72, hash3(vec3(rid, 15.0))) * smoothstep(0.06, 0.0, rx) * smoothstep(0.0, 0.5, fract(rp.y)) * smoothstep(1.0, 0.6, fract(rp.y));
	sky += vec3(0.45, 0.52, 0.7) * streak * rain * 0.45;
	float pane_edge = smoothstep(0.3, 0.46, max(f.x, f.y));
	sky *= 1.0 - pane_edge * 0.15;
	// Frost: thickest along the bottom and in the corners of the frame, feathered by noise.
	vec2 e = min(UV, 1.0 - UV);
	float edge_d = min(min(e.x, e.y) * 1.4, (1.0 - UV.y) * 0.9 + 0.02);
	float frost_e = smoothstep(0.16, 0.0, edge_d + (vnoise(vec3(p * 0.9, 4.0)) - 0.5) * 0.12);
	sky = mix(sky, vec3(0.55, 0.62, 0.78), frost_e * 0.55 * frost);
	ALBEDO = mix(sky, vec3(0.03, 0.025, 0.02), lead);
}
"""

static var _cache := {}
## Set false to compare against the smooth, realistic lighting.
static var toon := true
## Low quality: fewer noise octaves and no per-pixel relief (for weak mobile GPUs).
## Set before building the scene; the shader cache is keyed by it.
static var lite := false


static func _shader(key: String, body: String) -> Shader:
	key = key + ("#lite" if lite else "")
	if not _cache.has(key):
		var s := Shader.new()
		# Splice the shared noise helpers in right after the shader_type line.
		var anchor := body.find("render_mode")
		if anchor == -1:
			anchor = body.find("shader_type")
		var nl := body.find("\n", anchor)
		var defs := "#define LITE\n#define FBM_OCTAVES 2\n#define FBM3_OCTAVES 2\n" if lite else "#define FBM_OCTAVES 5\n#define FBM3_OCTAVES 3\n"
		var code := body.substr(0, nl + 1) + defs + NOISE_LIB + body.substr(nl + 1)
		# Every lit shader gets the painterly light unless it brings its own.
		if toon and not body.contains("unshaded") and not body.contains("void light()"):
			var wp := "toon_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;"
			if code.contains("void vertex() {"):
				code = code.replace("void vertex() {", "void vertex() { " + wp)
			else:
				code += "void vertex() { " + wp + " }\n"
			code = code.replace(NOISE_LIB, NOISE_LIB + "varying vec3 toon_wp;\n") + TOON_LIGHT
		s.code = code
		_cache[key] = s
	return _cache[key]


static func _mat(key: String, body: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(key, body)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func wood(params := {}) -> ShaderMaterial:
	return _mat("wood", WOOD, params)


static func stone(params := {}) -> ShaderMaterial:
	return _mat("stone", STONE, params)


static func parchment(params := {}) -> ShaderMaterial:
	return _mat("parchment", PARCHMENT, params)


static func velvet(color: Color) -> ShaderMaterial:
	return _mat("velvet", VELVET, {"color": color})


static func metal(color: Color, rough := 0.35, tarnish := 0.5) -> ShaderMaterial:
	return _mat("metal", METAL, {"color": color, "rough": rough, "tarnish": tarnish,
		"tarnish_color": color.darkened(0.75)})


static func coin(radius: float, half_height: float, seed_value: float) -> ShaderMaterial:
	return _mat("coin", COIN, {"radius": radius, "half_h": half_height, "seed": seed_value})


static func wax(color := Color("#efe2c2"), top_y := 1e6) -> ShaderMaterial:
	return _mat("wax", WAX, {"color": color, "top_y": top_y})


static var _windows: Array = []
static var _window_season := "winter"
const WINDOW_SEASONS := {"spring": [0.0, 0.5, 0.0], "summer": [0.0, 0.0, 0.0], "autumn": [0.0, 1.0, 0.25], "winter": [1.0, 0.0, 1.0]}


static func night_window() -> ShaderMaterial:
	var m := _mat("window", WINDOW, {})
	_windows = _windows.filter(func(w): return is_instance_valid(w))
	_windows.append(m)
	_apply_window(m)
	return m


## What the tavern windows show outside: snow and frost in winter, rain in autumn and spring.
static func set_window_season(season: String) -> void:
	_window_season = season
	for m in _windows:
		if is_instance_valid(m):
			_apply_window(m)


static func _apply_window(m: ShaderMaterial) -> void:
	var v: Array = WINDOW_SEASONS.get(_window_season, WINDOW_SEASONS.winter)
	m.set_shader_parameter("snow", v[0])
	m.set_shader_parameter("rain", v[1])
	m.set_shader_parameter("frost", v[2])


## Brush size of the painterly screen pass in pixels (0 turns the smear off, keeps the ink).
static var brush_px := 3

static func post() -> ShaderMaterial:
	var m := _mat("post", POST, {"brush_px": brush_px})
	m.render_priority = Material.RENDER_PRIORITY_MIN  # before flames and glass, which stay crisp
	return m


static func flame(params := {}) -> ShaderMaterial:
	var m := _mat("flame", FLAME, params)
	m.render_priority = 10
	return m


static func firewood(params := {}) -> ShaderMaterial:
	return _mat("log", LOG, params)


static func embers() -> ShaderMaterial:
	return _mat("embers", EMBERS, {})


static func foam() -> ShaderMaterial:
	return _mat("foam", FOAM, {})


static func dice(style: Dictionary, seed_value: float) -> ShaderMaterial:
	return _mat("dice", DICE, {
		"color_a": style.get("a", Color(0.6, 0.1, 0.1)),
		"color_b": style.get("b", Color(0.1, 0.0, 0.0)),
		"swirl": style.get("swirl", 1.0),
		"scale": style.get("scale", 2.0),
		"contrast": style.get("contrast", 1.0),
		"metal": style.get("metal", 0.0),
		"rough": style.get("rough", 0.25),
		"sparkle": style.get("sparkle", 0.0),
		"sparkle_color": style.get("sparkle_color", Color(1, 0.85, 0.5)),
		"seed": seed_value,
		"depth": style.get("depth", 0.35),
	})


static func glass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 0.4
	_toon_std(m)
	return m


static func plain(color: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	_toon_std(m)
	return m


static func _toon_std(m: StandardMaterial3D) -> void:
	if toon:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON


static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Soft round sprite for flames and embers, made from a radial gradient.
static func flame_particle() -> StandardMaterial3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true  # otherwise particle scale is ignored
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
