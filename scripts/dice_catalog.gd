extends RefCounted
## Data-only dice definitions. Everything visual is generated from these numbers.
##
## A theme describes the look of a matching set; make_set() turns it into the classic
## seven-piece tabletop set: d4, d6, d8, d10, d% (percentile), d12, d20.

static func themes() -> Array[Dictionary]:
	return [
		{"name": "Dragon's Blood",
			"a": Color("#c4231c"), "b": Color("#4a0608"), "swirl": 1.3, "scale": 1.4, "rough": 0.26,
			"sparkle": 0.6, "sparkle_color": Color("#ffb347"),
			"ink": Color("#f0c75e"), "ink_outline": Color("#3b1d00")},
		{"name": "Ancient Bone",
			"a": Color("#efe3c4"), "b": Color("#b9a27a"), "swirl": 0.6, "scale": 1.2, "contrast": 0.5, "rough": 0.55,
			"ink": Color("#3a1f10"), "ink_outline": Color("#7a5a3a")},
		{"name": "Elven Jade",
			"a": Color("#1f7a52"), "b": Color("#d8efe0"), "swirl": 1.8, "scale": 1.4, "rough": 0.25,
			"ink": Color("#f4f4f4"), "ink_outline": Color("#0d3324")},
		{"name": "Dwarven Brass",
			"a": Color("#c9a04a"), "b": Color("#8a6222"), "swirl": 0.4, "scale": 3.0, "contrast": 0.6,
			"metal": 0.85, "rough": 0.28,
			"ink": Color("#1c130a"), "ink_outline": Color("#5c4317")},
		{"name": "Arcane Amethyst",
			"a": Color("#6a32c0"), "b": Color("#1c0f40"), "swirl": 1.6, "scale": 1.8, "rough": 0.28,
			"sparkle": 1.0, "sparkle_color": Color("#b7c7ff"),
			"ink": Color("#e9e2ff"), "ink_outline": Color("#1a0b3d")},
	]


static func make_set(theme: Dictionary) -> Array[Dictionary]:
	var d10_labels := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
	var pct_labels := ["10", "20", "30", "40", "50", "60", "70", "80", "90", "00"]
	return [
		{"name": "d4", "sides": 4, "style": theme},
		{"name": "d6", "sides": 6, "style": theme},
		{"name": "d8", "sides": 8, "style": theme},
		{"name": "d10", "sides": 10, "style": theme, "labels": d10_labels, "numeric": true},
		{"name": "d%", "sides": 10, "style": theme, "labels": pct_labels, "percentile": true},
		{"name": "d12", "sides": 12, "style": theme},
		{"name": "d20", "sides": 20, "style": theme},
	]


## Two special dice that show off the variants.
static func extras() -> Array[Dictionary]:
	return [
		# Weighted: centre of mass pulled toward the 1, so the 6 tends to land up.
		{"name": "Loaded d6", "sides": 6, "loaded_face": 6, "load": 0.3,
			"style": {"a": Color("#e8dcc0"), "b": Color("#8c7a5a"), "swirl": 0.8, "scale": 1.0, "contrast": 0.6,
				"rough": 0.6, "ink": Color("#5a0a0a"), "ink_outline": Color("#2a0505")}},
		# Words instead of numbers: an RPG action die.
		{"name": "Combat d6", "sides": 6, "labels": ["MISS", "ATK", "ATK", "DEF", "HEAL", "CRIT"],
			"style": {"a": Color("#5a6470"), "b": Color("#2a3038"), "swirl": 0.5, "scale": 2.5, "contrast": 0.7,
				"metal": 0.85, "rough": 0.4, "ink": Color("#ffd27a"), "ink_outline": Color("#2b1a00")}},
	]


## Everything, for the fairness test.
static func default_set() -> Array[Dictionary]:
	var all := make_set(themes()[0])
	all.append_array(extras())
	return all
