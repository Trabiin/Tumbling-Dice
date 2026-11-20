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
##   seen:drowned_before              a campaign Chronicle mark
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
	if a.begins_with("seen:"):
		var camp = ctx.get("campaign")
		return camp != null and camp.has_mark(a.substr(5))
	for op in OPS:
		var at := a.find(op)
		if at > 0:
			var lhs := a.substr(0, at).strip_edges()
			var rhs_s := a.substr(at + op.length()).strip_edges()
			if not rhs_s.is_valid_int():
				# String comparison: climax==freed
				var sv := str(state.flags.get(lhs, ""))
				return (sv == rhs_s) if op == "==" else (sv != rhs_s)
			var rhs := int(rhs_s)
			var v := 0
			if lhs.begins_with("temper:"):
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
	return bool(state.flag(a))


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
			if a in ["wounds", "fate", "grit"]:
				continue
			out.append(a)
	return out
