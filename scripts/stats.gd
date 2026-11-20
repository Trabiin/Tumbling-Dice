extends Node3D
## Headless fairness test: throws every die in the catalogue many times and prints
## how often each face came up. Run with:
##   godot --headless --fixed-fps 120 res://stats.tscn -- --rolls=1000 --out=stats.md

const Die := preload("res://scripts/die.gd")
const Catalog := preload("res://scripts/dice_catalog.gd")
const Geo := preload("res://scripts/dice_geometry.gd")

const COPIES := 50      # dice of each type per round
const SPACING := 5.0

var rolls := 600
var out_path := ""
var rng := RandomNumberGenerator.new()
var seed_value := 12345
var only := ""   # e.g. --only=d12 to test a single die


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rolls="): rolls = int(a.substr(8))
		elif a.begins_with("--out="): out_path = a.substr(6)
		elif a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif a.begins_with("--only="): only = a.substr(7)
	rng.seed = seed_value

	var report := PackedStringArray()
	report.append(_geometry_check())

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	cs.position.y = -0.5
	floor_body.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.3
	floor_body.physics_material_override = pm
	add_child(floor_body)

	var specs := Catalog.default_set()
	if only != "":
		specs = specs.filter(func(s): return s.name == only)
	var counts := {}
	var cocked := {}
	var dice := []
	for s in specs:
		counts[s.name] = {}
		cocked[s.name] = 0
		for c in COPIES:
			var d := Die.new()
			d.setup(s)
			add_child(d)
			dice.append(d)

	var done := 0
	var t0 := Time.get_ticks_msec()
	while done < rolls:
		var cols := int(ceil(sqrt(dice.size())))
		for i in dice.size():
			var d = dice[i]
			var pos := Vector3((i % cols - cols / 2.0) * SPACING, rng.randf_range(2.0, 3.5), (i / cols - cols / 2.0) * SPACING)
			d.throw_from(pos, Vector3(rng.randfn(), 0, rng.randfn()), rng, 0.35)
		var frames := 0
		var still := 0
		while frames < 1800:
			await get_tree().physics_frame
			frames += 1
			still = still + 1 if dice.all(func(x): return x.sleeping or x.is_settled()) else 0
			if still > 20:
				break
		for d in dice:
			var r: Dictionary = d.read_result()
			if r.cocked:
				cocked[d.spec.name] += 1
				continue
			var tab: Dictionary = counts[d.spec.name]
			tab[r.label] = tab.get(r.label, 0) + 1
		done += COPIES
		print("round done: %d/%d throws per die (%d physics frames)" % [done, rolls, frames])

	report.append("## Face frequencies (%d throws per die, %d s wall time)\n" % [done, (Time.get_ticks_msec() - t0) / 1000])
	for s in specs:
		var tab: Dictionary = counts[s.name]
		var labels: Array = s.get("labels", range(1, s.sides + 1).map(func(v): return str(v)))
		var seen := {}
		var total := 0
		for k in tab:
			total += tab[k]
		var expected: float = float(total) / s.sides
		var chi2 := 0.0
		var cells := PackedStringArray()
		# Merge duplicate labels (e.g. ATK twice) for display, but test per face.
		for l in labels:
			if seen.has(l): continue
			seen[l] = true
			var mult := labels.count(l)
			var obs: int = tab.get(l, 0)
			chi2 += pow(obs - expected * mult, 2) / (expected * mult)
			cells.append("%s: %.1f%%" % [l, 100.0 * obs / maxi(total, 1)])
		var df: int = seen.size() - 1
		var verdict := "fair" if chi2 < _chi2_crit(df) else "**biased**"
		report.append("- **%s** (%s, chi²=%.1f, df=%d, %d cocked): %s" % [s.name, verdict, chi2, df, cocked[s.name], ", ".join(cells)])

	var text := "\n".join(report)
	print(text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text + "\n")
	get_tree().quit()


func _geometry_check() -> String:
	var lines := PackedStringArray(["## Geometry check\n"])
	for n in [4, 6, 8, 10, 12, 20]:
		var s := Geo.build(n, 1.0)
		var sizes := {}
		for f in s.faces:
			sizes[f.size()] = sizes.get(f.size(), 0) + 1
		lines.append("- d%d: %d vertices, %d faces, face sizes %s" % [n, s.verts.size(), s.faces.size(), str(sizes)])
	return "\n".join(lines) + "\n"


# 95th percentile of chi-squared for small df.
func _chi2_crit(df: int) -> float:
	var t := {1: 3.84, 2: 5.99, 3: 7.81, 4: 9.49, 5: 11.07, 7: 14.07, 9: 16.92, 11: 19.68, 19: 30.14}
	return t.get(df, 1.5 * df + 3)
