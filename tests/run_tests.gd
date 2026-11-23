extends SceneTree
## Headless tests, the tale linter and the balance bots.
##
##   godot --headless -s res://tests/run_tests.gd                       unit tests + linter + quick bots
##   godot --headless -s res://tests/run_tests.gd -- --runs=400 --report=media/balance.md
##   options: --only=<suite>  (pouch, scoring, odds, combat, contest, challenges, lint, format, preview, save, board, forge, campaign, practice, bots, year)
##
## Exit code is the number of failed checks.

const Dice := preload("res://scripts/rules/dice.gd")
const Pouch := preload("res://scripts/rules/pouch.gd")
const S := preload("res://scripts/rules/scoring.gd")
const Challenge := preload("res://scripts/rules/challenge.gd")
const Contest := preload("res://scripts/rules/contest.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Foes := preload("res://scripts/rules/foes.gd")
const Odds := preload("res://scripts/rules/odds.gd")
const Cond := preload("res://scripts/rules/conditions.gd")
const Campaign := preload("res://scripts/rules/campaign.gd")
const Runner := preload("res://scripts/rules/tale_runner.gd")
const Bot := preload("res://scripts/rules/bot.gd")
const Tales := preload("res://scripts/rules/tales.gd")
const Parser := preload("res://scripts/rules/tale_parser.gd")
const Writer := preload("res://scripts/rules/tale_writer.gd")
const Lint := preload("res://scripts/rules/tale_lint.gd")
const Preview := preload("res://scripts/rules/preview.gd")
const Practice := preload("res://scripts/tale/practice.gd")
const Board := preload("res://scripts/rules/board.gd")
const Forge := preload("res://scripts/rules/forge.gd")
const Patrons := preload("res://scripts/rules/patrons.gd")
const Mood := preload("res://scripts/rules/mood.gd")
const TaleState := preload("res://scripts/rules/tale_state.gd")
const Settings := preload("res://scripts/game/settings.gd")
const Controls := preload("res://scripts/game/controls.gd")
const I18n := preload("res://scripts/game/i18n.gd")
const Extract := preload("res://tools/extract_strings.gd")

var failures := 0
var checks := 0
var runs := 60
var report_path := ""
var only := ""
var report: Array[String] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="): runs = int(a.substr(7))
		elif a.begins_with("--report="): report_path = a.substr(9)
		elif a.begins_with("--only="): only = a.substr(7)
	var t0 := Time.get_ticks_msec()
	var suites := ["pouch", "scoring", "odds", "combat", "contest", "challenges", "lint", "format", "preview", "save", "board", "forge", "campaign", "m6", "access", "practice", "bots", "year", "builds"]
	for s in suites:
		if only == "" or only == s:
			print("== ", s)
			call("test_" + s)
	print("\n%d checks, %d failed (%.1f s)" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	if report_path != "":
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		f.store_string("\n".join(report) + "\n")
		print("Report: ", report_path)
	quit(failures)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL: ", msg)


func eq(a, b, msg: String) -> void:
	check(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])


func near(a: float, b: float, tol: float, msg: String) -> void:
	check(absf(a - b) <= tol, "%s (got %.3f, want %.3f +- %.3f)" % [msg, a, b, tol])


func die(base: String) -> Dictionary:
	return Dice.create(base)


func th(d: Dictionary, n: int) -> Dictionary:
	# thrown die showing the face whose number is n
	for i in d.sides:
		if d.faces[i].n == n:
			return S.make_thrown(d, i)
	push_error("no face %d" % n)
	return {}


# ===================================================================== pouch

func test_pouch() -> void:
	var p := Pouch.new()
	p.collection = Dice.starter_collection()
	eq(Pouch.weight_of(p.collection), 21, "starter shelf weighs 21")
	for d in p.collection:
		p.add(d)
	check(p.weight() <= 12, "pouch respects the weight limit")
	var heavy := die("dragon_d12")
	p.collection.append(heavy)
	check(not p.can_add(heavy) or p.weight() + 3 <= 12, "cannot overfill")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	p.start_tale(rng)
	var n := p.pouch.size()
	p.refill_hand(rng)
	eq(p.hand.size(), 5, "hand of 5")
	# throw everything until a reshuffle
	var fat := 0
	for k in 10:
		var h: Array = p.hand.duplicate()
		p.spend(h)
		p.refill_hand(rng)
	check(p.fatigue >= 1, "running dry adds Fatigue (fatigue %d)" % p.fatigue)
	check(p.hand_size() == 5 - p.fatigue / 2, "hand shrinks with Fatigue")
	eq(p.draw_pile.size() + p.discard.size() + p.hand.size(), n, "no dice lost while cycling")
	# cursed dice stay
	var bell := die("bellmetal_d20")
	p.gain(bell)
	check(p.pouch.has(bell), "cursed die forces its way into the Pouch")
	check(not p.remove(bell), "cursed die cannot be removed")
	p.rest(rng, 2)
	check(not p.waystone_swap(bell), "cursed die cannot be swapped out")
	eq(p.fatigue, 0, "rest clears Fatigue")
	# allies leave
	var ally := die("hobb_oak_d6")
	p.gain(ally)
	var gone := p.end_tale()
	check(gone.has(ally) and not p.collection.has(ally), "lent dice go home at the end")


# ===================================================================== scoring

func test_scoring() -> void:
	var oak_m := die("oak_might")
	var t := th(oak_m, 5)
	eq(S.slot_value(t, 5, "might"), 5, "on-aspect counts full")
	eq(S.slot_value(t, 5, "lore"), 2, "off-aspect counts half, rounded down")
	var jade := die("jade_d8")
	eq(S.slot_value(th(jade, 8), 8, "lore"), 16, "Keen doubles on-aspect")
	eq(S.slot_value(th(jade, 8), 8, "might"), 4, "Keen does nothing off-aspect")
	var am := die("amethyst_d6")
	eq(S.slot_value(th(am, 4), 4, "ward"), 4, "Glint: even amethyst counts full anywhere")
	eq(S.slot_value(th(am, 3), 3, "ward"), 1, "Glint: odd amethyst is still halved")
	var wild := die("wild_d4")
	eq(S.slot_value(th(wild, 3), 3, "grace"), 3, "Wild counts full anywhere")
	eq(S.slot_value(t, 5, "any"), 5, "Last Stand slots take everything")

	# combos
	var a := die("oak_might")
	var b := die("oak_lore")
	var c := die("oak_grace")
	var co := S.combos([th(a, 3), th(b, 4), th(c, 5)])
	eq(co.run.size(), 3, "3-4-5 is a Run")
	co = S.combos([th(a, 4), th(b, 4), th(c, 4)])
	check(co.triple, "4-4-4 is a Triple")
	co = S.combos([th(a, 6), th(b, 6)])
	check(co.high_table, "both on max is High Table")
	eq(co.pair.size(), 2, "and a Pair")
	co = S.combos([th(die("oak_might"), 2), th(die("dragon_d10"), 7)])
	check(co.kinship, "same aspect is Kinship")
	var ev := S.evaluate([th(die("oak_might"), 2), th(die("dragon_d10"), 7)], {})
	eq(ev.vals, [3, 8], "Kinship adds 1 to each")
	ev = S.evaluate([th(die("bone_d4"), 4), th(die("oak_grace"), 3)], {})
	# bone_d4 has Kin on 4: +2 to the other Grace die, and Kinship +1 each, Kin doubled to +4
	eq(ev.vals, [5, 3 + 1 + 4], "Kin rune under Kinship")
	ev = S.evaluate([th(die("oak_lore"), 2), th(die("oak_might"), 5)], {"pity": true})
	eq(ev.vals, [2, 6], "pity adds 1 to the highest die")
	var g := die("oak_lore")
	g.grudge = "test"
	ev = S.evaluate([th(g, 2)], {"kind": "test"})
	eq(ev.vals, [3], "a Grudge adds 1 in its kind of challenge")

	# tiers
	var slots := [{"aspect": "might", "target": 13}]
	eq(S.tier_of([9], slots), S.FAIL, "4 short is a Fail")
	eq(S.tier_of([10], slots), S.MIXED, "3 short is Mixed")
	eq(S.tier_of([13], slots), S.SUCCESS, "met is a Success")
	eq(S.tier_of([18], slots), S.SUCCESS, "+5 is still a Success")
	eq(S.tier_of([19], slots), S.TRIUMPH, "+6 is a Triumph")
	eq(S.tier_of([13], slots, false, true), S.TRIUMPH, "a Triple lifts a Success")
	eq(S.tier_of([2], slots, true), S.TRIUMPH, "High Table is always a Triumph")
	var two := [{"aspect": "might", "target": 9}, {"aspect": "ward", "target": 4}]
	eq(S.tier_of([12, 0], two), S.FAIL, "every slot must be within 3 for Mixed")
	eq(S.tier_of([9, 1], two), S.MIXED, "two slots: Mixed")

	# best assignment puts each die where it counts
	var ts := [th(die("oak_might"), 6), th(die("oak_ward"), 4)]
	var e2 := S.evaluate(ts, {})
	var best := S.best_assignment(ts, e2, two, [0, 0], true)
	eq(best.assign, [0, 1], "might to might, ward to ward")


# ===================================================================== odds

func test_odds() -> void:
	# Exact enumeration agrees with sampling, and both agree with playing it out.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var cases := [
		[["oak_might", "dragon_d10", "oak_lore"], "might", 13],
		[["jade_d8", "oak_lore", "bone_d4"], "lore", 11],
		[["loaded_d6", "amethyst_d6", "oak_guile"], "guile", 13],
		[["brass_d8", "oak_ward"], "ward", 9],
	]
	report.append("## Odds check: shown odds vs. 20,000 simulated throws\n")
	report.append("| Dice | Slot | Shown (F/M/S/T) | Simulated (F/M/S/T) |")
	report.append("|---|---|---|---|")
	for cs in cases:
		var dice: Array = cs[0].map(func(b): return die(b))
		var run = Challenge.create({"target": cs[2]}, cs[1])
		var exact := Odds.challenge_odds(run, dice, {})
		check(exact.exact, "single final throw is enumerated exactly")
		var tot := 0.0
		for p in exact.tiers:
			tot += p
		near(tot, 1.0, 0.0001, "exact odds sum to 1")
		var counts := [0.0, 0.0, 0.0, 0.0]
		var n := 20000
		for k in n:
			var r2 = Odds.clone(run)
			var ts := Odds.roll(dice, rng)
			var ev := S.evaluate(ts, {})
			var b := S.best_assignment(ts, ev, r2.slots, r2.progress, true)
			r2.apply(ts, ev, b)
			counts[r2.tier()] += 1.0
		var sim := counts.map(func(c): return c / n)
		for i in 4:
			near(sim[i], exact.tiers[i], 0.015, "%s tier %d matches the simulator" % [str(cs[0]), i])
		report.append("| %s | %s %d | %s | %s |" % [", ".join(cs[0]), cs[1], cs[2], _pct(exact.tiers), _pct(sim)])
	report.append("")
	# Multi-try odds come from simulation and should sum to 1
	var trial = Challenge.create({"kind": "trial", "progress": 18, "danger": 3}, "lore")
	var hand: Array = ["jade_d8", "oak_lore", "jade_d10", "oak_grace", "bone_d4"].map(func(b): return die(b))
	var o := Odds.challenge_odds(trial, hand.slice(0, 2), {}, hand, null, 400)
	check(not o.exact, "trials are simulated")
	near(o.tiers.reduce(func(a, b): return a + b, 0.0), 1.0, 0.0001, "trial odds sum to 1")
	# Measured face distribution of the loaded die
	var ld := die("loaded_d6")
	var p := Dice.dist(ld)
	near(p[5], 0.755, 0.0001, "loaded d6 uses the measured 75.5%")


