extends RefCounted
## Combat: a Contest where the foe throws first and you answer. You see the foe's dice before
## choosing yours, so every round is a puzzle with a known threat.
##
## Round: the foe throws (its intent freezes in the tray) -> you draw -> you throw up to Effort
## -> you put each die in one of five stances -> runes fire -> damage, blocks and effects.

const S := preload("res://scripts/rules/scoring.gd")
const Dice := preload("res://scripts/rules/dice.gd")
const Foes := preload("res://scripts/rules/foes.gd")

const STANCES := ["strike", "guard", "evade", "trick", "read"]
const STANCE_NAMES := {"strike": "Strike", "guard": "Guard", "evade": "Evade", "trick": "Trick", "read": "Read"}
const STANCE_ASPECT := {"strike": "might", "guard": "ward", "evade": "grace", "trick": "guile", "read": "lore"}
const STANCE_TEXT := {
	"strike": "Deal its number as damage.",
	"guard": "Block damage point for point.",
	"evade": "If it equals or beats one attack die, that attack misses.",
	"trick": "Lower the biggest attack die by its number.",
	"read": "3 or more: Expose (+50% damage) or Silence one trait for the round.",
}
const READ_THRESHOLD := 3
const BURN_DAMAGE := 2
const BURN_ROUNDS := 3

var foe: Dictionary
var phase_idx := 0
var resolve := 0
var resolve_max := 0
var round_no := 0
var foe_results: Array = []    # [{name, sides, kind, value}]
var summon_next := 0
var burning := 0
var effort_base := 3
var effort_penalty := 0
var penalty_next := 0
var taken_total := 0
var downed := 0
var danger := 0
var danger_size := 0
var danger_text := ""
var over := false
var outcome := ""              # "won", "lost", "fled"
var stolen = null              # the die a Thief holds
var wardens := true            # minion waves (the Abbess); Kettle's crew can hold them off
var bell_ready := false        # Wren's hand-bell: once, re-throw every die showing 1
var first_round_penalty := 0   # a Wound (Arrow in the Shoulder) or a tale mod: Effort -n in round one
var history: Array = []


static func create(foe_def: Dictionary, mods := {}):
	var c = load("res://scripts/rules/combat.gd").new()
	c.foe = foe_def
	c.wardens = not mods.get("no_wardens", false)
	c.bell_ready = mods.get("bell", false)
	c.first_round_penalty = int(mods.get("ambushed", 0))
	c.effort_base += int(mods.get("effort", 0))
	c._enter_phase(0)
	c.resolve += int(mods.get("resolve", 0))
	c.resolve_max = c.resolve
	return c


func phase() -> Dictionary:
	return foe.phases[phase_idx]


func traits() -> Array:
	return phase().get("traits", [])


func has_trait(t: String) -> bool:
	return traits().has(t)


func _enter_phase(i: int) -> void:
	phase_idx = i
	var p: Dictionary = foe.phases[i]
	resolve = int(p.resolve)
	resolve_max = resolve
	danger = 0
	danger_size = int(p.get("danger", 0))
	danger_text = p.get("danger_text", "")


## Which dice the foe throws this round.
func begin_round() -> Array:
	round_no += 1
	effort_penalty = penalty_next
	penalty_next = 0
	if round_no == 1 and has_trait("ambush"):
		effort_penalty += 1
	if round_no == 1:
		effort_penalty += first_round_penalty
	var p := phase()
	var dice: Array = p.dice.duplicate()
	if p.has("split") and resolve <= int(p.split):
		dice.pop_back()  # one of them is down
	if wardens and p.has("wardens"):
		dice.append_array(p.wardens)
	for k in summon_next:
		dice.append(p.summon)
	summon_next = 0
	return dice


func effort() -> int:
	return maxi(1, effort_base - effort_penalty)


func set_foe_results(dice: Array, values: Array) -> void:
	foe_results.clear()
	for i in dice.size():
		var d: Dictionary = dice[i]
		foe_results.append({"name": d.name, "sides": d.sides, "kind": d.kind, "value": int(values[i])})


