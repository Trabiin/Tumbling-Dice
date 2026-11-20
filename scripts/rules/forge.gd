extends RefCounted
## The tavern's two places for dice, as rules: Hollis's shelf behind the bar (buy and sell) and
## old Brannoc's bench, the Dicewright (recarve, inscribe, melt). Pure code: every action takes
## the campaign, checks it can be done, changes it and returns a line for the parchment, so the
## table and the tests use exactly the same calls.
##
## M4 has the forging the slice can feed: Recarve (Coin), Inscribe (a rune shard + Coin) and
## Melt (gives shards back). Loading, Rebind and Mend come with M5's materials and curses.
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


static func can_buy(campaign, item: Dictionary) -> Dictionary:
	if campaign.coin < int(item.price):
		return _r(false, "That's %d Coin." % int(item.price))
	return _r(true, "")


static func buy(campaign, item: Dictionary) -> Dictionary:
	var c := can_buy(campaign, item)
	if not c.ok:
		return c
	var d := Dice.create(item.base)
	d.history.append("Bought from Hollis's shelf.")
	campaign.coin -= int(item.price)
	campaign.pouch.collection.append(d)
	return _r(true, "Hollis sets a %s on the bar. (-%d Coin)" % [d.name, int(item.price)])
