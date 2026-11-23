extends RefCounted
## Reads a .tale text file into the dictionary the tale runner plays. Line-based and forgiving
## about indentation: markers at the start of a line decide what a line belongs to.
##
##   ## id: Title           a scene
##   * id: Text             an option in the current scene
##   > tier: Text           an outcome of the current option (fail, mixed, success, triumph, caught)
##   + id: Title            an ending (in a scene with type: ending)
##   ? condition :: text    a line shown only when the condition holds
##   key: value             a property of whatever came last (scene, option, outcome or ending)
##   anything else          narration for the current scene or ending
##   // comment             ignored; \ at the start of a line forces it to be narration
##
## The full format, with examples, is in docs/tale_format.md.
## parse() returns {tale, errors: [{line, msg}], lines: {path: line}}, where a path is
## "scene", "scene.option" or "scene.option.tier", for the linter to point at the right line.

const SCENE_KEYS := ["act", "type", "goto", "on enter", "tile", "at", "token"]
const OPTION_KEYS := ["if", "temper", "do", "goto", "reply", "challenge", "contest", "combat", "mod"]
const OUTCOME_KEYS := ["do", "goto", "retry", "cost"]
const ENDING_KEYS := ["if", "do", "renown"]
const HEADER_KEYS := ["title", "id", "patron", "start", "arc", "order", "pitch", "offer", "expires", "missed", "teller", "pouch", "saddle", "stakes"]
const TIERS := ["fail", "mixed", "success", "triumph", "caught"]
## choice, encounter and challenge all play as a choice scene; the name is for the writer.
const SCENE_TYPES := ["choice", "encounter", "challenge", "prepare", "waystone", "ending"]


## Does this line start like a marker or a property (so narration needs escaping)?
static func looks_special(text: String) -> bool:
	var t := text.strip_edges()
	for m in ["## ", "* ", "> ", "+ ", "? ", "//", "\\"]:
		if t.begins_with(m):
			return true
	var c := t.find(":")
	if c > 0:
		var key := t.substr(0, c)
		if key in SCENE_KEYS or key in OPTION_KEYS or key in OUTCOME_KEYS or key in HEADER_KEYS or key.begins_with("approach "):
			return true
	return false


static func parse_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"tale": {}, "errors": [{"line": 0, "msg": "Cannot open %s" % path}], "lines": {}}
	return parse(f.get_as_text())


static func parse(src: String) -> Dictionary:
	var p := _State.new()
	var raw := src.split("\n")
	for i in raw.size():
		p.line_no = i + 1
		p.feed(raw[i])
	p.finish()
	return {"tale": p.tale, "errors": p.errors, "lines": p.lines}


