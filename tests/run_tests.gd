extends SceneTree
## Headless tests, the tale linter and the balance bots.
##
##   godot --headless -s res://tests/run_tests.gd                       unit tests + linter + quick bots
##   godot --headless -s res://tests/run_tests.gd -- --runs=400 --report=media/balance.md
##   options: --only=<suite>  (pouch, scoring, odds, combat, contest, challenges, lint, format, preview, save, practice, bots)
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
	var suites := ["pouch", "scoring", "odds", "combat", "contest", "challenges", "lint", "format", "preview", "save", "practice", "bots"]
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
		if r.state.wager != null:
			check(r2.state.wager != null and r2.pouch.collection.has(r2.state.wager), "resume %d keeps the wager as the same die" % k)
		var bt2 := Bot.new()
		bt2.rng.seed = 77 + k
		bt2.play(r2)
		eq(r2.phase, "ending", "resumed run %d plays on to an ending" % k)
	check(resumed >= 8, "most runs were saved and resumed mid-tale (%d)" % resumed)


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
