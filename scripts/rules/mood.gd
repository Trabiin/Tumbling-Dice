extends RefCounted
## The Teller's Mood (an optional challenge ladder) and Story mode (for players who want the tales
## above all). Both are campaign settings, read by the tale runner when a tale starts and when it
## builds a challenge, contest or fight. Pure rules, like patrons.gd.
##
## Mood levels stack: level 3 has everything from levels 1 and 2. The dice and the odds stay honest
## at every level: difficulty only ever comes from targets, foes and resources (design doc, "Rules
## that keep it fair"). Winning a tale at a level unlocks that level's table felt for the tray.
##
## Story mode: Grit is doubled, and a Fail can always be Defied into a Mixed, for free.

const LEVELS := [
	{"name": "Fair", "text": "The Teller tells it as it is."},
	{"name": "Testy", "text": "Foes and opponents throw one extra d4."},
	{"name": "Grudging", "text": "You start every tale with 1 Fate."},
	{"name": "Sour", "text": "Waystones let you swap only one die."},
	{"name": "Bitter", "text": "Your Grit starts 4 lower."},
	{"name": "Black", "text": "Every target and every opponent's Resolve is 2 higher."},
]
const MAX_LEVEL := 5

## Table felts for the tray: the first is the tavern's own; each Mood level beaten unlocks one more.
const FELTS := [
	{"name": "Tavern teal", "color": Color("#163c3e")},
	{"name": "Claret", "color": Color("#4a1420")},
	{"name": "Midnight", "color": Color("#141c3a")},
	{"name": "Moss", "color": Color("#23361a")},
	{"name": "Ember", "color": Color("#4a2a10")},
	{"name": "Raven", "color": Color("#18141a")},
]

const EXTRA_DIE := {"name": "The Teller's Mood", "sides": 4}


static func level(campaign) -> int:
	if campaign == null or campaign.get("mood") == null:
		return 0
	return clampi(int(campaign.mood), 0, MAX_LEVEL)


static func story(campaign) -> bool:
	return campaign != null and campaign.get("story_mode") != null and bool(campaign.story_mode)


## The highest level the player may choose: one above the best they have beaten.
static func max_choosable(campaign) -> int:
	return clampi(int(campaign.mood_best) + 1, 1, MAX_LEVEL)


static func describe(lvl: int) -> String:
	var parts: Array[String] = []
	for i in range(1, lvl + 1):
		parts.append(LEVELS[i].text)
	return " ".join(parts) if not parts.is_empty() else LEVELS[0].text


## Grit and Fate at the start of a tale.
static func start_tale(campaign, state) -> void:
	var lvl := level(campaign)
	var g: int = state.START_GRIT
	if story(campaign):
		g *= 2
	if lvl >= 4:
		g -= 4
	state.grit_max = g
	state.grit = g
	if lvl >= 2:
		state.fate = 1


## How many dice a Waystone lets you swap.
static func swaps(campaign) -> int:
	return 1 if level(campaign) >= 3 else 2


## A challenge definition with the Mood applied (targets +2 at Black).
static func challenge_def(campaign, def: Dictionary) -> Dictionary:
	if level(campaign) < 5:
		return def
	var d := def.duplicate(true)
	if d.has("target"):
		d.target = int(d.target) + 2
	elif d.has("progress"):
		d.progress = int(d.progress) + 2
	else:
		d.target = load("res://scripts/rules/challenge.gd").target_for(String(d.get("difficulty", "standard"))) + 2
	if d.has("second"):
		d.second = d.second.duplicate()
		d.second.target = int(d.second.target) + 2
	return d


## An opponent for a Contest, with the Mood applied (an extra die from Testy, Resolve +2 at Black).
static func opponent(campaign, opp: Dictionary) -> Dictionary:
	var lvl := level(campaign)
	if lvl < 1:
		return opp
	var o := opp.duplicate(true)
	o.dice.append(EXTRA_DIE.duplicate())
	if lvl >= 5:
		o.resolve = int(o.resolve) + 2
	return o


## A foe for a fight, with the Mood applied (an extra attack die from Testy, Resolve +2 at Black).
static func foe(campaign, f: Dictionary) -> Dictionary:
	var lvl := level(campaign)
	if lvl < 1:
		return f
	var o := f.duplicate(true)
	for ph in o.phases:
		ph.dice.append({"name": EXTRA_DIE.name, "sides": 4, "kind": "attack"})
		if lvl >= 5:
			ph.resolve = int(ph.resolve) + 2
	return o


## Defy: 3 Fate once a tale normally; free and always in Story mode.
static func defy_cost(campaign) -> int:
	return 0 if story(campaign) else 3


static func can_defy(campaign, state) -> bool:
	if story(campaign):
		return true
	return not state.defy_used and state.fate >= 3


## Called when a tale ends: a win at a new Mood level unlocks its felt. Returns a line, or "".
static func record_win(campaign) -> String:
	var lvl := level(campaign)
	if story(campaign) or lvl <= int(campaign.mood_best):
		return ""
	campaign.mood_best = lvl
	return "The Teller's Mood: %s, beaten. A new felt for the tray: %s." % [LEVELS[lvl].name, FELTS[lvl].name]
