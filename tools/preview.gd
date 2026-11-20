extends SceneTree
## The text preview in a terminal: play a tale with no dice, choosing every outcome yourself.
##
##   godot --headless -s res://tools/preview.gd -- res://tales/drowned_bell.tale
##   godot --headless -s res://tools/preview.gd -- res://tales/drowned_bell.tale --walk=300
##   godot --headless -s res://tools/preview.gd -- res://tales/drowned_bell.tale --keys=1,2,1,s,c
##
## Interactive: type a choice's key, or a command (help lists them). --walk plays N random
## runs, choosing unseen options and outcomes first, and reports what was never reached.
## --keys plays a fixed list of keys and prints the transcript (for bug reports).

const Preview := preload("res://scripts/rules/preview.gd")


func _init() -> void:
	var path := "res://tales/drowned_bell.tale"
	var walk := 0
	var keys: Array = []
	var seed_value := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--walk="): walk = int(a.substr(7))
		elif a.begins_with("--keys="): keys = Array(a.substr(7).split(","))
		elif a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif not a.begins_with("--"): path = a
	var p := Preview.new()
	p.open(path, seed_value)
	if not p.errors.is_empty():
		print(p.errors_text())
		quit(1)
		return
	print(p.lint_text())
	if walk > 0:
		_walk(p, walk)
		return
	if not keys.is_empty():
		for k in keys:
			_show(p)
			print("\n>> ", k)
			_input(p, k.strip_edges())
		_show(p)
		quit(0)
		return
	while true:
		_show(p)
		printraw("\n> ")
		var line := OS.read_string_from_stdin().strip_edges()
		if line == "quit" or line == "q":
			break
		_input(p, line)
	quit(0)


func _input(p, line: String) -> void:
	if line == "":
		return
	var keys: Array = p.choices().map(func(c): return c.key)
	if line in keys:
		p.choose(line)
	else:
		var reply: String = p.command(line)
		if reply != "":
			print(reply)


func _show(p) -> void:
	var t: String = p.take_text()
	if t != "":
		print(_plain(t))
	print("")
	for c in p.choices():
		if c.get("info", false):
			print("     ", _plain(c.label))
		else:
			print("  [%s] %s" % [c.key, _plain(c.label)])


func _plain(t: String) -> String:
	return t.replace("[i]", "").replace("[/i]", "").replace("[b]", "").replace("[/b]", "")


func _walk(p, n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var endings := {}
	var stuck := 0
	for k in n:
		p.seed_value = k + 1
		p.archetype = ["balanced", "bruiser", "sage", "swindler"][k % 4]
		p.restart()
		p.take_text()
		p.walk(rng)
		if p.runner.phase == "ending":
			endings[p.runner.state.ending] = int(endings.get(p.runner.state.ending, 0)) + 1
		else:
			stuck += 1
			print("run %d stopped in %s at %s" % [k, p.runner.phase, p.scene_id()])
	print("%d walks. Endings: %s. Stuck: %d." % [n, str(endings), stuck])
	print(p.coverage_text())
	quit(stuck)