func quake() -> bool:
	for r in foe_results:
		if r.kind == "toll" and r.value >= 4:
			return true
	return false


func incoming() -> int:
	var t := 0
	for a in _attacks():
		t += a.value
	return t


func _attacks() -> Array:
	var out: Array = []
	for i in foe_results.size():
		var r: Dictionary = foe_results[i]
		if r.kind == "attack" or (r.kind == "toll" and r.value <= 3):
			out.append({"i": i, "value": r.value, "name": r.name})
	return out


func intent_text() -> String:
	var parts: Array[String] = []
	var atk := incoming()
	if atk > 0:
		parts.append("%d damage coming" % atk)
	for r in foe_results:
		if r.kind == "guard":
			parts.append("guarding %d" % r.value)
		elif r.kind == "pack" and r.value == r.sides:
			parts.append("calling the pack")
		elif r.kind == "toll" and r.value >= 4:
			parts.append("the bell tolls: the tray quakes")
	if parts.is_empty():
		parts.append("hesitating")
	return ", ".join(parts)


## What an assignment would do this round, without changing anything.
## assign[i] = stance index (0..4) or -1. read_mode: "expose" or "silence".
func simulate(ts: Array, ev: Dictionary, assign: Array, read_mode := "expose", pair_pick := 0) -> Dictionary:
	var vals: Array = ev.vals.duplicate()
	if not ev.combos.pair.is_empty():
		vals[ev.combos.pair[clampi(pair_pick, 0, 1)]] += 2
	var attacks := _attacks()
	var foe_guard := 0
	for r in foe_results:
		if r.kind == "guard":
			foe_guard += r.value
	var weak: String = foe.get("weakness", "")

	var sv: Array[int] = []      # value of each die in its stance
	for i in ts.size():
		var st: int = assign[i]
		if st < 0:
			sv.append(0)
			continue
		var stance: String = STANCES[st]
		var v := S.slot_value(ts[i], vals[i], STANCE_ASPECT[stance])
		if stance == "strike" and weak != "" and ts[i].die.aspect == weak:
			v = vals[i]  # the foe's weakness hits in full
		sv.append(v)

	# Read first: Expose or Silence.
	var exposed := false
	var silenced := ""
	var modes: Array = [read_mode, "silence" if read_mode == "expose" else "expose"]
	var reads := 0
	for i in ts.size():
		if assign[i] == 4 and sv[i] >= READ_THRESHOLD and reads < 2:
			var mode: String = modes[reads]
			reads += 1
			if mode == "silence":
				for t in traits():
					if Foes.CANCELLABLE.has(t):
						silenced = t
						break
				if silenced == "":
					exposed = true
			else:
				exposed = true
	var active := traits().filter(func(t): return t != silenced)

	# Trick lowers the biggest attack.
	var tricked := 0
	for i in ts.size():
		if assign[i] == 3 and not attacks.is_empty():
			var hi := 0
			for k in attacks.size():
				if attacks[k].value > attacks[hi].value:
					hi = k
			var cut := mini(attacks[hi].value, sv[i])
			attacks[hi].value -= cut
			tricked += cut

	# Evade: each die dodges the biggest attack it equals or beats.
	var evaded: Array = []
	var ev_order: Array = []
	for i in ts.size():
		if assign[i] == 2:
			ev_order.append(i)
	ev_order.sort_custom(func(a, b): return sv[a] > sv[b])
	for i in ev_order:
		var pick := -1
		for k in attacks.size():
			if not evaded.has(k) and attacks[k].value > 0 and attacks[k].value <= sv[i]:
				if pick < 0 or attacks[k].value > attacks[pick].value:
					pick = k
		if pick >= 0:
			evaded.append(pick)

	var block := 0
	var strike := 0
	var mend := 0
	var spark := 0
	var banes: Array = []
	var ember := false
	for i in ts.size():
		var r := S.rune(ts[i])
		match r:
			"guard": block += S.raw(ts[i])
			"strike":
				var rv := S.raw(ts[i])
				if active.has("ghostly") and ts[i].die.aspect == "might":
					rv /= 2
				strike += rv
			"mend": mend += 1
			"spark": spark += 1
			"bane": banes.append(ts[i].die)
		if Dice.trait_of(ts[i].die) == "ember" and S.is_max(ts[i]):
			ember = true
		if assign[i] == 1:
			block += sv[i]
		elif assign[i] == 0:
			var d := sv[i]
			if active.has("ghostly") and ts[i].die.aspect == "might":
				d /= 2
			strike += d
	if exposed:
		strike = int(strike * 1.5)
	if ev.combos.high_table:
		strike *= 2
	var dealt := maxi(0, strike - foe_guard)
	var burn := BURN_DAMAGE if (burning > 0 or ember) else 0

	var inc := 0
	for k in attacks.size():
		if not evaded.has(k):
			inc += attacks[k].value
	var taken := maxi(0, inc - block)
	if taken > 0 and active.has("relentless"):
		taken += 1
	return {
		"dealt": dealt, "burn": burn, "total_dealt": dealt + burn, "taken": taken, "blocked": mini(block, inc),
		"incoming": inc + block - mini(block, inc), "evaded": evaded.size(), "tricked": tricked,
		"exposed": exposed, "silenced": silenced, "ember": ember, "mend": mend, "spark": spark, "banes": banes,
		"hamstrung": taken > 0 and active.has("hamstring"),
		"killed": dealt + burn >= resolve,
	}


