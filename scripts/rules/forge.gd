extends RefCounted
## The tavern's two places for dice, as rules: Hollis's shelf behind the bar (buy and sell) and
## old Brannoc's bench, the Dicewright (recarve, inscribe, melt). Pure code: every action takes
## the campaign, checks it can be done, changes it and returns a line for the parchment, so the
## table and the tests use exactly the same calls.
##
## Recarve (Coin), Inscribe (a rune shard + Coin), Melt (gives shards back), and since M5 the
## forging that needs materials found in tales: Load (lead + Coin), Rebind (a binding + Coin),
## Mend (Coin, for a cracked face), and giving Brannoc rare materials to earn his trust. Load
## needs trust 1 and Rebind trust 2: he won't weight a die for a stranger.
##
## Every action returns {ok: bool, text: String}.

const Dice := preload("res://scripts/rules/dice.gd")

## Rune faces a die may carry, by rarity (design doc, "Forging").
const RUNE_CAP := {"common": 1, "fine": 2, "masterwork": 3, "relic": 4, "cursed": 0}
const RECARVE_COST := 8          # Coin per point
const RECARVE_LIMIT := 4         # a die's faces may rise by 4 in total, ever
const INSCRIBE_COST := 10
const SELL_PRICE := {"common": 3, "fine": 6, "masterwork": 12, "relic": 20, "cursed": 0}
const MELT_COIN := {"common": 1, "fine": 3, "masterwork": 6, "relic": 10, "cursed": 0}
const MIN_COLLECTION := 6        # Hollis won't let you sell or melt your way out of a Pouch
## What Hollis keeps behind the bar: plain dice for Coin.
const STOCK := [
	{"base": "oak_might", "price": 9}, {"base": "oak_guile", "price": 9}, {"base": "oak_lore", "price": 9},
	{"base": "oak_grace", "price": 9}, {"base": "oak_ward", "price": 9}, {"base": "brass_d4", "price": 12},
	{"base": "bone_d4", "price": 12},
]
const LOAD_COST := 15
const REBIND_COST := 10
const MEND_COST := 4
const LOAD_TRUST := 1
const REBIND_TRUST := 2
## Forging materials. Rare ones can be given to Brannoc for his trust.
const MATERIALS := {
	"lead": {"name": "Lead", "plural": "Lead", "text": "A slug of soft lead. Brannoc can sink it behind a face."},
	"binding_might": {"name": "a Binding of Might", "plural": "Bindings of Might", "text": "A strip of a warrior's oath-cord. It can rebind a die to Might."},
	"binding_guile": {"name": "a Binding of Guile", "plural": "Bindings of Guile", "text": "A card sharp's ribbon. It can rebind a die to Guile."},
	"binding_lore": {"name": "a Binding of Lore", "plural": "Bindings of Lore", "text": "A page of a lost book. It can rebind a die to Lore."},
	"binding_grace": {"name": "a Binding of Grace", "plural": "Bindings of Grace", "text": "A dancer's ribbon. It can rebind a die to Grace."},
	"binding_ward": {"name": "a Binding of Ward", "plural": "Bindings of Ward", "text": "A link of an old shield-chain. It can rebind a die to Ward."},
	"bellmetal": {"name": "Bellmetal scrap", "plural": "Bellmetal scrap", "rare": true, "text": "A sliver of the drowned abbey's bronze. Brannoc would give a lot to work it."},
	"heartwood": {"name": "Heartwood", "plural": "Heartwood", "rare": true, "text": "From the centre of a lightning-struck oak. Rare, and Brannoc knows it."},
	"black_iron": {"name": "Black iron", "plural": "Black iron", "rare": true, "text": "From the old watchtower's bell-cage. Dwarf-forged, they say."},
	"tide_pearl": {"name": "a Tide Pearl", "plural": "Tide Pearls", "rare": true, "text": "Grey and cold, from the Tide Court's floor."},
}

## The midsummer fair brings fine dice in from the river traders (summer only).
const FAIR_STOCK := [
	{"base": "jade_d8", "price": 24}, {"base": "bone_d6", "price": 22}, {"base": "amethyst_d6", "price": 22},
	{"base": "brass_d8", "price": 24},
]


static func stock(campaign) -> Array:
	var out: Array = STOCK.duplicate()
	if campaign.has_method("season") and campaign.season() == "summer" and not campaign.year_over():
		out.append_array(FAIR_STOCK)
	return out


## Runes Brannoc can cut (Bane is never inscribed on purpose).
const INSCRIBABLE := ["strike", "guard", "mend", "spark", "echo", "keen", "kin"]


static func _r(ok: bool, text: String) -> Dictionary:
	return {"ok": ok, "text": text}


