extends RefCounted
## The tale linter. Checks a tale for the mistakes that break play or break the design rules
## ("Choice and failure" in the design doc), and says where: give it the parser's line map and
## each issue carries the line in the .tale file.
##
##   Lint.run(tale, lines) -> [{line, where, msg}]

const Dice := preload("res://scripts/rules/dice.gd")
const Foes := preload("res://scripts/rules/foes.gd")
const Cond := preload("res://scripts/rules/conditions.gd")
const Board := preload("res://scripts/rules/board.gd")
const Forge := preload("res://scripts/rules/forge.gd")
const Campaign := preload("res://scripts/rules/campaign.gd")
## Condition prefixes that read the campaign (checked against what exists, where possible).
const SEASONS := ["spring", "summer", "autumn", "winter"]

const TIERS := ["fail", "mixed", "success", "triumph"]
const EFFECTS := ["if", "flag", "add", "random_flag", "grit", "fate", "coin", "fatigue", "wound", "gain", "ally",
	"temper", "regard", "standing", "rumour", "chronicle", "shard", "mark", "exhaust_best", "lose_lowest",
	"rest", "practice_reset", "toll", "lose_wager", "return_gold", "wager_pick", "material", "renown", "heal",
	"lift_curse", "crack_best", "give_up"]
const BUILTIN_FLAGS := ["climax", "defeat", "weather"]
const TEMPER := ["mercy", "honesty", "duty"]


static func run(tale: Dictionary, lines := {}) -> Array:
	var L := _Lint.new()
	L.lines = lines
	L.check_tale(tale)
	return L.issues


## A translated tale must have the same shape as the original: the same tale id, scenes, options,
## outcomes and endings (the parser's line map has one key for each). Returns readable problems.
static func same_shape(orig: Dictionary, orig_lines: Dictionary, tr_tale: Dictionary, tr_lines: Dictionary) -> Array:
	var out: Array = []
	if str(orig.get("id", "")) != str(tr_tale.get("id", "")):
		out.append("the tale id differs ('%s' against '%s')" % [tr_tale.get("id", ""), orig.get("id", "")])
	for k in orig_lines:
		if not tr_lines.has(k):
			out.append("missing '%s'" % k)
	for k in tr_lines:
		if not orig_lines.has(k):
			out.append("'%s' is not in the original" % k)
	return out


