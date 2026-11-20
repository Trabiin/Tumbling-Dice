extends RefCounted
## Honest odds, shown before every throw. Built from each die's real face distribution
## (dice.gd dist(), measured by stats.gd), so loaded dice and odd faces are reflected.
##
## Single final throws are enumerated exactly. Anything with more tries ahead, Echo runes or
## too many combinations is simulated: the rest of the challenge is played out by the same
## greedy policy the balance bots use.

const Dice := preload("res://scripts/rules/dice.gd")
const S := preload("res://scripts/rules/scoring.gd")
const Challenge := preload("res://scripts/rules/challenge.gd")

const EXACT_LIMIT := 6000
const ECHO_CHAIN := 3


## Throw dice in pure code (fast dice, bots, simulations). Echo faces chain up to 3 times.
static func roll(dice: Array, rng: RandomNumberGenerator) -> Array:
	var ts: Array = []
	for d in dice:
		var t := S.make_thrown(d, Dice.sample(d, rng))
		var face: int = t.face
		var chain := 0
		while Dice.face_rune(d, face) == "echo" and chain < ECHO_CHAIN:
			face = Dice.sample(d, rng)
			t.echo += Dice.face_n(d, face)
			chain += 1
		ts.append(t)
	return ts


## Expected value of a die in a slot of this aspect (for choosing what to throw).
static func expected_in(die: Dictionary, aspect: String) -> float:
	var p := Dice.dist(die)
	var s := 0.0
	for i in die.sides:
		var t := S.make_thrown(die, i)
		s += p[i] * S.slot_value(t, S.face_n(t), aspect)
	return s


static func best_slot_value(die: Dictionary, slots: Array) -> float:
	var b := 0.0
	for sl in slots:
		b = maxf(b, expected_in(die, sl.aspect))
	return b


## Which dice a sensible player throws from this hand. Trials weigh rushing against keeping
## dice back for later tries.
static func pick(hand: Array, slots: Array, n_max: int, run = null) -> Array:
	var ranked := hand.duplicate()
	ranked.sort_custom(func(a, b): return best_slot_value(a, slots) > best_slot_value(b, slots))
	var n := mini(n_max, ranked.size())
	if run != null and run.kind == "trial" and n >= 3:
		var left: int = run.danger_size - run.danger
		var need := S.shortfall(run.progress, run.slots)
		var e_full := 0.0
		for i in n:
			e_full += best_slot_value(ranked[i], slots)
		var e_care := e_full - best_slot_value(ranked[n - 1], slots)
		var careful_total := e_care * left
		var rush_total := e_full * (left / 2) + (e_care if left % 2 == 1 else 0.0)
		# Rush when it gets there faster with the same safety, or when only one tick is left anyway.
		if left > 1 and (careful_total >= rush_total or e_care * mini(left, 2) >= need * 1.1):
			n -= 1
	return ranked.slice(0, n)


# ------------------------------------------------------------------ tests and trials

