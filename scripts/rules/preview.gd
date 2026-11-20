extends RefCounted
## The writers' text preview: plays a tale as text with no dice. At every throw the writer picks
## the outcome (Fail, Mixed, Success, Triumph, Caught) or lets the bot roll for real. Any scene can
## be jumped to and any flag set. The console tool (tools/preview.gd) and the in-game preview
## panel both drive this class, so they behave the same.
##
##   var p = Preview.new(); p.open("res://tales/drowned_bell.tale")
##   p.take_text() -> new narration;  p.choices() -> [{key, label}];  p.choose(key)
##   p.command("goto chamber"), p.command("flag climax=freed"), p.command("reload") ...

const Runner := preload("res://scripts/rules/tale_runner.gd")
const Campaign := preload("res://scripts/rules/campaign.gd")
const Bot := preload("res://scripts/rules/bot.gd")
const Tales := preload("res://scripts/rules/tales.gd")
const Lint := preload("res://scripts/rules/tale_lint.gd")
const Parser := preload("res://scripts/rules/tale_parser.gd")
const S := preload("res://scripts/rules/scoring.gd")
const Cond := preload("res://scripts/rules/conditions.gd")

const TIER_KEYS := {"f": S.FAIL, "m": S.MIXED, "s": S.SUCCESS, "t": S.TRIUMPH}
const DICE_PHASES := ["foe_throw", "throw", "quake", "assign", "push"]

var path := ""
var tale: Dictionary = {}
var lines := {}
var errors: Array = []      # parse errors
var issues: Array = []      # lint issues
var runner
var campaign
var bot = Bot.new()
var seed_value := 1
var archetype := "balanced"     # the Pouch packed at the prepare scene (see bot.gd ARCHETYPES)
var _buffer: Array[String] = []
## Every option and outcome seen this session, for the coverage report: "scene.option.tier".
var seen := {}


func open(p_path: String, p_seed := 1) -> void:
	path = p_path
	seed_value = p_seed
	_load(true)
	restart()


func open_tale(t: Dictionary, p_seed := 1) -> void:
	path = ""
	tale = t
	lines = {}
	errors = []
	issues = Lint.run(tale)
	seed_value = p_seed
	restart()


func _load(reload: bool) -> void:
	var res: Dictionary = Tales.parsed(path, reload)
	tale = res.tale.duplicate(true)
	lines = res.lines
	errors = res.errors
	issues = Lint.run(tale, lines)


func restart() -> void:
	campaign = Campaign.new()
	campaign.new_campaign()
	bot.rng.seed = seed_value
	runner = Runner.new()
	runner.said.connect(_on_said)
	if errors.is_empty() and tale.has("start"):
		runner.start(tale, campaign, seed_value)
	_skip_setup()


func _on_said(text: String, style: String) -> void:
	match style:
		"title": _buffer.append("=== %s ===" % text)
		"scene": _buffer.append("\n--- %s ---" % text)
		"choice": _buffer.append("> " + text)
		"ending": _buffer.append("\n*** Ending: %s ***" % text)
		_:
			if style.begins_with("tier_"):
				_buffer.append("[%s]" % text.to_upper())
			else:
				_buffer.append(text)


## The narration since the last call (BBCode italics left in; the console strips them).
func take_text() -> String:
	var t := "\n".join(_buffer)
	_buffer.clear()
	return t


## Setup phases a writer never needs to stop at: pack a balanced Pouch, continue at Waystones.
func _skip_setup() -> void:
	var guard := 0
	while runner != null and guard < 20:
		guard += 1
		match runner.phase:
			"prepare":
				bot.pack(campaign, archetype)
				runner.done_prepare()
			"waystone":
				runner.done_waystone()
			_:
				return


func scene_id() -> String:
	return runner.scene.get("id", "") if runner != null else ""


func line_of(where: String) -> int:
	return int(lines.get(where, 0))