static func rune_faces(d: Dictionary) -> int:
	var n := 0
	for f in d.faces:
		if String(f.rune) != "" and String(f.rune) != "bane":
			n += 1
	return n


static func carved(d: Dictionary) -> int:
	return int(d.get("carved", 0))


## Why a die can't go to the bench at all, or "" if it can.
static func unworkable(d: Dictionary) -> String:
	if d.get("ally", false):
		return "It isn't yours to change."
	if d.get("cursed", false):
		return "Brannoc won't touch it. \"That one wants a tale, not a chisel.\""
	if d.has("loaded_face"):
		return "Loaded. Brannoc says recarving it would throw the weight off."
	return ""


static func material_name(m: String, n := 1) -> String:
	var info: Dictionary = MATERIALS.get(m, {"name": m, "plural": m})
	return info.name if n == 1 else "%d %s" % [n, info.plural]


static func material_text(m: String, n := 1) -> String:
	return material_name(m, n)


static func is_rare(m: String) -> bool:
	return MATERIALS.get(m, {}).get("rare", false)


static func materials_text(campaign) -> String:
	var parts: Array[String] = []
	for m in campaign.materials:
		parts.append(material_name(m, int(campaign.materials[m])) if int(campaign.materials[m]) > 1 else MATERIALS.get(m, {"name": m}).name)
	return ", ".join(parts) if not parts.is_empty() else "none"


# ------------------------------------------------------------------ trust

## Give Brannoc a rare material: he keeps it, and trusts you a little more.
static func can_give(campaign, m: String) -> Dictionary:
	if not is_rare(m):
		return _r(false, "Brannoc only wants rare stuff.")
	if campaign.material_count(m) < 1:
		return _r(false, "You have none.")
	return _r(true, "")


static func give(campaign, m: String) -> Dictionary:
	var c := can_give(campaign, m)
	if not c.ok:
		return c
	campaign.add_material(m, -1)
	campaign.trust += 1
	var lines := {1: "\"Now that's something.\" He turns it in the lamplight a long time. \"Bring me a d6 and some lead sometime. I'll show you a trick.\"",
		2: "He wraps it in a cloth like it's a sleeping child. \"You can bring me bindings now. I'll turn a die for you.\""}
	return _r(true, "You give Brannoc %s. %s (Brannoc's trust: %d)" % [material_name(m), lines.get(campaign.trust, "He nods, and puts it on the high shelf with his good tools."), campaign.trust])


# ------------------------------------------------------------------ loading

## Load: sink lead behind the face opposite the one you want, so that face lands about three
## times in four (measured: dice.gd LOADED_HIT). Only d6s: Brannoc has only ever weighted
## sixes true, and the odds shown must be measured, never guessed.
static func can_load(campaign, d: Dictionary, face: int) -> Dictionary:
	var why := unworkable(d)
	if why != "":
		return _r(false, why)
	if int(d.sides) != 6:
		return _r(false, "\"Only sixes. I've never weighted anything else true, and I won't guess.\"")
	if campaign.trust < LOAD_TRUST:
		return _r(false, "\"Loading? For you?\" Brannoc laughs. \"Bring me something rare first, and we'll see.\"")
	if face < 0 or face >= d.faces.size():
		return _r(false, "Pick the face you want it to favour.")
	if campaign.material_count("lead") < 1:
		return _r(false, "You need Lead.")
	if campaign.coin < LOAD_COST:
		return _r(false, "Loading costs %d Coin." % LOAD_COST)
	return _r(true, "")


static func load_die(campaign, d: Dictionary, face: int) -> Dictionary:
	var c := can_load(campaign, d, face)
	if not c.ok:
		return c
	campaign.add_material("lead", -1)
	campaign.coin -= LOAD_COST
	campaign.forged += 1
	d.loaded_face = face + 1
	d.load = 0.3
	d.history.append("Loaded by Brannoc to favour its %d." % int(d.faces[face].n))
	return _r(true, "Brannoc drills, pours, plugs and sands until you can't see where. \"It'll favour the %d. Card sharps can tell, mind.\" (-%d Coin, -1 Lead)" % [int(d.faces[face].n), LOAD_COST])


# ------------------------------------------------------------------ rebinding

static func can_rebind(campaign, d: Dictionary, aspect: String) -> Dictionary:
	var why := unworkable(d)
	if why != "" and not d.has("loaded_face"):
		return _r(false, why)
	if d.get("ally", false) or d.get("cursed", false):
		return _r(false, why)
	if d.get("rebound", false):
		return _r(false, "It has been rebound once already. It won't take another.")
	if campaign.trust < REBIND_TRUST:
		return _r(false, "\"Rebinding is old work. I'd want to know you better.\"")
	if not aspect in Dice.ASPECTS or aspect == d.aspect:
		return _r(false, "Pick another aspect.")
	if campaign.material_count("binding_" + aspect) < 1:
		return _r(false, "You need %s." % material_name("binding_" + aspect))
	if campaign.coin < REBIND_COST:
		return _r(false, "Rebinding costs %d Coin." % REBIND_COST)
	return _r(true, "")


