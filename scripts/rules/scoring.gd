extends RefCounted
## How thrown dice turn into numbers: face values, combos, Kin, Grudges, the Teller's pity,
## aspect matching (full on-aspect, half off-aspect), and the best assignment to slots.
## Shared by tests, trials, social contests, combat and the odds calculator.
##
## A thrown die is a Dictionary:
##   die     the die (see dice.gd)
##   face    physical face index that landed up
##   echo    extra points from Echo re-throws
##   cocked  landed leaning; must be settled (Steady, Lightfoot, or a free re-throw) before use
##   alt     the other face it leans toward, when cocked

const Dice := preload("res://scripts/rules/dice.gd")

enum { FAIL, MIXED, SUCCESS, TRIUMPH }
const TIER_NAMES := ["Fail", "Mixed", "Success", "Triumph"]
const TIER_COLORS := [Color("#b8452e"), Color("#c98a2e"), Color("#4f8a3a"), Color("#e8b830")]

## Tier rules from the design doc: Mixed when every slot is within MIXED_WINDOW of its target,
## Triumph when the slots are exceeded by TRIUMPH_SURPLUS in total.
const MIXED_WINDOW := 3
const TRIUMPH_SURPLUS := 6


static func make_thrown(die: Dictionary, face: int) -> Dictionary:
	return {"die": die, "face": face, "echo": 0, "cocked": false, "alt": -1}


static func face_n(t: Dictionary) -> int:
	return int(t.die.faces[t.face].n)


static func raw(t: Dictionary) -> int:
	return face_n(t) + int(t.echo)


static func rune(t: Dictionary) -> String:
	return String(t.die.faces[t.face].rune)


static func is_max(t: Dictionary) -> bool:
	return face_n(t) == Dice.max_n(t.die)


static func is_min(t: Dictionary) -> bool:
	return face_n(t) == Dice.min_n(t.die)


# ------------------------------------------------------------------ combos

## Combos are read from the faces as they land. Returns the indices involved.
static func combos(ts: Array) -> Dictionary:
	var out := {"pair": [], "triple": false, "run": [], "kinship": false, "high_table": false}
	var n := ts.size()
	if n < 2:
		return out
	var nums: Array[int] = []
	for t in ts:
		nums.append(face_n(t))
	# Triple and pair
	for i in n:
		var same: Array = [i]
		for j in range(i + 1, n):
			if nums[j] == nums[i]:
				same.append(j)
		if same.size() >= 3:
			out.triple = true
		if same.size() >= 2 and out.pair.is_empty():
			out.pair = [same[0], same[1]]
	# Run: three distinct numbers in sequence
	for i in n:
		for j in n:
			for k in n:
				if i != j and j != k and i != k and nums[j] == nums[i] + 1 and nums[k] == nums[i] + 2 and out.run.is_empty():
					out.run = [i, j, k]
	# Kinship: every die shares an aspect (Wild dice fit any)
	var asp := ""
	var kin := true
	for t in ts:
		var a: String = t.die.aspect
		if a == "wild":
			continue
		if asp == "" :
			asp = a
		elif a != asp:
			kin = false
	out.kinship = kin
	# High Table: every die shows its maximum
	out.high_table = ts.all(func(t): return is_max(t))
	return out


## Values before aspect matching. ctx: kind ("test", "trial", "combat", "contest"),
## pity (bool: +1 to the highest die), shaking (Wound: d12/d20 count -2).
static func evaluate(ts: Array, ctx := {}) -> Dictionary:
	var c := combos(ts)
	var vals: Array[int] = []
	var notes: Array[String] = []
	for t in ts:
		vals.append(raw(t))
	if not c.run.is_empty():
		for i in c.run:
			vals[i] += 1
		notes.append("Run: +1 to three dice")
	if c.kinship:
		for i in vals.size():
			vals[i] += 1
		notes.append("Kinship: +1 to each")
	for i in ts.size():
		if rune(ts[i]) == "kin":
			var bonus := 4 if c.kinship else 2
			for j in ts.size():
				if j != i and (ts[j].die.aspect == ts[i].die.aspect or ts[j].die.aspect == "wild"):
					vals[j] += bonus
			notes.append("Kin: +%d to %s's kin" % [bonus, ts[i].die.name])
	var kind: String = ctx.get("kind", "")
	for i in ts.size():
		if kind != "" and ts[i].die.grudge == kind:
			vals[i] += 1
			notes.append("Grudge: %s +1" % ts[i].die.name)
		if ctx.get("shaking", false) and ts[i].die.sides >= 12:
			vals[i] = maxi(0, vals[i] - 2)
	if ctx.get("pity", false) and not ts.is_empty():
		var hi := 0
		for i in vals.size():
			if vals[i] > vals[hi]:
				hi = i
		vals[hi] += 1
		notes.append("The Teller's pity: +1")
	if not c.pair.is_empty():
		notes.append("Pair: +2 to one of them")
	if c.triple:
		notes.append("Triple: +1 Fate, and a Success becomes a Triumph")
	if c.high_table:
		notes.append("High Table!")
	return {"vals": vals, "combos": c, "notes": notes}


