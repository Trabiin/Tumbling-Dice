extends RefCounted
## Dice as data: every die in the game is a Dictionary built by make().
## Pure rules code: no nodes, no rendering. The table turns these into physical dice.
##
## Die fields:
##   id        unique instance id ("oak_might_1")
##   base      type id from CATALOG ("oak_d6")
##   name      display name
##   sides     4, 6, 8, 10, 12 or 20
##   aspect    "might" | "guile" | "lore" | "grace" | "ward" | "wild"
##   material  "oak" | "dragon" | "amethyst" | "jade" | "bone" | "brass" | "bellmetal" | "driftwood"
##   rarity    "common" | "fine" | "masterwork" | "relic" | "cursed"
##   weight    pouch weight (from shape unless overridden)
##   faces     Array of {n: int, rune: String}, index = physical face slot (value - 1)
##   loaded_face, load   optional physical bias (see die.gd)
##   cursed, curse       a cursed die cannot leave the Pouch; curse text for the tooltip
##   ally      true for dice lent for one tale (they leave at the end)
##   notches, grudge, history, epithet   what the die has been through

const ASPECTS := ["might", "guile", "lore", "grace", "ward"]
const ASPECT_NAMES := {"might": "Might", "guile": "Guile", "lore": "Lore", "grace": "Grace", "ward": "Ward",
	"wild": "Wild", "any": "Any"}
## Colour-independent glyphs: aspects are marked by a letter on the die tile and the slot.
const ASPECT_GLYPH := {"might": "M", "guile": "G", "lore": "L", "grace": "R", "ward": "W", "wild": "*", "any": "?"}
const ASPECT_COLOR := {"might": Color("#c4231c"), "guile": Color("#7a3fd0"), "lore": Color("#1f8a5a"),
	"grace": Color("#c9b88a"), "ward": Color("#b8892e"), "wild": Color("#e0e0e0"), "any": Color("#8a7a6a")}
const SHAPE_WEIGHT := {4: 1, 6: 1, 8: 2, 10: 2, 12: 3, 20: 4}

## The eight runes of the slice. Each fires when its face lands, assigned or not.
const RUNES := {
	"strike": "Strike: deal this face as damage to a foe",
	"guard": "Guard: block damage equal to this face",
	"mend": "Mend: restore 2 Grit",
	"spark": "Spark: gain 1 Fate",
	"echo": "Echo: throw this die again and add the new number",
	"keen": "Keen: counts double in a slot of its own aspect",
	"kin": "Kin: +2 to every other die of the same aspect thrown with it",
	"bane": "Bane: something bad happens (named on the die)",
}
## ASCII marks only: Cinzel has no symbol glyphs.
const RUNE_GLYPH := {"strike": "!", "guard": "#", "mend": "+", "spark": "*", "echo": ">", "keen": "^",
	"kin": "&", "bane": "~", "": ""}

## Material traits, from the design doc (Glint adapted for free assignment; see README).
const MATERIALS := {
	"oak": {"name": "Oak", "trait": "", "text": "Plain oak. Cheap, honest, light."},
	"dragon": {"name": "Dragon's Blood", "trait": "ember", "text": "Ember: its highest face sets a foe Burning (2 damage a round for 3 rounds)."},
	"amethyst": {"name": "Arcane Amethyst", "trait": "glint", "text": "Glint: when it lands even it counts in full in any slot."},
	"jade": {"name": "Elven Jade", "trait": "clarity", "text": "Clarity: while it is in your Hand you see the odds of a foe's next throw."},
	"bone": {"name": "Ancient Bone", "trait": "lightfoot", "text": "Lightfoot: when it lands cocked you choose either leaning face for free."},
	"brass": {"name": "Dwarven Brass", "trait": "steadfast", "text": "Steadfast: never cocks, and the tray's quakes cannot move it."},
	"bellmetal": {"name": "Bellmetal", "trait": "toll", "text": "It hums when the lake is near."},
	"driftwood": {"name": "Driftwood", "trait": "", "text": "Grey, salt-stiff, older than it looks."},
}

