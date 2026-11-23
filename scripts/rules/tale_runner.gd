extends RefCounted
## Plays a tale. A state machine over the tale data: the table (a player) and the balance bots
## drive exactly the same code, through the same calls.
##
## Phases and the call that moves each one on:
##   choose     pick(option_index)              a scene's options are on the table
##   wager      pick_wager(die_or_null)          stake a die on the tale
##   prepare    done_prepare()                   pack the Pouch at the tavern
##   approach   pick_approach(i)                 how you go about it (the Hand is already drawn)
##   foe_throw  set_foe_values(values)           the foe / opponent throws first (or auto_foe_throw)
##   throw      submit_throw(thrown)             choose dice, throw them, report the settled faces
##   quake      apply_rethrow(map)               the tray quakes: dice under 3 are re-thrown
##   assign     assign(...) / assign_suggested() place dice in slots or stances; Fate can be spent
##   push       push() / stop()                  slots met with tries left: push for Triumph?
##   defy       defy(bool)                       spend 3 Fate to turn a Fail into a Mixed
##   cost       pick_cost(i)                     a Mixed result: choose what it costs
##   outcome    next()                           the result is told; carry on
##   waystone   done_waystone()                  swap up to 2 dice with the Saddlebag
##   ending     (done)

signal changed
signal said(text: String, style: String)