class _State:
	var tale := {"patron": "", "scenes": {}}
	var errors: Array = []
	var lines := {}
	var line_no := 0
	var scene = null        # current scene dict
	var option = null
	var outcome = null
	var ending = null
	var outcome_key := ""

	func err(msg: String) -> void:
		errors.append({"line": line_no, "msg": msg})

	func feed(line: String) -> void:
		var t := line.strip_edges()
		if t == "" or t.begins_with("//"):
			return
		if t.begins_with("\\"):
			_narration(t.substr(1))
			return
		if t.begins_with("## "):
			_new_scene(t.substr(3))
			return
		if scene == null:
			_header(t)
			return
		if t.begins_with("* "):
			_new_option(t.substr(2))
			return
		if t.begins_with("> "):
			_new_outcome(t.substr(2))
			return
		if t.begins_with("+ "):
			_new_ending(t.substr(2))
			return
		if t.begins_with("? "):
			var body := t.substr(2)
			var sep := body.find(" :: ")
			if sep < 0:
				err("A conditional line needs ' :: ' between the condition and the text.")
				return
			_add_text([body.substr(0, sep).strip_edges(), body.substr(sep + 4).strip_edges()])
			return
		var kv := _key(t)
		if kv.is_empty():
			_narration(t)
		else:
			_property(kv[0], kv[1])

	func finish() -> void:
		for k in ["title", "id", "start"]:
			if not tale.has(k):
				errors.append({"line": 1, "msg": "The tale has no '%s:' line at the top." % k})

	# -------------------------------------------------------------- structure

	func _header(t: String) -> void:
		var kv := _key(t)
		if kv.is_empty() or not kv[0] in HEADER_KEYS:
			err("Before the first scene only these are allowed: %s." % ", ".join(HEADER_KEYS.map(func(k): return k + ":")))
			return
		if kv[0] == "teller":
			# teller: event :: line   (the Teller's own lines for this tale, e.g. teller: fail :: ...)
			var sep: int = kv[1].find(" :: ")
			if sep < 0:
				err("teller: takes 'event :: line', e.g. 'teller: triumph :: They sang it for a week.'")
				return
			if not tale.has("teller"):
				tale.teller = {}
			var ev: String = kv[1].substr(0, sep).strip_edges()
			if not tale.teller.has(ev):
				tale.teller[ev] = []
			tale.teller[ev].append(kv[1].substr(sep + 4).strip_edges())
			return
		tale[kv[0]] = kv[1]

	func _id_title(t: String) -> Array:
		var c := t.find(":")
		if c < 0:
			return [t.strip_edges(), ""]
		return [t.substr(0, c).strip_edges(), t.substr(c + 1).strip_edges()]

	func _new_scene(t: String) -> void:
		var it := _id_title(t)
		if it[0] == "" or it[0].contains(" "):
			err("A scene id is one word with no spaces: '## id: Title'.")
		if tale.scenes.has(it[0]):
			err("Scene '%s' is defined twice." % it[0])
		scene = {"id": it[0], "title": it[1], "type": "choice"}
		tale.scenes[it[0]] = scene
		lines[it[0]] = line_no
		option = null
		outcome = null
		ending = null

	func _new_option(t: String) -> void:
		if scene.type == "ending":
			err("An ending scene has endings (+), not options (*).")
		var it := _id_title(t)
		option = {"id": it[0], "text": it[1]}
		if not scene.has("options"):
			scene.options = []
		for o in scene.options:
			if o.id == it[0]:
				err("Option '%s' appears twice in scene '%s'." % [it[0], scene.id])
		scene.options.append(option)
		lines["%s.%s" % [scene.id, it[0]]] = line_no
		outcome = null
		ending = null

	func _new_outcome(t: String) -> void:
		if option == null:
			err("An outcome (>) must follow an option (*).")
			return
		var it := _id_title(t)
		if not it[0] in TIERS:
			err("Unknown outcome '%s'. Use fail, mixed, success, triumph or caught." % it[0])
		if not option.has("outcomes"):
			option.outcomes = {}
		outcome = {"text": it[1]}
		option.outcomes[it[0]] = outcome
		outcome_key = it[0]
		lines["%s.%s.%s" % [scene.id, option.id, it[0]]] = line_no

	func _new_ending(t: String) -> void:
		if scene.type != "ending":
			err("Endings (+) belong in a scene with 'type: ending'.")
		var it := _id_title(t)
		ending = {"id": it[0], "title": it[1], "cond": "", "text": [], "effects": []}
		if not scene.has("endings"):
			scene.endings = []
		scene.endings.append(ending)
		lines["%s.%s" % [scene.id, it[0]]] = line_no
		option = null
		outcome = null

	# -------------------------------------------------------------- content

	func _narration(t: String) -> void:
		if outcome != null:
			# Continuation of the outcome's text.
			outcome.text = (outcome.text + " " + t).strip_edges()
		elif option != null:
			err("Text after an option must be a property (if:, do:, goto: ...) or an outcome (>). Start the line with \\ if it really is narration.")
		else:
			_add_text(t)

	func _add_text(item) -> void:
		if ending != null:
			ending.text.append(item)
		elif option != null or outcome != null:
			err("Conditional lines belong to a scene or an ending, not to an option.")
		else:
			if not scene.has("text"):
				scene.text = []
			scene.text.append(item)

	func _key(t: String) -> Array:
		var c := t.find(":")
		if c <= 0:
			return []
		var key := t.substr(0, c).strip_edges()
		if not (key in SCENE_KEYS or key in OPTION_KEYS or key in OUTCOME_KEYS or key in ENDING_KEYS or key in HEADER_KEYS or key.begins_with("approach ")):
			return []
		return [key, t.substr(c + 1).strip_edges()]

	func _property(key: String, val: String) -> void:
		if outcome != null:
			_outcome_prop(key, val)
		elif ending != null:
			_ending_prop(key, val)
		elif option != null:
			_option_prop(key, val)
		else:
			_scene_prop(key, val)

	func _scene_prop(key: String, val: String) -> void:
		match key:
			"act":
				if not val.is_valid_int():
					err("act: takes a number.")
				scene.act = int(val)
			"type":
				if not val in SCENE_TYPES:
					err("Unknown scene type '%s'. Use choice, encounter, challenge, prepare, waystone or ending." % val)
				scene.type = val
			"goto":
				scene.goto = val
			"on enter":
				scene.on_enter = _effects(val)
			"tile":
				scene.tile = val
			"at":
				var xy := val.split(",")
				if xy.size() != 2 or not xy[0].strip_edges().is_valid_float() or not xy[1].strip_edges().is_valid_float():
					err("at: takes two numbers, 'at: 3, -1.5' (across, then toward you).")
					return
				scene.at = Vector2(float(xy[0]), float(xy[1]))
			"token":
				var sep := val.find("=>")
				var rest := Lex.tokens(val.substr(sep + 2)) if sep >= 0 else []
				if sep < 0 or rest.is_empty():
					err("token: takes 'condition => icon \"label\"', e.g. 'token: gold_taken => coins \"The bell's gold, taken\"'.")
					return
				if not scene.has("tokens"):
					scene.tokens = []
				var label = Lex.value(rest[1]) if rest.size() > 1 else ""
				scene.tokens.append({"cond": val.substr(0, sep).strip_edges(), "icon": String(rest[0]), "label": str(label)})
			_:
				err("'%s:' does not belong to a scene." % key)

	func _option_prop(key: String, val: String) -> void:
		if key.begins_with("approach "):
			_approach(key.substr(9), val)
			return
		match key:
			"if":
				option.cond = val
			"temper":
				var d := {}
				for part in val.split(","):
					var bits := part.strip_edges().split(" ", false)
					if bits.size() != 2 or not bits[1].is_valid_int():
						err("temper: takes 'track +n', e.g. 'temper: duty +1, mercy -1'.")
						continue
					d[bits[0]] = int(bits[1])
				option.temper = d
			"do":
				option.effects = _effects(val)
			"goto":
				option.goto = val
			"reply":
				option.reply = val
			"challenge", "contest", "combat":
				option[key] = Lex.kv(val, self)
			"mod":
				var sep := val.find("=>")
				var kind := ""
				for k in ["challenge", "contest", "combat"]:
					if option.has(k):
						kind = k
				if sep < 0 or kind == "":
					err("mod: comes after challenge:, contest: or combat:, as 'mod: condition => key=value'.")
					return
				if not option[kind].has("mods"):
					option[kind].mods = []
				option[kind].mods.append([val.substr(0, sep).strip_edges(), Lex.kv(val.substr(sep + 2), self)])
			_:
				err("'%s:' does not belong to an option." % key)

	func _approach(head: String, text: String) -> void:
		var aspect := head.strip_edges()
		var ap := {}
		var b := aspect.find("[")
		if b >= 0:
			var e := aspect.rfind("]")
			if e < b:
				err("approach overrides go in [ ]: 'approach might [progress=19]: text'.")
				return
			ap.set = Lex.kv(aspect.substr(b + 1, e - b - 1), self)
			aspect = aspect.substr(0, b).strip_edges()
		var result := {"aspect": aspect, "text": text}
		if ap.has("set"):
			result.set = ap.set
		if not option.has("approaches"):
			option.approaches = []
		option.approaches.append(result)

	func _outcome_prop(key: String, val: String) -> void:
		match key:
			"do":
				outcome.effects = _effects(val)
			"goto":
				outcome.goto = val
			"retry":
				outcome.retry = val
			"cost":
				var sep := val.find(" :: ")
				if sep < 0:
					err("cost: takes 'label :: effects', e.g. 'cost: Lose 3 Grit :: grit -3'.")
					return
				if not outcome.has("costs"):
					outcome.costs = []
				outcome.costs.append({"label": val.substr(0, sep).strip_edges(), "effects": _effects(val.substr(sep + 4))})
			_:
				# An option property after an outcome is a common slip; say so plainly.
				err("'%s:' does not belong to an outcome (option properties go before the first >)." % key)

	func _ending_prop(key: String, val: String) -> void:
		match key:
			"if":
				ending.cond = val
			"do":
				ending.effects = _effects(val)
			"renown":
				if not val.is_valid_int():
					err("renown: takes a number (0 to 5).")
				ending.renown = int(val)
			_:
				err("'%s:' does not belong to an ending." % key)

	func _effects(val: String) -> Array:
		var out: Array = []
		for part in Lex.split_top(val, ";"):
			var e = Lex.effect(part.strip_edges(), self)
			if e != null:
				out.append(e)
		return out


