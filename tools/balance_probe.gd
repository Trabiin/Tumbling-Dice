extends SceneTree
## Balance probe: the `builds` test loop for one build, with per-tale detail.
##   godot --headless -s res://tools/balance_probe.gd -- --arch=bruiser --years=10 [--mood=N] [--story] [--seed=0] [--stakes=all:2,drowned_bell:-1]
## Prints one JSON line: {arch, told, won, done, years, lost_by, wound_src,
##   tales: {id: [told, won, wounds taken, wounds carried in, fails, mixeds, successes, triumphs]}}
## Run the four builds side by side (4 cores):
##   for a in balanced bruiser sage swindler; do godot --headless -s res://tools/balance_probe.gd -- --arch=$a --years=30 & done; wait

const Campaign := preload("res://scripts/rules/campaign.gd")
const Runner := preload("res://scripts/rules/tale_runner.gd")
const Bot := preload("res://scripts/rules/bot.gd")
const Tales := preload("res://scripts/rules/tales.gd")
const Patrons := preload("res://scripts/rules/patrons.gd")


func _init() -> void:
	var arch := "balanced"
	var years := 10
	var mood := 0
	var story := false
	var seed0 := 0
	var over := {}     # --stakes=all:2,drowned_bell:-1 overrides the tales' stakes: headers
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--arch="): arch = a.substr(7)
		elif a.begins_with("--years="): years = int(a.substr(8))
		elif a.begins_with("--mood="): mood = int(a.substr(7))
		elif a == "--story": story = true
		elif a.begins_with("--seed="): seed0 = int(a.substr(7))
		elif a.begins_with("--stakes="):
			for kv in a.substr(9).split(",", false):
				over[kv.get_slice(":", 0)] = kv.get_slice(":", 1)
	var cat := Patrons.catalog()
	var told := 0
	var won := 0
	var done := 0
	var per := {}
	var lost_by := {}
	var wound_src := {}
	var grit_end: Array = []
	for y0 in years:
		var y := y0 + seed0
		var c := Campaign.new()
		c.new_campaign()
		c.mood = mood
		c.story_mode = story
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
			offers.sort_custom(func(a, b): return Patrons.offer_note(c, a).length() > Patrons.offer_note(c, b).length())
			var h: Dictionary = offers[0] if rng.randf() < 0.6 else offers[rng.randi_range(0, offers.size() - 1)]
			var r := Runner.new()
			var bt := Bot.new()
			bt.rng.seed = y * 9173 + guard * 7 + arch.length()
			bt.archetype = arch
			if h.id == "strangers_throw":
				bt.pack(c, arch)
			var tale: Dictionary = Tales.load_tale(h.path)
			if over.has(h.id):
				tale.stakes = over[h.id]
			elif over.has("all"):
				tale.stakes = str(int(over.all) + int(tale.get("stakes", "0")))
			r.start(tale, c, y * 37 + guard)
			var tiers := [0, 0, 0, 0]
			r.said.connect(func(_t, style):
				var ti := ["tier_fail", "tier_mixed", "tier_success", "tier_triumph"].find(style)
				if ti >= 0:
					tiers[ti] += 1
				if _t.begins_with("Wound:") and r.active.has("outer"):
					var src: String = String(r.active.outer.get("type", "scene")) if not r.active.outer.is_empty() else "scene"
					wound_src[src] = wound_src.get(src, 0) + 1)
			var w0: int = c.wounds.size()
			bt.play(r)
			told += 1
			var w := 0
			if c.done(h.id) and c.ending_of(h.id) == r.state.ending:
				won += 1
				w = 1
			if not per.has(h.id):
				per[h.id] = [0, 0, 0, 0, 0, 0, 0, 0]
			per[h.id][0] += 1
			per[h.id][1] += w
			if w == 0:
				var why: String = "fallen" if r.state.defeated() else ("flag" if r.state.flag("defeat") else "other:" + r.state.ending)
				lost_by[why] = lost_by.get(why, 0) + 1
			per[h.id][2] += r.state.wounds.size() - r.state.carried.size()
			per[h.id][3] += r.state.carried.size()
			for k in 4:
				per[h.id][4 + k] += tiers[k]
			Patrons.pass_nights(c, 1, cat)
		if c.has_mark("campaign_done"):
			done += 1
	print(JSON.stringify({"arch": arch, "told": told, "won": won, "done": done, "years": years, "tales": per, "lost_by": lost_by, "wound_src": wound_src}))
	quit(0)