const Dice := preload("res://scripts/rules/dice.gd")
const S := preload("res://scripts/rules/scoring.gd")
const Challenge := preload("res://scripts/rules/challenge.gd")
const Contest := preload("res://scripts/rules/contest.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Foes := preload("res://scripts/rules/foes.gd")
const Odds := preload("res://scripts/rules/odds.gd")
const TaleState := preload("res://scripts/rules/tale_state.gd")
const Teller := preload("res://scripts/rules/teller.gd")
const Cond := preload("res://scripts/rules/conditions.gd")
const Forge := preload("res://scripts/rules/forge.gd")
const Mood := preload("res://scripts/rules/mood.gd")

const TIER_KEYS := ["fail", "mixed", "success", "triumph"]

var tale: Dictionary
var campaign
var pouch
var state
var teller = Teller.new()
var rng := RandomNumberGenerator.new()

var phase := ""
var scene: Dictionary = {}
var option: Dictionary = {}
var approach: Dictionary = {}
var active: Dictionary = {}        # {type, run, ...}
var thrown: Array = []             # the dice on the table being assigned
var ev: Dictionary = {}
var suggestion: Dictionary = {}
var last_thrown: Array = []        # the previous throw (for costs and grudges)
var foe_dice: Array = []           # what the foe / opponent throws this round
var tier := -1
var outcome: Dictionary = {}
var pending_goto := ""
var pending_retry := ""
var transcript: Array = []         # [{text, style}]
var events: Array = []             # notable things the table may want to stage (gains, wounds...)
var coin_gained := 0


func start(p_tale: Dictionary, p_campaign, seed_value := -1) -> void:
	tale = p_tale
	campaign = p_campaign
	pouch = campaign.pouch
	state = TaleState.new()
	Mood.start_tale(campaign, state)
	teller.extra = tale.get("teller", {})
	if seed_value >= 0:
		rng.seed = seed_value
		teller.rng.seed = seed_value + 1
	else:
		rng.randomize()
		teller.rng.randomize()
	pouch.hand_penalty = 0
	_say(tale.title, "title")
	_fixed_pouch()
	if campaign.get("wounds") != null and not campaign.wounds.is_empty():
		state.carry_in(campaign.wounds)
		_say("You carry %s from an earlier tale: %s" % ["a Wound" if campaign.wounds.size() == 1 else "%d Wounds" % campaign.wounds.size(),
			"; ".join(campaign.wounds.map(func(w): return "%s (%s)" % [w, TaleState.WOUNDS.get(w, "")]))], "foe")
	enter(tale.start)


## A mid-tale save, taken when a scene is waiting for a choice. tale_path says where the tale
## came from, so resume() can read it again.
func snapshot(tale_path: String) -> Dictionary:
	return {"version": 1, "tale_path": tale_path, "tale_id": tale.get("id", ""), "scene": scene.get("id", ""),
		"scene_title": scene.get("title", ""), "campaign": campaign.to_dict(), "pouch": pouch.tale_to_dict(),
		"state": state.to_dict(), "transcript": transcript.slice(-300), "coin_gained": coin_gained,
		"rng": str(rng.state), "saved_at": Time.get_datetime_string_from_system()}


func can_snapshot() -> bool:
	return phase == "choose" and active.is_empty()


## Pick a saved tale back up at the scene it was saved in. The scene's on-enter effects have
## already happened, so they are not run again.
func resume(p_tale: Dictionary, p_campaign, snap: Dictionary) -> void:
	tale = p_tale
	campaign = p_campaign
	teller.extra = tale.get("teller", {})
	campaign.from_dict(snap.campaign)
	pouch = campaign.pouch
	pouch.tale_from_dict(snap.get("pouch", {}))
	var by_id := {}
	for d in pouch.collection:
		by_id[d.id] = d
	state = TaleState.new()
	state.from_dict(snap.state, by_id)
	coin_gained = int(snap.get("coin_gained", 0))
	rng.randomize()
	if snap.has("rng"):
		rng.state = int(snap.rng)
	teller.rng.randomize()
	transcript = snap.get("transcript", [])
	var id: String = snap.get("scene", tale.start)
	if not tale.scenes.has(id):
		id = tale.start
	scene = tale.scenes[id]
	option = {}
	approach = {}
	active = {}
	_say("The tale picks up again: %s." % scene.get("title", id), "system")
	_set_phase("choose" if scene.get("type", "choice") != "prepare" else "prepare")


func ctx() -> Dictionary:
	return {"state": state, "pouch": pouch, "campaign": campaign}


func check(expr: String) -> bool:
	return Cond.check(expr, ctx())


func _say(text: String, style := "narration") -> void:
	if text == "":
		return
	transcript.append({"text": text, "style": style})
	said.emit(text, style)


func _set_phase(p: String) -> void:
	phase = p
	changed.emit()


# ------------------------------------------------------------------ scenes

func enter(id: String) -> void:
	if state.defeated() and id != "ending":
		id = "ending"
	scene = tale.scenes[id]
	state.visited.append(id)
	option = {}
	approach = {}
	active = {}
	_say(scene.title, "scene")
	for e in scene.get("on_enter", []):
		_effect(e)
	for line in scene.get("text", []):
		if line is Array:
			if check(line[0]):
				_say(line[1])
		else:
			_say(line)
	match scene.type:
		"prepare":
			_set_phase("prepare")
		"ending":
			_finish_tale()
		_:
			_set_phase("choose")


func visible_options() -> Array:
	return scene.get("options", []).filter(func(o): return check(o.get("cond", "")))


func pick(i: int) -> void:
	var opts := visible_options()
	option = opts[i]
	state.choices.append([scene.id, option.id])
	_say(option.text, "choice")
	for track in option.get("temper", {}):
		state.move_temper(track, option.temper[track])
	if option.has("challenge") or option.has("contest"):
		# The Hand is drawn before you choose how to go about it.
		_refill()
		_set_phase("approach")
	elif option.has("combat"):
		_start_combat()
	else:
		_say(option.get("reply", ""))
		var wager := false
		for e in option.get("effects", []):
			if e[0] == "wager_pick":
				wager = true
			else:
				_effect(e)
		pending_goto = option.get("goto", "")
		if wager:
			_set_phase("wager")
		elif scene.type == "waystone":
			_set_phase("waystone")
		else:
			_after_effects()


func pick_wager(die) -> void:
	if die != null:
		state.wager = die
		_say("You set your %s on the table. It stays with the tale until you come back." % die.name, "system")
	_after_effects()


func done_prepare() -> void:
	pouch.start_tale(rng)
	_say("You shoulder the Pouch: %d dice, weight %d of %d." % [pouch.pouch.size(), pouch.weight(), pouch.weight_limit], "system")
	_curses("set_out")
	enter(scene.goto)


func done_waystone() -> void:
	_after_effects()


func _after_effects() -> void:
	if state.grit <= 0:
		_start_last_stand({"goto": pending_goto})
		return
	if state.defeated():
		pending_goto = "ending"
	_set_phase("outcome")


func next() -> void:
	if pending_retry != "":
		var id := pending_retry
		pending_retry = ""
		var opts := visible_options()
		for k in opts.size():
			if opts[k].id == id:
				pick(k)
				return
	var g := pending_goto
	pending_goto = ""
	enter(g if g != "" else "ending")


# ------------------------------------------------------------------ approaches

func approaches() -> Array:
	return option.get("approaches", [])


func pick_approach(i: int) -> void:
	approach = approaches()[i]
	_say(approach.text, "choice")
	if option.has("challenge"):
		var def := challenge_def(approach)
		active = {"type": "challenge", "run": Challenge.create(def, approach.aspect)}
	else:
		var c: Dictionary = option.contest
		var mods := _mods(c.get("mods", []))
		active = {"type": "contest", "run": Contest.create(Mood.opponent(campaign, Foes.opponent(c.opponent)), approach.aspect, mods)}
	_begin_try()


## The challenge as it will be played with this approach: base, then conditional mods, then the
## approach's own overrides.
func challenge_def(appr: Dictionary) -> Dictionary:
	var def: Dictionary = option.challenge.duplicate(true)
	for k in appr.get("set", {}):
		def[k] = appr.set[k]
	var target: int = def.get("target", def.get("progress", Challenge.target_for(def.get("difficulty", "standard"))))
	var mods := _mods(def.get("mods", []))
	target += int(mods.get("progress", 0)) + int(mods.get("target", 0))
	if state.flag("no_lantern") and scene.id == "chamber":
		target += 2
	def.target = maxi(1, target)
	return Mood.challenge_def(campaign, def)


## Sum of the mods whose conditions hold: [[cond, {key: value}], ...]
func _mods(list: Array) -> Dictionary:
	var out := {}
	for m in list:
		if check(m[0]):
			for k in m[1]:
				var v = m[1][k]
				if v is bool:
					out[k] = v
				else:
					out[k] = int(out.get(k, 0)) + int(v)
	return out


func approach_odds(i: int) -> Dictionary:
	var appr: Dictionary = approaches()[i]
	if option.has("challenge"):
		return Odds.approach_odds(challenge_def(appr), appr.aspect, pouch.hand, throw_ctx("test"), pouch, 250)
	# Contests: how well the Hand matches, as expected value per die.
	var c = Contest.create(Mood.opponent(campaign, Foes.opponent(option.contest.opponent)), appr.aspect, _mods(option.contest.get("mods", [])))
	var best := Odds.pick(pouch.hand, [{"aspect": appr.aspect}], c.effort)
	var e := 0.0
	for d in best:
		e += Odds.expected_in(d, appr.aspect)
	return {"expected": e, "resolve": c.resolve, "catch": c.catch_odds(best)}


# ------------------------------------------------------------------ throwing

func _refill() -> void:
	var f0: int = pouch.fatigue
	pouch.hand_penalty = state.hand_penalty()
	pouch.refill_hand(rng)
	if pouch.fatigue > f0:
		_say(teller.line("fatigue"), "teller")


func _begin_try() -> void:
	match active.type:
		"challenge", "laststand", "flee":
			_refill()
			if active.type == "laststand":
				active.run.effort = pouch.hand.size()
			_set_phase("throw")
		"contest":
			foe_dice = active.run.begin_round()
			_set_phase("foe_throw")
		"combat":
			foe_dice = active.run.begin_round()
			if active.run.round_no == 1 and active.run.has_trait("thief") and active.get("stolen") == null:
				_thief()
			_set_phase("foe_throw")


func max_dice() -> int:
	match active.get("type", ""):
		"challenge", "laststand", "flee", "contest", "combat":
			if active.type == "combat":
				return active.run.effort()
			return active.run.effort
	return 0


func throw_ctx(kind := "") -> Dictionary:
	if kind == "":
		match active.get("type", ""):
			"challenge": kind = active.run.ctx_kind()
			"contest": kind = "contest"
			"combat": kind = "combat"
			_: kind = "test"
	return {"kind": kind, "pity": state.pity(), "shaking": state.shaking(), "broken_hand": state.broken_hand()}


## The foe or opponent throws first. values: the faces the table read (or rolled).
func set_foe_values(values: Array) -> void:
	if active.type == "combat":
		active.run.set_foe_results(foe_dice, values)
		_say("%s throws: %s." % [active.run.foe.name, active.run.intent_text()], "foe")
		if active.run.danger_size > 0:
			_say("%s (%d of %d)" % [active.run.danger_text, active.run.danger, active.run.danger_size], "system")
	else:
		active.run.set_opponent_throw(values)
		_say("%s pushes back with %d." % [active.run.opponent.name, active.run.pressure], "foe")
	_refill()
	_set_phase("throw")


func auto_foe_throw() -> void:
	var vals: Array = []
	for d in foe_dice:
		vals.append(rng.randi_range(1, int(d.sides)))
	set_foe_values(vals)


## Fast dice: roll in code from each die's measured distribution.
func auto_throw(dice: Array) -> void:
	submit_throw(Odds.roll(dice, rng))


## The dice have settled and every cocked die has been decided.
func submit_throw(ts: Array) -> void:
	thrown = ts
	state.throws += 1
	if active.type == "combat" and active.run.quake():
		var q := quake_targets()
		if not q.is_empty():
			_say("The bell tolls and the tray shakes: %d of your dice tumble again." % q.size(), "foe")
			_set_phase("quake")
			return
	_evaluate()


func quake_targets() -> Array:
	var out: Array = []
	for i in thrown.size():
		if S.raw(thrown[i]) < 3 and Dice.trait_of(thrown[i].die) != "steadfast":
			out.append(i)
	return out


## Replace some thrown dice with new results: {index: thrown}. Used for quakes, Rerolls,
## Bump the Table and Wren's bell.
func apply_rethrow(map: Dictionary) -> void:
	for i in map:
		thrown[i] = map[i]
	_evaluate()


func auto_rethrow(indices: Array) -> void:
	var map := {}
	for i in indices:
		map[i] = Odds.roll([thrown[i].die], rng)[0]
	apply_rethrow(map)


func _evaluate() -> void:
	ev = S.evaluate(thrown, throw_ctx())
	for line in teller.react_to_throw(thrown, ev.combos):
		_say(line, "teller")
	for t in thrown:
		if t.die.grudge != "" and t.die.grudge == throw_ctx().kind:
			_say(teller.line("grudge", {"die": t.die.name}), "teller")
	_suggest()
	_set_phase("assign")


func _suggest() -> void:
	match active.type:
		"challenge", "laststand", "flee":
			var run = active.run
			suggestion = S.best_assignment(thrown, ev, run.slots, run.progress, run.is_final(thrown.size()))
		"contest":
			suggestion = active.run.best_assignment(thrown, ev)
		"combat":
			suggestion = active.run.best_assignment(thrown, ev, state.grit)


## What the current assignment would give (for the challenge card preview).
func preview(assign_arr: Array, pair_pick := 0, read_mode := "expose") -> Dictionary:
	match active.type:
		"challenge", "laststand", "flee":
			var run = active.run
			var tot := S.totals(thrown, ev, run.slots, assign_arr, pair_pick)
			var prog: Array = []
			for k in run.slots.size():
				prog.append(int(run.progress[k]) + tot[k])
			var final: bool = run.is_final(thrown.size())
			var t := S.tier_of(prog, run.slots, run.high_table_hit or ev.combos.high_table, run.triple_hit or ev.combos.triple)
			return {"totals": tot, "progress": prog, "tier": t, "final": final}
		"contest":
			return active.run.simulate(thrown, ev, assign_arr, pair_pick)
		"combat":
			return active.run.simulate(thrown, ev, assign_arr, read_mode, pair_pick)
	return {}


# ------------------------------------------------------------------ Fate

func can_spend(n: int) -> bool:
	return state.fate >= n


func _spend(n: int, what: String) -> bool:
	if state.fate < n:
		return false
	state.fate -= n
	_say("%s (%d Fate)." % [what, n], "system")
	return true


## Nudge: turn one die one step up or down (1 Fate).
func nudge(i: int, dir: int) -> bool:
	var t: Dictionary = thrown[i]
	var nf: int = t.face + dir
	if nf < 0 or nf >= t.die.sides:
		return false
	if not _spend(1, "Nudge %s" % t.die.name):
		return false
	t.face = nf
	_evaluate()
	return true


## Reroll one die (1 Fate); the table throws it again and reports through apply_rethrow.
func pay_reroll(i: int) -> bool:
	if Dice.trait_of(thrown[i].die) == "obsidian":
		return false
	return _spend(1, "Reroll %s" % thrown[i].die.name)


## Steady: choose either face of a cocked die (1 Fate; Bone dice choose for free).
func steady_cost(t: Dictionary) -> int:
	return 0 if Dice.trait_of(t.die) == "lightfoot" else 1


func pay_steady(t: Dictionary) -> bool:
	var c := steady_cost(t)
	if c == 0:
		return true
	return _spend(c, "Steady %s" % t.die.name)


## Bump the table: re-throw every die showing its lowest face (2 Fate).
func bump_targets() -> Array:
	var out: Array = []
	for i in thrown.size():
		if S.is_min(thrown[i]):
			out.append(i)
	return out


func pay_bump() -> bool:
	if bump_targets().is_empty():
		return false
	return _spend(2, "Bump the table")


## Wren's hand-bell (once per climax): re-throw every die showing 1.
func bell_targets() -> Array:
	if active.get("type", "") != "combat" or not active.run.bell_ready:
		return []
	var out: Array = []
	for i in thrown.size():
		if S.face_n(thrown[i]) == 1:
			out.append(i)
	return out


func use_bell() -> void:
	active.run.bell_ready = false
	_say("Far above, Wren rings her little bell, and your fallen dice jump.", "teller")


# ------------------------------------------------------------------ assigning

func assign_suggested() -> void:
	match active.type:
		"combat":
			assign(suggestion.assign, suggestion.pair_pick, suggestion.read_mode)
		_:
			assign(suggestion.assign, suggestion.get("pair_pick", 0))


func assign(assign_arr: Array, pair_pick := 0, read_mode := "expose") -> void:
	last_thrown = thrown.duplicate()
	var dice: Array = thrown.map(func(t): return t.die)
	_fire_runes()
	match active.type:
		"challenge", "laststand", "flee":
			_assign_challenge(assign_arr, pair_pick)
		"contest":
			_assign_contest(assign_arr, pair_pick)
		"combat":
			_assign_combat(assign_arr, pair_pick, read_mode)
	pouch.spend(dice)
	var kind: String = throw_ctx().kind
	for t in last_thrown:
		if t.die.grudge == kind:
			t.die.grudge = ""


## Runes that fire whether or not the die is assigned (Strike and Guard are read by combat
## and contests directly).
func _fire_runes() -> void:
	for t in thrown:
		match S.rune(t):
			"mend":
				var g = state.add_grit(state.mend_amount())
				if g > 0:
					_say("%s mends: +%d Grit." % [t.die.name, g], "system")
			"spark":
				if state.add_fate(1) > 0:
					_say("%s sparks: +1 Fate." % t.die.name, "system")
			"bane":
				if t.die.bane == "fate":
					state.add_fate(-1)
					_say("%s's bane: -1 Fate." % t.die.name, "foe")
				else:
					state.add_grit(-2)
					_say("%s's bane bites: -2 Grit." % t.die.name, "foe")
	if ev.combos.triple:
		state.add_fate(1)


func _assign_challenge(assign_arr: Array, pair_pick: int) -> void:
	var run = active.run
	var tot := S.totals(thrown, ev, run.slots, assign_arr, pair_pick)
	var rep: Dictionary = run.apply(thrown, ev, {"totals": tot})
	_say(_progress_text(run), "result")
	if active.type == "laststand":
		_finish_last_stand(run.tier() >= S.SUCCESS)
		return
	if active.type == "flee":
		_finish_flee(run.tier() >= S.SUCCESS)
		return
	if run.over:
		_finish(run.tier())
	elif rep.can_push:
		_set_phase("push")
	else:
		if run.kind == "trial":
			_say("%s (%d of %d)" % [run.danger_text, run.danger, run.danger_size], "foe")
		_begin_try()


func _progress_text(run) -> String:
	var parts: Array[String] = []
	for k in run.slots.size():
		var sl: Dictionary = run.slots[k]
		parts.append("%s %d of %d" % [Dice.ASPECT_NAMES[sl.aspect], run.progress[k], sl.target])
	return ", ".join(parts)


func push() -> void:
	_say("You push on for more.", "system")
	_begin_try()


func stop() -> void:
	active.run.stop()
	_finish(active.run.tier())


func _assign_contest(assign_arr: Array, pair_pick: int) -> void:
	var c = active.run
	var r: Dictionary = c.resolve_round(thrown, ev, assign_arr, pair_pick, rng)
	if r.has("spotted"):
		_say(teller.line("loaded_caught", {"die": r.spotted}), "teller")
		_finish(S.FAIL, true)
		return
	for t in thrown:
		if t.die.has("loaded_face") and c.is_card_sharp():
			_say(teller.line("loaded_safe", {"die": t.die.name}), "teller")
			break
	_say("You press for %d and hold %d. %s: Resolve %d. Your Nerve: %d." % [r.press, r.hold, c.opponent.name, maxi(0, c.resolve), c.nerve], "result")
	if c.over:
		_finish(c.tier())
	else:
		_begin_try()


func _assign_combat(assign_arr: Array, pair_pick: int, read_mode: String) -> void:
	var c = active.run
	var r: Dictionary = c.resolve_round(thrown, ev, assign_arr, read_mode, pair_pick)
	var bits: Array[String] = []
	bits.append("You deal %d" % r.total_dealt)
	if r.burn > 0:
		bits.append("(%d of it fire)" % r.burn)
	if r.evaded > 0:
		bits.append("dodge %d attack%s" % [r.evaded, "s" if r.evaded > 1 else ""])
	if r.blocked > 0:
		bits.append("block %d" % r.blocked)
	if r.exposed:
		bits.append("its guard is open")
	if r.silenced != "":
		bits.append("its %s is silenced" % r.silenced)
	_say(", ".join(bits) + ". You take %d." % r.taken, "result")
	state.add_grit(-r.taken)
	if r.hamstrung:
		_say("Hamstrung: you will throw one die fewer next round.", "foe")
	if r.phase_changed:
		var p: Dictionary = c.phase()
		_say("%s rises again: %s." % [c.foe.name, p.get("title", "a new fury")], "foe")
	if state.grit <= 0 and not (c.over and c.outcome == "won"):
		c.downed += 1
		_start_last_stand({"combat": true})
		return
	if c.over:
		if r.get("dragged", false):
			_say(c.danger_text, "foe")
		_finish(c.tier())
	else:
		_begin_try()


# ------------------------------------------------------------------ fights

func _start_combat() -> void:
	var cb: Dictionary = option.combat
	var foe := Mood.foe(campaign, Foes.foe(cb.foe))
	var mods := _mods(cb.get("mods", []))
	if state.arrow():
		mods["ambushed"] = int(mods.get("ambushed", 0)) + 1
	var run = Combat.create(foe, mods)
	active = {"type": "combat", "run": run, "stolen": null}
	_say(foe.get("text", ""))
	for t in run.traits():
		_say(Foes.TRAIT_TEXT.get(t, t), "system")
	if foe.get("weakness", "") != "":
		_say("Weak to %s: your %s dice strike it in full." % [Dice.ASPECT_NAMES[foe.weakness], Dice.ASPECT_NAMES[foe.weakness]], "system")
	if state.flag("no_lantern") and scene.id == "chamber":
		run.effort_base -= 1
		_say("In the dark you can manage one die fewer.", "system")
	_begin_try()


func _thief() -> void:
	var target = null
	for d in pouch.pouch:
		if state.flag("gold_taken") and d.base == "bellmetal_d20":
			target = d
	if target == null:
		var best := -1.0
		for d in pouch.pouch:
			if pouch.exhausted.has(d):
				continue
			var m := Dice.mean_n(d)
			if m > best:
				best = m
				target = d
	if target != null:
		pouch.draw_pile.erase(target)
		pouch.hand.erase(target)
		pouch.discard.erase(target)
		active.stolen = target
		_say("%s snatches your %s." % [active.run.foe.name, target.name], "foe")


func can_flee() -> bool:
	return active.get("type", "") == "combat" and not active.run.foe.get("no_flee", false) and phase == "throw"


## Flee: a Grace Test against the foe's speed. Success skips the rest of the fight (Mixed).
func flee() -> void:
	var c = active.run
	var run = Challenge.create({"kind": "test", "target": int(c.foe.speed), "title": "Fleeing"}, "grace")
	active = {"type": "flee", "run": run, "combat": active}
	_say("You turn and run.", "choice")
	_set_phase("throw")


func _finish_flee(ok: bool) -> void:
	var cb: Dictionary = active.combat
	active = cb
	if ok:
		_say("You get clear.", "result")
		cb.run.flee()
		_finish(cb.run.tier())
	else:
		_say("They are faster. You take a blow as you turn back.", "result")
		state.add_grit(-3)
		if state.grit <= 0:
			cb.run.downed += 1
			_start_last_stand({"combat": true})
			return
		_begin_try()


# ------------------------------------------------------------------ Last Stand

func _start_last_stand(resume: Dictionary) -> void:
	_say(teller.line("downed"), "teller")
	pouch.return_hand(rng)
	var run = Challenge.last_stand(pouch.hand_size())
	active = {"type": "laststand", "run": run, "resume": resume, "outer": active}
	_begin_try()


func _finish_last_stand(ok: bool) -> void:
	var resume: Dictionary = active.resume
	var outer: Dictionary = active.outer
	pouch.return_hand(rng)
	var w = state.add_wound()
	state.grit = mini(5, state.grit_max)
	if ok:
		_say(teller.line("last_stand_win"), "teller")
	else:
		_say(teller.line("last_stand_fail"), "teller")
	_say("Wound: %s %s" % [w, TaleState.WOUNDS.get(w, "")], "foe")
	events.append({"type": "wound", "name": w})
	active = outer
	if resume.get("combat", false):
		if not ok:
			active.run.lose()
			_finish(active.run.tier())
		elif state.defeated():
			active.run.lose()
			_finish(S.FAIL)
		else:
			_begin_try()
	else:
		if state.defeated():
			pending_goto = "ending"
		_set_phase("outcome")


# ------------------------------------------------------------------ writers' preview

## Skip the dice and resolve whatever is being thrown for at this tier (the text preview uses it
## to read every outcome without having to roll for it). caught = spotted with a loaded die.
func force_outcome(t: int, caught := false) -> void:
	if active.is_empty():
		return
	last_thrown = []
	thrown = []
	match active.type:
		"laststand":
			_finish_last_stand(t >= S.SUCCESS)
		"flee":
			active = active.combat
			force_outcome(t, caught)
		"combat":
			active.run.over = true
			active.run.outcome = "won" if t >= S.SUCCESS else "lost"
			_finish(t)
		_:
			_finish(t, caught)


# ------------------------------------------------------------------ outcomes

func _finish(t: int, caught := false) -> void:
	pouch.return_hand(rng)
	if active.get("stolen") != null:
		pouch.draw_pile.append(active.stolen)
		_say("You take back your %s." % active.stolen.name, "system")
		active.stolen = null
	if active.type == "combat" and active.run.outcome == "won":
		# A fallen-foe token stays on the tale board where the fight was won.
		state.marks.append({"scene": scene.get("id", ""), "icon": "foe", "label": "%s, beaten" % active.run.foe.name,
			"figure": active.run.foe.get("figure", "")})
		var loot: String = active.run.foe.get("loot", "")
		if loot != "":
			_gain(loot, false, "%s drops a die: " % active.run.foe.name)
	tier = t
	state.record_tier(t)
	if t == S.FAIL:
		state.add_fate(1)
		_grudge()
		# Defy answers a single bad throw. A fight lost over many rounds has its own safety
		# net (the Last Stand), so it cannot be Defied.
		if not caught and Mood.can_defy(campaign, state) and active.type != "combat":
			outcome = {"caught": caught}
			_set_phase("defy")
			return
	_resolve(t, caught)


func _grudge() -> void:
	if last_thrown.is_empty():
		return
	var low = last_thrown[0]
	for t in last_thrown:
		if S.raw(t) < S.raw(low):
			low = t
	low.die.grudge = throw_ctx().kind
	low.die.history.append("Holds a grudge from %s." % scene.title)


func defy(yes: bool) -> void:
	var caught: bool = outcome.get("caught", false)
	if yes and Mood.can_defy(campaign, state):
		state.fate -= Mood.defy_cost(campaign)
		state.defy_used = true
		_say(teller.line("defy"), "teller")
		tier = S.MIXED
	_resolve(tier, caught)


func _resolve(t: int, caught: bool) -> void:
	var key: String = "caught" if caught else TIER_KEYS[t]
	var outs: Dictionary = option.get("outcomes", {})
	outcome = outs.get(key, outs.get("success", {}))
	_say(S.TIER_NAMES[t] if not caught else "Caught", "tier_%s" % key)
	if not caught:
		var near := false
		if t == S.MIXED and active.type == "challenge" and S.shortfall(active.run.progress, active.run.slots) == 1:
			near = true
		_say(teller.line("near_miss" if near else TIER_KEYS[t]), "teller")
	if t == S.TRIUMPH:
		for th in last_thrown:
			th.die.notches += 1
			th.die.history.append("Helped to a Triumph in %s." % scene.title)
	if t == S.FAIL and state.fail_streak >= 2:
		_say(teller.line("pity"), "teller")
	if key == "mixed" and outcome.has("costs"):
		_set_phase("cost")
		return
	_apply_outcome([])


func costs() -> Array:
	return outcome.get("costs", [])


func pick_cost(i: int) -> void:
	var c: Dictionary = costs()[i]
	_say(c.label, "choice")
	_apply_outcome(c.effects)


func _apply_outcome(extra: Array) -> void:
	for line in _lines(outcome.get("text", "")):
		_say(line)
	for e in outcome.get("effects", []):
		_effect(e)
	for e in extra:
		_effect(e)
	pending_goto = outcome.get("goto", "")
	pending_retry = outcome.get("retry", "")
	_after_effects()


func _lines(text) -> Array:
	if text is Array:
		return text.filter(func(l): return not l is Array or check(l[0])).map(func(l): return l[1] if l is Array else l)
	return [text] if text != "" else []


# ------------------------------------------------------------------ effects

func _effect(e: Array) -> void:
	match e[0]:
		"if":
			if check(e[1]):
				_effect(e[2])
		"flag": state.set_flag(e[1], e[2] if e.size() > 2 else true)
		"add": state.set_flag(e[1], state.num(e[1]) + int(e[2]))
		"random_flag":
			var vals: Array = e[2]
			state.set_flag(e[1], vals[rng.randi_range(0, vals.size() - 1)])
		"grit":
			var g = state.add_grit(int(e[1]))
			if g != 0:
				_say("%+d Grit." % g, "system" if g > 0 else "foe")
		"fate":
			var f = state.add_fate(int(e[1]))
			if f != 0:
				_say("%+d Fate." % f, "system")
		"coin":
			var c: int = campaign.add_coin(int(e[1]))
			state.coin += c
			if c > 0:
				coin_gained += c
			if c != 0:
				_say("%+d Coin." % c, "system")
		"fatigue":
			pouch.fatigue += int(e[1])
			_say("+%d Fatigue." % int(e[1]), "foe")
		"wound":
			var w = state.add_wound(e[1])
			_say("Wound: %s %s" % [w, TaleState.WOUNDS.get(w, "")], "foe")
			_say(teller.line("wound"), "teller")
			events.append({"type": "wound", "name": w})
		"gain": _gain(e[1], false)
		"ally": _gain(e[1], true)
		"temper": state.move_temper(e[1], int(e[2]))
		"regard":
			state.regard += int(e[1])
		"standing":
			var fname: String = campaign.faction_name(e[1]) if campaign.has_method("faction_name") else e[1]
			state.standing[fname] = int(state.standing.get(fname, 0)) + int(e[2])
			_say("%s standing %+d." % [fname, int(e[2])], "system")
		"rumour":
			# rumour "text", or rumour id "text" (an id later tales can read: rumour:id)
			var rtext: String = str(e[-1])
			if e.size() >= 3 and not state.rumour_ids.has(str(e[1])):
				state.rumour_ids.append(str(e[1]))
			if not state.rumours.has(rtext):
				state.rumours.append(rtext)
				_say("Rumour: " + rtext, "system")
		"material":
			var mid := str(e[1])
			var mn: int = int(e[2]) if e.size() > 2 else 1
			for k in mn:
				state.materials.append(mid)
			_say("You gain %s." % Forge.material_text(mid, mn), "gain")
		"renown":
			state.set_flag("renown_bonus", state.num("renown_bonus") + int(e[1]))
		"heal":
			if not state.wounds.is_empty():
				var hw: String = state.wounds.pop_back()
				state.carried.erase(hw)
				if hw == "Cracked Ribs":
					state.grit_max += 4
				elif hw == "Frostbite":
					state.grit_max += 3
				_say("Your %s is tended. It troubles you no more." % hw, "system")
		"lift_curse":
			for d in pouch.collection:
				if d.get("cursed", false) and (e.size() < 2 or d.base == str(e[1])):
					Dice.lift_curse(d, tale.get("title", "a tale"))
					state.lifted.append(d.name)
					_say("The curse goes out of it like heat from a stone. %s is yours now, and only yours." % d.name, "gain")
					events.append({"type": "lifted", "die": d})
		"give_up":
			# Part with a die for good (sold, given, left behind), cursed or not: give_up bellmetal_d20
			for d in pouch.collection.duplicate():
				if d.base == str(e[1]):
					pouch.lose(d)
					state.lost.append(d)
					_say("Your %s is gone. You feel lighter, one way or another." % d.name, "foe")
					events.append({"type": "lost", "die": d})
					break
		"crack_best":
			var cd = null
			for t in last_thrown:
				if t.die.get("ally", false):
					continue
				if cd == null or S.raw(t) > S.raw(cd):
					cd = t
			if cd == null:
				for d in pouch.pouch:
					if not d.get("ally", false) and (cd == null or Dice.mean_n(d) > Dice.mean_n(cd.die)):
						cd = {"die": d, "face": d.sides - 1}
			if cd != null:
				var f2 := Dice.crack(cd.die, int(cd.face))
				if f2 >= 0:
					_say("Your %s cracks across its %d. Brannoc can mend it." % [cd.die.name, int(cd.die.faces[f2].n) + 1], "foe")
		"chronicle": state.chronicle.append(e[1])
		"shard":
			state.shards.append(e[1])
			_say("You gain a %s rune shard." % e[1], "system")
		"mark": campaign.mark(e[1])
		"exhaust_best":
			var best = null
			for t in last_thrown:
				if best == null or S.raw(t) > S.raw(best):
					best = t
			if best != null:
				pouch.exhaust(best.die)
				_say("Your %s is set aside until the Waystone." % best.die.name, "foe")
		"lose_lowest":
			var low = null
			for t in last_thrown:
				if t.die == state.wager or t.die.cursed:
					continue
				if low == null or S.raw(t) < S.raw(low):
					low = t
			if low != null:
				pouch.lose(low.die)
				state.lost.append(low.die)
				_say("Your %s is gone, into the dark." % low.die.name, "foe")
				events.append({"type": "lost", "die": low.die})
		"rest":
			# A Waystone gets you back on your feet, not back to full: Grit rises to n if it is lower.
			var before_rest: int = state.grit
			state.grit = clampi(maxi(state.grit, int(e[1])), state.grit, state.grit_max)
			pouch.rest(rng, Mood.swaps(campaign))
			_say(teller.line("rest"), "teller")
			_curses("rest")
			var grit_text := ("Grit back up to %d." % state.grit) if state.grit > before_rest else ("Grit stays at %d." % state.grit)
			var sw: int = Mood.swaps(campaign)
			_say("%s Fatigue cleared. You may swap up to %d %s with your Saddlebag." % [grit_text, sw, "die" if sw == 1 else "dice"], "system")
		"practice_reset":
			# The practice table: every challenge starts from the same footing.
			state.grit_max = TaleState.START_GRIT
			state.grit = state.grit_max
			state.fate = TaleState.START_FATE
			state.wounds.clear()
			state.defy_used = false
			state.fail_streak = 0
			pouch.return_hand(rng)
			pouch.rest(rng, 0)
			pouch.hand_penalty = 0
		"toll":
			_curses("rest")
		"lose_wager":
			if state.wager != null:
				pouch.lose(state.wager)
				state.lost.append(state.wager)
				_say("Your wagered %s stays with the tale." % state.wager.name, "foe")
		"return_gold":
			for d in pouch.collection.duplicate():
				if d.base == "bellmetal_d20":
					pouch.lose(d)
					state.lost.append(d)
			campaign.add_coin(-60)
		_:
			push_error("Unknown effect %s" % str(e))


## Cursed dice in the Pouch act up: at a rest (every Waystone) or when you set out. Each rule
## throws the die; at or under its number, the curse takes its due.
func _curses(when: String) -> void:
	for d in pouch.pouch:
		if not d.get("cursed", false):
			continue
		var rule: Dictionary = d.get("curse_rule", {})
		if rule.is_empty() and d.base == "bellmetal_d20":
			rule = Dice.BELLMETAL_RULE
		if rule.get("when", "") != when:
			continue
		var n := Dice.face_n(d, Dice.sample(d, rng))
		if n <= int(rule.get("at_most", 3)):
			_say("%s %s: %d. %s" % [d.name, rule.get("verb", "stirs"), n, rule.get("text", "")], "foe")
			for ef in rule.get("effects", []):
				_effect(ef)
		else:
			_say("%s %s: %d. Nothing happens. This time." % [d.name, rule.get("verb", "stirs"), n], "system")


## "the Drowned Bell" for a title like "The Drowned Bell".
func _title_in_sentence() -> String:
	var t: String = tale.get("title", "")
	return ("the" + t.substr(3)) if t.begins_with("The ") else t


func _gain(base: String, ally: bool, prefix := "") -> void:
	var d := Dice.create(base)
	if ally:
		d.ally = true
	pouch.gain(d, true)
	state.gained.append(d)
	d.history.append("Found in %s." % tale.title)
	var where := "" if pouch.pouch.has(d) else " It waits on your shelf."
	_say("%s%s: %s%s" % [prefix, "Lent to you" if ally else "You gain", d.name, where], "gain")
	events.append({"type": "gain", "die": d})


# ------------------------------------------------------------------ a fixed Pouch

## A tale can hand you its own Pouch (the prologue: `pouch: oak_might, ...`, `saddle: oak_ward`).
## The dice are lent for the tale; your own packing is put aside and comes back at the ending.
func _fixed_pouch() -> void:
	var bases := String(tale.get("pouch", "")).split(",", false)
	if bases.is_empty():
		return
	state.set_flag("kept_pouch", ",".join(pouch.pouch.map(func(d): return d.id)))
	state.set_flag("kept_saddle", ",".join(pouch.saddlebag.map(func(d): return d.id)))
	pouch.pouch.clear()
	pouch.saddlebag.clear()
	for k in ["pouch", "saddle"]:
		for b in String(tale.get(k, "")).split(",", false):
			var d := Dice.create(b.strip_edges())
			d.ally = true
			d.history.append("Lent to you in %s." % tale.title)
			pouch.collection.append(d)
			if k == "pouch":
				pouch.pouch.append(d)
			else:
				pouch.saddlebag.append(d)
	pouch.start_tale(rng)
	_say("You are handed a Pouch for this tale: %s." % ", ".join(pouch.pouch.map(func(d): return d.name)), "system")


func _restore_pouch() -> void:
	if String(tale.get("pouch", "")) == "":
		return
	var by_id := {}
	for d in pouch.collection:
		by_id[d.id] = d
	pouch.pouch.clear()
	pouch.saddlebag.clear()
	for id in String(state.flags.get("kept_pouch", "")).split(",", false):
		if by_id.has(id):
			pouch.pouch.append(by_id[id])
	for id in String(state.flags.get("kept_saddle", "")).split(",", false):
		if by_id.has(id):
			pouch.saddlebag.append(by_id[id])
	# Dice gained in the tale go into the Pouch if they fit, as usual.
	for d in state.gained:
		if pouch.collection.has(d) and not pouch.pouch.has(d) and not d.get("ally", false) and pouch.weight() + int(d.weight) <= pouch.weight_limit:
			pouch.pouch.append(d)


# ------------------------------------------------------------------ the end

func _finish_tale() -> void:
	var chosen: Dictionary = {}
	for en in scene.endings:
		if check(en.cond):
			chosen = en
			break
	state.ending = chosen.id
	_say(chosen.title, "ending")
	for line in _lines(chosen.text):
		_say(line)
	for e in chosen.effects:
		_effect(e)
	if state.wager != null and not state.defeated() and not state.flag("defeat"):
		var bonus := coin_gained
		if bonus > 0:
			campaign.add_coin(bonus)
			_say("The wager pays double: +%d Coin." % bonus, "gain")
		state.wager.notches += 1
		state.wager.history.append("Wagered on %s, and came home." % tale.title)
	if state.regard >= 2:
		_say(Teller.REGARD_ASIDE[2], "teller")
	elif state.regard <= -2:
		_say(Teller.REGARD_ASIDE[-2], "teller")
	var ep = state.epithet()
	if ep != "":
		_say("[i]That was the tale of the %s traveller, and %s.[/i]" % [ep, _title_in_sentence()], "teller")
	# Into the campaign
	var tid: String = tale.get("id", "")
	var won: bool = not state.defeated() and not state.flag("defeat")
	campaign.tales_played += 1
	var ekey := "%s:%s" % [tid, chosen.id]
	if not campaign.endings_seen.has(ekey):
		campaign.endings_seen.append(ekey)
	if campaign.has_method("record_tale"):
		campaign.record_tale(tid, chosen.id, won)
		# Renown: 1 to 5, by the ending (renown: in the .tale, 2 if it doesn't say) and a Triumph.
		var rn: int = int(chosen.get("renown", 2 if won else 0))
		if won and state.triumphs > 0:
			rn += 1
		rn = clampi(rn + state.num("renown_bonus"), 0 if not won else 1, 5)
		var up: int = campaign.add_renown(rn)
		if won and campaign.get("mood_best") != null:
			var ml: String = Mood.record_win(campaign)
			if ml != "":
				_say(ml, "gain")
		if rn > 0:
			_say("Renown +%d%s." % [rn, (": your Pouch can carry weight %d now" % pouch.weight_limit) if up > 0 else ""], "gain")
		# Wounds come home with you, two at most: Sister Maud can treat them at the tavern.
		campaign.wounds = state.wounds.slice(0, campaign.MAX_CARRIED_WOUNDS) if state.wounds.size() > 0 else []
		if state.wounds.size() > campaign.wounds.size():
			_say("They carry you home. Some of it heals on the road.", "system")
		for m in state.materials:
			campaign.add_material(m, 1)
		for rid in state.rumour_ids:
			if not campaign.rumour_ids.has(rid):
				campaign.rumour_ids.append(rid)
	campaign.chronicle.append_array(state.chronicle)
	for r in state.rumours:
		if not campaign.rumours.has(r):
			campaign.rumours.append(r)
	for k in state.standing:
		if campaign.has_method("add_standing"):
			campaign.add_standing(k, int(state.standing[k]))
		else:
			campaign.standing[k] = int(campaign.standing.get(k, 0)) + int(state.standing[k])
	campaign.shards.append_array(state.shards)
	campaign.remember_map(tid, state.visited)
	for d in pouch.pouch:
		if not d.ally:
			d.history.append("Carried through %s (%s)." % [tale.title, chosen.title])
	var gone: Array = pouch.end_tale()
	for d in gone:
		_say("%s goes back to its owner." % d.name, "system")
	_restore_pouch()
	_set_phase("ending")