## Tokens: quoted strings, [lists], numbers, true/false, bare words.
class Lex:
	static func split_top(s: String, sep: String) -> Array:
		var out: Array = []
		var cur := ""
		var q := false
		var depth := 0
		var i := 0
		while i < s.length():
			var ch := s[i]
			if ch == "\\" and q and i + 1 < s.length():
				cur += ch + s[i + 1]
				i += 2
				continue
			if ch == "\"":
				q = not q
			elif not q and ch == "[":
				depth += 1
			elif not q and ch == "]":
				depth -= 1
			if ch == sep and not q and depth == 0:
				out.append(cur)
				cur = ""
			else:
				cur += ch
			i += 1
		if cur.strip_edges() != "":
			out.append(cur)
		return out

	static func tokens(s: String) -> Array:
		return split_top(s.strip_edges(), " ").filter(func(x): return x.strip_edges() != "")

	static func value(tok: String):
		var t := tok.strip_edges()
		if t.begins_with("\"") and t.ends_with("\"") and t.length() >= 2:
			return t.substr(1, t.length() - 2).replace("\\\"", "\"").replace("\\\\", "\\")
		if t.begins_with("[") and t.ends_with("]"):
			var inner := t.substr(1, t.length() - 2)
			return split_top(inner, ",").map(func(x): return value(x))
		if t.is_valid_int():
			return int(t)
		if t == "true":
			return true
		if t == "false":
			return false
		return t

	static func effect(s: String, st):
		if s == "":
			return null
		if s.begins_with("if "):
			var k := s.find(" then ")
			if k < 0:
				st.err("A conditional effect reads 'if condition then effect'.")
				return null
			return ["if", s.substr(3, k - 3).strip_edges(), effect(s.substr(k + 6).strip_edges(), st)]
		var toks := tokens(s)
		var e: Array = [toks[0]]
		for i in range(1, toks.size()):
			e.append(value(toks[i]))
		return e

	static func kv(s: String, st) -> Dictionary:
		var d := {}
		for tok in tokens(s):
			var eq: int = tok.find("=")
			if eq <= 0:
				st.err("Expected key=value, got '%s'." % tok)
				continue
			var path: Array = tok.substr(0, eq).split(".")
			var target := d
			for i in path.size() - 1:
				if not target.has(path[i]):
					target[path[i]] = {}
				target = target[path[i]]
			target[path[-1]] = value(tok.substr(eq + 1))
		return d
