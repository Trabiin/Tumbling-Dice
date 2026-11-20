extends RefCounted
## Everything one playthrough of a tale remembers: Grit, Fate, Wounds, flags, temperament,
## the Teller's regard, what you gained and lost. Campaign-wide memory lives in campaign.gd.

const S := preload("res://scripts/rules/scoring.gd")

const FATE_CAP := 6
const MAX_WOUNDS := 3
const START_GRIT := 20
const START_FATE := 3

## Wounds are named negative rules. Three of them and the tale is lost.
const WOUNDS := {
	"Waterlogged Lungs": "Hand size -1.",
	"Cracked Ribs": "Maximum Grit -4.",
	"Shaking Hands": "Your d12s and d20s count 2 less.",
	"Lake Chill": "You cannot gain Fate.",
	"Bitten": "Mend runes restore only 1 Grit.",
	"Arrow in the Shoulder": "Your first throw in every fight is one die short.",
	"Frostbite": "Maximum Grit -3.",
	"Broken Hand": "Your d4s and d6s count 1 less.",
	"Fever": "You start each tale with 1 Fate fewer.",
}
const WOUND_ORDER := ["Cracked Ribs", "Shaking Hands", "Bitten"]

var grit := START_GRIT
var grit_max := START_GRIT
var fate := START_FATE
var wounds: Array = []
var flags := {}
## Temperament: + is Mercy / Honesty / Duty, - is Ruthlessness / Cunning / Freedom.
## Neither end gives a bonus; each opens its own doors.
var temper := {"mercy": 0, "honesty": 0, "duty": 0}
var regard := 0                # the Teller's hidden opinion of you
var defy_used := false
var fail_streak := 0
var wager = null               # the die staked on the tale
var visited: Array = []
var chronicle: Array = []      # entries written at the ending
var gained: Array = []         # dice gained this tale
var lost: Array = []
var rumours: Array = []
var standing := {}             # faction -> delta this tale
var shards: Array = []
var coin := 0                  # coin earned this tale
var ending := ""
var throws := 0
var choices: Array = []        # [scene_id, option_id] for telemetry and the pick-rate check
var marks: Array = []          # tokens left on the tale board by play itself, e.g. a fallen foe
var rumour_ids: Array = []     # rumours by id, picked up this tale
var materials: Array = []      # forging materials found this tale
var lifted: Array = []         # curses lifted this tale (die names)
var carried: Array = []        # Wounds brought from the tavern (for the ending's tally)
var triumphs := 0


const SAVED := ["grit", "grit_max", "fate", "wounds", "flags", "temper", "regard", "defy_used", "fail_streak",
	"visited", "chronicle", "rumours", "standing", "shards", "coin", "ending", "throws", "choices", "marks",
	"rumour_ids", "materials", "lifted", "carried", "triumphs"]


## For a mid-tale save. Dice are saved whole (a lost die is no longer in the collection).
func to_dict() -> Dictionary:
	var d := {}
	for k in SAVED:
		d[k] = get(k)
	d.wager = wager
	d.gained = gained
	d.lost = lost
	return d


## by_id maps die ids to the restored collection's dice, so a gained die is the same object.
func from_dict(d: Dictionary, by_id: Dictionary) -> void:
	for k in SAVED:
		if d.has(k):
			var v = d[k]
			# JSON numbers come back as floats.
			if get(k) is int:
				v = int(v)
			set(k, v)
	for k in temper:
		temper[k] = int(temper[k])
	for k in standing:
		standing[k] = int(standing[k])
	for k in flags:
		if flags[k] is float and flags[k] == int(flags[k]):
			flags[k] = int(flags[k])
	var pick = func(x): return by_id.get(x.id, x) if x is Dictionary else x
	wager = pick.call(d.get("wager")) if d.get("wager") != null else null
	gained = d.get("gained", []).map(pick)
	lost = d.get("lost", [])


func flag(name: String):
	return flags.get(name, false)


func num(name: String) -> int:
	var v = flags.get(name, 0)
	if v is bool:
		return 1 if v else 0
	return int(v)


func set_flag(name: String, value = true) -> void:
	flags[name] = value


func add_grit(n: int) -> int:
	var before := grit
	grit = clampi(grit + n, -99, grit_max)
	return grit - before


func add_fate(n: int) -> int:
	var before := fate
	if n > 0 and wounds.has("Lake Chill"):
		return 0
	fate = clampi(fate + n, 0, FATE_CAP)
	return fate - before


## Add a Wound by name, or the next one in order when name is empty. Returns its name.
func add_wound(name := "") -> String:
	if name == "" or wounds.has(name):
		name = ""
		for w in WOUND_ORDER:
			if not wounds.has(w):
				name = w
				break
		if name == "":
			name = "Cracked Ribs (again)"
	wounds.append(name)
	_apply_wound(name)
	return name


func _apply_wound(name: String) -> void:
	match name:
		"Cracked Ribs":
			grit_max -= 4
			grit = mini(grit, grit_max)
		"Frostbite":
			grit_max -= 3
			grit = mini(grit, grit_max)


## Wounds carried in from the tavern take hold at the start of the tale.
func carry_in(list: Array) -> void:
	for w in list:
		wounds.append(String(w))
		carried.append(String(w))
		_apply_wound(String(w))
	if wounds.has("Fever"):
		fate = maxi(0, fate - 1)


func wound_count() -> int:
	return wounds.size()


func defeated() -> bool:
	return wounds.size() >= MAX_WOUNDS


func hand_penalty() -> int:
	return wounds.count("Waterlogged Lungs")


func shaking() -> bool:
	return wounds.has("Shaking Hands")


func broken_hand() -> bool:
	return wounds.has("Broken Hand")


func arrow() -> bool:
	return wounds.has("Arrow in the Shoulder")


func mend_amount() -> int:
	return 1 if wounds.has("Bitten") else 2


## After two Fails in a row the Teller takes pity: +1 to the highest die, shown in the odds.
func pity() -> bool:
	return fail_streak >= 2


func record_tier(tier: int) -> void:
	if tier == S.TRIUMPH:
		triumphs += 1
	if tier == S.FAIL:
		fail_streak += 1
	else:
		fail_streak = 0


func move_temper(track: String, amount: int) -> void:
	temper[track] = int(temper.get(track, 0)) + amount


## How the Teller describes you, from your temperament.
func epithet() -> String:
	var best := ""
	var best_v := 0
	var names := {"mercy": ["merciful", "ruthless"], "honesty": ["honest", "cunning"], "duty": ["dutiful", "free"]}
	for k in temper:
		var v: int = temper[k]
		if absi(v) > absi(best_v):
			best_v = v
			best = names[k][0] if v > 0 else names[k][1]
	return best
