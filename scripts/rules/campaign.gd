extends RefCounted
## What lasts between tales: the dice you own and how your Pouch is packed, Coin, the Chronicle,
## marks other tales read, Rumours, Standing, endings seen. Saved as one JSON file.

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
		for f in die.faces:
			f.n = int(f.n)
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
	endings_seen = d.get("endings_seen", [])
	tales_played = int(d.get("tales_played", 0))
	map_memory = d.get("map_memory", {})
	forged = int(d.get("forged", 0))
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
