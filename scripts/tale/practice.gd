extends RefCounted
## THE PRACTICE TABLE: twenty challenges with no story stakes, for learning the dice and for the
## M2 playtest gate ("five playtesters each play 20 challenges and can explain why they chose
## their dice"). Every tester meets the same twenty in the same order, so their logs compare.
##
## Grit, Fate, Wounds and the Pouch are reset before each challenge (the "practice_reset"
## effect), so one bad fight never colours the next decision.

const ASPECT_TEXT := {
	"might": "Force it.",
	"guile": "Find the trick to it.",
	"lore": "Work out how it's done.",
	"grace": "Do it lightly, and quickly.",
	"ward": "Brace yourself and endure it.",
}
const ROTATION := ["might", "guile", "lore", "grace", "ward"]

## The twenty, in order: [kind, definition, one line of setting].
static func challenges() -> Array:
	return [
		["test", {"kind": "test", "difficulty": "easy", "title": "The wobbly ladder"},
			"A ladder with a missing rung, and a cask on the top shelf."],
		["contest", {"opponent": "odile", "title": "A word with the innkeeper"},
			"Odile knows something, and she isn't saying it for free."],
		["test", {"kind": "test", "difficulty": "standard", "tries": 2, "title": "The locked chest"},
			"An iron-bound chest. Two tries before someone hears you."],
		["combat", {"foe": "mire_wolf"}, "Yellow eyes in the reeds. The wolf does not wait."],
		["trial", {"kind": "trial", "progress": 17, "danger": 3, "danger_text": "The current takes the boat.", "title": "Across the ford"},
			"Get the cart across before the river rises."],
		["test", {"kind": "test", "difficulty": "standard", "title": "The rope bridge",
			"second": {"aspect": "ward", "target": 6, "label": "Hold on"}},
			"Cross it, and don't let go when it sways."],
		["contest", {"opponent": "kettle", "title": "Haggling at the market"},
			"Mother Kettle has the only boat. She watches your hands."],
		["combat", {"foe": "drowned_pair"}, "Two grey men walk out of the water."],
		["test", {"kind": "test", "difficulty": "hard", "tries": 2, "title": "The old cipher"},
			"A page of numbers no one has read in forty years."],
		["trial", {"kind": "trial", "progress": 20, "danger": 4, "danger_text": "The fire reaches the stair.", "title": "The burning mill"},
			"Get the miller's family out before the roof comes down."],
		["contest", {"opponent": "kettle_threat", "title": "Facing down a smuggler"},
			"Kettle again, and this time she isn't haggling."],
		["combat", {"foe": "mire_wolf"}, "Another wolf, hungrier than the first."],
		["test", {"kind": "test", "difficulty": "standard", "title": "The night watch"},
			"Stay awake until dawn, and notice what moves."],
		["trial", {"kind": "trial", "progress": 18, "danger": 3, "danger_text": "The candle gutters.", "title": "The last candle"},
			"Copy the map before the candle burns out."],
		["test", {"kind": "test", "difficulty": "easy", "title": "The frightened horse",
			"second": {"aspect": "grace", "target": 5, "label": "Calm it"}},
			"Catch the bolting horse, then calm it."],
		["combat", {"foe": "kettle_knives"}, "Three knives come out together in the alley."],
		["contest", {"opponent": "abbess_name", "title": "Grief at the water's edge"},
			"A drowned nun asks you why you came."],
		["test", {"kind": "test", "difficulty": "hard", "title": "The cliff path"},
			"A goat track, a long drop, and the wind getting up."],
		["trial", {"kind": "trial", "progress": 20, "danger": 3, "danger_text": "Your breath gives out.", "title": "The sunken stair"},
			"Swim down to the door at the bottom of the stair."],
		["combat", {"foe": "abbess"}, "The Drowned Abbess rises from the lake. The last one."],
	]


static func tale() -> Dictionary:
	var scenes := {}
	var list := challenges()
	scenes["prepare"] = {
		"id": "prepare", "title": "The Practice Table", "act": 1, "type": "prepare", "goto": "c1",
		"text": [
			"[i]A practice hand, then. No tale tonight, no cost: just you and the dice, twenty times over.[/i]",
			"[i]Pack a Pouch the way you would for a real tale. After every challenge your Grit, Fate and Pouch come back to you whole.[/i]",
		],
	}
	for i in list.size():
		var entry: Array = list[i]
		var id := "c%d" % (i + 1)
		var nxt := "c%d" % (i + 2) if i + 1 < list.size() else "ending"
		var opt := {"id": "take", "text": "Take it on.", "outcomes": _outcomes(nxt)}
		match entry[0]:
			"combat":
				opt.combat = entry[1]
			"contest":
				opt.contest = entry[1]
				opt.approaches = _approaches(i)
				opt.outcomes.caught = {"text": "[i]Caught with a loaded die. In a real tale, that would follow you.[/i]", "goto": nxt}
			_:
				opt.challenge = entry[1]
				opt.approaches = _approaches(i)
		var title: String = entry[1].get("title", "")
		if entry[0] == "combat":
			title = "A fight"
		scenes[id] = {
			"id": id, "title": "%d of %d: %s" % [i + 1, list.size(), title], "act": 1 + i * 3 / list.size(),
			"type": "choice", "on_enter": [["practice_reset"]],
			"text": [entry[2]],
			"options": [opt],
		}
	scenes["ending"] = {
		"id": "ending", "title": "Practice Done", "act": 3, "type": "ending",
		"endings": [{"id": "practice", "title": "Practice done", "cond": "",
			"text": ["[i]Twenty throws of the dice. You know them a little better now, and they know you.[/i]"],
			"effects": []}],
	}
	return {"id": "practice", "title": "The Practice Table", "patron": "", "start": "prepare", "scenes": scenes}


## Three approaches, rotating through the aspects so every one comes up.
static func _approaches(i: int) -> Array:
	var out: Array = []
	for k in 3:
		var a: String = ROTATION[(i * 2 + k) % ROTATION.size()]
		out.append({"aspect": a, "text": ASPECT_TEXT[a]})
	return out


static func _outcomes(nxt: String) -> Dictionary:
	return {
		"triumph": {"text": "[i]Beautifully done.[/i]", "goto": nxt},
		"success": {"text": "[i]Done, and cleanly.[/i]", "goto": nxt},
		"mixed": {"text": "[i]Done, but it costs you. In a real tale, this is where you would choose the price.[/i]", "goto": nxt,
			"costs": [
				{"label": "Pay in Grit (lose 2 Grit)", "effects": [["grit", -2]]},
				{"label": "Pay in Coin (lose 2 Coin)", "effects": [["coin", -2]]},
			]},
		"fail": {"text": "[i]Not this time. In a real tale the story would go on anyway, a darker way.[/i]", "goto": nxt},
	}