func _pct(t: Array) -> String:
	return "/".join(t.map(func(x): return "%d" % roundi(x * 100)))


# ===================================================================== combat

func test_combat() -> void:
	# The design doc's worked example: Mire Wolf, Fang 7, Pack 2. You throw Dragon's Blood d10
	# (8), Brass d8 (5), Oak d6 of Might (4).
	var wolf := Foes.foe("mire_wolf")
	var c = Combat.create(wolf)
	var fd: Array = c.begin_round()
	c.set_foe_results(fd, [7, 2])
	eq(c.incoming(), 7, "a 7-point bite is coming")
	var ts := [th(die("dragon_d10"), 8), th(die("brass_d8"), 5), th(die("oak_might"), 4)]
	var ev := S.evaluate(ts, {"kind": "combat"})
	# Kinship? d10 and oak are Might, brass is Ward: no. Plain values.
	eq(ev.vals, [8, 5, 4], "plain values")
	var a = c.simulate(ts, ev, [0, 1, 0])   # Option A: d10 + oak strike, brass guard
	eq(a.dealt, 12, "Option A deals 12")
	eq(a.taken, 2, "Option A lets 2 through")
	check(a.hamstrung, "Option A triggers Hamstring")
	var b = c.simulate(ts, ev, [0, 1, 1])   # Option B: d10 strike, brass + oak guard (oak at half)
	eq(b.dealt, 8, "Option B deals 8")
	eq(b.taken, 0, "Option B blocks everything")
	check(not b.hamstrung, "Option B avoids Hamstring")
	var best = c.best_assignment(ts, ev, 20)
	var bs = c.simulate(ts, ev, best.assign, best.read_mode, best.pair_pick)
	# The bot sees what the doc's example missed: all three in Strike (8 + 2 + 4) kills the wolf outright.
	check(bs.killed, "the bot finds the killing blow")
	# Evade with a Bone d6 showing 6 dodges the 7? No: 6 < 7. Showing 6 vs a 6 bite: yes.
	c.set_foe_results(fd, [6, 2])
	var ts2 := [th(die("bone_d6"), 6)]
	var r = c.simulate(ts2, S.evaluate(ts2, {}), [2])
	eq(r.taken, 0, "Evade equal to the attack dodges it")
	c.set_foe_results(fd, [7, 2])
	r = c.simulate(ts2, S.evaluate(ts2, {}), [2])
	eq(r.taken, 7, "Evade below the attack does nothing")
	# Trick lowers the bite
	var ts3 := [th(die("oak_guile"), 5)]
	r = c.simulate(ts3, S.evaluate(ts3, {}), [3])
	eq(r.taken, 2, "Trick 5 lowers a 7 bite to 2")
	# Pack on 4 summons
	c.set_foe_results(fd, [3, 4])
	c.resolve_round(ts3, S.evaluate(ts3, {}), [0])
	eq(c.summon_next, 1, "Pack on its highest face calls another wolf")
	eq(c.begin_round().size(), 3, "and it throws next round")
	# Ghostly halves Might
	var dr = Combat.create(Foes.foe("drowned_pair"))
	var dd: Array = dr.begin_round()
	dr.set_foe_results(dd, [1, 1])
	var ts4 := [th(die("oak_might"), 6)]
	eq(dr.simulate(ts4, S.evaluate(ts4, {}), [0]).dealt, 3, "Ghostly halves Might damage")
	var ts5 := [th(die("oak_lore"), 6)]
	eq(dr.simulate(ts5, S.evaluate(ts5, {}), [0]).dealt, 6, "weakness (Lore) strikes in full")
	var ts6 := [th(die("oak_lore"), 6), th(die("oak_might"), 6)]
	var ev6 := S.evaluate(ts6, {})
	var sil = dr.simulate(ts6, ev6, [4, 0], "silence")
	check(sil.silenced == "ghostly", "Read can silence Ghostly")

	# A bot fights the Mire Wolf many times (milestone gate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var wins := 0
	var rounds := 0
	var taken := 0
	var fights := 400
	for k in fights:
		var cb = Combat.create(Foes.foe("mire_wolf"))
		var grit := 20
		var pouch := Pouch.new()
		pouch.collection = Dice.starter_collection()
		var bt := Bot.new()
		var camp := Campaign.new()
		camp.pouch = pouch
		bt.pack(camp, "balanced")
		pouch.start_tale(rng)
		while not cb.over and grit > 0:
			var fdice: Array = cb.begin_round()
			var vals: Array = fdice.map(func(d): return rng.randi_range(1, d.sides))
			cb.set_foe_results(fdice, vals)
			pouch.refill_hand(rng)
			var hand := pouch.hand.duplicate()
			hand.sort_custom(func(x, y): return Dice.mean_n(x) > Dice.mean_n(y))
			var pick := hand.slice(0, cb.effort())
			var tsx := Odds.roll(pick, rng)
			if cb.quake():
				pass
			var evx := S.evaluate(tsx, {"kind": "combat"})
			var bb = cb.best_assignment(tsx, evx, grit)
			var rr = cb.resolve_round(tsx, evx, bb.assign, bb.read_mode, bb.pair_pick)
			grit -= rr.taken
			pouch.spend(pick)
		if cb.outcome == "won":
			wins += 1
		rounds += cb.round_no
		taken += cb.taken_total
	var wr := float(wins) / fights
	print("  Mire Wolf: bot wins %d%%, %.1f rounds, %.1f Grit lost on average" % [roundi(wr * 100), float(rounds) / fights, float(taken) / fights])
	check(wr > 0.6, "a balanced Pouch usually beats the Mire Wolf")
	report.append("## Mire Wolf (bot, balanced Pouch, %d fights)\n" % fights)
	report.append("Wins %d%%, %.1f rounds, %.1f Grit lost on average.\n" % [roundi(wr * 100), float(rounds) / fights, float(taken) / fights])


# ===================================================================== contest

func test_contest() -> void:
	var k = Contest.create(Foes.opponent("kettle"), "guile")
	check(k.is_card_sharp(), "Kettle is a card sharp")
	var ld := die("loaded_d6")
	near(k.catch_odds([ld]), 0.755 * 0.5 + 0.245 / 6.0, 0.0001, "catch odds shown for a loaded die")
	eq(k.catch_odds([die("oak_guile")]), 0.0, "honest dice are never caught")
	k.begin_round()
	k.set_opponent_throw([4, 3])
	eq(k.pressure, 7, "opponent pressure is their total")
	var ts := [th(die("oak_guile"), 6), th(die("oak_guile"), 5), th(die("oak_lore"), 4)]
	var ev := S.evaluate(ts, {})
	var best: Dictionary = k.best_assignment(ts, ev)
	var r: Dictionary = k.simulate(ts, ev, best.assign, best.pair_pick)
	check(r.press + r.hold >= 13, "every point goes somewhere")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Many contests with loaded dice: caught about as often as shown
	var caught := 0
	var n := 4000
	for i in n:
		var kc = Contest.create(Foes.opponent("kettle"), "guile")
		kc.begin_round()
		kc.set_opponent_throw([3, 3])
		var tsl := Odds.roll([ld], rng)
		var evl := S.evaluate(tsl, {})
		kc.resolve_round(tsl, evl, [0], 0, rng)
		if kc.caught:
			caught += 1
	near(float(caught) / n, k.catch_odds([ld]), 0.025, "caught as often as the odds say")
	# tiers
	var t = Contest.create(Foes.opponent("odile"), "grace")
	t.round_no = 1
	t.resolve = 0
	eq(t.tier(), S.TRIUMPH, "breaking them in round 1 is a Triumph")
	t.round_no = 3
	t.nerve = 6
	eq(t.tier(), S.SUCCESS, "breaking them later is a Success")
	t.resolve = 2
	eq(t.tier(), S.MIXED, "close at the end is Mixed")
	t.resolve = 6
	eq(t.tier(), S.FAIL, "far off is a Fail")


# ===================================================================== challenge types