## Physics feel per material, read by the table when it spawns the die.
const PHYSICS := {
	"oak": {"mass": 0.8, "bounce": 0.3, "friction": 0.55},
	"dragon": {"mass": 1.0, "bounce": 0.25, "friction": 0.55},
	"amethyst": {"mass": 1.0, "bounce": 0.25, "friction": 0.42},
	"jade": {"mass": 1.3, "bounce": 0.12, "friction": 0.6},
	"bone": {"mass": 0.6, "bounce": 0.42, "friction": 0.5},
	"brass": {"mass": 2.2, "bounce": 0.05, "friction": 0.7},
	"bellmetal": {"mass": 2.0, "bounce": 0.1, "friction": 0.6},
	"driftwood": {"mass": 0.7, "bounce": 0.3, "friction": 0.6},
}

## Measured by stats.gd over 2,000 physical throws: the prototype's loaded d6 (load 0.3)
## lands on its favoured face 75.5% of the time. Odds use this, never an assumption.
const LOADED_HIT := 0.755
## Every die base create() knows (the linter checks gain/ally effects against it).
const ALL_IDS := ["oak_might", "oak_guile", "oak_lore", "oak_grace", "oak_ward", "dragon_d10", "brass_d8", "jade_d8", "bone_d6", "amethyst_d6", "loaded_d6", "bone_d4", "jade_d10", "dragon_d12", "brass_d4", "knuckle_d4", "brine_d6", "fisher_bone_d6", "hobb_oak_d6", "hook_d6", "kettle_knife_d8", "bellmetal_d20", "rosary_d12", "bellshard_d8", "wild_d4"]

static var _serial := 0


## Build a die. opts: name, faces (Array[int]), runes ({face_value: rune}), rarity, weight,
## loaded_face, load, cursed, curse, bane (what its Bane rune does), ally, desc.
static func make(base: String, sides: int, aspect: String, material: String, opts := {}) -> Dictionary:
	_serial += 1
	var nums: Array = opts.get("faces", range(1, sides + 1))
	assert(nums.size() == sides, "%s: %d faces for a d%d" % [base, nums.size(), sides])
	var runes: Dictionary = opts.get("runes", {})
	var faces: Array = []
	for i in sides:
		faces.append({"n": int(nums[i]), "rune": String(runes.get(i + 1, ""))})
	var d := {
		"id": "%s_%d" % [base, _serial],
		"base": base,
		"name": opts.get("name", "%s d%d" % [MATERIALS[material].name, sides]),
		"sides": sides,
		"aspect": aspect,
		"material": material,
		"rarity": opts.get("rarity", "common"),
		"weight": opts.get("weight", SHAPE_WEIGHT[sides]),
		"faces": faces,
		"cursed": opts.get("cursed", false),
		"curse": opts.get("curse", ""),
		"bane": opts.get("bane", ""),
		"ally": opts.get("ally", false),
		"desc": opts.get("desc", ""),
		"notches": 0,
		"grudge": "",
		"history": [],
		"epithet": "",
	}
	if opts.has("loaded_face"):
		d.loaded_face = opts.loaded_face
		d.load = opts.get("load", 0.3)
	return d


