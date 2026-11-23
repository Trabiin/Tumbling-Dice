extends SceneTree
## Writes the translation template res://locale/tumbling_dice.pot from the interface text in the
## game's scripts: every tr("..."), the text given to UI labels, buttons and card titles, tooltips,
## and lines the tavern says. Tales are translated as whole files instead (see i18n.gd).
##
##   godot --headless -s res://tools/extract_strings.gd
##   godot --headless -s res://tools/extract_strings.gd -- --check    (fails if the .pot is stale)
##
## A translator copies the .pot to res://locale/<code>.po (de.po, fr.po...) and fills in msgstr.

const I18n := preload("res://scripts/game/i18n.gd")
const OUT := "res://locale/tumbling_dice.pot"
const ROOTS := ["res://scripts"]

## The string literal at the start of these calls and assignments is interface text.
const PATTERNS := [
	"\\btr\\(\\s*",
	"\\bUI\\.(?:label|wrap_label|seal_button|card_button)\\(\\s*",
	"\\b_card_title\\(\\s*",
	"\\b(?:_header|say)\\(\\s*",
	"\\b(?:tooltip_text|text)\\s*=\\s*",
	"\"(?:name|text|label)\"\\s*:\\s*",
]


func _init() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var found := collect()
	var text := pot(found)
	if check:
		var old := FileAccess.get_file_as_string(OUT)
		var same := _body(old) == _body(text)
		print("translation template %s (%d strings)" % ["up to date" if same else "is stale: run tools/extract_strings.gd", found.size()])
		quit(0 if same else 1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote %s: %d strings" % [OUT, found.size()])
	quit(0)


## {msgid: ["file:line", ...]} in a stable order.
static func collect() -> Dictionary:
	var res: Array[RegEx] = []
	for p in PATTERNS:
		var r := RegEx.new()
		r.compile(p + "\"((?:[^\"\\\\]|\\\\.)*)\"")
		res.append(r)
	var found := {}
	for path in _scripts():
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			for r in res:
				for m in r.search_all(line):
					var s := m.get_string(1).c_unescape()
					if not _wanted(s):
						continue
					if not found.has(s):
						found[s] = []
					found[s].append("%s:%d" % [path.trim_prefix("res://"), i + 1])
	return found


static func _wanted(s: String) -> bool:
	if s.strip_edges() == "" or s.length() < 2:
		return false
	# Ids, paths, colours and BBCode-only strings are not for translators.
	if s.begins_with("res://") or s.begins_with("user://") or s.begins_with("#") or s.begins_with("["):
		return false
	var r := RegEx.new()
	r.compile("^[a-z0-9_./:%-]+$")
	if r.search(s) != null:
		return false
	# Something to translate: a word of three letters or more, once format codes are taken out.
	var spec := RegEx.new()
	spec.compile("%[-+0-9.]*[dsf]")
	var word := RegEx.new()
	word.compile("[A-Za-z]{3}")
	return word.search(spec.sub(s, "", true)) != null


static func _scripts() -> Array:
	var out: Array = []
	var stack: Array = ROOTS.duplicate()
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append(dir.path_join(sub))
		for f in d.get_files():
			if f.ends_with(".gd"):
				out.append(dir.path_join(f))
	out.sort()
	return out


static func pot(found: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("# Tales of the Tumbling Dice: interface text.\n# Made by tools/extract_strings.gd; do not edit by hand.\nmsgid \"\"\nmsgstr \"\"\n\"Content-Type: text/plain; charset=UTF-8\\n\"\n")
	var keys := found.keys()
	keys.sort()
	for k in keys:
		var refs: Array = found[k]
		parts.append("#: %s\nmsgid %s\nmsgstr \"\"\n" % [" ".join(refs.slice(0, 4)), I18n.po_quote(k)])
	return "\n".join(parts)


## The template without its reference comments, for --check (line numbers move all the time).
static func _body(t: String) -> String:
	var keep: Array[String] = []
	for l in t.split("\n"):
		if not l.begins_with("#:"):
			keep.append(l)
	return "\n".join(keep)