func test_challenges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var hand: Array = ["oak_lore", "jade_d8", "jade_d10", "oak_grace", "bone_d4"].map(func(b): return die(b))
	# Test
	var t = Challenge.create({"kind": "test", "difficulty": "standard"}, "lore")
	eq(t.slots[0].target, 13, "Standard target is 13")
	check(t.is_final(3), "a one-try test is final")
	# Trial: rushing ticks twice
	var tr = Challenge.create({"kind": "trial", "progress": 18, "danger": 3}, "lore")
	eq(tr.ticks_for(3), 2, "throwing full Effort in a trial rushes")
	eq(tr.ticks_for(2), 1, "holding a die back ticks once")
	var ts := Odds.roll(hand.slice(0, 2), rng)
	var ev := S.evaluate(ts, {})
	var b := S.best_assignment(ts, ev, tr.slots, tr.progress, false)
	tr.apply(ts, ev, b)
	eq(tr.danger, 1, "clock ticks")
	check(not tr.over or tr.high_table_hit, "trial continues")
	# Last Stand takes the whole hand at full value
	var ls = Challenge.last_stand(5)
	eq(ls.effort, 5, "Last Stand throws the whole Hand")
	eq(ls.slots[0].aspect, "any", "and every die counts in full")
	# Tier distribution on- and off-aspect for a Standard test with a typical Pouch
	report.append("## Standard test (target 13), best 3 of a 5-die Hand, 20,000 throws\n")
	report.append("| Hand | Fail | Mixed | Success | Triumph |")
	report.append("|---|---|---|---|---|")
	var p := Pouch.new()
	p.collection = Dice.starter_collection()
	var camp := Campaign.new()
	camp.pouch = p
	var bt := Bot.new()
	bt.pack(camp, "balanced")
	for asp in ["lore", "might"]:
		var counts := [0.0, 0.0, 0.0, 0.0]
		var on := 0.0
		var n := 20000
		for k in n:
			p.start_tale(rng)
			p.refill_hand(rng)
			var run = Challenge.create({"kind": "test", "difficulty": "standard"}, asp)
			var dice := Odds.pick(p.hand, run.slots, 3)
			var tsx := Odds.roll(dice, rng)
			var evx := S.evaluate(tsx, {})
			run.apply(tsx, evx, S.best_assignment(tsx, evx, run.slots, run.progress, true))
			counts[run.tier()] += 1
		report.append("| balanced Pouch, %s | %s |" % [asp, " | ".join(counts.map(func(c): return "%d%%" % roundi(c * 100.0 / n)))])
	var cands := [["jade_d8", "jade_d10", "oak_lore"], ["oak_might", "oak_guile", "oak_grace"]]
	for cand in cands:
		var counts := [0.0, 0.0, 0.0, 0.0]
		var dice: Array = cand.map(func(x): return die(x))
		var run = Challenge.create({"kind": "test", "difficulty": "standard"}, "lore")
		var o := Odds.challenge_odds(run, dice, {})
		report.append("| %s vs Lore 13 | %s |" % [", ".join(cand), " | ".join(o.tiers.map(func(c): return "%d%%" % roundi(c * 100.0)))])
	report.append("")


# ===================================================================== linter

func test_lint() -> void:
	for path in Tales.all_paths():
		var res: Dictionary = Tales.parsed(path)
		eq(res.errors.size(), 0, "%s parses cleanly %s" % [path, str(res.errors)])
		var issues: Array = Lint.run(res.tale, res.lines)
		for i in issues:
			print("    %s:%d: %s" % [path.get_file(), i.line, i.msg])
		eq(issues.size(), 0, "%s passes the linter" % path)
		print("  %s: %d scenes" % [path.get_file(), res.tale.scenes.size()])
	var pr: Array = Lint.run(Practice.tale())
	for i in pr:
		print("    practice: ", i.msg)
	eq(pr.size(), 0, "the practice table passes the linter")
	eq(Practice.challenges().size(), 20, "the practice table has 20 challenges")


## The .tale format: the parser, the writer, and error messages that point at the right line.
func test_format() -> void:
	var path := Tales.DROWNED_BELL
	var text := FileAccess.get_file_as_string(path)
	var res := Parser.parse(text)
	eq(res.errors.size(), 0, "drowned_bell.tale parses without errors")
	eq(Writer.write(res.tale), text, "writing the parsed tale gives back the same file")
	var pt: Dictionary = Practice.tale()
	var back: Dictionary = Parser.parse(Writer.write(pt)).tale
	check(_norm(back) == _norm(pt), "the practice table survives a write and parse unchanged")
	# The parsed tale plays: a bot reaches an ending.
	var camp := Campaign.new()
	camp.new_campaign()
	var r := Runner.new()
	var bt := Bot.new()
	bt.rng.seed = 11
	r.start(res.tale, camp, 3)
	bt.play(r)
	eq(r.phase, "ending", "a bot plays the parsed tale to an ending")
	# Values and effects.
	var t: Dictionary = Parser.parse("title: T\nid: t\nstart: a\n\n## a: A\non enter: flag x 3; standing \"Thieves' Guild\" -2; random_flag w [fog, rain]; if x>=2 then grit -1\n\n* go: Go.\n  goto: a\n").tale
	eq(t.scenes.a.on_enter, [["flag", "x", 3], ["standing", "Thieves' Guild", -2], ["random_flag", "w", ["fog", "rain"]], ["if", "x>=2", ["grit", -1]]], "effects parse with numbers, quotes, lists and if")
	var t2: Dictionary = Parser.parse("title: T\nid: t\nstart: a\n## a: A\n* f: Fight.\n  challenge: kind=test second.aspect=ward second.target=6 title=\"A b\"\n  mod: x => progress=-4\n  approach might [progress=19]: Hit it.\n  > mixed: Hm.\n    It continues.\n    cost: Lose 3 Grit :: grit -3\n").tale
	var o: Dictionary = t2.scenes.a.options[0]
	eq(o.challenge, {"kind": "test", "second": {"aspect": "ward", "target": 6}, "title": "A b", "mods": [["x", {"progress": -4}]]}, "challenge key=values, dotted keys and mods")
	eq(o.approaches[0], {"aspect": "might", "text": "Hit it.", "set": {"progress": 19}}, "approach with overrides")
	eq(o.outcomes.mixed.text, "Hm. It continues.", "outcome text continues over lines")
	eq(o.outcomes.mixed.costs[0], {"label": "Lose 3 Grit", "effects": [["grit", -3]]}, "costs")
	# Errors carry line numbers.
	var bad := Parser.parse("title: T\nid: t\nstart: a\n## a: A\n* x: X\n  goto: a\n  this is stray text\n  > perhaps: no\n")
	eq(bad.errors.size(), 2, "two mistakes, two errors")
	if bad.errors.size() == 2:
		eq(bad.errors[0].line, 7, "stray text after an option is reported on its line")
		eq(bad.errors[1].line, 8, "an unknown tier is reported on its line")
	# The linter points at lines too.
	var lt := Parser.parse("title: T\nid: t\nstart: a\n## a: A\n* x: Fight it.\n  combat: foe=dragon\n  > fail: F\n    goto: nowhere\n  > mixed: M\n    goto: a\n    cost: One :: grit -1\n  > success: S\n    goto: a\n")
	var li: Array = Lint.run(lt.tale, lt.lines)
	var msgs := " | ".join(li.map(func(i): return "%d %s" % [i.line, i.msg]))
	check(msgs.contains("5 Unknown foe 'dragon'"), "unknown foe is reported at the option's line (%s)" % msgs)
	check(msgs.contains("No outcome for triumph"), "missing tier is reported")
	check(msgs.contains("9 A Mixed outcome offers 2"), "one-cost Mixed is reported at the outcome's line")
	check(msgs.contains("'nowhere' is not a scene"), "a bad goto is reported")


## The M3 gate: The Drowned Bell plays start to finish in the text preview, every ending is
## reachable, and the walks see (nearly) every option and outcome.
func test_preview() -> void:
	var p := Preview.new()
	p.open(Tales.DROWNED_BELL)
	eq(p.errors.size(), 0, "the preview opens the tale")
	eq(p.issues.size(), 0, "the preview's linter is clean")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var endings := {}
	var n := maxi(120, runs)
	for k in n:
		p.seed_value = k + 1
		p.archetype = ["balanced", "bruiser", "sage", "swindler"][k % 4]
		p.restart()
		p.walk(rng)
		check(p.runner.phase == "ending", "walk %d reaches an ending (stopped in %s at %s)" % [k, p.runner.phase, p.scene_id()])
		endings[p.runner.state.ending] = true
	for e in ["rest", "silence", "greed", "bargain", "drowned"]:
		check(endings.has(e), "the preview reaches the %s ending" % e)
	var all: Array = p.all_targets()
	var seen := all.filter(func(k): return p.seen.has(k)).size()
	print("  " + p.coverage_text())
	check(seen >= all.size() * 0.95, "walks see 95%% of options and outcomes (%d of %d)" % [seen, all.size()])
	# Commands.
	p.restart()
	p.command("goto chamber")
	eq(p.scene_id(), "chamber", "goto jumps to a scene")
	p.command("flag climax=freed")
	eq(p.runner.state.flags.get("climax"), "freed", "flag sets a word value")
	check(p.command("check climax==freed").ends_with("true"), "check evaluates a condition")