## What can be done now: [{key, label, info}] (info: true for lines that are not choices).
func choices() -> Array:
	var out: Array = []
	if runner == null or not errors.is_empty():
		return out
	match runner.phase:
		"choose":
			var vis: Array = runner.visible_options()
			for i in vis.size():
				var o: Dictionary = vis[i]
				var tag := ""
				if o.has("challenge"):
					tag = " (%s)" % o.challenge.get("kind", "test")
				elif o.has("contest"):
					tag = " (contest: %s)" % o.contest.get("opponent", "")
				elif o.has("combat"):
					tag = " (fight: %s)" % o.combat.get("foe", "")
				out.append({"key": str(i + 1), "label": o.text + tag})
			# Hidden options, so the writer can see what a different path would show.
			for o in runner.scene.get("options", []):
				if not vis.has(o):
					out.append({"key": "", "label": "(hidden, needs %s) %s" % [o.get("cond", ""), o.text], "info": true})
		"wager":
			out.append({"key": "1", "label": "Stake a die"})
			out.append({"key": "2", "label": "Keep your dice"})
		"approach":
			var aps: Array = runner.approaches()
			for i in aps.size():
				out.append({"key": str(i + 1), "label": "[%s] %s" % [aps[i].aspect.capitalize(), aps[i].text]})
		"defy":
			out.append({"key": "y", "label": "Defy the Fail (3 Fate): make it Mixed"})
			out.append({"key": "n", "label": "Take the Fail"})
		"cost":
			var cs: Array = runner.costs()
			for i in cs.size():
				out.append({"key": str(i + 1), "label": cs[i].label})
		"outcome":
			out.append({"key": "c", "label": "Continue"})
		"ending":
			out.append({"key": "r", "label": "Tell it again from the start"})
		_:
			if runner.phase in DICE_PHASES:
				var what: String = runner.active.get("type", "")
				out.append({"key": "f", "label": "Fail"})
				if what != "laststand":
					out.append({"key": "m", "label": "Mixed"})
				out.append({"key": "s", "label": "Success"})
				out.append({"key": "t", "label": "Triumph"})
				if what == "contest" and runner.option.get("outcomes", {}).has("caught"):
					out.append({"key": "c", "label": "Caught with a loaded die"})
				out.append({"key": "r", "label": "Roll the dice for real (the bot throws)"})
	return out


func choose(key: String) -> void:
	if runner == null:
		return
	match runner.phase:
		"choose":
			var i := int(key) - 1
			var vis: Array = runner.visible_options()
			if i >= 0 and i < vis.size():
				seen["%s.%s" % [scene_id(), vis[i].id]] = true
				runner.pick(i)
		"wager":
			runner.pick_wager(campaign.pouch.collection[0] if key == "1" else null)
		"approach":
			var i := int(key) - 1
			if i >= 0 and i < runner.approaches().size():
				runner.pick_approach(i)
		"defy":
			runner.defy(key == "y")
		"cost":
			var i := int(key) - 1
			if i >= 0 and i < runner.costs().size():
				runner.pick_cost(i)
		"outcome":
			runner.next()
		"ending":
			restart()
			return
		_:
			if runner.phase in DICE_PHASES:
				var sc := scene_id()
				var oid: String = runner.option.get("id", "")
				if key in TIER_KEYS:
					seen["%s.%s.%s" % [sc, oid, ["fail", "mixed", "success", "triumph"][TIER_KEYS[key]]]] = true
					runner.force_outcome(TIER_KEYS[key])
				elif key == "c":
					seen["%s.%s.caught" % [sc, oid]] = true
					runner.force_outcome(S.FAIL, true)
				elif key == "r":
					_roll()
	_skip_setup()


## Let the bot throw real (fast) dice until the dice part is over.
func _roll() -> void:
	var guard := 0
	var sc := scene_id()
	var oid: String = runner.option.get("id", "")
	while runner.phase in DICE_PHASES and guard < 200:
		guard += 1
		bot.step(runner)
	if runner.phase in ["outcome", "cost", "defy"] and runner.tier >= 0:
		seen["%s.%s.%s" % [sc, oid, ["fail", "mixed", "success", "triumph"][runner.tier]]] = true


## Writer commands. Returns a reply to show.
func command(line: String) -> String:
	var parts := line.strip_edges().split(" ", false, 1)
	if parts.is_empty():
		return ""
	var arg: String = parts[1] if parts.size() > 1 else ""
	match parts[0]:
		"goto":
			if not tale.scenes.has(arg):
				return "No scene '%s'. Scenes: %s" % [arg, ", ".join(tale.scenes.keys())]
			runner.pending_goto = ""
			runner.pending_retry = ""
			runner.enter(arg)
			_skip_setup()
			return ""
		"flag":
			var eq := arg.find("=")
			var name := arg if eq < 0 else arg.substr(0, eq).strip_edges()
			var val = true if eq < 0 else Parser.Lex.value(arg.substr(eq + 1))
			runner.state.set_flag(name, val)
			return "%s = %s" % [name, str(val)]
		"unflag":
			runner.state.flags.erase(arg)
			return "%s cleared" % arg
		"mark":
			campaign.mark(arg)
			return "Chronicle mark %s set" % arg
		"grit":
			runner.state.grit = clampi(int(arg), 0, runner.state.grit_max)
			return "Grit %d" % runner.state.grit
		"fate":
			runner.state.fate = clampi(int(arg), 0, 6)
			return "Fate %d" % runner.state.fate
		"check":
			return "%s -> %s" % [arg, str(runner.check(arg))]
		"state":
			return state_text()
		"scenes":
			return ", ".join(tale.scenes.keys())
		"reload":
			if path == "":
				return "Nothing to reload (this tale is not from a file)."
			var at := scene_id()
			var keep_flags: Dictionary = runner.state.flags.duplicate(true)
			_load(true)
			if not errors.is_empty():
				return errors_text()
			restart()
			runner.state.flags = keep_flags
			if tale.scenes.has(at):
				runner.enter(at)
				_skip_setup()
			return "Reloaded %s (%d scenes). %s" % [path.get_file(), tale.scenes.size(), lint_text()]
		"lint":
			return lint_text()
		"restart":
			restart()
			return ""
		"seed":
			seed_value = int(arg)
			restart()
			return "Seed %d" % seed_value
		"pouch":
			if not Bot.ARCHETYPES.has(arg):
				return "Pouches: %s" % ", ".join(Bot.ARCHETYPES.keys())
			archetype = arg
			restart()
			return "Restarted with the %s Pouch." % arg
		"coverage":
			return coverage_text()
		"help":
			return HELP
	return "Unknown command '%s'. Type help." % parts[0]


