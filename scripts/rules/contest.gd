extends RefCounted
## A social Contest: you against someone who throws back. Each round the opponent throws first
## (their argument lands in the tray), then you throw and split your dice between Press (wears
## down their Resolve) and Hold (blocks their pressure on your Nerve). Up to three rounds.
##
## Card sharps watch for loaded dice: every loaded die you throw in front of one risks being
## spotted, and the odds are shown before you throw.

const S := preload("res://scripts/rules/scoring.gd")
const Dice := preload("res://scripts/rules/dice.gd")

const STANCES := ["press", "hold"]
const NERVE := 10

var opponent: Dictionary       # {name, resolve, dice: [{name, sides}], traits, rounds}
var aspect := "guile"
var resolve := 10
var resolve_start := 10
var nerve := NERVE
var rounds_max := 3
var round_no := 0
var effort := 3
var opp_values: Array = []     # this round's opponent throw
var pressure := 0
var caught := false
var over := false
var history: Array = []


static func create(opp: Dictionary, p_aspect: String, mods := {}):
	var c = load("res://scripts/rules/contest.gd").new()
	c.opponent = opp
	c.aspect = p_aspect
	c.resolve_start = int(opp.resolve) + int(mods.get("resolve", 0))
	c.resolve = c.resolve_start
	c.rounds_max = opp.get("rounds", 3)
	c.effort = opp.get("effort", 3)
	return c


func slots() -> Array:
	return [{"aspect": aspect, "target": resolve, "label": "Press"},
		{"aspect": aspect, "target": pressure, "label": "Hold"}]


func is_card_sharp() -> bool:
	return opponent.get("traits", []).has("card_sharp")


## Chance that a loaded die is spotted: 1 in 2 when it lands on its favoured face, 1 in 6
## otherwise. Shown to the player before throwing.
static func spot_chance(t_or_die: Dictionary, landed_favoured := true) -> float:
	return 0.5 if landed_favoured else 1.0 / 6.0


## Expected chance of being caught if these dice are thrown (before the throw).
func catch_odds(dice: Array) -> float:
	if not is_card_sharp():
		return 0.0
	var safe := 1.0
	for d in dice:
		if d.has("loaded_face"):
			var p_fav := Dice.LOADED_HIT
			safe *= 1.0 - (p_fav * 0.5 + (1.0 - p_fav) / 6.0)
	return 1.0 - safe


func begin_round() -> Array:
	round_no += 1
	return opponent.dice


func set_opponent_throw(values: Array) -> void:
	opp_values = values.duplicate()
	pressure = 0
	for v in values:
		pressure += int(v)


## What this assignment would do. assign[i]: 0 = Press, 1 = Hold, -1 = none.
func simulate(ts: Array, ev: Dictionary, assign: Array, pair_pick := 0) -> Dictionary:
	var vals: Array = ev.vals.duplicate()
	if not ev.combos.pair.is_empty():
		vals[ev.combos.pair[clampi(pair_pick, 0, 1)]] += 2
	var press := 0
	var hold := 0
	for i in ts.size():
		var r := S.rune(ts[i])
		if r == "strike":
			press += S.raw(ts[i])
		elif r == "guard":
			hold += S.raw(ts[i])
		if assign[i] == 0:
			press += S.slot_value(ts[i], vals[i], aspect)
		elif assign[i] == 1:
			hold += S.slot_value(ts[i], vals[i], aspect)
	if ev.combos.high_table:
		press += resolve
	var taken := maxi(0, pressure - hold)
	return {"press": press, "hold": hold, "taken": taken,
		"broken": resolve - press <= 0, "nerve_after": nerve - taken}


func best_assignment(ts: Array, ev: Dictionary) -> Dictionary:
	var n := ts.size()
	var best := {"assign": [], "pair_pick": 0, "score": -INF}
	var picks := [0, 1] if not ev.combos.pair.is_empty() else [0]
	var final := round_no >= rounds_max
	for code in int(pow(2, n)):
		var assign: Array = []
		for i in n:
			assign.append((code >> i) & 1)
		for pp in picks:
			var r := simulate(ts, ev, assign, pp)
			var score: float
			if r.broken:
				score = 1000.0 - r.taken * 10.0
			elif r.nerve_after <= 0:
				score = -1000.0 + r.press
			elif final:
				# Last round: only how far Resolve falls matters, unless Nerve would break.
				score = r.press * 10.0 - r.taken
			else:
				score = r.press * 1.0 - r.taken * 0.9
			if score > best.score:
				best = {"assign": assign, "pair_pick": pp, "score": score}
	return best


func resolve_round(ts: Array, ev: Dictionary, assign: Array, pair_pick: int, rng: RandomNumberGenerator) -> Dictionary:
	var r := simulate(ts, ev, assign, pair_pick)
	# A card sharp watches your hands.
	var spotted := ""
	if is_card_sharp():
		for t in ts:
			if t.die.has("loaded_face"):
				var fav: bool = t.face == t.die.loaded_face - 1
				if rng.randf() < spot_chance(t, fav):
					spotted = t.die.name
					break
	if spotted != "":
		caught = true
		over = true
		r.spotted = spotted
		history.append(r)
		return r
	resolve -= r.press
	nerve -= r.taken
	if resolve <= 0 or nerve <= 0 or round_no >= rounds_max:
		over = true
	r.resolve = resolve
	r.nerve = nerve
	history.append(r)
	return r


func won() -> bool:
	return resolve <= 0 and not caught


func tier() -> int:
	if caught:
		return S.FAIL
	if resolve <= 0:
		return S.TRIUMPH if (round_no <= 1 or nerve >= NERVE) else S.SUCCESS
	if nerve <= 0:
		return S.FAIL
	return S.MIXED if resolve <= ceili(resolve_start * 0.3) else S.FAIL
