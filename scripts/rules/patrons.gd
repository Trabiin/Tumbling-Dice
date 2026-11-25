extends RefCounted
## The campaign around the tales: who offers which tale and when, the calendar (a tale takes a
## night, the season turns every 6 nights), what the turning of a season brings, tales that go by
## without you, and Sister Maud's corner, where Wounds are treated. Pure rules, like forge.gd:
## every call takes the campaign and returns lines for the parchment.
##
## A tale says who offers it, and when, in its header (docs/tale_format.md):
##   patron: Wren            arc: wren            order: 2
##   pitch: The bell of Marrowmere is for sale in the river market.
##   offer: ended:drowned_bell and not season==winter
##   expires: winter         missed: Holloway fell in the first snow, without you.

const Cond := preload("res://scripts/rules/conditions.gd")
const Tales := preload("res://scripts/rules/tales.gd")
const Campaign := preload("res://scripts/rules/campaign.gd")

## The patrons with arcs in M5. Their tables are places in the tavern.
const PATRONS := {
	"wren": {"name": "Wren", "place": "Wren's table", "who": "a fisherman's daughter",
		"idle": "Wren is mending a net by the window, and doesn't look up."},
	"ashgrove": {"name": "Captain Ashgrove", "place": "Captain Ashgrove's table", "who": "a disgraced knight",
		"idle": "The captain sits with his back to the wall, his sword across his knees, saying nothing to anyone."},
	"kettle": {"name": "Mother Kettle", "place": "Mother Kettle's table", "who": "a smuggler and card sharp",
		"idle": "Mother Kettle is dealing patience in the corner, and cheating at it."},
	"pilgrim": {"name": "The Hooded Pilgrim", "place": "The pilgrim's stool", "who": "a stranger on the road",
		"idle": "The stool by the hearth is empty, but somebody has left a single die on it, six up."},
	# Secret tales: offered only when the right rumours have been found. No idle line.
	"brannoc": {"name": "Brannoc", "place": "Brannoc's bench", "who": "the Dicewright", "secret": true, "idle": ""},
	"hollis": {"name": "Hollis", "place": "The cellar door", "who": "the barkeep", "secret": true, "idle": ""},
}

## What the turning of each season brings. Each fires once, when the season begins, if its
## condition holds. effects use the campaign's own words: mark, chronicle, coin.
const SEASON_EVENTS := [
	{"id": "summer_fair", "season": "summer", "cond": "",
		"text": "Summer comes in loud. The midsummer fair sets up in the square, and Hollis gets fine dice in from the river traders.",
		"chronicle": "Midsummer: the fair came to town."},
	{"id": "marrowmere_flood", "season": "autumn", "cond": "seen:greed",
		"text": "The autumn rains come, and the lake rises. A woman from Marrowmere sits by the fire tonight with nothing but the coat she ran in. She looks at your Pouch, where the Bellmetal hums, and then away.",
		"chronicle": "Autumn: Marrowmere flooded. The lake remembered its gold.", "mark": "marrowmere_flooded"},
	{"id": "autumn_refugees", "season": "autumn", "cond": "missed:pretender_road or ending:pretender_road==joined",
		"text": "Autumn, and the road from the north fills with carts. The Pretender's men are taking the harvest, and the people of the hill farms are walking south ahead of them.",
		"chronicle": "Autumn: the hill farms emptied ahead of the Pretender.", "mark": "hill_farms_burned"},
	{"id": "winter_road", "season": "winter", "cond": "",
		"text": "The first snow. By morning the mountain road is shut, and it will stay shut until spring. The tavern fills with people who meant to be somewhere else.",
		"chronicle": "Winter: the mountain road closed.", "mark": "road_closed"},
]

const HEAL_COST := 6           # Coin, less 2 a point of Abbey standing (2 to 12)
const HEAL_NIGHTS := 1
const WORK_NIGHTS := 2         # or help in the infirmary instead of paying


# ------------------------------------------------------------------ tales and offers

## Every shipped tale's header (no scenes), with its path. Cached by Tales.
static func catalog() -> Array:
	var out: Array = []
	for path in Tales.all_paths():
		var t: Dictionary = Tales.parsed(path).tale
		if t.get("arc", "") == "":
			continue
		var h := {"path": path}
		for k in ["id", "title", "patron", "arc", "order", "pitch", "offer", "expires", "missed"]:
			h[k] = t.get(k, "")
		h.order = int(h.order) if str(h.order).is_valid_int() else 0
		out.append(h)
	out.sort_custom(func(a, b): return [a.arc, a.order] < [b.arc, b.order])
	return out


static func ctx(campaign) -> Dictionary:
	return {"state": null, "pouch": campaign.pouch, "campaign": campaign}


## Is this tale on offer tonight?
static func offered(campaign, h: Dictionary) -> bool:
	if campaign.told(h.id) or campaign.missed.has(h.id):
		return false
	return Cond.check(String(h.offer), ctx(campaign))


## The tale each patron offers tonight (the earliest one in their arc), or nothing.
static func offers(campaign, cat := []) -> Array:
	if cat.is_empty():
		cat = catalog()
	var by_arc := {}
	for h in cat:
		if offered(campaign, h) and not by_arc.has(h.arc):
			by_arc[h.arc] = h
	var out: Array = []
	for arc in PATRONS:
		if by_arc.has(arc):
			out.append(by_arc[arc])
	for arc in by_arc:
		if not PATRONS.has(arc):
			out.append(by_arc[arc])
	return out