const HELP := """Pick a choice by its key. Commands:
  goto <scene>         jump to a scene (flags so far are kept)
  flag <name>[=value]  set a flag;  unflag <name>;  mark <name> (a Chronicle mark)
  grit <n>, fate <n>   set them;  check <condition>  test a condition now
  state                Grit, Fate, Wounds, flags, temperament
  scenes               list scene ids;  lint  run the linter;  coverage  what you have seen
  reload               re-read the file, stay in this scene;  restart;  seed <n>
  pouch <name>         restart with another Pouch: balanced, bruiser, sage, swindler"""


func state_text() -> String:
	var st = runner.state
	var fl: Array[String] = []
	for k in st.flags:
		fl.append("%s=%s" % [k, str(st.flags[k])])
	return "Scene %s (line %d). Grit %d/%d, Fate %d, Wounds %s.\nFlags: %s\nTemper: %s. Regard %d." % [
		scene_id(), line_of(scene_id()), st.grit, st.grit_max, st.fate, str(st.wounds),
		", ".join(fl) if not fl.is_empty() else "none", str(st.temper), st.regard]


func errors_text() -> String:
	return "\n".join(errors.map(func(e): return "%s:%d: %s" % [path.get_file(), e.line, e.msg]))


func lint_text() -> String:
	if issues.is_empty():
		return "Linter: clean."
	return "Linter: %d issue%s\n" % [issues.size(), "" if issues.size() == 1 else "s"] + \
		"\n".join(issues.map(func(i): return "  line %d: %s" % [i.line, i.msg]))


## Every option and dice outcome in the tale, and which this session has seen.
func all_targets() -> Array:
	var out: Array = []
	for id in tale.get("scenes", {}):
		for o in tale.scenes[id].get("options", []):
			out.append("%s.%s" % [id, o.id])
			for k in o.get("outcomes", {}):
				out.append("%s.%s.%s" % [id, o.id, k])
	return out


func coverage_text() -> String:
	var all := all_targets()
	var missing := all.filter(func(k): return not seen.has(k))
	var t := "Seen %d of %d options and outcomes." % [all.size() - missing.size(), all.size()]
	if not missing.is_empty():
		t += " Not yet: " + ", ".join(missing.slice(0, 30)) + (" ..." if missing.size() > 30 else "")
	return t


## Play through by itself, picking choices and outcomes at random. For the coverage test and
## for the console's 'walk' mode. Returns the number of steps taken.
func walk(rng: RandomNumberGenerator, max_steps := 400) -> int:
	var steps := 0
	while steps < max_steps:
		steps += 1
		if runner.phase == "ending":
			return steps
		var cs := choices().filter(func(c): return not c.get("info", false) and c.key != "r")
		if cs.is_empty():
			return steps
		# At the dice: prefer an outcome nobody has seen yet.
		if runner.phase in DICE_PHASES:
			var sc := scene_id()
			var oid: String = runner.option.get("id", "")
			var fresh := cs.filter(func(c):
				var k: String = {"f": "fail", "m": "mixed", "s": "success", "t": "triumph", "c": "caught"}.get(c.key, "")
				return k != "" and not seen.has("%s.%s.%s" % [sc, oid, k]))
			if not fresh.is_empty():
				cs = fresh
		elif runner.phase == "choose":
			var sc := scene_id()
			var vis: Array = runner.visible_options()
			var fresh := cs.filter(func(c): return not seen.has("%s.%s" % [sc, vis[int(c.key) - 1].id]))
			if not fresh.is_empty():
				cs = fresh
		choose(cs[rng.randi_range(0, cs.size() - 1)].key)
	return steps