## Every die type in the slice, by base id. Starter shelf, tale rewards, foe drops.
static func create(base: String) -> Dictionary:
	match base:
		# ---- the starter shelf (Collection at the start of a campaign)
		"oak_might": return make(base, 6, "might", "oak", {"name": "Oak d6 of Might"})
		"oak_guile": return make(base, 6, "guile", "oak", {"name": "Oak d6 of Guile"})
		"oak_lore": return make(base, 6, "lore", "oak", {"name": "Oak d6 of Lore"})
		"oak_grace": return make(base, 6, "grace", "oak", {"name": "Oak d6 of Grace"})
		"oak_ward": return make(base, 6, "ward", "oak", {"name": "Oak d6 of Ward"})
		"dragon_d10": return make(base, 10, "might", "dragon", {"name": "Dragon's Blood d10",
			"runes": {9: "strike", 10: "strike"}, "rarity": "fine",
			"desc": "Red resin with a black heart. It wants to hit something."})
		"brass_d8": return make(base, 8, "ward", "brass", {"name": "Dwarven Brass d8",
			"runes": {7: "guard", 8: "guard"}, "rarity": "fine",
			"desc": "Heavy as a promise. It lands where it lands."})
		"jade_d8": return make(base, 8, "lore", "jade", {"name": "Elven Jade d8",
			"runes": {8: "keen"}, "rarity": "fine",
			"desc": "Cool to the touch, green as deep water."})
		"bone_d6": return make(base, 6, "grace", "bone", {"name": "Ancient Bone d6",
			"runes": {6: "echo"}, "rarity": "fine",
			"desc": "Light and skittish. Nobody remembers whose bone."})
		"amethyst_d6": return make(base, 6, "guile", "amethyst", {"name": "Arcane Amethyst d6",
			"runes": {6: "spark"}, "rarity": "fine",
			"desc": "Starlight caught in purple glass. It glints when it lies."})
		"loaded_d6": return make(base, 6, "guile", "bone", {"name": "Loaded d6", "loaded_face": 6, "load": 0.3,
			"rarity": "fine", "desc": "Lead behind the one. It lands on six three times in four, and card sharps know the look of it."})
		"bone_d4": return make(base, 4, "grace", "bone", {"name": "Bone d4", "runes": {4: "kin"},
			"desc": "A knucklebone carved to a point. It likes company."})
		"jade_d10": return make(base, 10, "lore", "jade", {"name": "Elven Jade d10",
			"runes": {1: "mend", 10: "mend"}, "rarity": "fine",
			"desc": "A healer's die. The ones and tens are worn smooth."})
		"dragon_d12": return make(base, 12, "might", "dragon", {"name": "Dragon's Blood d12",
			"runes": {1: "bane", 12: "strike"}, "bane": "grit", "rarity": "fine",
			"desc": "Huge and hungry. On a one it bites the hand that threw it (lose 2 Grit)."})
		"brass_d4": return make(base, 4, "ward", "brass", {"name": "Brass d4", "runes": {4: "guard"}})

		# ---- found in The Drowned Bell
		"knuckle_d4": return make(base, 4, "ward", "driftwood", {"name": "Drowned Man's Knuckle d4",
			"faces": [2, 2, 3, 4], "runes": {4: "guard"},
			"desc": "Fished out of the silt when the shore threw you down. No face lower than two."})
		"brine_d6": return make(base, 6, "ward", "driftwood", {"name": "Brine d6",
			"runes": {5: "guard", 6: "guard"},
			"desc": "Dropped by a Drowned. It is always a little damp."})
		"fisher_bone_d6": return make(base, 6, "grace", "bone", {"name": "Fisher's Bone d6",
			"runes": {6: "spark"},
			"desc": "A widow's gift. Her husband carved it on long nights at sea."})
		"hobb_oak_d6": return make(base, 6, "ward", "oak", {"name": "Hobb's Oak d6",
			"runes": {6: "guard"}, "ally": true,
			"desc": "Wren's father's die, lent for one night. Bring it back."})
		"hook_d6": return make(base, 6, "guile", "brass", {"name": "Smuggler's Hook d6",
			"runes": {5: "strike", 6: "spark"}, "ally": true,
			"desc": "Mother Kettle's crew lend it to friends. They expect it back."})
		"kettle_knife_d8": return make(base, 8, "guile", "brass", {"name": "Kettle's Knife d8",
			"runes": {7: "strike", 8: "strike"}, "rarity": "fine",
			"desc": "Taken from her crew. The Thieves' Guild will know it on sight."})
		"bellmetal_d20": return make(base, 20, "might", "bellmetal", {"name": "Bellmetal d20",
			"faces": [1, 2, 3, 8, 9, 10, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 17, 18, 19, 20],
			"runes": {1: "bane", 2: "bane", 20: "strike"}, "bane": "fate", "rarity": "cursed", "cursed": true,
			"curse": "At every Waystone it tolls: throw it, and on 3 or lower lose 1 Fate. It cannot leave your Pouch.",
			"desc": "Gold from the drowned bell, still ringing faintly. Its faces are huge. So is its hunger."})
		"rosary_d12": return make(base, 12, "lore", "jade", {"name": "Abbess's Rosary d12",
			"runes": {9: "mend", 10: "mend", 11: "mend", 12: "mend"}, "rarity": "relic",
			"desc": "Mother Ysolde's beads, strung into a die. It is warm, like a held hand."})
		"bellshard_d8": return make(base, 8, "ward", "bellmetal", {"name": "Bellmetal Shard d8",
			"faces": [2, 3, 4, 5, 6, 7, 8, 8], "runes": {6: "guard", 7: "guard", 8: "guard"}, "rarity": "masterwork",
			"desc": "A piece of the broken bell. The abbey is silent forever."})
		"wild_d4": return make(base, 4, "wild", "amethyst", {"name": "Wanderer's Wild d4", "rarity": "fine",
			"desc": "Counts in full for any aspect. Nobody sells these."})
	push_error("Unknown die base: " + base)
	return {}