class _Lint:
	var issues: Array = []
	var lines := {}
	var set_flags := {}
	var read_flags := {}     # flag -> where first read

	func add(where: String, msg: String) -> void:
		var line := 0
		var w := where
		while w != "":
			if lines.has(w):
				line = lines[w]
				break
			var dot := w.rfind(".")
			w = w.substr(0, dot) if dot > 0 else ""
		issues.append({"line": line, "where": where, "msg": msg})

	func reads(expr: String, where: String) -> void:
		for f in Cond.flags_read(expr):
			if not read_flags.has(f):
				read_flags[f] = where
		campaign_reads(expr, where)

	## Campaign conditions: known factions, seasons and condition words.
	func campaign_reads(expr: String, where: String) -> void:
		for alt in expr.split(" or "):
			for term in alt.split(" and "):
				var a := term.strip_edges()
				if a.begins_with("not "):
					a = a.substr(4).strip_edges()
				if a.begins_with("standing:"):
					var f := a.substr(9)
					for op in Cond.OPS:
						var at := f.find(op)
						if at > 0:
							f = f.substr(0, at)
							break
					if not Campaign.FACTIONS.has(f):
						add(where, "Unknown faction '%s' in a condition. Use one of: %s." % [f, ", ".join(Campaign.FACTIONS.keys())])
				elif a.begins_with("season"):
					var v := a.substr(a.find("==") + 2) if a.contains("==") else ""
					if not v in SEASONS:
						add(where, "season== takes a season (spring, summer, autumn, winter).")
				elif a.contains(":"):
					var pre := a.substr(0, a.find(":"))
					if not pre in ["has", "mat", "seen", "rumour", "told", "ended", "fell", "missed", "ending", "standing", "temper"]:
						add(where, "Unknown condition '%s:'." % pre)

	func check_tale(tale: Dictionary) -> void:
		var scenes: Dictionary = tale.get("scenes", {})
		# A tale with an arc is offered by a patron: it needs a pitch, and expires: names a season.
		if tale.get("arc", "") != "":
			if tale.get("pitch", "") == "":
				add("", "A tale in an arc needs a pitch: (what the patron says when offering it).")
			if tale.get("expires", "") != "" and not tale.expires in SEASONS:
				add("", "expires: takes a season (spring, summer, autumn, winter), not '%s'." % tale.expires)
			if tale.get("expires", "") != "" and tale.get("missed", "") == "":
				add("", "A tale that expires needs a missed: line, told when it goes by without you.")
			campaign_reads(tale.get("offer", ""), "")
		# A fixed Pouch (the prologue): every die named must exist.
		for k in ["pouch", "saddle"]:
			for b in String(tale.get(k, "")).split(",", false):
				if not b.strip_edges() in Dice.ALL_IDS:
					add("", "%s: names an unknown die '%s'." % [k, b.strip_edges()])
		if not scenes.has(tale.get("start", "")):
			add("", "The start scene '%s' does not exist." % tale.get("start", ""))
		var edges := {}
		for id in scenes:
			var sc: Dictionary = scenes[id]
			edges[id] = []
			if sc.has("goto"):
				edges[id].append(sc.goto)
			elif sc.get("type", "") == "prepare":
				add(id, "A prepare scene needs a goto: for where the tale goes next.")
			effects(sc.get("on_enter", []), id)
			for line in sc.get("text", []):
				if line is Array:
					reads(line[0], id)
			if sc.has("tile") and not sc.tile in Board.ICONS:
				add(id, "Unknown tile '%s'. Use one of: %s." % [sc.tile, ", ".join(Board.ICONS)])
			if sc.has("at") and not sc.has("tile"):
				add(id, "at: places a tile, so the scene needs a tile: too.")
			for tok in sc.get("tokens", []):
				reads(tok.cond, id)
				if not tok.icon in Board.TOKENS:
					add(id, "Unknown token '%s'. Use one of: %s." % [tok.icon, ", ".join(Board.TOKENS)])
				if not sc.has("tile"):
					add(id, "A token sits on a tile, so the scene needs a tile: too.")
			if sc.get("type", "") == "ending":
				if sc.get("endings", []).is_empty():
					add(id, "An ending scene has no endings (+).")
				elif sc.endings[-1].get("cond", "") != "":
					# Not an error on its own, but the runner needs some ending to hold.
					pass
			elif sc.get("options", []).is_empty() and sc.get("type", "") not in ["prepare"]:
				add(id, "Scene '%s' has no options, so the tale stops here." % id)
			for o in sc.get("options", []):
				option(sc, o, edges[id])
			for en in sc.get("endings", []):
				var w := "%s.%s" % [id, en.id]
				reads(en.get("cond", ""), w)
				effects(en.get("effects", []), w)
				for line in en.get("text", []):
					if line is Array:
						reads(line[0], w)
		for id in edges:
			for target in edges[id]:
				if not scenes.has(target):
					add(id, "goto: '%s' is not a scene in this tale." % target)
		# Every scene can be reached from the start.
		var seen := {tale.get("start", ""): true}
		var queue := [tale.get("start", "")]
		while not queue.is_empty():
			var cur = queue.pop_front()
			for nx in edges.get(cur, []):
				if not seen.has(nx):
					seen[nx] = true
					queue.append(nx)
		for id in scenes:
			if not seen.has(id) and scenes[id].get("type", "") != "ending":
				add(id, "Scene '%s' cannot be reached from the start." % id)
		for f in read_flags:
			if not set_flags.has(f) and not f in BUILTIN_FLAGS:
				add(read_flags[f], "The flag '%s' is read here but never set anywhere." % f)

	func option(sc: Dictionary, o: Dictionary, out_edges: Array) -> void:
		var w := "%s.%s" % [sc.id, o.get("id", "?")]
		if o.get("text", "") == "":
			add(w, "Option '%s' has no text." % o.get("id", "?"))
		reads(o.get("cond", ""), w)
		# Character choices never name an aspect or preview a reward.
		var txt: String = o.get("text", "")
		for asp in Dice.ASPECT_NAMES.values():
			if txt.contains(asp + " "):
				add(w, "Option text names an aspect (%s). Choices are about the character, not the dice." % asp)
		if txt.contains("Coin"):
			add(w, "Option text previews a reward (Coin).")
		for k in o.get("temper", {}):
			if not k in TEMPER:
				add(w, "Unknown temperament track '%s' (mercy, honesty, duty)." % k)
		effects(o.get("effects", []), w)
		if o.has("goto"):
			out_edges.append(o.goto)
		var dice := o.has("challenge") or o.has("contest") or o.has("combat")
		if not dice and not o.has("goto") and sc.get("type", "") != "waystone":
			add(w, "Option '%s' has no goto: and no dice, so the tale cannot move on." % o.id)
		if o.has("combat") and not o.combat.get("foe", "") in Foes.FOE_IDS:
			add(w, "Unknown foe '%s'. Known: %s." % [o.combat.get("foe", ""), ", ".join(Foes.FOE_IDS)])
		if o.has("contest") and not o.contest.get("opponent", "") in Foes.OPPONENT_IDS:
			add(w, "Unknown opponent '%s'. Known: %s." % [o.contest.get("opponent", ""), ", ".join(Foes.OPPONENT_IDS)])
		if o.has("challenge"):
			var c: Dictionary = o.challenge
			if not c.get("kind", "test") in ["test", "trial"]:
				add(w, "challenge kind is test or trial, not '%s'." % c.kind)
			if c.get("kind", "test") == "trial" and not c.has("progress"):
				add(w, "A trial needs progress= (how much it takes).")
			if c.has("difficulty") and not c.difficulty in ["easy", "standard", "hard", "heroic"]:
				add(w, "Unknown difficulty '%s'." % c.difficulty)
		for kind in ["challenge", "contest", "combat"]:
			if o.has(kind):
				for m in o[kind].get("mods", []):
					reads(m[0], w)
		if o.has("challenge") or o.has("contest"):
			var asp := {}
			for ap in o.get("approaches", []):
				asp[ap.aspect] = true
				if not ap.aspect in Dice.ASPECTS:
					add(w, "Unknown aspect '%s' in an approach." % ap.aspect)
			if asp.size() < 2:
				add(w, "Every challenge can be done with 2 or more aspects; this one has %d." % asp.size())
		if not dice:
			return
		var outs: Dictionary = o.get("outcomes", {})
		for k in TIERS:
			if not outs.has(k):
				add(w, "No outcome for %s (every tier tells its own story)." % k)
		if o.has("contest") and Foes.opponent(o.contest.get("opponent", "")).get("traits", []).has("card_sharp") and not outs.has("caught"):
			add(w, "This opponent is a card sharp: add a > caught: outcome for being spotted with a loaded die.")
		for k in outs:
			var oc: Dictionary = outs[k]
			var ow := "%s.%s" % [w, k]
			effects(oc.get("effects", []), ow)
			for c in oc.get("costs", []):
				effects(c.effects, ow)
			if not oc.has("goto"):
				add(ow, "The %s outcome has no goto:." % k)
			else:
				out_edges.append(oc.goto)
			if oc.has("retry"):
				var found := false
				for o2 in sc.get("options", []):
					if o2.id == oc.retry:
						found = true
				if not found:
					add(ow, "retry: '%s' is not an option in this scene." % oc.retry)
		if outs.has("mixed") and outs.mixed.get("goto", "") != "ending" and outs.mixed.get("costs", []).size() < 2:
			add(w + ".mixed", "A Mixed outcome offers 2 or more costs to choose from.")

	func effects(list: Array, where: String) -> void:
		for e in list:
			effect(e, where)

	func effect(e, where: String) -> void:
		if not e is Array or e.is_empty():
			add(where, "Malformed effect %s." % str(e))
			return
		if not e[0] in EFFECTS:
			add(where, "Unknown effect '%s'." % str(e[0]))
			return
		match e[0]:
			"flag", "add", "random_flag":
				if e.size() < 2:
					add(where, "'%s' needs a flag name." % e[0])
				else:
					set_flags[e[1]] = true
				if e[0] == "add" and (e.size() < 3 or not e[2] is int):
					add(where, "add takes a flag and a number.")
			"if":
				if e.size() < 3:
					add(where, "if needs a condition and an effect.")
					return
				reads(e[1], where)
				effect(e[2], where)
			"gain", "ally":
				if e.size() < 2 or not e[1] in Dice.ALL_IDS:
					add(where, "Unknown die '%s'." % (str(e[1]) if e.size() > 1 else ""))
			"grit", "fate", "coin", "fatigue", "regard", "rest":
				if e.size() < 2 or not e[1] is int:
					add(where, "'%s' takes a number." % e[0])
			"temper":
				if e.size() < 3 or not e[1] in TEMPER or not e[2] is int:
					add(where, "temper takes a track (mercy, honesty, duty) and a number.")
			"material":
				if e.size() < 2 or not Forge.MATERIALS.has(str(e[1])):
					add(where, "Unknown material '%s'. Known: %s." % [str(e[1]) if e.size() > 1 else "", ", ".join(Forge.MATERIALS.keys())])
			"renown":
				if e.size() < 2 or not e[1] is int:
					add(where, "renown takes a number.")
			"lift_curse", "give_up":
				if (e.size() > 1 or e[0] == "give_up") and (e.size() < 2 or not e[1] in Dice.ALL_IDS):
					add(where, "Unknown die '%s'." % str(e[1]))
			"standing":
				if e.size() < 3 or not e[2] is int:
					add(where, "standing takes a faction and a number.")
				elif not Campaign.FACTIONS.has(str(e[1]).to_lower()) and not Campaign.FACTIONS.values().has(str(e[1])):
					add(where, "Unknown faction '%s'. Use one of: %s." % [str(e[1]), ", ".join(Campaign.FACTIONS.values())])
