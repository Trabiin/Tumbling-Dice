extends RefCounted
## Tiny condition language for tales, readable by a writer and checkable by the linter.
##
##   rumour_smugglers                 a flag is set (truthy)
##   villagers_saved>=2               numeric flag comparison (>=, <=, ==, >, <)
##   climax==freed                    string flag comparison
##   has:guile                        the Pouch holds a die of that aspect
##   mat:jade                         the Pouch holds a die of that material
##   temper:mercy>=2                  temperament track
##   wounds>=1                        Wound count
##   fallen                           you have taken Wounds enough to lose the tale
##   seen:drowned_before              a campaign Chronicle mark
##   rumour:tide_turn                 a Rumour you hold (from this tale or an earlier one)
##   told:drowned_bell                you have told that tale (any ending)
##   ended:drowned_bell               it ended without defeat
##   missed:siege_holloway            it went by without you
##   ending:drowned_bell==rest        how it ended (the last ending that was not a defeat)
##   standing:guild>=1                faction standing, -3 to 3 (guild, abbey, crown, holloway...)
##   season==winter, night>=7         the campaign calendar (night counts from 1 for the whole year)
##   renown>=5, trust>=1, coin>=40    Renown, Brannoc's trust, Coin in your purse
##   cursed, loaded                   you carry a cursed die / a loaded die
##   not X, X and Y, X or Y           ("and" binds tighter than "or"; no parentheses)

const OPS := [">=", "<=", "==", ">", "<"]


## ctx: {state: TaleState, pouch: Pouch, campaign: Campaign (optional)}
static func check(expr: String, ctx: Dictionary) -> bool:
	expr = expr.strip_edges()
	if expr == "" or expr == "true":
		return true
	for alt in expr.split(" or "):
		var ok := true
		for term in alt.split(" and "):
			if not _atom(term.strip_edges(), ctx):
				ok = false
				break
		if ok:
			return true
	return false


static func _atom(a: String, ctx: Dictionary) -> bool:
	if a.begins_with("not "):
		return not _atom(a.substr(4).strip_edges(), ctx)
	var state = ctx.get("state")
	var pouch = ctx.get("pouch")
	if a.begins_with("has:"):
		return pouch != null and pouch.has_aspect(a.substr(4))
	if a.begins_with("mat:"):
		return pouch != null and pouch.has_material(a.substr(4))
	var camp = ctx.get("campaign")
	if a.begins_with("seen:"):
		return camp != null and camp.has_mark(a.substr(5))
	if a.begins_with("rumour:"):
		var rid := a.substr(7)
		if state != null and state.get("rumour_ids") != null and state.rumour_ids.has(rid):
			return true
		return camp != null and camp.rumour_ids.has(rid)
	if a.begins_with("told:"):
		return camp != null and camp.told(a.substr(5))
	if a.begins_with("ended:"):
		return camp != null and camp.done(a.substr(6))
	if a.begins_with("missed:"):
		return camp != null and camp.missed.has(a.substr(7))
	if a == "fallen":
		return state != null and state.defeated()
	if a == "cursed":
		return pouch != null and pouch.pouch.any(func(d): return d.get("cursed", false))
	if a == "loaded":
		return pouch != null and pouch.pouch.any(func(d): return d.has("loaded_face"))
	for op in OPS:
		var at := a.find(op)
		if at > 0:
			var lhs := a.substr(0, at).strip_edges()
			var rhs_s := a.substr(at + op.length()).strip_edges()
			if not rhs_s.is_valid_int():
				# String comparison: climax==freed, season==winter, ending:drowned_bell==rest
				var sv := ""
				if lhs == "season":
					sv = camp.season() if camp != null else "spring"
				elif lhs.begins_with("ending:"):
					sv = camp.ending_of(lhs.substr(7)) if camp != null else ""
				elif state != null:
					sv = str(state.flags.get(lhs, ""))
				return (sv == rhs_s) if op == "==" else (sv != rhs_s)
			var rhs := int(rhs_s)
			var v := 0
			if lhs.begins_with("standing:"):
				v = camp.standing_of(lhs.substr(9)) if camp != null else 0
				if state != null:
					v += int(state.standing.get(camp.faction_name(lhs.substr(9)) if camp != null else lhs.substr(9), 0))
			elif lhs == "night":
				v = camp.night if camp != null else 1
			elif lhs == "renown":
				v = camp.renown if camp != null else 0
			elif lhs == "trust":
				v = camp.trust if camp != null else 0
			elif lhs == "coin":
				v = camp.coin if camp != null else 0
			elif state == null:
				v = 0
			elif lhs.begins_with("temper:"):
				v = int(state.temper.get(lhs.substr(7), 0))
			elif lhs == "wounds":
				v = state.wound_count()
			elif lhs == "fate":
				v = state.fate
			elif lhs == "grit":
				v = state.grit
			else:
				v = state.num(lhs)
			match op:
				">=": return v >= rhs
				"<=": return v <= rhs
				"==": return v == rhs
				">": return v > rhs
				"<": return v < rhs
	return state != null and bool(state.flag(a))


## Flag names an expression reads (for the linter).
static func flags_read(expr: String) -> Array:
	var out: Array = []
	for alt in expr.split(" or "):
		for term in alt.split(" and "):
			var a := term.strip_edges()
			if a.begins_with("not "):
				a = a.substr(4).strip_edges()
			if a == "" or a == "true" or a.contains(":"):
				continue
			for op in OPS:
				var at := a.find(op)
				if at > 0:
					a = a.substr(0, at).strip_edges()
					break
			if a in ["wounds", "fate", "grit", "season", "night", "renown", "trust", "cursed", "loaded", "coin", "fallen"]:
				continue
			out.append(a)
	return out
