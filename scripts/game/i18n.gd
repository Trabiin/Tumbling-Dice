extends RefCounted
## Translation support.
##
## Interface text: res://locale/<code>.po files (standard gettext, made from the template
## res://locale/tumbling_dice.pot that tools/extract_strings.gd writes). They are read at start-up
## by this small loader rather than imported, so a translator can drop a .po file in and run the
## game, with no editor step. Labels and buttons translate their text automatically; formatted
## text goes through tr() before the values are filled in.
##
## Tales: a translated tale is a whole .tale file at res://tales/locale/<code>/<same name>.tale,
## with the same scene, option and ending ids (tales.gd picks it up; the linter checks the ids).

const LOCALE_DIR := "res://locale"
const NAMES := {"en": "English", "de": "Deutsch", "fr": "Français", "es": "Español", "it": "Italiano",
	"nl": "Nederlands", "pl": "Polski", "pt": "Português", "sv": "Svenska", "ja": "日本語", "zh": "中文"}

static var loaded: Array[String] = ["en"]


## Load every .po file and set the language ("" follows the system).
static func setup(locale: String) -> void:
	loaded = ["en"]
	var d := DirAccess.open(LOCALE_DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".po"):
				var t := load_po(LOCALE_DIR.path_join(f))
				if t != null:
					TranslationServer.add_translation(t)
					loaded.append(t.locale)
	set_locale(locale)


static func set_locale(locale: String) -> void:
	var want := locale if locale != "" else OS.get_locale_language()
	TranslationServer.set_locale(want if want in loaded else "en")


static func current() -> String:
	var l := TranslationServer.get_locale().get_slice("_", 0)
	return l if l in loaded else "en"


static func name_of(code: String) -> String:
	return NAMES.get(code, code)


## A minimal gettext .po reader: msgctxt is ignored, plural forms take the first form.
static func load_po(path: String) -> Translation:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var t := Translation.new()
	t.locale = path.get_file().get_basename()
	var msgs := parse_po(f.get_as_text())
	for k in msgs:
		if k != "" and msgs[k] != "":
			t.add_message(k, msgs[k])
	return t


## {msgid: msgstr} from .po text. The header entry (empty msgid) is kept under "".
static func parse_po(text: String) -> Dictionary:
	var out := {}
	var id := ""
	var str_ := ""
	var field := ""
	var have := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#") or line == "":
			if have:
				out[id] = str_
				have = false
				id = ""
				str_ = ""
			field = ""
			continue
		if line.begins_with("msgid_plural"):
			field = "skip"
		elif line.begins_with("msgid "):
			if have:
				out[id] = str_
				str_ = ""
			id = _unquote(line.substr(6))
			field = "id"
			have = true
		elif line.begins_with("msgstr[0] "):
			str_ = _unquote(line.substr(10))
			field = "str"
		elif line.begins_with("msgstr["):
			field = "skip"
		elif line.begins_with("msgstr "):
			str_ = _unquote(line.substr(7))
			field = "str"
		elif line.begins_with("msgctxt"):
			field = "skip"
		elif line.begins_with("\""):
			match field:
				"id": id += _unquote(line)
				"str": str_ += _unquote(line)
	if have:
		out[id] = str_
	return out


static func _unquote(s: String) -> String:
	s = s.strip_edges()
	if s.begins_with("\"") and s.ends_with("\"") and s.length() >= 2:
		s = s.substr(1, s.length() - 2)
	return s.c_unescape()


## Quote a string for a .po file.
static func po_quote(s: String) -> String:
	return "\"" + s.c_escape().replace("\\'", "'") + "\""