## How the patron's offer reads at their table, and whether it is running out.
static func offer_note(campaign, h: Dictionary) -> String:
	var exp := String(h.get("expires", ""))
	if campaign.told(h.id) or exp == "" or not exp in Campaign.SEASONS:
		return ""
	var left: int = Campaign.SEASONS.find(exp) * Campaign.NIGHTS_PER_SEASON + 1 - campaign.night
	if left <= 0:
		return ""
	if left <= Campaign.NIGHTS_PER_SEASON:
		return "Before %s: %d night%s left." % [exp, left, "" if left == 1 else "s"]
	return "Before %s." % exp


static func patron_of(h: Dictionary) -> Dictionary:
	return PATRONS.get(String(h.get("arc", "")), {"name": h.get("patron", ""), "place": "%s's table" % h.get("patron", "")})


# ------------------------------------------------------------------ the calendar

## Let n nights pass. Seasons turn, their events happen, tales that run out are missed, and the
## turning of a season mends one Wound. Returns lines for the parchment: [{text, style}].
static func pass_nights(campaign, n: int, cat := []) -> Array:
	if cat.is_empty():
		cat = catalog()
	var out: Array = []
	for k in n:
		var before: int = campaign.season_index()
		var was_over: bool = campaign.year_over()
		campaign.night += 1
		if campaign.year_over() and not was_over:
			out.append({"text": "[i]And that is a year. The snow goes grey, the road opens, and the tavern is still here, and so are you. Some tales are still waiting to be told.[/i]", "style": "teller"})
			campaign.chronicle.append("The year turned.")
			continue
		if campaign.season_index() != before and not campaign.year_over():
			out.append_array(_turn_season(campaign, cat))
	return out


static func _turn_season(campaign, cat: Array) -> Array:
	var out: Array = []
	var s: String = campaign.season()
	out.append({"text": s.capitalize(), "style": "scene"})
	for h in cat:
		if String(h.expires) == s and not campaign.told(h.id) and not campaign.missed.has(h.id):
			campaign.missed.append(h.id)
			var txt := String(h.missed) if String(h.missed) != "" else "%s went by without you." % h.title
			out.append({"text": "[i]%s[/i]" % txt, "style": "teller"})
			campaign.chronicle.append("Missed: %s. %s" % [h.title, txt])
	for ev in SEASON_EVENTS:
		if ev.season != s or campaign.events_seen.has(ev.id):
			continue
		if not Cond.check(String(ev.cond), ctx(campaign)):
			continue
		campaign.events_seen.append(ev.id)
		out.append({"text": "[i]%s[/i]" % ev.text, "style": "teller"})
		campaign.chronicle.append(ev.chronicle)
		if ev.has("mark"):
			campaign.mark(ev.mark)
	if not campaign.wounds.is_empty():
		var w: String = campaign.wounds.pop_front()
		out.append({"text": "The season turns, and your %s mends on its own." % w, "style": "system"})
	return out


## Nights until the next season (for "wait for spring").
static func nights_to_next_season(campaign) -> int:
	if campaign.year_over():
		return 1
	return Campaign.NIGHTS_PER_SEASON - campaign.season_night() + 1


# ------------------------------------------------------------------ Sister Maud's corner

static func heal_cost(campaign) -> int:
	return clampi(HEAL_COST - 2 * campaign.standing_of("abbey"), 2, 12)


## Treat one Wound: pay, or help in the infirmary for longer. Either way the night goes.
static func can_heal(campaign, pay: bool) -> Dictionary:
	if campaign.wounds.is_empty():
		return {"ok": false, "text": "You have no Wounds to treat."}
	if pay and campaign.coin < heal_cost(campaign):
		return {"ok": false, "text": "Treating a Wound costs %d Coin." % heal_cost(campaign)}
	return {"ok": true, "text": ""}


static func heal(campaign, pay: bool, w_index := 0, cat := []) -> Dictionary:
	var c := can_heal(campaign, pay)
	if not c.ok:
		return {"ok": false, "text": c.text, "lines": []}
	var w: String = campaign.wounds[clampi(w_index, 0, campaign.wounds.size() - 1)]
	campaign.wounds.erase(w)
	var text := ""
	var nights := HEAL_NIGHTS
	if pay:
		var cost := heal_cost(campaign)
		campaign.coin -= cost
		text = "Sister Maud sets your %s, mutters a prayer over it and a worse word under it, and sends you up to bed. (-%d Coin, a night)" % [w, cost]
	else:
		nights = WORK_NIGHTS
		text = "Maud treats your %s for nothing, and then hands you a mop. Two nights of boiling bandages and carrying slops later, you are square. (two nights)" % w
	return {"ok": true, "text": text, "lines": pass_nights(campaign, nights, cat)}


## What Maud says about a cursed die: she can't lift it, but she knows who can.
static func curse_advice(d: Dictionary) -> String:
	if d.base == "bellmetal_d20":
		return "Maud won't touch the Bellmetal. \"That's the lake's. Ask the fisher girl, Wren. Whoever lifts that curse will do it on the water.\""
	if d.base == "oath_d10":
		return "Maud crosses herself. \"A broken oath. Only the one it was sworn to can loose it. Your captain knows whose it was.\""
	if d.base == "gilt_d20":
		return "Maud weighs it in her hand and gives it straight back. \"Gold that hungry was stolen from somebody. Give it back where it was struck, and it'll go quiet.\""
	return "Maud turns it over and gives it back. \"Not mine to lift. Whoever it was taken from, that's where it ends.\""
