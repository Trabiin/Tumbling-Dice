extends RefCounted
## Where tales come from: .tale text files under res://tales, parsed once and cached.
## Each call returns a fresh copy, so a runner can never change the cached tale.

const Parser := preload("res://scripts/rules/tale_parser.gd")

const DROWNED_BELL := "res://tales/drowned_bell.tale"

static var _cache := {}


## The parse result: {tale, errors: [{line, msg}], lines}. Cached by path.
static func parsed(path: String, reload := false) -> Dictionary:
	if reload or not _cache.has(path):
		_cache[path] = Parser.parse_file(path)
		for e in _cache[path].errors:
			push_error("%s:%d: %s" % [path, e.line, e.msg])
	return _cache[path]


static func load_tale(path: String, reload := false) -> Dictionary:
	return parsed(path, reload).tale.duplicate(true)


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