## Chance of each tier if these dice are thrown now. ctx: kind, pity, shaking.
## pouch (optional) lets later tries draw realistically; otherwise later tries reuse the hand.
static func challenge_odds(run, dice: Array, ctx: Dictionary, hand: Array = [], pouch = null, samples := 500,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = 7
	var tiers := [0.0, 0.0, 0.0, 0.0]
	if dice.is_empty():
		tiers[run.tier()] = 1.0
		return {"tiers": tiers, "exact": true}
	var final: bool = run.is_final(dice.size())
	var has_echo := dice.any(func(d): return d.faces.any(func(f): return f.rune == "echo"))
	var combos := 1
	for d in dice:
		combos *= int(d.sides)
	if final and not has_echo and combos <= EXACT_LIMIT:
		return _exact(run, dice, ctx)
	for k in samples:
		var sim = clone(run)
		var ts := roll(dice, rng)
		var ev := S.evaluate(ts, ctx)
		var best := S.best_assignment(ts, ev, sim.slots, sim.progress, sim.is_final(ts.size()))
		sim.apply(ts, ev, best)
		if not sim.over and sim.is_met():
			sim.stop()  # a cautious player takes the Success
		var spare := hand.filter(func(d): return not dice.has(d))
		var pool: Array = pouch.draw_pile.duplicate() if pouch != null else []
		pool.shuffle()
		var c2 := ctx.duplicate()
		c2.pity = false
		while not sim.over:
			while spare.size() < (pouch.hand_size() if pouch != null else hand.size()) and not pool.is_empty():
				spare.append(pool.pop_back())
			if spare.is_empty():
				spare = dice.duplicate()
			var p2 := pick(spare, sim.slots, sim.effort, sim)
			var ts2 := roll(p2, rng)
			var ev2 := S.evaluate(ts2, c2)
			var b2 := S.best_assignment(ts2, ev2, sim.slots, sim.progress, sim.is_final(ts2.size()))
			sim.apply(ts2, ev2, b2)
			for d in p2:
				spare.erase(d)
			if not sim.over and sim.is_met():
				sim.stop()
		tiers[sim.tier()] += 1.0
	for i in 4:
		tiers[i] /= samples
	return {"tiers": tiers, "exact": false}


static func _exact(run, dice: Array, ctx: Dictionary) -> Dictionary:
	var tiers := [0.0, 0.0, 0.0, 0.0]
	var dists: Array = []
	for d in dice:
		dists.append(Dice.dist(d))
	var n := dice.size()
	var idx: Array = []
	idx.resize(n)
	idx.fill(0)
	while true:
		var p := 1.0
		var ts: Array = []
		for i in n:
			p *= dists[i][idx[i]]
			ts.append(S.make_thrown(dice[i], idx[i]))
		var ev := S.evaluate(ts, ctx)
		var best := S.best_assignment(ts, ev, run.slots, run.progress, true)
		var prog: Array = []
		for k in run.slots.size():
			prog.append(int(run.progress[k]) + best.totals[k])
		var t := S.tier_of(prog, run.slots, run.high_table_hit or ev.combos.high_table, run.triple_hit or ev.combos.triple)
		tiers[t] += p
		# next combination
		var k2 := 0
		while k2 < n:
			idx[k2] += 1
			if idx[k2] < dice[k2].sides:
				break
			idx[k2] = 0
			k2 += 1
		if k2 == n:
			break
	return {"tiers": tiers, "exact": true}


static func clone(run):
	var c = Challenge.new()
	c.kind = run.kind
	c.title = run.title
	c.slots = run.slots
	c.progress = run.progress.duplicate()
	c.effort = run.effort
	c.tries_total = run.tries_total
	c.tries_used = run.tries_used
	c.danger_size = run.danger_size
	c.danger = run.danger
	c.triple_hit = run.triple_hit
	c.high_table_hit = run.high_table_hit
	c.over = run.over
	return c


## Odds for each approach of a challenge, before choosing it: the dice a sensible player would
## throw from this Hand, played out to the end.
static func approach_odds(def: Dictionary, aspect: String, hand: Array, ctx: Dictionary, pouch = null, samples := 300) -> Dictionary:
	var run = Challenge.create(def, aspect)
	var dice := pick(hand, run.slots, run.effort, run)
	return challenge_odds(run, dice, ctx, hand, pouch, samples)


# ------------------------------------------------------------------ contests and combat

## This round of a contest, with the opponent's throw already on the table.
static func contest_round(contest, dice: Array, ctx: Dictionary, samples := 400) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var broke := 0.0
	var taken := 0.0
	var press := 0.0
	for k in samples:
		var ts := roll(dice, rng)
		var ev := S.evaluate(ts, ctx)
		var b: Dictionary = contest.best_assignment(ts, ev)
		var r: Dictionary = contest.simulate(ts, ev, b.assign, b.pair_pick)
		broke += 1.0 if r.broken else 0.0
		taken += r.taken
		press += r.press
	return {"break": broke / samples, "taken": taken / samples, "press": press / samples,
		"caught": contest.catch_odds(dice)}


## This round of combat, with the foe's throw already frozen in the tray.
static func combat_round(combat, dice: Array, ctx: Dictionary, grit: int, samples := 300) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var kill := 0.0
	var taken := 0.0
	var dealt := 0.0
	for k in samples:
		var ts := roll(dice, rng)
		var ev := S.evaluate(ts, ctx)
		var b: Dictionary = combat.best_assignment(ts, ev, grit)
		var r: Dictionary = combat.simulate(ts, ev, b.assign, b.read_mode, b.pair_pick)
		kill += 1.0 if r.killed else 0.0
		taken += r.taken
		dealt += r.total_dealt
	return {"kill": kill / samples, "taken": taken / samples, "dealt": dealt / samples}


## The spread of a foe's next throw (Elven Jade's Clarity shows this).
static func foe_throw_odds(foe_dice: Array) -> String:
	var parts: Array[String] = []
	for d in foe_dice:
		parts.append("%s d%d (avg %.1f)" % [d.name, d.sides, (d.sides + 1) / 2.0])
	return ", ".join(parts)
