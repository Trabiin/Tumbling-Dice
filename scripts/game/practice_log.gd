extends RefCounted
## The practice table's notebook: for every throw, what was in the Hand, what the player picked,
## what a sensible player (the bot) would have picked, the odds of each, the player's own reason
## if they gave one, and how it turned out. Saved as JSON under user://playtests/ for the M2
## playtest gate, and summarised on screen at the end.

const Odds := preload("res://scripts/rules/odds.gd")
const S := preload("res://scripts/rules/scoring.gd")
const Dice := preload("res://scripts/rules/dice.gd")

const REASONS := ["Best odds", "Right aspect", "Saving dice", "Chasing a combo", "Hunch"]

var entries: Array = []
var started := ""


func _init() -> void:
	started = Time.get_datetime_string_from_system()


## How good a pick is for the throw ahead, as one comparable number (0 to 1) plus a readable line.
static func rate(runner, dice: Array, samples := 300) -> Dictionary:
	var a: Dictionary = runner.active
	var ctx: Dictionary = runner.throw_ctx()
	match a.type:
		"challenge", "laststand", "flee":
			var o := Odds.challenge_odds(a.run, dice, ctx, runner.pouch.hand, runner.pouch, samples)
			var good: float = o.tiers[2] + o.tiers[3]
			return {"value": good + o.tiers[1] * 0.5, "text": "Success or better %d%%" % roundi(good * 100)}
		"contest":
			var o := Odds.contest_round(a.run, dice, ctx, samples)
			return {"value": clampf(o["break"] + (1.0 - o.taken / 10.0) * 0.5 - o.caught, 0.0, 1.5) / 1.5,
				"text": "Break them %d%%, Nerve lost %.1f" % [roundi(o["break"] * 100), o.taken]}
		"combat":
			var o := Odds.combat_round(a.run, dice, ctx, runner.state.grit, samples)
			var resolve: float = maxf(1.0, a.run.resolve)
			return {"value": clampf(o.kill + o.dealt / resolve * 0.5 - o.taken / 20.0, 0.0, 1.5) / 1.5,
				"text": "Finish it %d%%, deal %.1f, take %.1f" % [roundi(o.kill * 100), o.dealt, o.taken]}
	return {"value": 0.0, "text": ""}


func record(runner, picked: Array, suggested: Array, reason: String, how: String) -> void:
	var a: Dictionary = runner.active
	var rp := rate(runner, picked)
	var same0: bool = picked.size() == suggested.size() and picked.all(func(d): return suggested.has(d))
	var rs := rp if same0 else rate(runner, suggested)
	var ids := func(arr): return arr.map(func(d): return d.id)
	var same: bool = picked.size() == suggested.size() and picked.all(func(d): return suggested.has(d))
	entries.append({
		"n": entries.size() + 1,
		"scene": runner.scene.id,
		"title": runner.scene.title,
		"type": a.type,
		"aspect": runner.approach.get("aspect", ""),
		"hand": runner.pouch.hand.map(func(d): return d.name),
		"picked": picked.map(func(d): return d.name),
		"suggested": suggested.map(func(d): return d.name),
		"picked_ids": ids.call(picked),
		"same_as_suggested": same,
		"odds_picked": rp.text,
		"odds_suggested": rs.text,
		"value_picked": snappedf(rp.value, 0.001),
		"value_suggested": snappedf(rs.value, 0.001),
		"reason": reason,
		"throw": how,
		"tier": "",
	})


## Write the outcome onto this scene's throws (a fight has several).
func settle(scene_id: String, tier: int) -> void:
	for e in entries:
		if e.scene == scene_id and e.tier == "":
			e.tier = S.TIER_NAMES[tier]


func summary() -> Dictionary:
	var n := entries.size()
	var same := 0
	var given_up := 0.0
	var better := 0
	var reasons := {}
	var tiers := {}
	var scenes := {}
	for e in entries:
		if e.same_as_suggested:
			same += 1
		var diff: float = e.value_suggested - e.value_picked
		given_up += maxf(0.0, diff)
		if diff < -0.02:
			better += 1
		var r: String = e.reason if e.reason != "" else "(none given)"
		reasons[r] = int(reasons.get(r, 0)) + 1
		if not scenes.has(e.scene):
			scenes[e.scene] = e.tier
	for sc in scenes:
		var t: String = scenes[sc] if scenes[sc] != "" else "?"
		tiers[t] = int(tiers.get(t, 0)) + 1
	return {"throws": n, "challenges": scenes.size(), "same": same, "better": better,
		"given_up": given_up / maxf(1, n), "reasons": reasons, "tiers": tiers}


func save() -> String:
	DirAccess.make_dir_recursive_absolute("user://playtests")
	var stamp := started.replace(":", "-")
	var path := "user://playtests/practice-%s.json" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({"started": started, "summary": summary(), "throws": entries}, "  "))
	return ProjectSettings.globalize_path(path)
