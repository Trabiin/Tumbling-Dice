extends RefCounted
## What lasts between tales: the dice you own and how your Pouch is packed, Coin, the Chronicle,
## marks other tales read, Rumours, Standing, endings seen. Saved as one JSON file.
##
## M5 adds the campaign around the tales: the calendar (nights and four seasons), Renown (which
## raises the Pouch's weight limit), Wounds you carry home, forging materials and Brannoc's
## trust, and what happened in every tale you told (read by later tales: `ending:drowned_bell==rest`).
## The rules that move the calendar on and decide which tales patrons offer are in patrons.gd.

const Dice := preload("res://scripts/rules/dice.gd")
const Pouch := preload("res://scripts/rules/pouch.gd")

const SAVE_PATH := "user://campaign.json"

var pouch = Pouch.new()
var coin := 0
var chronicle: Array = []
var marks := {}
var rumours: Array = []
var standing := {}
var shards: Array = []
var endings_seen: Array = []
var tales_played := 0
var map_memory := {}           # tale id -> scene ids walked in any telling (the board remembers)
var forged := 0                # times the Dicewright has worked for you

const SEASONS := ["spring", "summer", "autumn", "winter"]
const NIGHTS_PER_SEASON := 6
const YEAR_NIGHTS := 24
## Renown needed for each extra point of Pouch weight (12 at the start, 20 at most).
const RENOWN_STEPS := [3, 7, 12, 18, 25, 33, 42, 52]
const BASE_WEIGHT := 12
const BASE_SADDLE := 4
## Wounds you can carry home. The second (TaleState.MAX_WOUNDS) loses a tale, so at most one comes back with you.
const MAX_CARRIED_WOUNDS := 1
## Factions as tales name them, and the short ids conditions use (standing:guild>=1).
const FACTIONS := {"guild": "Thieves' Guild", "abbey": "Abbey", "crown": "The Crown", "holloway": "Holloway",
	"marrowmere": "Marrowmere", "wood": "The Old Wood"}
const STANDING_CAP := 3

var night := 1                 # the night you are on; a tale takes one
var renown := 0
var wounds: Array = []         # Wounds carried between tales, until Sister Maud treats them
var materials := {}            # forging materials by id -> count (lead, binding_lore, heartwood...)
var trust := 0                 # Brannoc's trust, earned by bringing him rare materials
var tales := {}                # tale id -> {told, ending, won, night, endings: []}
var missed: Array = []         # tale ids that went by without you
var rumour_ids: Array = []     # rumours by id, for conditions (rumour:tide_turn)
var events_seen: Array = []    # season events that have already happened
var debts := {}                # who you owe: "maud" -> nights of work, etc.
var mood := 0                  # the Teller's Mood, 0 (Fair) to 5 (Black): see mood.gd
var mood_best := 0             # the highest Mood a tale has been won at (unlocks felts)
var story_mode := false        # Story mode: Grit doubled, Defy always free
var felt := 0                  # which table felt the tray wears


func new_campaign() -> void:
	pouch = Pouch.new()
	pouch.collection = Dice.starter_collection()
	coin = 10
	chronicle.clear()
	marks.clear()
	rumours.clear()
	standing.clear()
	shards.clear()
	endings_seen.clear()
	tales_played = 0
	map_memory.clear()
	forged = 0
	night = 1
	renown = 0
	wounds.clear()
	materials.clear()
	trust = 0
	tales.clear()
	missed.clear()
	rumour_ids.clear()
	events_seen.clear()
	debts.clear()
	mood = 0
	mood_best = 0
	story_mode = false
	felt = 0
	apply_renown()


func has_mark(m: String) -> bool:
	return marks.has(m)


func mark(m: String) -> void:
	marks[m] = true


## Scenes walked in earlier tellings show on the tale board as remembered roads, not fog.
func remember_map(tale_id: String, visited: Array) -> void:
	var seen: Array = map_memory.get(tale_id, [])
	for id in visited:
		if not seen.has(id):
			seen.append(id)
	map_memory[tale_id] = seen


func map_seen(tale_id: String) -> Array:
	return map_memory.get(tale_id, [])


# ------------------------------------------------------------------ the calendar

func season() -> String:
	return SEASONS[clampi((night - 1) / NIGHTS_PER_SEASON, 0, 3)]


func season_index() -> int:
	return clampi((night - 1) / NIGHTS_PER_SEASON, 0, 3)


## Night within the season, 1 to 6.
func season_night() -> int:
	if night > YEAR_NIGHTS:
		return NIGHTS_PER_SEASON
	return (night - 1) % NIGHTS_PER_SEASON + 1


func year_over() -> bool:
	return night > YEAR_NIGHTS


func calendar_text() -> String:
	if year_over():
		return "The year is out (night %d)" % night
	return "Night %d of %s" % [season_night(), season()]


# ------------------------------------------------------------------ Renown

func renown_level() -> int:
	var lvl := 0
	for s in RENOWN_STEPS:
		if renown >= s:
			lvl += 1
	return lvl


## Renown still needed for the next point of Pouch weight, or -1 at the top.
func renown_to_next() -> int:
	for s in RENOWN_STEPS:
		if renown < s:
			return s - renown
	return -1


func apply_renown() -> void:
	pouch.weight_limit = BASE_WEIGHT + renown_level()
	pouch.saddle_limit = BASE_SADDLE + (1 if renown_level() >= 3 else 0) + (1 if renown_level() >= 6 else 0)


func add_renown(n: int) -> int:
	var before := renown_level()
	renown += maxi(0, n)
	apply_renown()
	return renown_level() - before


