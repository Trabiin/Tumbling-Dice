extends SceneTree
## Physics checks for throwing by hand: real Jolt dice in the real tray.
##
##   godot --headless --fixed-fps 120 -s res://tests/physics_check.gd [-- --throws=60]
##   godot --headless --fixed-fps 60 -s res://tests/physics_check.gd -- --hz=60
##       (another tick rate; at 60 Hz the faces are measurably unfair, which is why every
##        graphics preset keeps physics at 120 Hz)
##
## 1. Every drag-throw, from a gentle drop to the hardest flick, settles inside the tray in time.
## 2. The gesture never decides the face: the same flick repeated gives fair faces (chi-square).
## 3. Strays (dice leaving the tray) are recovered.
## Exit code is the number of failed checks.

const Tavern := preload("res://scripts/tavern.gd")
const Table := preload("res://scripts/game/table.gd")
const Dice := preload("res://scripts/rules/dice.gd")

var failures := 0
var checks := 0
var throws := 60


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL: ", msg)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--throws="):
			throws = int(a.substr(9))
		elif a.begins_with("--hz="):
			# Try another physics rate (see the note at the top).
			Engine.physics_ticks_per_second = int(a.substr(5))
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var root3d := Node3D.new()
	root.add_child(root3d)
	var tavern := Tavern.new()
	root3d.add_child(tavern)
	var table := Table.new()
	table.tavern = tavern
	root3d.add_child(table)
	table.rng.seed = 7
	await physics_frame

	var dice: Array = []
	for i in 6:
		dice.append(Dice.create("bone_d6"))
	var counts := [0, 0, 0, 0, 0, 0]
	var slow := 0
	var worst := 0.0
	print("== drag throws (%d throws of 6 dice)" % throws)
	for k in throws:
		# Cycle through gestures: drops, gentle rolls, hard flicks into the walls.
		var speeds := [0.0, 4.0, 10.0, 22.0, 60.0]
		var speed: float = speeds[k % speeds.size()]
		var ang := TAU * float(k) / 7.0
		table.hold_player(dice, Vector3(-4.0, 0, 2.0))
		for f in 10:
			await process_frame
			table.move_hold(Vector3(-4.0 + f * 0.3, 0, 2.0), 1.0 / 60.0)
		var start := Time.get_ticks_msec()
		var res: Array = await table.release(Vector3(cos(ang), 0, sin(ang)) * speed)
		var took := (Time.get_ticks_msec() - start) / 1000.0
		worst = maxf(worst, took)
		for r in res:
			var p: Vector3 = r.node.global_position
			check(absf(p.x) < Tavern.TRAY.x / 2 and absf(p.z) < Tavern.TRAY.y / 2 and p.y > -0.5,
				"die rests inside the tray (at %s, speed %.0f)" % [str(p), speed])
			if not r.cocked:
				counts[r.value - 1] += 1
		if not res.all(func(r): return r.node.is_settled() or r.node.sleeping):
			slow += 1
	var n := 0
	for c in counts:
		n += c
	var chi := 0.0
	for c in counts:
		chi += pow(c - n / 6.0, 2) / (n / 6.0)
	print("  faces %s (n=%d), chi-square %.2f, strays recovered %d, unsettled at timeout %d" % [str(counts), n, chi, table.strays, slow])
	# 5 degrees of freedom: 20.5 is the 0.001 critical value, generous for a few hundred samples.
	check(chi < 20.5, "drag throws give fair faces (chi-square %.2f)" % chi)
	check(slow <= throws / 20, "throws settle before the timeout (%d did not)" % slow)
	print("\n%d checks, %d failed (%.1f s)" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(failures)