## Rebind: the die changes aspect, once in its life, and forgets half its notches.
static func rebind(campaign, d: Dictionary, aspect: String) -> Dictionary:
	var c := can_rebind(campaign, d, aspect)
	if not c.ok:
		return c
	campaign.add_material("binding_" + aspect, -1)
	campaign.coin -= REBIND_COST
	campaign.forged += 1
	var before: String = d.aspect
	d.aspect = aspect
	d.rebound = true
	var lost := int(d.get("notches", 0)) - int(d.get("notches", 0)) / 2
	d.notches = int(d.get("notches", 0)) / 2
	d.name = String(d.name).replace(Dice.ASPECT_NAMES[before], Dice.ASPECT_NAMES[aspect])
	d.history.append("Rebound by Brannoc from %s to %s." % [Dice.ASPECT_NAMES[before], Dice.ASPECT_NAMES[aspect]])
	return _r(true, "Brannoc wraps the binding round the die and holds it in the coals until the cord is ash. It is a die of %s now%s. (-%d Coin)" % [
		Dice.ASPECT_NAMES[aspect], ", and it has forgotten %d notch%s" % [lost, "" if lost == 1 else "es"] if lost > 0 else "", REBIND_COST])


# ------------------------------------------------------------------ mending

static func can_mend(campaign, d: Dictionary) -> Dictionary:
	if d.get("ally", false):
		return _r(false, "It isn't yours to mend.")
	if Dice.cracked_faces(d).is_empty():
		return _r(false, "Nothing to mend.")
	if campaign.coin < MEND_COST:
		return _r(false, "Mending costs %d Coin a face." % MEND_COST)
	return _r(true, "")


static func mend(campaign, d: Dictionary) -> Dictionary:
	var c := can_mend(campaign, d)
	if not c.ok:
		return c
	var i: int = Dice.cracked_faces(d)[0]
	var f: Dictionary = d.faces[i]
	f.n = int(f.n) + int(f.get("crack", 1))
	f.erase("crack")
	campaign.coin -= MEND_COST
	campaign.forged += 1
	d.history.append("Mended by Brannoc.")
	return _r(true, "A little glue, a pin, a lot of muttering. The %s's %d is whole again. (-%d Coin)" % [d.name, int(f.n), MEND_COST])


# ------------------------------------------------------------------ the Dicewright

## Recarve: change one face's number by 1 (up or down), for Coin.
static func can_recarve(campaign, d: Dictionary, face: int, delta: int) -> Dictionary:
	var why := unworkable(d)
	if why != "":
		return _r(false, why)
	if absi(delta) != 1:
		return _r(false, "One point at a time.")
	if face < 0 or face >= d.faces.size():
		return _r(false, "No such face.")
	var n: int = int(d.faces[face].n) + delta
	if n < 1 or n > int(d.sides) + 2:
		return _r(false, "The face won't take that number.")
	if delta > 0 and carved(d) + delta > RECARVE_LIMIT:
		return _r(false, "This die has been carved up as far as it will go (+%d)." % RECARVE_LIMIT)
	if campaign.coin < RECARVE_COST:
		return _r(false, "Recarving costs %d Coin." % RECARVE_COST)
	return _r(true, "")


static func recarve(campaign, d: Dictionary, face: int, delta: int) -> Dictionary:
	var c := can_recarve(campaign, d, face, delta)
	if not c.ok:
		return c
	var before: int = int(d.faces[face].n)
	d.faces[face].n = before + delta
	d.carved = carved(d) + delta
	campaign.coin -= RECARVE_COST
	campaign.forged += 1
	d.history.append("Recarved by Brannoc: a %d became a %d." % [before, before + delta])
	return _r(true, "Brannoc squints, cuts, blows the dust off. The %s's %d is a %d now. (-%d Coin)" % [d.name, before, before + delta, RECARVE_COST])


## Inscribe: cut a rune into a plain face, using a rune shard of that rune.
static func shard_count(campaign, rune: String) -> int:
	var n := 0
	for s in campaign.shards:
		if String(s).to_lower() == rune:
			n += 1
	return n


