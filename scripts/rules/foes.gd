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
	"hollowmen", "ormond", "tide_guard", "lake_wrath", "deserters", "outriders", "sappers", "harrow",
	"moor_hounds", "river_watch", "seawatch_guard", "dukes_men", "assayer", "kettle_crew",
	"willow_men", "huntsman", "reliquary_thieves", "hollow_saint", "king_of_hollows", "cinder_smith"]
const OPPONENT_IDS := ["odile", "kettle", "kettle_threat", "abbess_name",
	"pell", "ormond_bid", "court_judge", "drowned_court", "brask", "magistrate", "harrow_parley", "holloway_council",
	"absalom", "purser", "grisewold", "watch_captain", "steward", "isolde", "duke_parley", "lock_keeper", "kettle_final",
	"willow_elder", "mag_sallow", "prior_anselm", "king_wager", "cinder_smith_parley", "fae_queen"]
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
				"weakness": "grace", "loot": "", "figure": "wolf"}
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
				"phases": [{"resolve": 24, "traits": ["thief", "ambush"],
					"dice": [{"name": "Knife", "sides": 8, "kind": "attack"}, {"name": "Knife", "sides": 8, "kind": "attack"},
						{"name": "Cudgel", "sides": 6, "kind": "guard"}]}],
				"weakness": "grace", "loot": "kettle_knife_d8", "figure": "smuggler"}
		"abbess":
			return {"id": id, "name": "The Drowned Abbess", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "Mother Ysolde, forty years under the lake, her habit drifting like weed.",
				"phases": [
					{"resolve": 16, "traits": ["ghostly"], "title": "The Toll",
						"dice": [{"name": "Toll", "sides": 6, "kind": "toll"}, {"name": "Grief", "sides": 8, "kind": "attack"}],
						"wardens": [{"name": "Wardens", "sides": 4, "kind": "attack"}]},
					{"resolve": 10, "traits": ["relentless"], "title": "Under the Water", "danger": 5,
						"danger_text": "The water closes over your head.",
						"dice": [{"name": "Drag", "sides": 8, "kind": "attack"}, {"name": "Grief", "sides": 6, "kind": "attack"}]},
				],
				"weakness": "lore", "loot": "", "figure": "abbess"}

		# ---- Wren's arc: The Bell Market, The Tide Court
		"hollowmen":
			return {"id": id, "name": "Ormond's Hollowmen", "kind": "minion", "speed": 7,
				"text": "Drowned men in good black coats, bought out of the river and made to stand up. Their buttons are new.",
				"phases": [{"resolve": 18, "traits": ["ghostly"],
					"dice": [{"name": "Grasp", "sides": 6, "kind": "attack"}, {"name": "Grasp", "sides": 6, "kind": "attack"},
						{"name": "Boathook", "sides": 8, "kind": "attack"}],
					"split": 8}],
				"weakness": "lore", "loot": "", "figure": "drowned"}
		"ormond":
			return {"id": id, "name": "Ormond Vane, Collector", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "A thin man in river-green, with a silver-headed cane and the patient smile of somebody who buys the dead.",
				"phases": [
					{"resolve": 18, "traits": ["relentless"], "title": "The Collector",
						"dice": [{"name": "Cane", "sides": 8, "kind": "attack"}, {"name": "Cloak", "sides": 6, "kind": "guard"}],
						"wardens": [{"name": "Hollowman", "sides": 4, "kind": "attack"}]},
					{"resolve": 12, "traits": ["ghostly"], "title": "The River Answers", "danger": 4,
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
				"phases": [{"resolve": 24, "traits": ["ambush"],
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
				"phases": [{"resolve": 14, "traits": [],
					"dice": [{"name": "Pick", "sides": 6, "kind": "attack"}, {"name": "Pick", "sides": 6, "kind": "attack"},
						{"name": "Pitch", "sides": 4, "kind": "attack"}],
					"split": 8}],
				"weakness": "might", "loot": "", "figure": "smuggler"}
		"harrow":
			return {"id": id, "name": "Harrow, the Pretender", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "Lord Marshal Harrow, who would be king, in black plate with a gold circlet welded to the helm. He fights like a man who has never once doubted he was right.",
				"phases": [
					{"resolve": 18, "traits": ["relentless"], "title": "The Breach",
						"dice": [{"name": "Sword", "sides": 10, "kind": "attack"}, {"name": "Shield", "sides": 8, "kind": "guard"}],
						"wardens": [{"name": "Men-at-arms", "sides": 6, "kind": "attack"}]},
					{"resolve": 12, "traits": ["hamstring"], "title": "The Pretender Alone",
						"dice": [{"name": "Sword", "sides": 10, "kind": "attack"}, {"name": "Fury", "sides": 8, "kind": "attack"}]},
				],
				"weakness": "guile", "loot": "", "figure": "knight"}
		# ---- the prologue: The Stranger's Throw
		"moor_hounds":
			return {"id": id, "name": "Moor Hounds", "kind": "minion", "speed": 8,
				"text": "Two lean grey hounds gone wild on the moor, ribs showing, circling the stone.",
				"phases": [{"resolve": 10, "traits": [],
					"dice": [{"name": "Fang", "sides": 6, "kind": "attack"}, {"name": "Fang", "sides": 4, "kind": "attack"}],
					"split": 5}],
				"weakness": "grace", "loot": "", "figure": "wolf"}

		# ---- Mother Kettle's arc: The Long Con, The Duke's Ledger, The Gilded Ruin
		"river_watch":
			return {"id": id, "name": "The Duke's River Watch", "kind": "elite", "speed": 10,
				"text": "Six men in the Duke's blue with boathooks and lanterns, and a sergeant who has been waiting all evening for this.",
				"phases": [{"resolve": 20, "traits": ["ambush"],
					"dice": [{"name": "Boathook", "sides": 8, "kind": "attack"}, {"name": "Cudgel", "sides": 6, "kind": "attack"},
						{"name": "Lantern", "sides": 6, "kind": "guard"}]}],
				"weakness": "grace", "loot": "", "figure": "warrior"}
		"seawatch_guard":
			return {"id": id, "name": "The Seawatch Guard", "kind": "elite", "speed": 11,
				"text": "The Duke's household guard, in silver masks for the masque, with very real swords under the silk.",
				"phases": [{"resolve": 22, "traits": ["relentless"],
					"dice": [{"name": "Rapier", "sides": 8, "kind": "attack"}, {"name": "Rapier", "sides": 6, "kind": "attack"},
						{"name": "Buckler", "sides": 6, "kind": "guard"}]}],
				"weakness": "guile", "loot": "", "figure": "knight"}
		"dukes_men":
			return {"id": id, "name": "The Duke's Last Men", "kind": "elite", "speed": 9,
				"text": "Hired swords from across the river, paid in gold they haven't seen yet, and not happy about it.",
				"phases": [{"resolve": 20, "traits": ["hamstring"],
					"dice": [{"name": "Sword", "sides": 8, "kind": "attack"}, {"name": "Crossbow", "sides": 8, "kind": "attack"}]}],
				"weakness": "lore", "loot": "", "figure": "warrior"}
		"assayer":
			return {"id": id, "name": "The Assayer", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "The old Mint's keeper: a man of gilded brass and clockwork, three hundred years at his scales, weighing everything that comes into the vault, including you.",
				"phases": [
					{"resolve": 18, "traits": ["relentless"], "title": "The Scales",
						"dice": [{"name": "Balance", "sides": 8, "kind": "attack"}, {"name": "Weight", "sides": 8, "kind": "guard"}],
						"wardens": [{"name": "Counting-arms", "sides": 4, "kind": "attack"}]},
					{"resolve": 12, "traits": ["hamstring"], "title": "Found Wanting", "danger": 5,
						"danger_text": "The vault doors grind shut, and the river comes in under them.",
						"dice": [{"name": "Hammer", "sides": 10, "kind": "attack"}, {"name": "Toll", "sides": 6, "kind": "toll"}]},
				],
				"weakness": "lore", "loot": "", "figure": "warrior"}
		"kettle_crew":
			return {"id": id, "name": "Mother Kettle's Crew", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "Every knife Mother Kettle owns, and Mother Kettle behind them with a crossbow, looking sorry about it.",
				"phases": [
					{"resolve": 18, "traits": ["thief"], "title": "The Knives",
						"dice": [{"name": "Knife", "sides": 8, "kind": "attack"}, {"name": "Knife", "sides": 6, "kind": "attack"}],
						"wardens": [{"name": "Cudgel", "sides": 4, "kind": "attack"}]},
					{"resolve": 10, "traits": ["relentless"], "title": "Mother Kettle",
						"dice": [{"name": "Crossbow", "sides": 10, "kind": "attack"}, {"name": "Shuffle", "sides": 6, "kind": "guard"}]},
				],
				"weakness": "grace", "loot": "", "figure": "kettle"}
		# ---- the Hooded Pilgrim's arc: The Witch of Sallow Wood, The Hollow Saint, The Teller's Tale
		"willow_men":
			return {"id": id, "name": "The Willow Court", "kind": "elite", "speed": 7,
				"text": "The oldest willows in the Wood, with faces of bark and eyes of knots, and arms like whips.",
				"phases": [{"resolve": 20, "traits": ["hamstring", "ghostly"],
					"dice": [{"name": "Lash", "sides": 6, "kind": "attack"}, {"name": "Lash", "sides": 6, "kind": "attack"},
						{"name": "Bark", "sides": 8, "kind": "guard"}]}],
				"weakness": "lore", "loot": "", "figure": "hooded"}
		"huntsman":
			return {"id": id, "name": "The Wood's Huntsman", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "Antlers on his helm, a spear of ash, and a horse made of fog. He has seen out every guest who ever left the Wood in a hurry.",
				"phases": [
					{"resolve": 16, "traits": ["relentless"], "title": "The Ride",
						"dice": [{"name": "Spear", "sides": 8, "kind": "attack"}, {"name": "Hooves", "sides": 6, "kind": "attack"}],
						"wardens": [{"name": "Hounds", "sides": 4, "kind": "attack"}]},
					{"resolve": 10, "traits": ["ghostly"], "title": "On Foot in the Mist",
						"dice": [{"name": "Spear", "sides": 10, "kind": "attack"}, {"name": "Mist", "sides": 6, "kind": "guard"}]},
				],
				"weakness": "lore", "loot": "", "figure": "knight"}
		"reliquary_thieves":
			return {"id": id, "name": "Sister Thorn's Crew", "kind": "elite", "speed": 9,
				"text": "Five burglars in pilgrim grey, with bark on their sleeves and the Wood's green at the edges of their eyes.",
				"phases": [{"resolve": 22, "traits": ["thief"],
					"dice": [{"name": "Knife", "sides": 6, "kind": "attack"}, {"name": "Knife", "sides": 6, "kind": "attack"},
						{"name": "Staff", "sides": 8, "kind": "guard"}]}],
				"weakness": "lore", "loot": "", "figure": "hooded"}
		"hollow_saint":
			return {"id": id, "name": "Saint Hollow", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "A saint of bark and bone in a robe of moss, six hundred years in the ground, empty behind the eyes.",
				"phases": [
					{"resolve": 18, "traits": ["ghostly"], "title": "The Saint Rises",
						"dice": [{"name": "Grief", "sides": 8, "kind": "attack"}, {"name": "Bark", "sides": 6, "kind": "guard"}],
						"wardens": [{"name": "Roots", "sides": 4, "kind": "attack"}]},
					{"resolve": 14, "traits": ["relentless", "ghostly"], "title": "Hollow", "danger": 5,
						"danger_text": "The ground opens under the stones.",
						"dice": [{"name": "Grasp", "sides": 10, "kind": "attack"}, {"name": "Toll", "sides": 6, "kind": "toll"}]},
				],
				"weakness": "grace", "loot": "", "figure": "abbess"}
		"king_of_hollows":
			return {"id": id, "name": "The King of Hollows", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "The Old Wood gathered into one shape: antlers of willow, a face of bark, eyes like green light under deep water.",
				"phases": [
					{"resolve": 20, "traits": ["ghostly"], "title": "The Table Overturned",
						"dice": [{"name": "Antler", "sides": 10, "kind": "attack"}, {"name": "Bark", "sides": 8, "kind": "guard"}],
						"wardens": [{"name": "Willows", "sides": 6, "kind": "attack"}]},
					{"resolve": 14, "traits": ["relentless", "ghostly"], "title": "The Whole Wood", "danger": 5,
						"danger_text": "The Wood closes in, every tree at once.",
						"dice": [{"name": "Root", "sides": 10, "kind": "attack"}, {"name": "Winter", "sides": 6, "kind": "toll"}]},
				],
				"weakness": "guile", "loot": "", "figure": "hooded"}
		# ---- secret tales: The Dicewright's Debt, The Card Sharps' Moon
		"cinder_smith":
			return {"id": id, "name": "The Smith of the Black Forge", "kind": "boss", "speed": 99, "no_flee": true,
				"text": "Cinders and old iron in the shape of a smith, with a furnace door for a face, a thousand years at the anvil.",
				"phases": [
					{"resolve": 18, "traits": ["relentless"], "title": "The Hammer",
						"dice": [{"name": "Hammer", "sides": 10, "kind": "attack"}, {"name": "Anvil", "sides": 8, "kind": "guard"}],
						"wardens": [{"name": "Sparks", "sides": 4, "kind": "attack"}]},
					{"resolve": 12, "traits": ["hamstring"], "title": "The Fire", "danger": 5,
						"danger_text": "The forge roars up, and the heat comes in a wave.",
						"dice": [{"name": "Tongs", "sides": 8, "kind": "attack"}, {"name": "Bellows", "sides": 6, "kind": "toll"}]},
				],
				"weakness": "lore", "loot": "", "figure": "warrior"}
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
		"absalom":
			return {"id": id, "name": "Old Absalom, the bridge-keeper", "resolve": 10,
				"dice": [{"name": "Grumble", "sides": 6}, {"name": "Grumble", "sides": 4}], "traits": []}
		"purser":
			return {"id": id, "name": "Purser Quill", "resolve": 14,
				"dice": [{"name": "Suspicion", "sides": 6}, {"name": "Suspicion", "sides": 6}], "traits": []}
		"grisewold":
			return {"id": id, "name": "Assessor Grisewold", "resolve": 17,
				"dice": [{"name": "Greed", "sides": 8}, {"name": "Bluff", "sides": 6}], "traits": ["card_sharp"]}
		"watch_captain":
			return {"id": id, "name": "Captain Maelis of the River Watch", "resolve": 16,
				"dice": [{"name": "Duty", "sides": 8}, {"name": "Doubt", "sides": 6}], "traits": []}
		"steward":
			return {"id": id, "name": "The Steward of Seawatch House", "resolve": 15,
				"dice": [{"name": "Etiquette", "sides": 6}, {"name": "Etiquette", "sides": 8}], "traits": []}
		"isolde":
			return {"id": id, "name": "Lady Isolde Mallory", "resolve": 14,
				"dice": [{"name": "Wit", "sides": 8}, {"name": "Wit", "sides": 4}], "traits": []}
		"duke_parley":
			return {"id": id, "name": "Duke Orrin Mallory", "resolve": 19,
				"dice": [{"name": "Power", "sides": 8}, {"name": "Purse", "sides": 8}], "traits": ["card_sharp"]}
		"lock_keeper":
			return {"id": id, "name": "Ferrant the lock-keeper", "resolve": 13,
				"dice": [{"name": "Thirst", "sides": 6}, {"name": "Fear", "sides": 6}], "traits": []}
		"kettle_final":
			return {"id": id, "name": "Mother Kettle", "resolve": 20,
				"dice": [{"name": "Shuffle", "sides": 8}, {"name": "Shuffle", "sides": 8}], "traits": ["card_sharp"]}
		"willow_elder":
			return {"id": id, "name": "The Eldest Willow", "resolve": 16,
				"dice": [{"name": "Age", "sides": 8}, {"name": "Patience", "sides": 6}], "traits": []}
		"mag_sallow":
			return {"id": id, "name": "Mag Sallow", "resolve": 17,
				"dice": [{"name": "Cunning", "sides": 8}, {"name": "Cunning", "sides": 6}], "traits": ["card_sharp"]}
		"prior_anselm":
			return {"id": id, "name": "Prior Anselm", "resolve": 15,
				"dice": [{"name": "Worry", "sides": 6}, {"name": "Duty", "sides": 8}], "traits": ["card_sharp"]}
		"king_wager":
			return {"id": id, "name": "The King of Hollows", "resolve": 22,
				"dice": [{"name": "Wood", "sides": 8}, {"name": "Wood", "sides": 8}], "traits": ["card_sharp"]}
		"cinder_smith_parley":
			return {"id": id, "name": "The Smith of the Black Forge", "resolve": 18,
				"dice": [{"name": "Iron", "sides": 8}, {"name": "Fire", "sides": 8}], "traits": ["card_sharp"]}
		"fae_queen":
			return {"id": id, "name": "The Queen of Hours", "resolve": 18,
				"dice": [{"name": "Moonstone", "sides": 8}, {"name": "Moonstone", "sides": 6}], "traits": ["card_sharp"]}
	push_error("Unknown opponent " + id)
	return {}