## The Collection a new campaign starts with: more than the Pouch can hold, so the first
## real decision is what to leave on the shelf. Total weight 21 against a limit of 12.
static func starter_collection() -> Array:
	var out: Array = []
	for b in ["oak_might", "oak_guile", "oak_lore", "oak_grace", "oak_ward", "dragon_d10", "brass_d8",
			"jade_d8", "bone_d6", "amethyst_d6", "loaded_d6", "bone_d4", "jade_d10", "dragon_d12", "brass_d4"]:
		out.append(create(b))
	return out


static func face_n(die: Dictionary, face: int) -> int:
	return int(die.faces[face].n)


static func face_rune(die: Dictionary, face: int) -> String:
	return String(die.faces[face].rune)


static func max_n(die: Dictionary) -> int:
	var m := 0
	for f in die.faces:
		m = maxi(m, int(f.n))
	return m


static func min_n(die: Dictionary) -> int:
	var m := 999
	for f in die.faces:
		m = mini(m, int(f.n))
	return m


static func mean_n(die: Dictionary) -> float:
	var p := dist(die)
	var s := 0.0
	for i in die.sides:
		s += p[i] * die.faces[i].n
	return s


static func trait_of(die: Dictionary) -> String:
	return MATERIALS[die.material].trait


## Probability of each physical face landing up. Fair dice are uniform (stats.gd confirms it);
## a loaded die uses the measured hit rate.
static func dist(die: Dictionary) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(die.sides)
	if die.has("loaded_face"):
		var other: float = (1.0 - LOADED_HIT) / (die.sides - 1)
		p.fill(other)
		p[die.loaded_face - 1] = LOADED_HIT
	else:
		p.fill(1.0 / die.sides)
	return p


## Sample a face index from the die's distribution.
static func sample(die: Dictionary, rng: RandomNumberGenerator) -> int:
	if not die.has("loaded_face"):
		return rng.randi_range(0, die.sides - 1)
	var p := dist(die)
	var r := rng.randf()
	for i in die.sides:
		r -= p[i]
		if r <= 0.0:
			return i
	return die.sides - 1


## A short face list for tooltips: "1 2 3 4 5 6*".
static func faces_text(die: Dictionary) -> String:
	var parts: Array[String] = []
	for f in die.faces:
		parts.append("%d%s" % [f.n, RUNE_GLYPH.get(f.rune, "")])
	return " ".join(parts)


static func tooltip(die: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("%s  (%s, weight %d)" % [die.name, ASPECT_NAMES[die.aspect], die.weight])
	lines.append("Faces: " + faces_text(die))
	var seen := {}
	for f in die.faces:
		if f.rune != "" and not seen.has(f.rune):
			seen[f.rune] = true
			var t: String = RUNES[f.rune]
			if f.rune == "bane":
				t = "Bane: " + {"grit": "lose 2 Grit", "fate": "lose 1 Fate"}.get(die.bane, "a curse stirs")
			lines.append(t)
	var mt: String = MATERIALS[die.material].text
	if mt != "":
		lines.append(mt)
	if die.has("loaded_face"):
		lines.append("Loaded: lands on %d about %d%% of the time." % [die.faces[die.loaded_face - 1].n, roundi(LOADED_HIT * 100)])
	if die.cursed:
		lines.append("Cursed. " + die.curse)
	if die.ally:
		lines.append("Lent for this tale only.")
	if die.epithet != "":
		lines.append("Epithet: " + die.epithet)
	if die.notches > 0:
		lines.append("Notches: %d" % die.notches)
	if die.grudge != "":
		lines.append("Holds a Grudge: +1 in its next %s." % die.grudge)
	if die.desc != "":
		lines.append(die.desc)
	for h in die.history.slice(-3):
		lines.append("· " + h)
	return "\n".join(lines)
