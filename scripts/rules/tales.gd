extends RefCounted
## Where tales come from: .tale text files under res://tales, parsed once and cached.
## Each call returns a fresh copy, so a runner can never change the cached tale.

const Parser := preload("res://scripts/rules/tale_parser.gd")

const DROWNED_BELL := "res://tales/drowned_bell.tale"

static var _cache := {}

## Translated tales: res://tales/locale/<code>/<file>.tale stands in for res://tales/<file>.tale when
## the game runs in that language (same ids, so saves carry across languages; see docs/translating.md).
const LOCALE_ROOT := "res://tales/locale"


## The file to read for a tale in a language: its translation if there is one, else the original.
static func localized_path(path: String, locale := "", root := LOCALE_ROOT) -> String:
	if locale == "":
		locale = TranslationServer.get_locale().get_slice("_", 0)
	if locale == "" or locale == "en":
		return path
	var alt := root.path_join(locale).path_join(path.get_file())
	return alt if FileAccess.file_exists(alt) else path


## Every translated tale: [[original path, translated path], ...].
static func translations(root := LOCALE_ROOT) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	for code in d.get_directories():
		var sub := DirAccess.open(root.path_join(code))
		for f in sub.get_files():
			if f.ends_with(".tale"):
				out.append(["res://tales".path_join(f), root.path_join(code).path_join(f)])
	return out


## The parse result: {tale, errors: [{line, msg}], lines}. Cached by path.
static func parsed(path: String, reload := false) -> Dictionary:
	if reload or not _cache.has(path):
		_cache[path] = Parser.parse_file(path)
		for e in _cache[path].errors:
			push_error("%s:%d: %s" % [path, e.line, e.msg])
	return _cache[path]


## The tale is read in the current language when it has a translation; the path stays the original's,
## so saves and the Chronicle never depend on the language.
static func load_tale(path: String, reload := false) -> Dictionary:
	return parsed(localized_path(path), reload).tale.duplicate(true)


static func drowned_bell() -> Dictionary:
	return load_tale(DROWNED_BELL)


## Every .tale file shipped with the game.
static func all_paths() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://tales")
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tale"):
			out.append("res://tales/" + f)
	out.sort()
	return out
