extends RefCounted
## Balance bots: play whole tales through the same TaleRunner the table uses, with fast dice.
## Choices are made by a policy; dice decisions are made sensibly (best odds, best assignment).

const Dice := preload("res://scripts/rules/dice.gd")
const S := preload("res://scripts/rules/scoring.gd")
const Odds := preload("res://scripts/rules/odds.gd")
const Combat := preload("res://scripts/rules/combat.gd")

## Archetype Pouches from the starter shelf, all at weight 12 (design doc, "Builds").
const ARCHETYPES := {
	"balanced": ["oak_might", "oak_guile", "oak_lore", "oak_grace", "oak_ward", "brass_d8", "jade_d8", "bone_d6", "amethyst_d6", "bone_d4"],
	"bruiser": ["dragon_d10", "dragon_d12", "oak_might", "brass_d8", "oak_ward", "oak_grace", "oak_lore", "oak_guile"],
	"sage": ["jade_d8", "jade_d10", "oak_lore", "oak_grace", "bone_d6", "oak_ward", "brass_d8", "oak_guile", "oak_might"],
	"swindler": ["loaded_d6", "amethyst_d6", "oak_guile", "bone_d6", "bone_d4", "oak_grace", "oak_lore", "oak_might", "oak_ward", "brass_d8", "brass_d4"],
}

## What each build reaches for on the shelf once its starting dice are packed (dice won in tales).
const ARCH_ASPECTS := {
	"balanced": ["might", "guile", "lore", "grace", "ward", "wild"],
	"bruiser": ["might", "ward", "wild"],
	"sage": ["lore", "grace", "wild"],
	"swindler": ["guile", "grace", "wild"],
}

var rng := RandomNumberGenerator.new()
var archetype := "balanced"
var choice_policy := "random"     # "random" or "first"
var max_steps := 2000


func pack(campaign, kind: String) -> void:
	var p = campaign.pouch
	p.pouch = p.pouch.filter(func(d): return d.get("cursed", false))  # cursed dice stay put
	p.saddlebag.clear()
	var want: Array = ARCHETYPES.get(kind, ARCHETYPES.balanced)
	for b in want:
		for d in p.collection:
			if d.base == b and not p.pouch.has(d):
				p.add(d)
				break
	# Then the best dice won in tales that suit the build, while the weight allows.
	var likes: Array = ARCH_ASPECTS.get(kind, ARCH_ASPECTS.balanced)
	var extra: Array = p.shelf().filter(func(d): return likes.has(d.aspect) and not d.get("ally", false) and not d.has("loaded_face") or kind == "swindler" and d.has("loaded_face"))
	extra.sort_custom(func(a, b): return Dice.mean_n(a) / maxf(1.0, float(a.weight)) > Dice.mean_n(b) / maxf(1.0, float(b.weight)))
	for d in extra:
		if p.can_add(d):
			# Swap out a starter Oak die of an aspect the build doesn't lean on, if it makes room.
			p.add(d)
		else:
			for o in p.pouch:
				if String(o.base).begins_with("oak_") and not likes.has(o.aspect) and int(o.weight) >= int(d.weight) - (p.weight_limit - p.weight()):
					p.remove(o)
					if p.can_add(d):
						p.add(d)
					else:
						p.add(o)
					break
	for d in p.shelf():
		p.bag(d)


## Play the runner to its ending. Returns the number of steps taken.
func play(runner) -> int:
	var steps := 0
	while runner.phase != "ending" and steps < max_steps:
		steps += 1
		step(runner)
	return steps


func step(r) -> void:
	match r.phase:
		"choose":
			var opts: Array = r.visible_options()
			var i := 0 if choice_policy == "first" else rng.randi_range(0, opts.size() - 1)
			r.pick(i)
		"wager":
			r.pick_wager(r.pouch.collection[rng.randi_range(0, r.pouch.collection.size() - 1)] if rng.randf() < 0.5 else null)
		"prepare":
			pack(r.campaign, archetype)
			r.done_prepare()
		"approach":
			r.pick_approach(best_approach(r))
		"foe_throw":
			r.auto_foe_throw()
		"throw":
			r.auto_throw(choose_dice(r))
		"quake":
			r.auto_rethrow(r.quake_targets())
		"assign":
			if not r.bell_targets().is_empty():
				r.use_bell()
				r.auto_rethrow(r.bell_targets())
				return
			r.assign_suggested()
		"push":
			r.stop()
		"defy":
			# Save the once-per-tale Defy for the last act.
			r.defy(r.scene.get("act", 1) >= 3)
		"cost":
			r.pick_cost(rng.randi_range(0, r.costs().size() - 1))
		"outcome":
			r.next()
		"waystone":
			r.done_waystone()


func best_approach(r) -> int:
	var best := 0
	var best_v := -INF
	for i in r.approaches().size():
		var o: Dictionary = r.approach_odds(i)
		var v: float
		if o.has("tiers"):
			v = o.tiers[2] + o.tiers[3] + o.tiers[1] * 0.4
		else:
			v = o.expected - o.get("catch", 0.0) * 10.0
		if v > best_v:
			best_v = v
			best = i
	return best


func choose_dice(r) -> Array:
	var hand: Array = r.pouch.hand
	var n: int = r.max_dice()
	match r.active.type:
		"laststand":
			return hand.duplicate()
		"challenge", "flee":
			return Odds.pick(hand, r.active.run.slots, n, r.active.run)
		"contest":
			var c = r.active.run
			var ranked := hand.duplicate()
			# Card sharps: leave loaded dice in the Pouch.
			if c.is_card_sharp():
				ranked = ranked.filter(func(d): return not d.has("loaded_face"))
				if ranked.is_empty():
					ranked = hand.duplicate()
			ranked.sort_custom(func(a, b): return Odds.expected_in(a, c.aspect) > Odds.expected_in(b, c.aspect))
			return ranked.slice(0, n)
		"combat":
			var ranked := hand.duplicate()
			ranked.sort_custom(func(a, b): return _combat_value(a) > _combat_value(b))
			return ranked.slice(0, n)
	return hand.slice(0, n)


func _combat_value(d: Dictionary) -> float:
	var best := 0.0
	for st in Combat.STANCES:
		best = maxf(best, Odds.expected_in(d, Combat.STANCE_ASPECT[st]))
	return best + Dice.mean_n(d) * 0.2
