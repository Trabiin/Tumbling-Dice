extends RefCounted
## The Teller: an old storyteller at the hearth, never seen. He reacts to the dice, remembers,
## has an opinion of you, and embellishes a little. Never about the mechanics: dice and odds
## are always shown honestly.
##
## line(event, ctx) picks a line keyed to an event, avoiding lines said recently.
## Placeholders: {die} a die's name, {you} how he describes you ("the merciful traveller").

const LINES := {
	"nat_max": [
		"{die} lands on its highest face, and the fire leans in to look.",
		"Now that is a throw. {die} could not have done better if you had placed it by hand.",
		"{die}, showing everything it has. Remember this one.",
		"A perfect face. I have seen grown men weep for less.",
	],
	"nat_one": [
		"{die} shows a one. The candles dip, as if embarrassed for it.",
		"One. Well. {die} will want to make that up to you.",
		"A one, from {die}. Every die has a night like this.",
		"The lowest face. Even I winced, and I have seen it all.",
	],
	"cocked": [
		"{die} has come to rest leaning on the wall, unable to decide. Decide for it.",
		"Neither one face nor the other. {die} is waiting for you.",
	],
	"triumph": [
		"Better than you hoped. Much better. The whole village will hear of this, and I will tell it bigger.",
		"Triumph. They will sing that one in taverns, slightly wrong, for years.",
		"Now, that is how a tale is supposed to go.",
		"Even the fire went quiet for that.",
	],
	"success": [
		"Clean. No more, no less.",
		"It goes as it should. Rare enough, in this tale.",
		"Done, and done well.",
	],
	"mixed": [
		"You get what you came for. The road takes its share.",
		"Through, but not free. Nothing in a tale is free.",
		"Half a victory is still a victory. Choose what it costs you.",
	],
	"fail": [
		"It goes wrong. It was always going to go wrong somewhere. Better here than at the end.",
		"No. Not this time. But the tale goes on, and so do you.",
		"The dice say no. The story does not stop for them.",
		"A failure, and a Fate token for your trouble. Spend it well.",
	],
	"near_miss": [
		"One short. One. I felt that from here.",
		"So close the dice almost argued about it.",
	],
	"pity": [
		"Even I can't watch this. Your highest die gets one more, on me.",
		"Two in a row. Let an old man put his thumb on the scale, just this once, in plain sight.",
	],
	"fatigue": [
		"The Pouch runs dry and you shake it out again. Your hands are tiring.",
		"Back into the bag they go. You are slower to draw now.",
	],
	"high_table": [
		"Every die on its highest face. In forty years at this hearth I have seen it twice. Three times, now.",
	],
	"triple": [
		"Three alike. The dice are agreeing with each other, and that is never an accident.",
	],
	"grudge": [
		"{die} had not forgotten. It comes up stronger for it.",
		"There is {die}, settling its grudge.",
	],
	"downed": [
		"You are down. Throw everything you have.",
	],
	"last_stand_win": [
		"Up again, bleeding and stubborn. The tale will have to try harder.",
	],
	"last_stand_fail": [
		"Hands drag you out of the dark. Not tonight, then. But it will leave a mark.",
	],
	"defy": [
		"You refuse it. Very well. I will remember that you did.",
	],
	"loaded_caught": [
		"Their eyes go to {die}, and stay there. Oh dear.",
	],
	"loaded_safe": [
		"{die} lands on its favourite face, and nobody looks twice. Lucky.",
	],
	"echo": [
		"{die} rings again and keeps going.",
	],
	"fate_spent": [
		"A Fate token clicks onto the table.",
	],
	"wound": [
		"That will not heal tonight.",
		"You will carry that one home.",
	],
	"rest": [
		"A fire, a dry stone, a moment's quiet. You were owed one.",
	],
}

## Opinions he forms of you (by Regard).
const REGARD_ASIDE := {
	-2: "I confess I am not sure I like you, traveller.",
	2: "I am beginning to like you, traveller. Don't let it go to your head.",
	4: "You know, I could swear that guard was asleep. My memory is not what it was.",
}

var recent: Array = []
var rng := RandomNumberGenerator.new()
## The tale's own lines (its teller: header), said alongside the general ones.
var extra := {}
const COOLDOWN := 10


func line(event: String, ctx := {}) -> String:
	var pool: Array = LINES.get(event, []) + extra.get(event, [])
	if pool.is_empty():
		return ""
	var fresh := pool.filter(func(l): return not recent.has(l))
	if fresh.is_empty():
		fresh = pool
	var l: String = fresh[rng.randi_range(0, fresh.size() - 1)]
	recent.append(l)
	if recent.size() > COOLDOWN:
		recent.pop_front()
	return fill(l, ctx)


static func fill(text: String, ctx: Dictionary) -> String:
	var out := text
	for k in ctx:
		out = out.replace("{%s}" % k, str(ctx[k]))
	return out


## Short reaction lines for a settled throw: maximums, ones, combos.
func react_to_throw(ts: Array, combos: Dictionary) -> Array[String]:
	var S = load("res://scripts/rules/scoring.gd")
	var out: Array[String] = []
	if combos.high_table:
		out.append(line("high_table"))
		return out
	if combos.triple:
		out.append(line("triple"))
	for t in ts:
		if t.die.sides >= 8 and S.is_max(t):
			out.append(line("nat_max", {"die": t.die.name}))
			break
	for t in ts:
		if t.die.sides >= 6 and S.face_n(t) == 1:
			out.append(line("nat_one", {"die": t.die.name}))
			break
	return out
