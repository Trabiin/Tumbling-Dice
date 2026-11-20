extends RefCounted
## Foes and social opponents for the slice, as data. Foes are built from the same parts as the
## player: dice with faces, traits, a weakness and a pattern, plus the die they drop.
##
## Foe die kinds:
##   attack  its number is damage aimed at you
##   pack    on its highest face another attacker joins next round (no damage)
##   toll    1 to 3 is damage; 4 or more makes the tray quake (your dice under 3 are re-thrown)
##   guard   blocks that much of your Strike damage this round
##
## Traits (Read in Silence mode cancels one for the round, except thief and ambush):
##   hamstring  if any of its damage lands unblocked, your Effort drops by 1 next round
##   ghostly    Might dice deal half damage in Strike
##   thief      at the start of the fight it takes your best die until the fight ends
##   ambush     your Effort is 1 lower in the first round
##   relentless unblocked damage hits 1 harder

const CANCELLABLE := ["hamstring", "ghostly", "relentless"]
const TRAIT_TEXT := {
	"hamstring": "Hamstring: if its damage lands unblocked, your Effort drops by 1 next round.",
	"ghostly": "Ghostly: Might dice deal half damage.",
	"thief": "Thief: it holds your best die until the fight ends.",
	"ambush": "Ambush: your Effort is 1 lower in the first round.",
	"relentless": "Relentless: unblocked damage hits 1 harder.",
	"card_sharp": "Card sharp: watches for loaded dice.",
}


static func foe(id: String) -> Dictionary:
	match id:
		"mire_wolf":
			# The worked example from the design doc.
			return {"id": id, "name": "Mire Wolf", "kind": "foe", "speed": 9,
				"phases": [{"resolve": 14, "traits": ["hamstring"],
					"dice": [{"name": "Fang", "sides": 8, "kind": "attack"}, {"name": "Pack", "sides": 4, "kind": "pack"}],
					"summon": {"name": "Second Wolf", "sides": 6, "kind": "attack"}}],
				"weakness": "", "loot": "", "figure": "wolf"}
		"drowned_pair":
			return {"id": id, "name": "Two Drowned", "kind": "minion", "speed": 6,
				"text": "Grey men in sodden wool, lake water pouring from their sleeves.",
				"phases": [{"resolve": 16, "traits": ["ghostly"],
					"dice": [{"name": "Grasp", "sides": 8, "kind": "attack"}, {"name": "Grasp", "sides": 8, "kind": "attack"}],
					"split": 8}],
				"weakness": "lore", "loot": "brine_d6", "figure": "drowned"}
		"kettle_knives":
			return {"id": id, "name": "Kettle's Knives", "kind": "elite", "speed": 11, "no_flee": false,
				"text": "Three of Mother Kettle's crew, and the knives come out together.",
				"phases": [{"resolve": 26, "traits": ["thief", "ambush"],
					"dice": [{"name": "Knife", "sides": 8, "kind": "attack"}, {"name": "Knife", "sides": 8, "kind": "attack"},
						{"name": "Cudgel", "sides": 6, "kind": "guard"}]}],
				"weakness": "grace", "loot": "kettle_knife_d8", "figure": "smuggler"}
		"abbess":
			return {"id": id, "name": "The Drowned Abbess", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "Mother Ysolde, forty years under the lake, her habit drifting like weed.",
				"phases": [
					{"resolve": 18, "traits": ["ghostly"], "title": "The Toll",
						"dice": [{"name": "Toll", "sides": 6, "kind": "toll"}, {"name": "Grief", "sides": 8, "kind": "attack"}],
						"wardens": [{"name": "Wardens", "sides": 4, "kind": "attack"}]},
					{"resolve": 12, "traits": ["relentless"], "title": "Under the Water", "danger": 5,
						"danger_text": "The water closes over your head.",
						"dice": [{"name": "Drag", "sides": 8, "kind": "attack"}, {"name": "Grief", "sides": 6, "kind": "attack"}]},
				],
				"weakness": "lore", "loot": "", "figure": "abbess"}
	push_error("Unknown foe " + id)
	return {}


## Social opponents for Contests.
static func opponent(id: String) -> Dictionary:
	match id:
		"odile":
			return {"id": id, "name": "Odile, keeper of the Drowned Lamb", "resolve": 12,
				"dice": [{"name": "Doubt", "sides": 6}, {"name": "Doubt", "sides": 6}], "traits": []}
		"kettle":
			return {"id": id, "name": "Mother Kettle", "resolve": 14,
				"dice": [{"name": "Haggle", "sides": 6}, {"name": "Haggle", "sides": 6}], "traits": ["card_sharp"]}
		"kettle_threat":
			return {"id": id, "name": "Mother Kettle", "resolve": 18,
				"dice": [{"name": "Scorn", "sides": 8}, {"name": "Scorn", "sides": 6}], "traits": ["card_sharp"]}
		"abbess_name":
			return {"id": id, "name": "Mother Ysolde", "resolve": 18,
				"dice": [{"name": "Grief", "sides": 8}, {"name": "Grief", "sides": 8}], "traits": []}
	push_error("Unknown opponent " + id)
	return {}
