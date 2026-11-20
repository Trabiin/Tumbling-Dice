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

const FOE_IDS := ["mire_wolf", "drowned_pair", "kettle_knives", "abbess",
	"hollowmen", "ormond", "tide_guard", "lake_wrath", "deserters", "outriders", "sappers", "harrow"]
const OPPONENT_IDS := ["odile", "kettle", "kettle_threat", "abbess_name",
	"pell", "ormond_bid", "court_judge", "drowned_court", "brask", "magistrate", "harrow_parley", "holloway_council"]
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
				"phases": [{"resolve": 18, "traits": ["ghostly"],
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

		# ---- Wren's arc: The Bell Market, The Tide Court
		"hollowmen":
			return {"id": id, "name": "Ormond's Hollowmen", "kind": "minion", "speed": 7,
				"text": "Drowned men in good black coats, bought out of the river and made to stand up. Their buttons are new.",
				"phases": [{"resolve": 16, "traits": ["ghostly"],
					"dice": [{"name": "Grasp", "sides": 6, "kind": "attack"}, {"name": "Grasp", "sides": 6, "kind": "attack"},
						{"name": "Boathook", "sides": 8, "kind": "attack"}],
					"split": 8}],
				"weakness": "lore", "loot": "", "figure": "drowned"}
		"ormond":
			return {"id": id, "name": "Ormond Vane, Collector", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "A thin man in river-green, with a silver-headed cane and the patient smile of somebody who buys the dead.",
				"phases": [
					{"resolve": 16, "traits": ["relentless"], "title": "The Collector",
						"dice": [{"name": "Cane", "sides": 8, "kind": "attack"}, {"name": "Cloak", "sides": 6, "kind": "guard"}],
						"wardens": [{"name": "Hollowman", "sides": 4, "kind": "attack"}]},
					{"resolve": 10, "traits": ["ghostly"], "title": "The River Answers", "danger": 4,
						"danger_text": "The river comes up over the quay, cold to the knee.",
						"dice": [{"name": "Toll", "sides": 6, "kind": "toll"}, {"name": "Drown", "sides": 8, "kind": "attack"}]},
				],
				"weakness": "grace", "loot": "", "figure": "mage"}
		"tide_guard":
			return {"id": id, "name": "The Tide Guard", "kind": "elite", "speed": 8,
				"text": "Drowned soldiers of some old war, in green bronze, standing to attention on the lake floor.",
				"phases": [{"resolve": 22, "traits": ["relentless"],
					"dice": [{"name": "Spear", "sides": 8, "kind": "attack"}, {"name": "Spear", "sides": 6, "kind": "attack"},
						{"name": "Shield", "sides": 8, "kind": "guard"}]}],
				"weakness": "lore", "loot": "tide_d8", "figure": "warrior"}
		"lake_wrath":
			return {"id": id, "name": "The Lake's Wrath", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "There is no judge on the throne. There is only the water, and the water is angry.",
				"phases": [
					{"resolve": 18, "traits": ["ghostly"], "title": "The Court Rises",
						"dice": [{"name": "Wave", "sides": 8, "kind": "attack"}, {"name": "Undertow", "sides": 6, "kind": "toll"}],
						"wardens": [{"name": "Drowned", "sides": 4, "kind": "attack"}]},
					{"resolve": 12, "traits": ["relentless"], "title": "The Deep", "danger": 5,
						"danger_text": "The light goes green, then black.",
						"dice": [{"name": "Crush", "sides": 10, "kind": "attack"}, {"name": "Grief", "sides": 6, "kind": "attack"}]},
				],
				"weakness": "ward", "loot": "", "figure": "warrior"}

		# ---- Captain Ashgrove's arc: The Last Watch, The Pretender's Road, Siege of Holloway
		"deserters":
			return {"id": id, "name": "Brask's Deserters", "kind": "elite", "speed": 10,
				"text": "Five men in what is left of the Greyfell livery, with the badges cut off. They were soldiers once. They remember how.",
				"phases": [{"resolve": 22, "traits": ["ambush"],
					"dice": [{"name": "Axe", "sides": 8, "kind": "attack"}, {"name": "Club", "sides": 6, "kind": "attack"},
						{"name": "Shield", "sides": 6, "kind": "guard"}]}],
				"weakness": "ward", "loot": "deserter_d6", "figure": "innkeeper"}
		"outriders":
			return {"id": id, "name": "The Pretender's Outriders", "kind": "elite", "speed": 12,
				"text": "Three riders in Harrow's black and gold, lances down, coming at a canter that is about to become a charge.",
				"phases": [{"resolve": 20, "traits": ["hamstring"],
					"dice": [{"name": "Lance", "sides": 10, "kind": "attack"}, {"name": "Sword", "sides": 6, "kind": "attack"}]}],
				"weakness": "guile", "loot": "outrider_d8", "figure": "knight"}
		"sappers":
			return {"id": id, "name": "Harrow's Sappers", "kind": "minion", "speed": 6,
				"text": "Men with picks and pitch, digging under Holloway's wall by lantern light.",
				"phases": [{"resolve": 16, "traits": [],
					"dice": [{"name": "Pick", "sides": 6, "kind": "attack"}, {"name": "Pick", "sides": 6, "kind": "attack"},
						{"name": "Pitch", "sides": 4, "kind": "attack"}],
					"split": 8}],
				"weakness": "might", "loot": "", "figure": "smuggler"}
		"harrow":
			return {"id": id, "name": "Harrow, the Pretender", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "Lord Marshal Harrow, who would be king, in black plate with a gold circlet welded to the helm. He fights like a man who has never once doubted he was right.",
				"phases": [
					{"resolve": 20, "traits": ["relentless"], "title": "The Breach",
						"dice": [{"name": "Sword", "sides": 10, "kind": "attack"}, {"name": "Shield", "sides": 8, "kind": "guard"}],
						"wardens": [{"name": "Men-at-arms", "sides": 6, "kind": "attack"}]},
					{"resolve": 14, "traits": ["hamstring"], "title": "The Pretender Alone",
						"dice": [{"name": "Sword", "sides": 10, "kind": "attack"}, {"name": "Fury", "sides": 8, "kind": "attack"}]},
				],
				"weakness": "guile", "loot": "", "figure": "knight"}
	push_error("Unknown foe " + id)
	return {}


## Social opponents for Contests.
static func opponent(id: String) -> Dictionary:
	match id:
		"odile":
			return {"id": id, "name": "Odile, keeper of the Drowned Lamb", "resolve": 15,
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
		"pell":
			return {"id": id, "name": "Pell the fence", "resolve": 14,
				"dice": [{"name": "Haggle", "sides": 6}, {"name": "Haggle", "sides": 6}], "traits": ["card_sharp"]}
		"ormond_bid":
			return {"id": id, "name": "Ormond Vane", "resolve": 18,
				"dice": [{"name": "Purse", "sides": 8}, {"name": "Purse", "sides": 6}], "traits": []}
		"court_judge":
			return {"id": id, "name": "The Judge of the Tide Court", "resolve": 16,
				"dice": [{"name": "Judgement", "sides": 8}, {"name": "Judgement", "sides": 6}], "traits": []}
		"drowned_court":
			return {"id": id, "name": "The Drowned Court", "resolve": 20,
				"dice": [{"name": "Grief", "sides": 8}, {"name": "Grief", "sides": 8}], "traits": []}
		"brask":
			return {"id": id, "name": "Sergeant Brask", "resolve": 15,
				"dice": [{"name": "Pride", "sides": 6}, {"name": "Shame", "sides": 6}], "traits": []}
		"magistrate":
			return {"id": id, "name": "Magistrate Coyle", "resolve": 17,
				"dice": [{"name": "Doubt", "sides": 8}, {"name": "Seal", "sides": 6}], "traits": ["card_sharp"]}
		"harrow_parley":
			return {"id": id, "name": "Harrow, the Pretender", "resolve": 20,
				"dice": [{"name": "Scorn", "sides": 8}, {"name": "Scorn", "sides": 8}], "traits": []}
		"holloway_council":
			return {"id": id, "name": "The Holloway council", "resolve": 14,
				"dice": [{"name": "Fear", "sides": 6}, {"name": "Fear", "sides": 6}], "traits": []}
	push_error("Unknown opponent " + id)
	return {}