func _norm(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			var x = _norm(v[k])
			if (x is Array or x is Dictionary) and x.is_empty():
				continue
			d[k] = x
		return d
	if v is Array:
		return v.map(func(x): return _norm(x))
	return v


# ===================================================================== save

func test_save() -> void:
	var c := Campaign.new()
	c.new_campaign()
	c.pouch.add(c.pouch.collection[0])
	c.pouch.add(c.pouch.collection[5])
	c.pouch.collection[5].notches = 2
	c.mark("drowned_before")
	var path := "user://test_campaign.json"
	c.save(path)
	var c2 := Campaign.new()
	check(c2.load_save(path), "save loads")
	eq(c2.pouch.collection.size(), c.pouch.collection.size(), "collection survives")
	eq(c2.pouch.pouch.size(), 2, "pouch survives")
	eq(c2.pouch.collection[5].notches, 2, "notches survive")
	check(c2.has_mark("drowned_before"), "marks survive")
	eq(typeof(c2.pouch.collection[0].faces[0].n), TYPE_INT, "face numbers come back as ints")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Mid-tale saves: stop at every scene of several runs, save through JSON, resume, finish.
	var resumed := 0
	for k in 12:
		var camp := Campaign.new()
		camp.new_campaign()
		var r := Runner.new()
		var bt := Bot.new()
		bt.rng.seed = 900 + k
		r.start(Tales.drowned_bell(), camp, 50 + k)
		var stop_at := 3 + k % 6
		var guard := 0
		while guard < 2000 and r.phase != "ending" and not (r.can_snapshot() and r.state.visited.size() >= stop_at):
			guard += 1
			bt.step(r)
		if r.phase == "ending":
			continue
		var snap = JSON.parse_string(JSON.stringify(r.snapshot(Tales.DROWNED_BELL)))
		var camp2 := Campaign.new()
		var r2 := Runner.new()
		r2.resume(Tales.drowned_bell(), camp2, snap)
		resumed += 1
		eq(r2.scene.id, r.scene.id, "resume %d returns to the same scene" % k)
		eq(r2.phase, "choose", "resume %d waits for a choice" % k)
		eq(r2.state.grit, r.state.grit, "resume %d keeps Grit" % k)
		eq(r2.state.fate, r.state.fate, "resume %d keeps Fate" % k)
		eq(r2.state.wounds, r.state.wounds, "resume %d keeps Wounds" % k)
		eq(JSON.stringify(r2.state.flags), JSON.stringify(r.state.flags), "resume %d keeps flags" % k)
		eq(r2.pouch.pouch.map(func(d): return d.id), r.pouch.pouch.map(func(d): return d.id), "resume %d keeps the Pouch" % k)
		eq(r2.pouch.draw_pile.size() + r2.pouch.discard.size(), r.pouch.draw_pile.size() + r.pouch.discard.size(), "resume %d keeps the draw pile" % k)
		eq(r2.pouch.fatigue, r.pouch.fatigue, "resume %d keeps Fatigue" % k)
		eq(r2.visible_options().size(), r.visible_options().size(), "resume %d shows the same options" % k)
		var v1 := Board.view(r.tale, r.state, [], r.ctx())
		var v2 := Board.view(r2.tale, r2.state, [], r2.ctx())
		eq(JSON.stringify([v2.tiles, v2.roads, v2.path, v2.tokens]), JSON.stringify([v1.tiles, v1.roads, v1.path, v1.tokens]), "resume %d brings the tale board back as it was" % k)
		if r.state.wager != null:
			check(r2.state.wager != null and r2.pouch.collection.has(r2.state.wager), "resume %d keeps the wager as the same die" % k)
		var bt2 := Bot.new()
		bt2.rng.seed = 77 + k
		bt2.play(r2)
		eq(r2.phase, "ending", "resumed run %d plays on to an ending" % k)
	check(resumed >= 8, "most runs were saved and resumed mid-tale (%d)" % resumed)


# ===================================================================== tale board

func test_board() -> void:
	var tale: Dictionary = Tales.drowned_bell()
	var lay := Board.layout(tale)
	eq(lay.tiles.size(), 11, "The Drowned Bell has 11 tiles (wager, prepare and the ending are not places)")
	eq(lay.start, "plea", "the board starts at Wren's table")
	var keys: Array = lay.roads.map(func(r): return Board.road_key(r.a, r.b))
	for pair in [["plea", "arrival"], ["arrival", "waystone"], ["fork", "dive"], ["dive", "gold"], ["gold", "waystone"], ["waystone", "chamber"], ["kettle", "kettle_brawl"]]:
		check(keys.has(Board.road_key(pair[0], pair[1])), "a road joins %s and %s" % pair)
	check(not keys.has(Board.road_key("plea", "wager")), "scenes that are not tiles are walked through, not drawn")
	# Roads bend around tiles they would otherwise run through.
	for r in lay.roads:
		for id in lay.pos:
			if id == r.a or id == r.b:
				continue
			var d := Board._dist_to_curve(lay.pos[id], lay.pos[r.a], lay.pos[r.b], r.bend)
			check(d >= Board.MIN_GAP * 0.99 or r.bend == 0.0, "the road %s-%s keeps clear of %s" % [r.a, r.b, id])
	# A walk: at the fork, three roads open; after the cove, the others stay as roads not taken.
	var camp := Campaign.new()
	camp.new_campaign()
	var st = load("res://scripts/rules/tale_state.gd").new()
	st.visited = ["plea", "wager", "prepare", "arrival", "tolls", "fork"]
	var v := Board.view(tale, st)
	eq(v.here, "fork", "the figurine stands at the jetty")
	eq(v.path, ["plea", "arrival", "tolls", "fork"], "the path skips scenes that are not tiles")
	eq(v.tiles.fork, Board.CURRENT, "current tile")
	eq(v.tiles.arrival, Board.VISITED, "visited tile")
	for id in ["scriptorium", "kettle", "dive"]:
		eq(v.tiles[id], Board.OPEN, "%s is a road you could take" % id)
	eq(v.tiles.chamber, Board.FOG, "the Bell Chamber is still in fog")
	eq(v.tiles.waystone, Board.PASSED, "the row-out road you didn't take leaves the shrine sketched")
	eq(v.roads[Board.road_key("arrival", "tolls")], Board.VISITED, "walked roads are inked")
	eq(v.roads[Board.road_key("arrival", "waystone")], Board.PASSED, "the road not taken stays faded")
	st.visited.append("kettle")
	v = Board.view(tale, st)
	eq(v.tiles.dive, Board.PASSED, "after the cove, the dive is a road not taken")
	eq(v.tiles.kettle_brawl, Board.OPEN, "from the cove, the brawl is open")
	# Tokens: choices leave marks; a won fight leaves the foe's figurine.
	st.set_flag("smugglers_allied")
	st.set_flag("villagers_saved", 2)
	st.set_flag("fisherman_lost")
	st.marks.append({"scene": "tolls", "icon": "foe", "label": "Two Drowned, beaten", "figure": "drowned"})
	v = Board.view(tale, st, [], {"state": st, "pouch": camp.pouch, "campaign": camp})
	var labels: Array = v.tokens.map(func(t): return t.label)
	check(labels.has("Kettle's crew, allies"), "an alliance leaves Kettle's flag on the cove")
	check(labels.has("The village, every lamp lit"), "saving the village leaves lit lamps")
	check(labels.has("Aldous, taken by the lake"), "a lost fisherman leaves a grave")
	check(labels.has("Two Drowned, beaten"), "a won fight leaves the foe's figurine")
	check(not labels.has("Ysolde, at rest"), "the ending's marks wait for the ending")
	# The board remembers earlier tellings: roads walked before are not fog.
	st.visited = ["plea", "wager", "prepare", "arrival"]
	v = Board.view(tale, st, ["plea", "arrival", "tolls", "fork", "dive", "gold", "waystone", "chamber"])
	eq(v.tiles.chamber, Board.REMEMBERED, "a tile from an earlier telling is remembered")
	eq(v.roads[Board.road_key("dive", "gold")], Board.REMEMBERED, "and so is its road")
	eq(v.tiles.scriptorium, Board.FOG, "places never seen stay in fog")
	camp.remember_map("drowned_bell", ["plea", "fork", "plea"])
	camp.remember_map("drowned_bell", ["fork", "dive"])
	eq(camp.map_seen("drowned_bell"), ["plea", "fork", "dive"], "the campaign remembers each place once")
	var path := "user://test_board_campaign.json"
	camp.save(path)
	var c2 := Campaign.new()
	c2.load_save(path)
	eq(c2.map_seen("drowned_bell"), ["plea", "fork", "dive"], "map memory survives a save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# A tale with no tiles still gets a board, laid out by distance from the start.
	var bare: Dictionary = Parser.parse("title: T\nid: t\nstart: a\n## a: A\n* x: X\n  goto: b\n* y: Y\n  goto: c\n## b: B\n* z: Z\n  goto: d\n## c: C\n* z: Z\n  goto: d\n## d: D\n* z: Z\n  goto: e\n## e: E\ntype: ending\n+ end: End\n").tale
	var bl := Board.layout(bare)
	check(bl.auto, "a tale without tiles is laid out automatically")
	eq(bl.tiles.size(), 4, "every scene but the ending is a tile")
	eq(bl.pos.b.x, 1.0, "laid out by distance from the start")
	eq(bl.pos.d.x, 2.0, "branches rejoin a column further on")
	# The parser and linter know tiles and tokens.
	var bt := Parser.parse("title: T\nid: t\nstart: a\n## a: A\ntile: castle\nat: 1, 2.5\ntoken: nope => banana \"A b\"\n* x: X\n  goto: a\n")
	eq(bt.tale.scenes.a.at, Vector2(1, 2.5), "at: reads two numbers")
	eq(bt.tale.scenes.a.tokens[0], {"cond": "nope", "icon": "banana", "label": "A b"}, "token: reads condition, icon and label")
	var li := " | ".join(Lint.run(bt.tale, bt.lines).map(func(i): return i.msg))
	check(li.contains("Unknown tile 'castle'"), "the linter catches an unknown tile")
	check(li.contains("Unknown token 'banana'"), "the linter catches an unknown token")
	check(li.contains("'nope' is read here but never set"), "token conditions count as flags read")
	# A real run leaves a fallen-foe mark where it won a fight, and the board can show it.
	var found := false
	for k in 30:
		var cc := Campaign.new()
		cc.new_campaign()
		var r := Runner.new()
		var b := Bot.new()
		b.rng.seed = 300 + k
		r.start(Tales.drowned_bell(), cc, 400 + k)
		b.play(r)
		for m in r.state.marks:
			if m.icon == "foe":
				found = true
				check(Board.layout(r.tale).pos.has(m.scene), "the fallen foe lies on a tile (%s)" % m.scene)
		check(cc.map_seen("drowned_bell").size() >= 4, "a finished tale is remembered on the map")
	check(found, "bots win fights and leave fallen-foe tokens")


# ===================================================================== the Dicewright and the shelf

func test_forge() -> void:
	var c := Campaign.new()
	c.new_campaign()
	c.coin = 100
	var oak: Dictionary = c.pouch.collection[0]
	var r := Forge.recarve(c, oak, 0, 1)
	check(r.ok, "recarve a plain oak face")
	eq(oak.faces[0].n, 2, "the 1 is a 2 now")
	eq(c.coin, 100 - Forge.RECARVE_COST, "recarving costs Coin")
	for i in 3:
		Forge.recarve(c, oak, 1 + i, 1)
	eq(Forge.carved(oak), 4, "four points carved")
	check(not Forge.can_recarve(c, oak, 5, 1).ok, "a die's faces rise by 4 at most")
	check(Forge.can_recarve(c, oak, 5, -1).ok, "carving down is still allowed")
	check(not Forge.can_recarve(c, oak, 0, 2).ok, "one point at a time")
	var loaded: Dictionary = c.pouch.collection.filter(func(d): return d.has("loaded_face"))[0]
	check(not Forge.can_recarve(c, loaded, 0, 1).ok, "Brannoc won't recarve a loaded die")
	# Inscribe needs a shard, a plain face and room under the rune cap.
	check(not Forge.can_inscribe(c, oak, 2, "guard").ok, "no shard, no rune")
	c.shards.append("Guard")
	r = Forge.inscribe(c, oak, 2, "guard")
	check(r.ok, "inscribe Guard from a shard")
	eq(oak.faces[2].rune, "guard", "the face carries Guard")
	eq(c.shards.size(), 0, "the shard is used up")
	c.shards.append("Spark")
	check(not Forge.can_inscribe(c, oak, 3, "spark").ok, "a common die holds one rune face")
	var brass: Dictionary = c.pouch.collection.filter(func(d): return d.base == "brass_d8")[0]
	check(not Forge.can_inscribe(c, brass, 6, "spark").ok, "a face with a rune can't take another")
	check(not Forge.can_inscribe(c, brass, 0, "spark").ok, "a fine die with two rune faces is full")
	var jade: Dictionary = c.pouch.collection.filter(func(d): return d.base == "jade_d8")[0]
	check(Forge.can_inscribe(c, jade, 0, "spark").ok, "a fine die with one rune face has room for another")
	# Melt gives the runes back as shards.
	var dragon: Dictionary = c.pouch.collection.filter(func(d): return d.base == "dragon_d10")[0]
	var n: int = c.pouch.collection.size()
	r = Forge.melt(c, dragon)
	check(r.ok, "melt a die")
	eq(c.pouch.collection.size(), n - 1, "the die is gone")
	check(c.shards.has("Strike"), "its Strike runes come back as a shard")
	var bell := Dice.create("bellmetal_d20")
	c.pouch.collection.append(bell)
	check(not Forge.can_melt(c, bell).ok, "a cursed die won't melt")
	check(not Forge.can_sell(c, bell).ok, "or sell")
	check(Forge.unworkable(bell) != "", "or go under the chisel")
	# Hollis buys and sells, but won't leave you with nothing to throw.
	var coin := c.coin
	r = Forge.buy(c, Forge.STOCK[0])
	check(r.ok, "buy an oak die")
	eq(c.coin, coin - int(Forge.STOCK[0].price), "it costs its price")
	var sold: Dictionary = c.pouch.collection[1]
	coin = c.coin
	r = Forge.sell(c, sold)
	check(r.ok and not c.pouch.collection.has(sold), "sell a die")
	eq(c.coin, coin + Forge.sell_price(sold), "for its price")
	while c.pouch.collection.size() > Forge.MIN_COLLECTION:
		c.pouch.lose(c.pouch.collection[0])
	check(not Forge.can_sell(c, c.pouch.collection[0]).ok, "Hollis keeps you to %d dice at least" % Forge.MIN_COLLECTION)
	check(not Forge.can_melt(c, c.pouch.collection[0]).ok, "and so does Brannoc")
	# Forged dice survive a save, with their history.
	var path := "user://test_forge.json"
	c.save(path)
	var c2 := Campaign.new()
	c2.load_save(path)
	var oak2: Array = c2.pouch.collection.filter(func(d): return d.id == oak.id)
	if not oak2.is_empty():
		eq(oak2[0].faces[0].n, 2, "a recarved face survives a save")
		eq(oak2[0].faces[2].rune, "guard", "an inscribed rune survives a save")
		eq(int(oak2[0].get("carved", 0)), 4, "so does how far it has been carved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===================================================================== the campaign

func test_campaign() -> void:
	var c := Campaign.new()
	c.new_campaign()
	# Calendar: four seasons of six nights.
	eq(c.night, 1, "a campaign starts on night 1")
	eq(c.season(), "spring", "in spring")
	var lines := Patrons.pass_nights(c, 6)
	eq(c.season(), "summer", "six nights later it is summer")
	check(c.events_seen.has("summer_fair"), "the midsummer fair comes with summer")
	check(lines.any(func(l): return l.text == "Summer"), "the turning of the season is told")
	eq(Forge.stock(c).size() > Forge.STOCK.size(), true, "the fair brings fine dice to Hollis's shelf")
	# Wounds: one mends when the season turns.
	c.wounds = ["Cracked Ribs", "Fever"]
	Patrons.pass_nights(c, Patrons.nights_to_next_season(c))
	eq(c.season(), "autumn", "waiting for the next season lands on its first night")
	eq(c.wounds, ["Fever"], "the turning of a season mends one Wound")
	check(c.events_seen.has("winter_road") == false, "winter hasn't come yet")
	# Expiring tales are missed when their season comes.
	Patrons.pass_nights(c, Patrons.nights_to_next_season(c))
	eq(c.season(), "winter", "winter")
	for t in ["bell_market", "pretender_road", "siege_holloway"]:
		check(c.missed.has(t), "%s goes by without you when winter comes" % t)
	check(c.has_mark("road_closed"), "the first snow closes the road")
	check(not Patrons.offered(c, _header("bell_market")), "a missed tale is not offered")
	Patrons.pass_nights(c, Patrons.nights_to_next_season(c))
	check(c.year_over(), "after winter the year is out")
	# Renown buys Pouch weight.
	c = Campaign.new()
	c.new_campaign()
	var w: int = c.pouch.weight_limit
	eq(c.add_renown(3), 1, "3 Renown is the first step")
	eq(c.pouch.weight_limit, w + 1, "and a point of Pouch weight")
	c.add_renown(9)
	eq(c.renown_level(), 3, "12 Renown is three steps")
	eq(c.pouch.saddle_limit, Campaign.BASE_SADDLE + 1, "the third step widens the Saddlebag")
	# Standing is clamped, and faction ids and names both work.
	c.add_standing("guild", 5)
	eq(c.standing_of("Thieves' Guild"), 3, "Standing tops out at 3")
	c.add_standing("Abbey", -1)
	eq(c.standing_of("abbey"), -1, "names and ids are the same faction")
	# What happened in each tale, and the conditions that read it.
	var ctx := Patrons.ctx(c)
	check(not Cond.check("told:drowned_bell", ctx), "an untold tale")
	c.record_tale("drowned_bell", "drowned", false)
	check(Cond.check("told:drowned_bell", ctx) and not Cond.check("ended:drowned_bell", ctx), "told, but lost")
	eq(c.ending_of("drowned_bell"), "drowned", "the defeat is all there is")
	c.record_tale("drowned_bell", "greed", true)
	c.record_tale("drowned_bell", "drowned", false)
	check(Cond.check("ended:drowned_bell and ending:drowned_bell==greed", ctx), "a later defeat doesn't overwrite how it ended")
	check(Cond.check("standing:guild>=3 and standing:abbey<0", ctx), "Standing conditions")
	check(Cond.check("season==spring and night<=1", ctx), "calendar conditions")
	c.rumour_ids.append("tide_turn")
	check(Cond.check("rumour:tide_turn and not rumour:kettle_lake", ctx), "rumour conditions")
	c.missed.append("siege_holloway")
	check(Cond.check("missed:siege_holloway", ctx), "missed conditions")
	check(not Cond.check("cursed", ctx), "no cursed die yet")
	c.pouch.collection.append(Dice.create("bellmetal_d20"))
	c.pouch.add(c.pouch.collection[-1])
	check(Cond.check("cursed", ctx), "carrying the Bellmetal is cursed")
	# Patrons' offers follow the arcs.
	c = Campaign.new()
	c.new_campaign()
	var ids: Array = Patrons.offers(c).filter(func(h): return h.arc in ["wren", "ashgrove"]).map(func(h): return h.id)
	eq(ids, ["drowned_bell", "last_watch"], "the first night, Wren and the captain each offer their first tale")
	c.record_tale("drowned_bell", "rest", true)
	c.record_tale("last_watch", "banner", true)
	ids = Patrons.offers(c).filter(func(h): return h.arc in ["wren", "ashgrove"]).map(func(h): return h.id)
	eq(ids, ["bell_market", "pretender_road"], "then the second tale of each arc")
	c.record_tale("bell_market", "rest", true)
	c.record_tale("pretender_road", "joined", true)
	c.mark("sided_harrow")
	ids = Patrons.offers(c).filter(func(h): return h.arc in ["wren", "ashgrove"]).map(func(h): return h.id)
	eq(ids, [], "the Tide Court waits for autumn, and the siege won't come to a turncoat")
	c.night = 13
	ids = Patrons.offers(c).filter(func(h): return h.arc in ["wren", "ashgrove"]).map(func(h): return h.id)
	eq(ids, ["tide_court"], "in autumn the Tide Court sits")
	check(Patrons.offer_note(c, _header("bell_market")) == "", "a done tale has nothing running out")
	c.tales.erase("bell_market")
	c.night = 15
	eq(Patrons.offer_note(c, _header("bell_market")), "Before winter: 4 nights left.", "the expiry is shown in nights")
	# Season events read earlier tales.
	c = Campaign.new()
	c.new_campaign()
	c.mark("greed")
	c.record_tale("pretender_road", "joined", true)
	Patrons.pass_nights(c, 12)
	check(c.has_mark("marrowmere_flooded"), "keeping the gold floods Marrowmere in autumn")
	check(c.has_mark("hill_farms_burned"), "siding with the Pretender empties the hill farms")
	# Sister Maud.
	c = Campaign.new()
	c.new_campaign()
	c.coin = 20
	check(not Patrons.can_heal(c, true).ok, "no Wounds, nothing to treat")
	c.wounds = ["Broken Hand", "Fever"]
	eq(Patrons.heal_cost(c), Patrons.HEAL_COST, "full price with no Abbey standing")
	c.add_standing("abbey", 2)
	eq(Patrons.heal_cost(c), 2, "the Abbey's friends pay less")
	var r := Patrons.heal(c, true, 1)
	check(r.ok and c.wounds == ["Broken Hand"], "Maud treats the Wound you pick")
	eq(c.coin, 18, "for Coin")
	eq(c.night, 2, "and a night")
	c.coin = 0
	r = Patrons.heal(c, false)
	check(r.ok and c.wounds.is_empty(), "or for work")
	eq(c.night, 4, "which takes two nights")
	# Brannoc: trust, loading, rebinding, mending, prices.
	c = Campaign.new()
	c.new_campaign()
	c.coin = 100
	var six: Dictionary = c.pouch.collection.filter(func(d): return d.base == "oak_might")[0]
	c.add_material("lead")
	check(not Forge.can_load(c, six, 5).ok, "Brannoc won't load for a stranger")
	check(not Forge.can_give(c, "lead").ok, "lead isn't rare")
	c.add_material("heartwood")
	check(Forge.give(c, "heartwood").ok and c.trust == 1, "a rare material earns his trust")
	check(Forge.load_die(c, six, 5).ok, "then he loads a d6")
	eq(int(six.loaded_face), 6, "to favour the face picked")
	eq(c.material_count("lead"), 0, "using the lead")
	check(Cond.check("loaded", Patrons.ctx(c)) == c.pouch.pouch.has(six), "the loaded condition reads the Pouch")
	var lore: Dictionary = c.pouch.collection.filter(func(d): return d.base == "oak_lore")[0]
	lore.notches = 5
	c.add_material("binding_grace")
	check(not Forge.can_rebind(c, lore, "grace").ok, "rebinding needs more trust")
	c.trust = 2
	check(Forge.rebind(c, lore, "grace").ok, "rebind")
	eq(lore.aspect, "grace", "the aspect changes")
	eq(int(lore.notches), 2, "half the notches are forgotten")
	check(not Forge.can_rebind(c, lore, "might").ok, "only once")
	var n0: int = int(lore.faces[5].n)
	Dice.crack(lore, 5)
	check(int(lore.faces[5].n) < n0 and Dice.cracked_faces(lore) == [5], "a cracked face loses its number")
	check(Forge.mend(c, lore).ok and int(lore.faces[5].n) == n0, "Brannoc mends it")
	c.standing["Thieves' Guild"] = 3
	eq(Forge.price(c, Forge.STOCK[0]), int(Forge.STOCK[0].price) - 3, "the Guild's friends pay less at Hollis's shelf")
	# Curses: lifted where the tale says.
	var bell := Dice.create("bellmetal_d20")
	Dice.lift_curse(bell, "The Tide Court")
	check(not bell.cursed and not bell.faces.any(func(f): return f.rune == "bane"), "a lifted curse takes the bane runes with it")
	check(String(bell.name).begins_with("Quiet "), "and the die is renamed")
	# All of it survives a save.
	c.night = 9
	c.renown = 14
	c.wounds = ["Frostbite"]
	c.missed = ["siege_holloway"]
	c.rumour_ids = ["harrow_traitor"]
	c.events_seen = ["summer_fair"]
	c.record_tale("last_watch", "letter", true)
	var path := "user://test_campaign2.json"
	c.save(path)
	var c2 := Campaign.new()
	c2.load_save(path)
	eq([c2.night, c2.renown, c2.trust, c2.wounds, c2.missed, c2.rumour_ids, c2.events_seen], [9, 14, 2, ["Frostbite"], ["siege_holloway"], ["harrow_traitor"], ["summer_fair"]], "the campaign survives a save")
	eq(c2.ending_of("last_watch"), "letter", "and so does how each tale ended")
	eq(c2.pouch.weight_limit, Campaign.BASE_WEIGHT + c2.renown_level(), "Renown's weight comes back")
	var lore2: Array = c2.pouch.collection.filter(func(d): return d.id == lore.id)
	check(not lore2.is_empty() and lore2[0].aspect == "grace" and lore2[0].get("rebound", false), "a rebound die survives a save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## M6: the prologue's lent Pouch, the new arcs' offers.
## Accessibility, controls and translation: text speed, remapping, the stick throw, the .po reader,
## the translation template, and translated tales.
func test_access() -> void:
	# Text speed
	var was_speed := Settings.text_speed
	Settings.text_speed = "instant"
	eq(Settings.type_seconds(200), 0.0, "text at once takes no time")
	Settings.text_speed = "slow"
	var slow := Settings.type_seconds(200)
	Settings.text_speed = "fast"
	check(Settings.type_seconds(200) < slow, "fast text is quicker than slow")
	Settings.text_speed = was_speed
	eq(Settings.cycle(Settings.TEXT_SPEEDS, "instant"), "slow", "text speed cycles round")
	# Controls: every action is bound and survives a save as text
	var was_bind := Settings.bindings.duplicate(true)
	Settings.bindings = {}
	Controls.apply()
	for a in Controls.ACTIONS:
		check(InputMap.has_action(a[0]) and not InputMap.action_get_events(a[0]).is_empty(), "action %s is bound" % a[0])
		for code in a[2]:
			eq(Controls.code_of(Controls.parse(code)), code, "binding %s reads back" % code)
	check(Controls.describe_action("throw").contains("Space"), "the throw action names its key")
	Settings.bindings = {"throw": ["key:%d" % KEY_T, "pad:%d" % JOY_BUTTON_Y]}
	Controls.apply()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	ev.keycode = KEY_T
	ev.pressed = true
	check(InputMap.event_is_action(ev, "throw"), "a remapped key throws")
	ev.physical_keycode = KEY_SPACE
	ev.keycode = KEY_SPACE
	check(not InputMap.event_is_action(ev, "throw"), "the old key no longer throws")
	Settings.bindings = was_bind
	Controls.apply()
	# The right stick: pushed up is away from you, harder is faster, never past the tray's limit
	var up := Controls.stick_velocity(Vector2(0, -1), Basis.IDENTITY, 22.0)
	check(up.z < 0.0 and absf(up.x) < 0.01, "a stick pushed up throws away from you")
	check(Controls.stick_velocity(Vector2(0.4, 0), Basis.IDENTITY, 22.0).length() < up.length(), "a gentle push throws softer")
	check(up.length() <= 22.0, "no stick throw is harder than the tray allows")
	# The .po reader
	var po := 'msgid ""\nmsgstr ""\n"Language: de\\n"\n\n#: x\nmsgid "Throw"\nmsgstr "Werfen"\n\nmsgid ""\n"Round %d "\n"of %d"\nmsgstr "Runde %d von %d"\n\nmsgid "Say \\"hi\\""\nmsgstr ""\n'
	var m := I18n.parse_po(po)
	eq(m.get("Throw", ""), "Werfen", "a .po entry is read")
	eq(m.get("Round %d of %d", ""), "Runde %d von %d", "a .po entry split over lines is joined")
	eq(m.get("Say \"hi\"", "?"), "", "quotes are unescaped, and an untranslated entry stays empty")
	# The translation template is up to date with the scripts
	var found: Dictionary = Extract.collect()
	check(found.size() > 300, "the extractor finds the interface text (%d strings)" % found.size())
	check(found.has("Options") or found.has("Back"), "the extractor finds button text")
	check(not found.has("res://tales/strangers_throw.tale"), "paths are left out of the template")
	eq(Extract._body(FileAccess.get_file_as_string(Extract.OUT)), Extract._body(Extract.pot(found)),
		"locale/tumbling_dice.pot is up to date (run tools/extract_strings.gd)")
	# Translated tales: picked up by language, and must keep the original's shape
	var root := "user://test_tale_locale"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root + "/xx"))
	var text := FileAccess.get_file_as_string(Tales.DROWNED_BELL)
	var f := FileAccess.open(root + "/xx/drowned_bell.tale", FileAccess.WRITE)
	f.store_string(text.replace("The Drowned Bell", "La Cloche Noyée"))
	f.close()
	eq(Tales.localized_path(Tales.DROWNED_BELL, "xx", root), root + "/xx/drowned_bell.tale", "a translated tale is used in its language")
	eq(Tales.localized_path(Tales.DROWNED_BELL, "yy", root), Tales.DROWNED_BELL, "other languages keep the original")
	eq(Tales.localized_path(Tales.DROWNED_BELL, "en", root), Tales.DROWNED_BELL, "English is the original")
	var o := Parser.parse(text)
	var t := Parser.parse_file(root + "/xx/drowned_bell.tale")
	eq(Lint.same_shape(o.tale, o.lines, t.tale, t.lines).size(), 0, "a faithful translation has the same shape")
	var first: String = o.tale.scenes.keys()[1]
	var bad := Parser.parse(text.replace("## %s:" % first, "## %s_renamed:" % first))
	check(Lint.same_shape(o.tale, o.lines, bad.tale, bad.lines).size() >= 2, "a renamed scene in a translation is caught")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/xx/drowned_bell.tale"))
	for pair in Tales.translations():
		var po2: Dictionary = Tales.parsed(pair[0])
		var tr2: Dictionary = Tales.parsed(pair[1])
		var probs := Lint.same_shape(po2.tale, po2.lines, tr2.tale, tr2.lines)
		eq(probs.size(), 0, "%s keeps the original's ids %s" % [pair[1], str(probs.slice(0, 3))])
		eq(Lint.run(tr2.tale, tr2.lines).size(), 0, "%s passes the linter" % pair[1])


func test_m6() -> void:
	# Every foe, opponent and die named in the data is complete.
	for id in Foes.FOE_IDS:
		var f: Dictionary = Foes.foe(id)
		check(not f.is_empty() and not f.get("phases", []).is_empty(), "foe %s exists" % id)
		for ph in f.get("phases", []):
			var packs: bool = (ph.dice + ph.get("wardens", [])).any(func(d): return d.kind == "pack")
			check(not packs or ph.has("summon"), "foe %s: a pack die needs a summon" % id)
	for id in Foes.OPPONENT_IDS:
		check(Foes.opponent(id).has("resolve"), "opponent %s exists" % id)
	for b in Dice.ALL_IDS:
		check(not Dice.create(b).is_empty(), "die %s exists" % b)
	# The prologue lends a fixed Pouch and hands your own back at the end, plus the die you chose.
	for k in 6:
		var c := Campaign.new()
		c.new_campaign()
		var bt := Bot.new()
		bt.rng.seed = 900 + k
		bt.pack(c, "sage")
		var before: Array = c.pouch.pouch.map(func(d): return d.id)
		var n_before: int = c.pouch.collection.size()
		var r := Runner.new()
		var lent := []
		r.changed.connect(func():
			if r.phase == "approach" and lent.is_empty():
				lent.append(r.pouch.pouch.map(func(d): return d.base)))
		r.start(Tales.load_tale("res://tales/strangers_throw.tale"), c, 77 + k)
		bt.play(r)
		check(r.phase == "ending", "prologue run %d reaches an ending" % k)
		check(not lent.is_empty() and lent[0].has("oak_might") and lent[0].has("dragon_d10") and not lent[0].has("jade_d8"), "the prologue is played with the stranger's Pouch")
		var after: Array = c.pouch.pouch.map(func(d): return d.id)
		for id in before:
			check(after.has(id), "your own Pouch comes back after the prologue (%s)" % id)
		check(not c.pouch.collection.any(func(d): return d.get("ally", false)), "the lent dice go back to the stranger")
		if r.state.ending == "found":
			eq(c.pouch.collection.size(), n_before + 1, "and you keep one gift die")
			check(c.pouch.collection.any(func(d): return String(d.base).begins_with("stranger_")), "a stranger's die")
	# The Teller's Mood and Story mode.
	var cm := Campaign.new()
	cm.new_campaign()
	var st := TaleState.new()
	Mood.start_tale(cm, st)
	eq([st.grit_max, st.fate], [20, 3], "at Fair, a tale starts with 20 Grit and 3 Fate")
	cm.mood = 4
	st = TaleState.new()
	Mood.start_tale(cm, st)
	eq([st.grit_max, st.fate], [16, 1], "at Bitter, 16 Grit and 1 Fate")
	eq(Mood.swaps(cm), 1, "and Waystones swap one die")
	check(Mood.foe(cm, Foes.foe("mire_wolf")).phases[0].dice.size() == 3, "foes throw an extra die")
	check(Foes.foe("mire_wolf").phases[0].dice.size() == 2, "without changing the foe itself")
	eq(Mood.opponent(cm, Foes.opponent("odile")).dice.size(), 3, "opponents too")
	cm.mood = 5
	eq(int(Mood.challenge_def(cm, {"kind": "test", "difficulty": "standard"}).target), Challenge.target_for("standard") + 2, "at Black, targets are 2 higher")
	eq(int(Mood.opponent(cm, Foes.opponent("odile")).resolve), 17, "and Resolve")
	cm.mood = 0
	cm.story_mode = true
	st = TaleState.new()
	Mood.start_tale(cm, st)
	eq(st.grit_max, 40, "Story mode doubles Grit")
	st.fate = 0
	st.defy_used = true
	check(Mood.can_defy(cm, st) and Mood.defy_cost(cm) == 0, "and Defy is always there, for free")
	eq(Mood.record_win(cm), "", "Story mode earns no felts")
	cm.story_mode = false
	cm.mood = 1
	check(Mood.record_win(cm) != "" and cm.mood_best == 1, "a win at a new Mood unlocks its felt")
	eq(Mood.max_choosable(cm), 2, "and the next level")
	var path := "user://test_mood.json"
	cm.felt = 1
	cm.save(path)
	var cm2 := Campaign.new()
	cm2.load_save(path)
	eq([cm2.mood, cm2.mood_best, cm2.felt, cm2.story_mode], [1, 1, 1, false], "the Mood survives a save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Harder Moods are harder: The Drowned Bell's non-defeat rate falls as the Mood rises.
	var rates := []
	for lvl in [0, 3, 5]:
		var wins := 0
		var n := 40
		for k in n:
			var c3 := Campaign.new()
			c3.new_campaign()
			c3.mood = lvl
			var r3 := Runner.new()
			var b3 := Bot.new()
			b3.rng.seed = 5000 + k
			r3.start(Tales.drowned_bell(), c3, 600 + k)
			b3.play(r3)
			if r3.state.ending != "drowned":
				wins += 1
		rates.append(wins * 100 / n)
	print("  Drowned Bell non-defeat at Mood 0/3/5: %s" % str(rates))
	report.append("The Teller's Mood, The Drowned Bell non-defeat at Mood 0 / 3 / 5: %d%% / %d%% / %d%%\n" % rates)
	check(rates[2] < rates[0], "Black is harder than Fair (%s)" % str(rates))
	# Offers: the prologue is offered first; Kettle turns up on night 3 or after The Drowned Bell's cove.
	var c2 := Campaign.new()
	c2.new_campaign()
	var ids: Array = Patrons.offers(c2).map(func(h): return h.id)
	check(ids.has("strangers_throw"), "a new campaign offers the prologue")
	check(not ids.has("long_con"), "Mother Kettle isn't in on the first night")
	Patrons.pass_nights(c2, 2)
	check(Patrons.offers(c2).map(func(h): return h.id).has("long_con"), "she is by night 3")
	c2.record_tale("long_con", "river", true)
	check(Patrons.offers(c2).map(func(h): return h.id).has("dukes_ledger"), "The Duke's Ledger follows The Long Con")
	c2.record_tale("dukes_ledger", "burned", true)
	check(not Patrons.offers(c2).map(func(h): return h.id).has("gilded_ruin"), "The Gilded Ruin waits for autumn")
	Patrons.pass_nights(c2, 12)
	check(Patrons.offers(c2).map(func(h): return h.id).has("gilded_ruin"), "and comes in autumn")


func _header(id: String) -> Dictionary:
	for h in Patrons.catalog():
		if h.id == id:
			return h
	return {}


## A whole year, played by bots: each night take a patron's tale (or see Maud, or wait), and check
## that every tale gets told, nothing gets stuck, and what happened in one tale changes the words of
## a later one (the M5 gate: choices in tale 1 visibly change tale 4).
func test_year() -> void:
	var years := maxi(10, runs / 6)
	var told := {}
	var endings := {}
	var openings := {}      # "tale <- earlier:ending" -> {opening text: true}
	var nights_used: Array = []
	var cat := Patrons.catalog()
	var stuck := 0
	for y in years:
		var c := Campaign.new()
		c.new_campaign()
		var rng := RandomNumberGenerator.new()
		rng.seed = 4243 + y * 101
		var arch: String = Bot.ARCHETYPES.keys()[y % Bot.ARCHETYPES.size()]
		var guard := 0
		while not c.year_over() and guard < 60:
			guard += 1
			if not c.wounds.is_empty() and rng.randf() < 0.6:
				var pay: bool = c.coin >= Patrons.heal_cost(c) and rng.randf() < 0.7
				Patrons.heal(c, pay, 0, cat)
				continue
			var offers := Patrons.offers(c, cat)
			if offers.is_empty():
				Patrons.pass_nights(c, Patrons.nights_to_next_season(c) if rng.randf() < 0.5 else 1, cat)
				continue
			var h: Dictionary = offers[rng.randi_range(0, offers.size() - 1)]
			var r := Runner.new()
			var bt := Bot.new()
			bt.rng.seed = y * 7907 + guard
			bt.archetype = arch
			var first := []
			r.said.connect(func(text, style):
				if first.size() < 12 and r.scene.get("id", "") == r.tale.start and style != "scene":
					first.append(text))
			r.start(Tales.load_tale(h.path), c, y * 31 + guard)
			bt.play(r)
			if r.phase != "ending":
				stuck += 1
				check(false, "year %d: %s stuck in %s at %s" % [y, h.id, r.phase, r.scene.get("id", "?")])
				break
			told[h.id] = told.get(h.id, 0) + 1
			var ek: String = "%s:%s" % [h.id, r.state.ending]
			endings[ek] = endings.get(ek, 0) + 1
			# Which earlier ending was this telling built on?
			var prev := {"bell_market": "drowned_bell", "tide_court": "drowned_bell", "pretender_road": "last_watch", "siege_holloway": "last_watch",
				"dukes_ledger": "long_con", "gilded_ruin": "long_con"}
			if prev.has(h.id):
				var key: String = "%s <- %s:%s" % [h.id, prev[h.id], c.ending_of(prev[h.id])]
				if not openings.has(h.id):
					openings[h.id] = {}
				if not openings[h.id].has(key):
					openings[h.id][key] = {}
				openings[h.id][key]["\n".join(first)] = true
			Patrons.pass_nights(c, 1, cat)
		nights_used.append(c.night)
		check(c.year_over(), "year %d runs to the end (night %d)" % [y, c.night])
	eq(stuck, 0, "no tale got stuck in a year of play")
	for h in cat:
		check(told.has(h.id), "%s is told in some year" % h.id)
	# The gate: the opening of a later tale reads differently depending on how an earlier one ended.
	for later in ["bell_market", "tide_court", "siege_holloway", "dukes_ledger", "gilded_ruin"]:
		var by_ending: Dictionary = openings.get(later, {})
		var texts := {}
		for k in by_ending:
			for t in by_ending[k]:
				texts[t] = true
		check(by_ending.size() >= 2, "%s is reached after different endings of the tale before (%s)" % [later, ", ".join(by_ending.keys())])
		check(texts.size() >= 2, "and its opening reads differently for them")
	report.append("## A year of play, by bots (%d years)\n" % years)
	report.append("| Tale | Told | Endings |")
	report.append("|---|---|---|")
	for h in cat:
		var es: Array = []
		for k in endings:
			if k.begins_with(h.id + ":"):
				es.append("%s %d" % [k.substr(h.id.length() + 1), endings[k]])
		report.append("| %s | %d | %s |" % [h.title, told.get(h.id, 0), ", ".join(es)])
		print("  %-16s told %3d  %s" % [h.id, told.get(h.id, 0), ", ".join(es)])
	report.append("")


## Every build archetype plays whole campaign years: the share of tales it brings home, and how
## often it finishes the campaign (The Teller's Tale, any ending but defeat). The M6 gate: every
## build within 10 points of the others. `--runs=` scales the years (60 runs: 5 years a build).
func test_builds() -> void:
	var years := maxi(5, runs / 12)
	var cat := Patrons.catalog()
	var rows := {}
	for arch in Bot.ARCHETYPES:
		var told := 0
		var won := 0
		var done := 0
		for y in years:
			var c := Campaign.new()
			c.new_campaign()
			var rng := RandomNumberGenerator.new()
			rng.seed = 7717 + y * 131
			var guard := 0
			while not c.year_over() and guard < 60:
				guard += 1
				if not c.wounds.is_empty() and c.coin >= Patrons.heal_cost(c):
					Patrons.heal(c, true, 0, cat)
					continue
				var offers := Patrons.offers(c, cat)
				if offers.is_empty():
					Patrons.pass_nights(c, 1, cat)
					continue
				# Take whatever runs out soonest, otherwise any offer.
				offers.sort_custom(func(a, b): return Patrons.offer_note(c, a).length() > Patrons.offer_note(c, b).length())
				var h: Dictionary = offers[0] if rng.randf() < 0.6 else offers[rng.randi_range(0, offers.size() - 1)]
				var r := Runner.new()
				var bt := Bot.new()
				bt.rng.seed = y * 9173 + guard * 7 + arch.length()
				bt.archetype = arch
				if h.id == "strangers_throw":
					bt.pack(c, arch)
				r.start(Tales.load_tale(h.path), c, y * 37 + guard)
				bt.play(r)
				check(r.phase == "ending", "%s year %d: %s reaches an ending" % [arch, y, h.id])
				told += 1
				if c.done(h.id) and c.ending_of(h.id) == r.state.ending:
					won += 1
				Patrons.pass_nights(c, 1, cat)
			if c.has_mark("campaign_done"):
				done += 1
		rows[arch] = [told, won, done]
	report.append("## Builds over whole campaign years (%d years each)\n" % years)
	report.append("| Build | Tales told | Brought home | Campaign finished |")
	report.append("|---|---|---|---|")
	var rates: Array = []
	for arch in rows:
		var v: Array = rows[arch]
		var rate: float = v[1] * 100.0 / maxf(1, v[0])
		rates.append(rate)
		report.append("| %s | %d | %d%% | %d of %d |" % [arch, v[0], roundi(rate), v[2], years])
		print("  %-9s told %3d, brought home %d%%, campaign finished %d of %d" % [arch, v[0], roundi(rate), v[2], years])
	report.append("")
	var spread: float = rates.max() - rates.min()
	check(spread <= 10.0, "every build brings home tales within 10 points of the others (spread %d)" % roundi(spread))


# ===================================================================== bots

## The practice table, played by the bot: every run reaches the end, nothing carries over between
## challenges, and the tier mix per kind of challenge goes in the report.
func test_practice() -> void:
	var by_type := {}
	var n := maxi(10, runs / 4)
	for k in n:
		var camp := Campaign.new()
		camp.new_campaign()
		var r := Runner.new()
		var bt := Bot.new()
		bt.rng.seed = k * 104729 + 3
		var fresh := [true]
		r.said.connect(func(text, style):
			if style.begins_with("tier_") and style != "tier_caught":
				var ty: String = "combat" if r.option.has("combat") else ("contest" if r.option.has("contest") else r.option.challenge.kind)
				if not by_type.has(ty):
					by_type[ty] = [0, 0, 0, 0]
				by_type[ty][["tier_fail", "tier_mixed", "tier_success", "tier_triumph"].find(style)] += 1)
		r.changed.connect(func():
			if r.phase == "choose" and r.scene.id.begins_with("c"):
				if r.state.grit != r.state.grit_max or r.state.fate != 3 or not r.state.wounds.is_empty() or r.pouch.fatigue != 0:
					fresh[0] = false)
		r.start(Practice.tale(), camp, k * 13 + 5)
		bt.play(r)
		check(r.phase == "ending" and r.state.ending == "practice", "practice run %d reaches the end (stuck in %s at %s)" % [k, r.phase, r.scene.get("id", "?")])
		check(fresh[0], "practice run %d starts every challenge whole" % k)
		check(r.state.visited.size() == 22, "practice run %d visits all 20 challenges (%d scenes)" % [k, r.state.visited.size()])
	report.append("## The practice table, played by the bot (%d runs)\n" % n)
	report.append("| Kind | Fail | Mixed | Success | Triumph |")
	report.append("|---|---|---|---|---|")
	for ty in by_type:
		var t: Array = by_type[ty]
		var tot := float(t[0] + t[1] + t[2] + t[3])
		report.append("| %s | %d%% | %d%% | %d%% | %d%% |" % [ty, roundi(t[0] / tot * 100), roundi(t[1] / tot * 100), roundi(t[2] / tot * 100), roundi(t[3] / tot * 100)])
		print("  %-8s F/M/S/T %s" % [ty, _pct(t.map(func(x): return x / tot))])
	report.append("")


func test_bots() -> void:
	report.append("## The Drowned Bell, played by bots (%d runs per Pouch, random choices)\n" % runs)
	report.append("| Pouch | Non-defeat | Endings | Grit at the climax (median) | Throws | Scenes | Tier mix |")
	report.append("|---|---|---|---|---|---|---|")
	var picks := {}
	var all_endings := {}
	var per_option := {}
	for arch in Bot.ARCHETYPES:
		var endings := {}
		var wins := 0
		var grits: Array = []
		var throws := 0
		var scenes := 0
		var tiers := [0, 0, 0, 0]
		for k in runs:
			var camp := Campaign.new()
			camp.new_campaign()
			var r := Runner.new()
			var bt := Bot.new()
			bt.rng.seed = k * 7919 + arch.length()
			bt.archetype = arch
			var climax_grit := [-1]
			r.said.connect(func(text, style):
				if style == "scene" and text == "The Bell Chamber":
					climax_grit[0] = r.state.grit
				if style.begins_with("tier_"):
					var key2: String = "%s.%s" % [r.scene.id, r.option.id]
					if not per_option.has(key2):
						per_option[key2] = [0, 0, 0, 0, 0]
					var ti := ["tier_fail", "tier_mixed", "tier_success", "tier_triumph", "tier_caught"].find(style)
					per_option[key2][ti] += 1
					if ti < 4:
						tiers[ti] += 1)
			r.start(Tales.drowned_bell(), camp, k * 31 + 1)
			var steps := bt.play(r)
			check(r.phase == "ending", "%s run %d reaches an ending (stuck in %s at %s after %d steps)" % [arch, k, r.phase, r.scene.get("id", "?"), steps])
			var e: String = r.state.ending
			endings[e] = endings.get(e, 0) + 1
			all_endings[e] = true
			if e != "drowned":
				wins += 1
			if climax_grit[0] >= 0:
				grits.append(climax_grit[0])
			throws += r.state.throws
			scenes += r.state.visited.size()
			for ch in r.state.choices:
				var key := "%s" % ch[0]
				if not picks.has(key):
					picks[key] = {}
				picks[key][ch[1]] = picks[key].get(ch[1], 0) + 1
		grits.sort()
		var med = grits[grits.size() / 2] if not grits.is_empty() else -1
		var ends: Array[String] = []
		for e in endings:
			ends.append("%s %d" % [e, endings[e]])
		var tt = tiers[0] + tiers[1] + tiers[2] + tiers[3]
		var mix := "/".join(tiers.map(func(x): return "%d" % roundi(x * 100.0 / maxi(1, tt))))
		report.append("| %s | %d%% | %s | %s | %.1f | %.1f | %s |" % [arch, roundi(wins * 100.0 / runs), ", ".join(ends), str(med), float(throws) / runs, float(scenes) / runs, mix])
		print("  %s: %d%% non-defeat, endings %s, median climax Grit %s, %.1f throws, tiers F/M/S/T %s" % [arch, roundi(wins * 100.0 / runs), str(endings), str(med), float(throws) / runs, mix])
	report.append("")
	for e in ["rest", "silence", "greed", "bargain", "drowned"]:
		if runs >= 40:
			check(all_endings.has(e), "ending %s is reached by some bot" % e)
	report.append("Every ending reached: %s\n" % ", ".join(all_endings.keys()))
	report.append("### Outcome tiers per challenge (all Pouches)\n")
	report.append("| Challenge | Plays | Fail | Mixed | Success | Triumph | Caught |")
	report.append("|---|---|---|---|---|---|---|")
	var keys := per_option.keys()
	keys.sort()
	for key in keys:
		var v: Array = per_option[key]
		var tot: int = v.reduce(func(a, b): return a + b, 0)
		report.append("| %s | %d | %s |" % [key, tot, " | ".join(v.map(func(x): return "%d%%" % roundi(x * 100.0 / tot)))])
		print("  %-22s %4d  F/M/S/T/C %s" % [key, tot, "/".join(v.map(func(x): return "%d" % roundi(x * 100.0 / tot)))])
	report.append("")
	report.append("Choices under random play are uniform by construction; real pick rates need playtest telemetry.\n")
