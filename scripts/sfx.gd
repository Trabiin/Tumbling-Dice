extends RefCounted
## Sound effects synthesised in code at startup: no audio files.
##
## Each sound is a few decaying sine "modes" (the ringing of a struck object) plus a burst of
## noise for the impact, written straight into 16-bit PCM. A few random variants of each are
## kept so repeated hits don't sound identical.

const RATE := 22050

static var _bank := {}


## Returns a random variant of `kind`: "wood", "felt", "dice", or the seamless loops "crackle"
## and "wind".
static func get_sound(kind: String) -> AudioStreamWAV:
	if _bank.is_empty():
		_build()
	var v: Array = _bank[kind]
	return v[randi() % v.size()]


static func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_bank.wood = []
	_bank.felt = []
	_bank.dice = []
	for i in 4:
		# Resin die hitting the hardwood rim: bright knock with a short woody ring.
		_bank.wood.append(_strike(rng, 0.12, [[900.0, 0.030, 0.5], [1900.0, 0.025, 0.8], [3200.0, 0.018, 0.6], [5100.0, 0.010, 0.4]], 0.5, 0.004, 6000.0))
		# Landing on velvet: a muffled thump, mostly low noise.
		_bank.felt.append(_strike(rng, 0.09, [[160.0, 0.025, 0.7], [320.0, 0.012, 0.3]], 0.6, 0.012, 900.0))
		# Die against die: a sharp, glassy click.
		_bank.dice.append(_strike(rng, 0.07, [[3400.0, 0.012, 0.7], [5600.0, 0.008, 0.6], [8200.0, 0.005, 0.4]], 0.35, 0.002, 9000.0))
	_bank.crackle = [_crackle(rng, 6.0)]
	_bank.wind = [_wind(rng, 16.0)]


## modes: [frequency Hz, decay seconds, amplitude]; noise: amount; noise_t: noise decay;
## cutoff: low-pass for the noise burst.
static func _strike(rng: RandomNumberGenerator, length: float, modes: Array, noise: float, noise_t: float, cutoff: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var detune := rng.randf_range(0.9, 1.1)
	var lp := 0.0
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for m in modes:
			s += m[2] * sin(TAU * m[0] * detune * t) * exp(-t / m[1])
		lp += (rng.randf_range(-1, 1) - lp) * k
		s += lp * noise * exp(-t / noise_t)
		s *= minf(1.0, t * RATE / 20.0)  # 1 ms fade-in avoids a click
		buf[i] = s
	return _to_wav(buf, 0.9)


## A seamless loop of a log fire: low rumble, hiss, and random pops and snaps.
static func _crackle(rng: RandomNumberGenerator, seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var brown := 0.0
	var hiss := 0.0
	for i in n:
		brown = clampf(brown + rng.randf_range(-1, 1) * 0.02, -1.0, 1.0) * 0.998
		var w := rng.randf_range(-1, 1)
		hiss += (w - hiss) * 0.5
		var swell := 0.6 + 0.4 * sin(TAU * i / n * 3.0)   # whole cycles, so the loop is seamless
		buf[i] = brown * 0.35 + (w - hiss) * 0.025 * swell
	var pops := int(seconds * 9.0)
	for p in pops:
		var at := rng.randi() % n
		var big := rng.randf() < 0.15
		var amp := rng.randf_range(0.3, 1.0) * (1.0 if big else 0.4)
		var dec := rng.randf_range(0.0015, 0.006) * (2.0 if big else 1.0)
		var f := rng.randf_range(1500.0, 4500.0)
		for j in int(dec * 6.0 * RATE):
			var t := float(j) / RATE
			var idx := (at + j) % n  # wrap round, keeping the loop seamless
			buf[idx] += (rng.randf_range(-1, 1) * 0.7 + sin(TAU * f * t) * 0.3) * amp * exp(-t / dec)
	var wav := _to_wav(buf, 0.7)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


## A winter wind outside the window: noise through a soft band-pass whose pitch and loudness
## rise and fall in slow gusts, with a faint whistle at the top of each gust. The gusts run in
## whole cycles and the tail is cross-faded into the head, so the loop has no seam.
static func _wind(rng: RandomNumberGenerator, seconds: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var xf := int(1.5 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + xf)
	var low := 0.0
	var band := 0.0
	var ph := 0.0
	var dark := 0.0
	for i in n + xf:
		var u := float(i % n) / n
		# Three slow gusts and a quicker flutter, all whole cycles over the loop.
		var gust := 0.5 + 0.3 * sin(TAU * u * 3.0) + 0.15 * sin(TAU * u * 7.0 + 1.3) + 0.05 * sin(TAU * u * 23.0)
		gust = clampf(gust, 0.0, 1.0)
		var fc := 180.0 + 520.0 * gust * gust
		var f := 2.0 * sin(PI * fc / RATE)
		var q := 0.35
		var w := rng.randf_range(-1, 1)
		low += f * band
		var high := w - low - q * band
		band += f * high
		ph += TAU * (600.0 + 500.0 * gust) / RATE
		var whistle := sin(ph) * smoothstep(0.75, 1.0, gust) * 0.04
		dark += ((band * 0.6 + low * 0.15) - dark) * 0.25   # roll off the hiss above ~1 kHz
		raw[i] = dark * (0.25 + 0.75 * gust) + whistle
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = raw[i]
	for i in xf:
		var a := float(i) / xf
		buf[i] = raw[n + i] * (1.0 - a) + raw[i] * a
	var wav := _to_wav(buf, 0.6)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


static func _to_wav(buf: PackedFloat32Array, peak_target: float) -> AudioStreamWAV:
	var peak := 0.0001
	for s in buf:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * peak_target, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