# ------------------------------------------------------------------ Standing

static func faction_name(f: String) -> String:
	return FACTIONS.get(f.to_lower(), f)


func standing_of(f: String) -> int:
	return int(standing.get(faction_name(f), 0))


func add_standing(f: String, n: int) -> void:
	var k := faction_name(f)
	standing[k] = clampi(int(standing.get(k, 0)) + n, -STANDING_CAP, STANDING_CAP)


# ------------------------------------------------------------------ what happened in each tale

func told(tale_id: String) -> bool:
	return tales.has(tale_id)


## The tale ended without defeat.
func done(tale_id: String) -> bool:
	return tales.has(tale_id) and bool(tales[tale_id].get("won", false))


## The tale ended in defeat. A defeat is an ending like any other: the tale is told, patrons do
## not offer it again, and the tales after it read how you fell.
func fell(tale_id: String) -> bool:
	return tales.has(tale_id) and not bool(tales[tale_id].get("won", false))


## How a tale ended: the last ending that was not a defeat, or the defeat if that is all there is.
func ending_of(tale_id: String) -> String:
	return String(tales.get(tale_id, {}).get("ending", ""))


func record_tale(tale_id: String, ending: String, won: bool) -> void:
	var t: Dictionary = tales.get(tale_id, {"told": 0, "ending": "", "won": false, "endings": []})
	t.told = int(t.get("told", 0)) + 1
	t.night = night
	if won or not bool(t.get("won", false)):
		t.ending = ending
	t.won = bool(t.get("won", false)) or won
	var ends: Array = t.get("endings", [])
	if not ends.has(ending):
		ends.append(ending)
	t.endings = ends
	tales[tale_id] = t


# ------------------------------------------------------------------ materials

func material_count(m: String) -> int:
	return int(materials.get(m, 0))


func add_material(m: String, n := 1) -> void:
	materials[m] = maxi(0, material_count(m) + n)
	if materials[m] == 0:
		materials.erase(m)


func add_coin(n: int) -> int:
	var before := coin
	coin = maxi(0, coin + n)
	return coin - before


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"collection": pouch.collection,
		"pouch": pouch.pouch.map(func(d): return d.id),
		"saddlebag": pouch.saddlebag.map(func(d): return d.id),
		"weight_limit": pouch.weight_limit,
		"coin": coin, "chronicle": chronicle, "marks": marks, "rumours": rumours,
		"standing": standing, "shards": shards, "endings_seen": endings_seen, "tales_played": tales_played,
		"map_memory": map_memory, "forged": forged,
		"night": night, "renown": renown, "wounds": wounds, "materials": materials, "trust": trust,
		"tales": tales, "missed": missed, "rumour_ids": rumour_ids, "events_seen": events_seen, "debts": debts,
		"mood": mood, "mood_best": mood_best, "story_mode": story_mode, "felt": felt,
	}


func from_dict(d: Dictionary) -> void:
	pouch = Pouch.new()
	pouch.collection = []
	for die in d.get("collection", []):
		# JSON numbers come back as floats; dice want ints.
		die.sides = int(die.sides)
		die.weight = int(die.weight)
		die.notches = int(die.get("notches", 0))
		if die.has("loaded_face"):
			die.loaded_face = int(die.loaded_face)
		if die.has("carved"):
			die.carved = int(die.carved)
		for f in die.faces:
			f.n = int(f.n)
			if f.has("crack"):
				f.crack = int(f.crack)
		pouch.collection.append(die)
	var by_id := {}
	for die in pouch.collection:
		by_id[die.id] = die
	for id in d.get("pouch", []):
		if by_id.has(id):
			pouch.pouch.append(by_id[id])
	for id in d.get("saddlebag", []):
		if by_id.has(id):
			pouch.saddlebag.append(by_id[id])
	pouch.weight_limit = int(d.get("weight_limit", 12))
	coin = int(d.get("coin", 0))
	chronicle = d.get("chronicle", [])
	marks = d.get("marks", {})
	rumours = d.get("rumours", [])
	standing = d.get("standing", {})
	shards = d.get("shards", [])
	endings_seen = d.get("endings_seen", []).map(func(e): return e if String(e).contains(":") else "drowned_bell:" + String(e))
	tales_played = int(d.get("tales_played", 0))
	map_memory = d.get("map_memory", {})
	forged = int(d.get("forged", 0))
	night = int(d.get("night", 1))
	renown = int(d.get("renown", 0))
	wounds = d.get("wounds", []).slice(0, MAX_CARRIED_WOUNDS)
	materials = {}
	var mats: Dictionary = d.get("materials", {})
	for k in mats:
		materials[k] = int(mats[k])
	trust = int(d.get("trust", 0))
	tales = d.get("tales", {})
	for k in tales:
		tales[k].told = int(tales[k].get("told", 1))
		tales[k].night = int(tales[k].get("night", 0))
	missed = d.get("missed", [])
	rumour_ids = d.get("rumour_ids", [])
	events_seen = d.get("events_seen", [])
	debts = d.get("debts", {})
	mood = int(d.get("mood", 0))
	mood_best = int(d.get("mood_best", 0))
	story_mode = bool(d.get("story_mode", false))
	felt = int(d.get("felt", 0))
	for k in standing:
		standing[k] = int(standing[k])
	apply_renown()
	Dice._serial = maxi(Dice._serial, pouch.collection.size() * 10 + 1000)


func save(path := SAVE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))


func load_save(path := SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return false
	from_dict(data)
	return true