## What a die is worth in a slot of `aspect`: full on its own aspect, half (rounded down)
## anywhere else. Wild counts full anywhere; Keen doubles on-aspect; Glint (amethyst) counts
## full anywhere when it lands even. "any" slots (Last Stand) take every die in full.
static func slot_value(t: Dictionary, v: int, aspect: String) -> int:
	if aspect == "any":
		return v
	var d: Dictionary = t.die
	var on: bool = d.aspect == aspect or d.aspect == "wild"
	if not on and Dice.trait_of(d) == "glint" and face_n(t) % 2 == 0:
		on = true
	if on:
		if rune(t) == "keen" and (d.aspect == aspect or d.aspect == "wild"):
			return v * 2
		return v
	return v / 2


static func on_aspect(t: Dictionary, aspect: String) -> bool:
	return slot_value(t, 2, aspect) >= 2


# ------------------------------------------------------------------ tiers

## The tier of a challenge's progress against its slots.
static func tier_of(progress: Array, slots: Array, high_table := false, triple := false) -> int:
	if high_table:
		return TRIUMPH
	var all_met := true
	var all_close := true
	var surplus := 0
	for i in slots.size():
		var short: int = int(slots[i].target) - int(progress[i])
		if short > 0:
			all_met = false
			if short > MIXED_WINDOW:
				all_close = false
		else:
			surplus -= short
	if all_met:
		if surplus >= TRIUMPH_SURPLUS or triple:
			return TRIUMPH
		return SUCCESS
	return MIXED if all_close else FAIL


static func shortfall(progress: Array, slots: Array) -> int:
	var s := 0
	for i in slots.size():
		s += maxi(0, int(slots[i].target) - int(progress[i]))
	return s


static func surplus(progress: Array, slots: Array) -> int:
	var s := 0
	for i in slots.size():
		s += maxi(0, int(progress[i]) - int(slots[i].target))
	return s


# ------------------------------------------------------------------ assignment

## Slot totals for one assignment. assign[i] = slot index for die i (or -1 = unassigned).
## pair_pick chooses which die of a Pair takes the +2.
static func totals(ts: Array, ev: Dictionary, slots: Array, assign: Array, pair_pick := 0) -> Array[int]:
	var out: Array[int] = []
	out.resize(slots.size())
	out.fill(0)
	var vals: Array = ev.vals.duplicate()
	var pair: Array = ev.combos.pair
	if not pair.is_empty():
		vals[pair[clampi(pair_pick, 0, 1)]] += 2
	for i in ts.size():
		var s: int = assign[i]
		if s >= 0:
			out[s] += slot_value(ts[i], vals[i], slots[s].aspect)
	return out


## The best way to place these dice. `final` means no tries remain, so aim for the best tier;
## otherwise close as much of the gap as possible.
static func best_assignment(ts: Array, ev: Dictionary, slots: Array, progress: Array, final: bool) -> Dictionary:
	var n := ts.size()
	var s := slots.size()
	var best := {"assign": [], "pair_pick": 0, "totals": [], "score": -INF}
	if n == 0:
		var z: Array[int] = []
		z.resize(s)
		z.fill(0)
		return {"assign": [], "pair_pick": 0, "totals": z, "score": 0}
	var picks := [0, 1] if not ev.combos.pair.is_empty() else [0]
	var total_combos := int(pow(s, n))
	var assign: Array = []
	assign.resize(n)
	for code in total_combos:
		var c := code
		for i in n:
			assign[i] = c % s
			c /= s
		for pp in picks:
			var tot := totals(ts, ev, slots, assign, pp)
			var prog: Array = []
			for k in s:
				prog.append(int(progress[k]) + tot[k])
			var score := _score(prog, slots, ev.combos, final)
			if score > best.score:
				best = {"assign": assign.duplicate(), "pair_pick": pp, "totals": tot, "score": score}
	return best


static func _score(prog: Array, slots: Array, combos_d: Dictionary, final: bool) -> float:
	var short := shortfall(prog, slots)
	var sur := surplus(prog, slots)
	if final:
		var t := tier_of(prog, slots, combos_d.high_table, combos_d.triple)
		return t * 10000.0 + (sur if t >= SUCCESS else -short * 10.0)
	return -short * 100.0 + sur