static func can_inscribe(campaign, d: Dictionary, face: int, rune: String) -> Dictionary:
	var why := unworkable(d)
	if why != "":
		return _r(false, why)
	if not rune in INSCRIBABLE:
		return _r(false, "Brannoc doesn't know that rune.")
	if face < 0 or face >= d.faces.size():
		return _r(false, "No such face.")
	if String(d.faces[face].rune) != "":
		return _r(false, "That face already carries a rune.")
	if rune_faces(d) >= int(RUNE_CAP.get(d.rarity, 1)):
		return _r(false, "A %s die holds only %d rune face%s." % [d.rarity, RUNE_CAP.get(d.rarity, 1), "" if RUNE_CAP.get(d.rarity, 1) == 1 else "s"])
	if shard_count(campaign, rune) < 1:
		return _r(false, "You need a %s rune shard." % rune.capitalize())
	if campaign.coin < INSCRIBE_COST:
		return _r(false, "Inscribing costs %d Coin." % INSCRIBE_COST)
	return _r(true, "")


static func inscribe(campaign, d: Dictionary, face: int, rune: String) -> Dictionary:
	var c := can_inscribe(campaign, d, face, rune)
	if not c.ok:
		return c
	for i in campaign.shards.size():
		if String(campaign.shards[i]).to_lower() == rune:
			campaign.shards.remove_at(i)
			break
	d.faces[face].rune = rune
	campaign.coin -= INSCRIBE_COST
	campaign.forged += 1
	d.history.append("Inscribed by Brannoc: %s on the %d." % [rune.capitalize(), int(d.faces[face].n)])
	return _r(true, "The shard crumbles into the cut as Brannoc works it in. The %s's %d now carries %s. (-%d Coin, -1 shard)" % [d.name, int(d.faces[face].n), rune.capitalize(), INSCRIBE_COST])


## Melt: the die is gone, its history with it. You get back a shard of each rune it carried
## (Bane excepted) and a little Coin for the metal or wood.
static func can_melt(campaign, d: Dictionary) -> Dictionary:
	if d.get("ally", false):
		return _r(false, "It isn't yours to melt.")
	if d.get("cursed", false):
		return _r(false, "It won't melt. It won't even get warm.")
	if campaign.pouch.collection.size() <= MIN_COLLECTION:
		return _r(false, "Brannoc shakes his head. \"Keep a few, or what will you throw?\"")
	return _r(true, "")


static func melt(campaign, d: Dictionary) -> Dictionary:
	var c := can_melt(campaign, d)
	if not c.ok:
		return c
	var got: Array = []
	for f in d.faces:
		var r := String(f.rune)
		if r != "" and r != "bane" and not got.has(r.capitalize()):
			got.append(r.capitalize())
	campaign.shards.append_array(got)
	var coin: int = MELT_COIN.get(d.rarity, 1)
	campaign.coin += coin
	campaign.pouch.lose(d)
	campaign.forged += 1
	var shards_text := ("shards: " + ", ".join(got)) if not got.is_empty() else "no shards"
	return _r(true, "Into the crucible. The %s is gone, and %d notch%s of history with it. You keep %s, and %d Coin." % [
		d.name, int(d.get("notches", 0)), "" if int(d.get("notches", 0)) == 1 else "es", shards_text, coin])


# ------------------------------------------------------------------ Hollis's shelf

static func sell_price(d: Dictionary) -> int:
	return int(SELL_PRICE.get(d.rarity, 3))


static func can_sell(campaign, d: Dictionary) -> Dictionary:
	if d.get("ally", false):
		return _r(false, "It isn't yours to sell.")
	if d.get("cursed", false):
		return _r(false, "Hollis won't have it behind the bar.")
	if campaign.pouch.collection.size() <= MIN_COLLECTION:
		return _r(false, "\"Sell that and you'll have nothing to throw,\" says Hollis.")
	return _r(true, "")


static func sell(campaign, d: Dictionary) -> Dictionary:
	var c := can_sell(campaign, d)
	if not c.ok:
		return c
	var price := sell_price(d)
	campaign.pouch.lose(d)
	campaign.coin += price
	return _r(true, "Hollis weighs the %s in his palm and counts out %d Coin." % [d.name, price])


## Kettle's fences keep Hollis's shelf stocked: friends of the Thieves' Guild pay less, its
## enemies more. 1 Coin per point of standing, never below half price.
static func price(campaign, item: Dictionary) -> int:
	var st := 0
	if campaign.has_method("standing_of"):
		st = campaign.standing_of("guild")
	return maxi(int(item.price) / 2, int(item.price) - st)


static func can_buy(campaign, item: Dictionary) -> Dictionary:
	var p := price(campaign, item)
	if campaign.coin < p:
		return _r(false, "That's %d Coin." % p)
	return _r(true, "")


static func buy(campaign, item: Dictionary) -> Dictionary:
	var c := can_buy(campaign, item)
	if not c.ok:
		return c
	var d := Dice.create(item.base)
	d.history.append("Bought from Hollis's shelf.")
	var p := price(campaign, item)
	campaign.coin -= p
	campaign.pouch.collection.append(d)
	return _r(true, "Hollis sets a %s on the bar. (-%d Coin)" % [d.name, p])