func best_assignment(ts: Array, ev: Dictionary, grit := 99) -> Dictionary:
	var n := ts.size()
	var best := {"assign": [], "pair_pick": 0, "read_mode": "expose", "score": -INF}
	var picks := [0, 1] if not ev.combos.pair.is_empty() else [0]
	var last_phase: bool = phase_idx >= foe.phases.size() - 1
	for code in int(pow(5, n)):
		var assign: Array = []
		var c := code
		var any_read := false
		for i in n:
			assign.append(c % 5)
			any_read = any_read or (c % 5) == 4
			c /= 5
		for pp in picks:
			for mode in (["expose", "silence"] if any_read else ["expose"]):
				var r := simulate(ts, ev, assign, mode, pp)
				var score: float
				if r.taken >= grit:
					score = -500.0 - r.taken + mini(r.total_dealt, resolve) * 0.5
				elif r.killed:
					score = (1000.0 if last_phase else 200.0) - r.taken * 10.0
				else:
					score = mini(r.total_dealt, resolve) * 1.0 - r.taken * 1.25 - (4.0 if r.hamstrung else 0.0) + r.mend * 1.5
				if danger_size > 0 and not r.killed:
					score -= 3.0  # the clock is ticking: prefer finishing
				if score > best.score:
					best = {"assign": assign, "pair_pick": pp, "read_mode": mode, "score": score}
	return best


func resolve_round(ts: Array, ev: Dictionary, assign: Array, read_mode := "expose", pair_pick := 0) -> Dictionary:
	var r := simulate(ts, ev, assign, read_mode, pair_pick)
	resolve -= r.total_dealt
	if r.ember:
		burning = BURN_ROUNDS
	elif burning > 0:
		burning -= 1
	if r.hamstrung:
		penalty_next += 1
	for fr in foe_results:
		if fr.kind == "pack" and fr.value == fr.sides:
			summon_next += 1
	taken_total += r.taken
	r.phase_changed = false
	if resolve <= 0:
		if phase_idx < foe.phases.size() - 1:
			_enter_phase(phase_idx + 1)
			burning = 0
			r.phase_changed = true
		else:
			over = true
			outcome = "won"
	elif danger_size > 0:
		danger += 1
		if danger >= danger_size:
			over = true
			outcome = "lost"
			r.dragged = true
	history.append(r)
	return r


func flee() -> void:
	over = true
	outcome = "fled"


func lose() -> void:
	over = true
	outcome = "lost"


func tier() -> int:
	match outcome:
		"won":
			if downed > 0:
				return S.MIXED
			return S.TRIUMPH if taken_total <= 5 else S.SUCCESS
		"fled":
			return S.MIXED
	return S.FAIL
