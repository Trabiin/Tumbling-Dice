extends RefCounted
## Writes a tale (the dictionary the runner plays) as a .tale text file. The inverse of
## tale_parser.gd; used to convert tales written as data, and by the round-trip test.
## The format is described in docs/tale_format.md.

const Parser := preload("res://scripts/rules/tale_parser.gd")


static func write(tale: Dictionary) -> String:
	var out: Array[String] = []
	out.append("title: " + tale.get("title", ""))
	out.append("id: " + tale.get("id", ""))
	if tale.get("patron", "") != "":
		out.append("patron: " + tale.patron)
	out.append("start: " + tale.get("start", ""))
	for id in tale.scenes:
		out.append("")
		_scene(tale.scenes[id], out)
	return "\n".join(out) + "\n"


static func _scene(sc: Dictionary, out: Array[String]) -> void:
	out.append("## %s: %s" % [sc.id, sc.get("title", "")])
	if sc.has("act"):
		out.append("act: %d" % sc.act)
	if sc.get("type", "choice") != "choice":
		out.append("type: " + sc.type)
	if sc.has("goto"):
		out.append("goto: " + sc.goto)
	if not sc.get("on_enter", []).is_empty():
		out.append("on enter: " + effects(sc.on_enter))
	if not sc.get("text", []).is_empty():
		out.append("")
		_lines(sc.text, out, "")
	for o in sc.get("options", []):
		out.append("")
		_option(o, out)
	for en in sc.get("endings", []):
		out.append("")
		out.append("+ %s: %s" % [en.id, en.get("title", "")])
		if en.get("cond", "") != "":
			out.append("  if: " + en.cond)
		_lines(en.get("text", []), out, "  ")
		if not en.get("effects", []).is_empty():
			out.append("  do: " + effects(en.effects))


static func _lines(lines: Array, out: Array[String], indent: String) -> void:
	for line in lines:
		if line is Array:
			out.append(indent + "? %s :: %s" % [line[0], line[1]])
		else:
			out.append(indent + _escape(line))


## A narration line that would read as a marker or a key gets a leading backslash.
static func _escape(text: String) -> String:
	if Parser.looks_special(text):
		return "\\" + text
	return text


static func _option(o: Dictionary, out: Array[String]) -> void:
	out.append("* %s: %s" % [o.id, o.text])
	if o.get("cond", "") != "":
		out.append("  if: " + o.cond)
	if not o.get("temper", {}).is_empty():
		var parts: Array[String] = []
		for k in o.temper:
			parts.append("%s %+d" % [k, o.temper[k]])
		out.append("  temper: " + ", ".join(parts))
	if not o.get("effects", []).is_empty():
		out.append("  do: " + effects(o.effects))
	if o.has("goto"):
		out.append("  goto: " + o.goto)
	if o.get("reply", "") != "":
		out.append("  reply: " + o.reply)
	for kind in ["challenge", "contest", "combat"]:
		if o.has(kind):
			var d: Dictionary = o[kind].duplicate(true)
			var mods: Array = d.get("mods", [])
			d.erase("mods")
			out.append("  %s: %s" % [kind, kv(d)])
			for m in mods:
				out.append("  mod: %s => %s" % [m[0], kv(m[1])])
	for ap in o.get("approaches", []):
		var head: String = "  approach " + ap.aspect
		if not ap.get("set", {}).is_empty():
			head += " [%s]" % kv(ap.set)
		out.append(head + ": " + ap.text)
	var outs: Dictionary = o.get("outcomes", {})
	for key in outs:
		var oc: Dictionary = outs[key]
		out.append("  > %s: %s" % [key, oc.get("text", "")])
		if not oc.get("effects", []).is_empty():
			out.append("    do: " + effects(oc.effects))
		if oc.has("goto"):
			out.append("    goto: " + oc.goto)
		if oc.has("retry"):
			out.append("    retry: " + oc.retry)
		for c in oc.get("costs", []):
			out.append("    cost: %s :: %s" % [c.label, effects(c.effects)])


static func effects(list: Array) -> String:
	return "; ".join(list.map(func(e): return _effect(e)))


static func _effect(e: Array) -> String:
	if e[0] == "if":
		return "if %s then %s" % [e[1], _effect(e[2])]
	var parts: Array[String] = [str(e[0])]
	for i in range(1, e.size()):
		parts.append(value(e[i]))
	return " ".join(parts)


## One value as a token: numbers and true/false bare, lists in [ ], strings quoted when needed.
static func value(v) -> String:
	if v is bool:
		return "true" if v else "false"
	if v is int:
		return str(v)
	if v is float:
		return str(int(v)) if v == int(v) else str(v)
	if v is Array:
		return "[" + ", ".join(v.map(func(x): return value(x))) + "]"
	var s := str(v)
	if s == "" or s.is_valid_int() or s in ["true", "false"] or s.contains(" ") or s.contains(";") \
			or s.contains("\"") or s.contains("[") or s.contains("]") or s.contains(",") or s.contains("="):
		return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
	return s


## key=value pairs; nested dictionaries become dotted keys (second.aspect=ward).
static func kv(d: Dictionary, prefix := "") -> String:
	var parts: Array[String] = []
	for k in d:
		if d[k] is Dictionary:
			parts.append(kv(d[k], prefix + k + "."))
		else:
			parts.append("%s%s=%s" % [prefix, k, value(d[k])])
	return " ".join(parts)
