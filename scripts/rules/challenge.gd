extends RefCounted
## A Test or a Trial: aspect slots with targets, an Effort limit, tries, and partial progress
## that carries between tries. Resolves into one of four tiers.
##
## Test:  one moment, usually one try.
## Trial: a longer effort against a Danger clock. Each try ticks the clock once; throwing your
##        full Effort (rushing) ticks it twice. When the clock fills, the trial ends.
## Last Stand: thrown with your whole Hand, every die counting in full.

const S := preload("res://scripts/rules/scoring.gd")

var kind := "test"
var title := ""
var slots: Array = []          # [{aspect, target, label}]
var progress: Array = []
var effort := 3
var tries_total := 1
var tries_used := 0
var danger_size := 0           # trials only
var danger := 0
var danger_text := ""
var triple_hit := false
var high_table_hit := false
var over := false
var throws: Array = []         # history of [{values, totals}]


## Difficulty as a share of what three on-aspect dice from a typical Pouch average (about 15).
## See the design doc, "Setting targets". Tuned with the balance report (tests/run_tests.gd).
const BASELINE := 15.0
const DIFFICULTY := {"easy": 0.6, "standard": 0.85, "hard": 1.1, "heroic": 1.4}


static func target_for(difficulty: String) -> int:
	return roundi(BASELINE * DIFFICULTY.get(difficulty, 0.85))


## def: {kind, title, difficulty | target, tries, effort, progress (trial), danger, danger_text,
##       second: {aspect, target}} ; aspect comes from the chosen approach.
static func create(def: Dictionary, aspect: String):
	var c = load("res://scripts/rules/challenge.gd").new()
	c.kind = def.get("kind", "test")
	c.title = def.get("title", "")
	c.effort = def.get("effort", 3)
	var target: int = def.get("target", def.get("progress", target_for(def.get("difficulty", "standard"))))
	c.slots = [{"aspect": aspect, "target": target, "label": def.get("label", "")}]
	if def.has("second"):
		c.slots.append({"aspect": def.second.aspect, "target": def.second.target, "label": def.second.get("label", "")})
	c.progress = []
	for s in c.slots:
		c.progress.append(0)
	if c.kind == "trial":
		c.danger_size = def.get("danger", 3)
		c.danger_text = def.get("danger_text", "")
		c.tries_total = 99
	else:
		c.tries_total = def.get("tries", 1)
	return c


static func last_stand(hand_size: int):
	var c = load("res://scripts/rules/challenge.gd").new()
	c.kind = "laststand"
	c.title = "Last Stand"
	c.effort = hand_size
	c.slots = [{"aspect": "any", "target": target_for("hard"), "label": "Stand"}]
	c.progress = [0]
	return c


## How many clock ticks a try with this many dice costs (trials only).
func ticks_for(n_dice: int) -> int:
	if kind != "trial":
		return 0
	return 2 if (n_dice >= effort and effort >= 3) else 1


func is_rushing(n_dice: int) -> bool:
	return kind == "trial" and ticks_for(n_dice) == 2


## Would a throw of n dice be the last one?
func is_final(n_dice: int) -> bool:
	if kind == "trial":
		return danger + ticks_for(n_dice) >= danger_size
	return tries_used + 1 >= tries_total


func tries_left() -> int:
	if kind == "trial":
		return danger_size - danger
	return tries_total - tries_used


func is_met() -> bool:
	for i in slots.size():
		if progress[i] < slots[i].target:
			return false
	return true


func ctx_kind() -> String:
	return "trial" if kind == "trial" else "test"


## Apply a settled, assigned throw. `best` is a result of S.best_assignment (or a manual
## assignment with the same keys). Returns a report for the narrator and the table.
func apply(ts: Array, ev: Dictionary, best: Dictionary) -> Dictionary:
	var before := progress.duplicate()
	for i in slots.size():
		progress[i] += best.totals[i]
	tries_used += 1
	danger += ticks_for(ts.size())
	if ev.combos.triple:
		triple_hit = true
	if ev.combos.high_table:
		high_table_hit = true
	throws.append({"values": ev.vals.duplicate(), "totals": best.totals.duplicate()})
	if high_table_hit or tries_left() <= 0:
		over = true
	return {
		"before": before,
		"after": progress.duplicate(),
		"met": is_met(),
		"over": over,
		"can_push": is_met() and not over,
		"danger_fired": kind == "trial" and danger >= danger_size and not is_met(),
	}


## The player takes what they have instead of pushing on.
func stop() -> void:
	over = true


func tier() -> int:
	return S.tier_of(progress, slots, high_table_hit, triple_hit)


func summary() -> String:
	var parts: Array[String] = []
	for i in slots.size():
		parts.append("%s %d/%d" % [slots[i].aspect, progress[i], slots[i].target])
	return ", ".join(parts)
