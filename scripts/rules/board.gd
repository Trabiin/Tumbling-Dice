extends RefCounted
## The tale board as data: which scenes are tiles, where they sit, which roads join them, and
## what each one looks like right now (inked, open, a road not taken, remembered, or in fog),
## plus the tokens your choices left on it. Pure code: the 3D board (scripts/game/tale_board.gd)
## only draws what this returns, and the tests check it headless.
##
## A scene is a tile when it has `tile: icon` in the .tale file; `at: x,y` places it (grid
## units, x to the right, y toward the player). A tale with no tiles at all gets one tile per
## scene, laid out by distance from the start. Tokens come from `token: condition => icon "label"`
## lines on a scene, and from the runner (state.marks), which leaves a fallen-foe token
## wherever a fight is won.

const Cond := preload("res://scripts/rules/conditions.gd")

## Tile looks. The writer picks one per scene; anything else falls back to "place".
const ICONS := ["inn", "village", "shore", "drowned", "jetty", "abbey", "cove", "camp", "dive", "chest",
	"shrine", "bell", "tower", "forest", "cave", "bridge", "place", "market", "keep", "road"]
## Token looks.
const TOKENS := ["chest", "coins", "grave", "lamp", "beacon", "flag", "knife", "rune", "boat", "footprints",
	"handbell", "candle", "broken_bell", "wave", "dove", "foe", "skull", "fire", "seal"]

## Tile and road states.
const VISITED := "visited"       # you were here: inked in full
const CURRENT := "current"       # where the figurine stands
const OPEN := "open"             # a road from where you stand, sketched faintly
const PASSED := "passed"         # a road you could have taken and didn't: stays faded
const REMEMBERED := "remembered" # walked in an earlier telling of this tale
const FOG := "fog"               # not yet known

const MIN_GAP := 0.9             # how close a road may pass to another tile, in grid units


## The static shape of a tale's board: tiles with positions, and the roads between them.
static func layout(tale: Dictionary) -> Dictionary:
	var scenes: Dictionary = tale.get("scenes", {})
	var ids: Array = []
	for id in scenes:
		if scenes[id].has("tile"):
			ids.append(id)
	var auto := ids.is_empty()
	if auto:
		for id in scenes:
			var t: String = scenes[id].get("type", "choice")
			if t != "ending" and t != "prepare":
				ids.append(id)
	var on_board := {}
	for id in ids:
		on_board[id] = true
	# Roads: follow every goto, passing through scenes that are not tiles.
	var roads: Array = []
	var seen_pair := {}
	for a in ids:
		for b in _reach(scenes, a, on_board):
			var key: String = a + ">" + b if a < b else b + ">" + a
			if a == b or seen_pair.has(key):
				continue
			seen_pair[key] = true
			roads.append({"a": a, "b": b})
	# Positions: from at:, or by distance from the start.
	var pos := {}
	var depth := _depths(tale, ids, roads)
	var columns := {}
	for id in ids:
		var at: Variant = scenes[id].get("at", null)
		if at is Vector2:
			pos[id] = at
		else:
			var d: int = depth.get(id, 0)
			if not columns.has(d):
				columns[d] = []
			columns[d].append(id)
	for d in columns:
		var col: Array = columns[d]
		for k in col.size():
			pos[col[k]] = Vector2(d, (k - (col.size() - 1) / 2.0) * 1.3)
	var tiles: Array = []
	for id in ids:
		var icon: String = scenes[id].get("tile", "place")
		if not icon in ICONS:
			icon = "place"
		tiles.append({"id": id, "icon": icon, "pos": pos[id], "title": scenes[id].get("title", id),
			"act": int(scenes[id].get("act", 1))})
	for r in roads:
		r.bend = _bend(pos[r.a], pos[r.b], pos, [r.a, r.b])
	var bounds := Rect2(pos[ids[0]], Vector2.ZERO) if not ids.is_empty() else Rect2()
	for id in ids:
		bounds = bounds.expand(pos[id])
	var out := {"tiles": tiles, "roads": roads, "pos": pos, "bounds": bounds, "auto": auto,
		"start": _first_tile(tale, on_board, scenes)}
	return out


## The board as it stands: the layout, plus each tile's and road's state, the figurine's path
## and the tokens to show. memory: scene ids walked in earlier tellings (campaign.map_memory).
static func view(tale: Dictionary, state, memory: Array = [], ctx := {}) -> Dictionary:
	var lay := layout(tale)
	var on_board: Dictionary = lay.pos
	# The figurine's path: visited scenes that are tiles, in order, without repeats in a row.
	var path: Array = []
	for id in state.visited:
		if on_board.has(id) and (path.is_empty() or path[-1] != id):
			path.append(id)
	if path.is_empty() and lay.start != "":
		path.append(lay.start)
	var here: String = path[-1] if not path.is_empty() else ""
	var visited := {}
	for id in path:
		visited[id] = true
	var walked := {}
	for k in range(1, path.size()):
		walked[_key(path[k - 1], path[k])] = true
	var remembered := {}
	for id in memory:
		remembered[id] = true
	var tile_state := {}
	for t in lay.tiles:
		tile_state[t.id] = CURRENT if t.id == here else (VISITED if visited.has(t.id) else (REMEMBERED if remembered.has(t.id) else FOG))
	var road_state := {}
	for r in lay.roads:
		var k := _key(r.a, r.b)
		var s := FOG
		if walked.has(k):
			s = VISITED
		elif r.a == here or r.b == here:
			s = OPEN
		elif visited.has(r.a) or visited.has(r.b):
			s = PASSED
		elif remembered.has(r.a) and remembered.has(r.b):
			s = REMEMBERED
		road_state[k] = s
		# The far end of an open or passed road is sketched, not fogged.
		for end in [r.a, r.b]:
			if tile_state[end] == FOG:
				if s == OPEN:
					tile_state[end] = OPEN
				elif s == PASSED:
					tile_state[end] = PASSED
	if ctx.is_empty():
		ctx = {"state": state}
	var tokens: Array = []
	for t in lay.tiles:
		for tok in tale.scenes[t.id].get("tokens", []):
			if tile_state[t.id] == FOG:
				continue
			if Cond.check(tok.cond, ctx):
				tokens.append({"scene": t.id, "icon": tok.icon, "label": tok.label})
	for m in state.marks:
		if on_board.has(m.get("scene", "")):
			tokens.append(m)
	return {"layout": lay, "tiles": tile_state, "roads": road_state, "path": path, "here": here, "tokens": tokens}


static func road_key(a: String, b: String) -> String:
	return _key(a, b)


static func _key(a: String, b: String) -> String:
	return a + ">" + b if a < b else b + ">" + a


## Board scenes reachable from scene a by gotos that pass only through non-board scenes.
static func _reach(scenes: Dictionary, a: String, on_board: Dictionary) -> Array:
	var out: Array = []
	var stack: Array = _gotos(scenes.get(a, {}))
	var seen := {a: true}
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id) or not scenes.has(id):
			continue
		seen[id] = true
		if on_board.has(id):
			out.append(id)
		else:
			stack.append_array(_gotos(scenes[id]))
	return out


static func _gotos(scene: Dictionary) -> Array:
	var out: Array = []
	if scene.has("goto"):
		out.append(scene.goto)
	for o in scene.get("options", []):
		if o.has("goto"):
			out.append(o.goto)
		for tier in o.get("outcomes", {}):
			var oc: Dictionary = o.outcomes[tier]
			if oc.has("goto"):
				out.append(oc.goto)
	return out


static func _first_tile(tale: Dictionary, on_board: Dictionary, scenes: Dictionary) -> String:
	var start: String = tale.get("start", "")
	if on_board.has(start):
		return start
	var r := _reach(scenes, start, on_board)
	return r[0] if not r.is_empty() else ""


static func _depths(tale: Dictionary, ids: Array, roads: Array) -> Dictionary:
	var scenes: Dictionary = tale.get("scenes", {})
	var on_board := {}
	for id in ids:
		on_board[id] = true
	var depth := {}
	var first := _first_tile(tale, on_board, scenes)
	if first == "":
		return depth
	depth[first] = 0
	var queue: Array = [first]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for b in _reach(scenes, id, on_board):
			if not depth.has(b):
				depth[b] = depth[id] + 1
				queue.append(b)
	return depth


## How far a road bows sideways (grid units) so it does not run through another tile. 0 is
## straight; the sign picks the side.
static func _bend(a: Vector2, b: Vector2, pos: Dictionary, skip: Array) -> float:
	for amount in [0.0, 0.8, -0.8, 1.4, -1.4, 2.0, -2.0, 2.8, -2.8]:
		var clear := true
		for id in pos:
			if id in skip:
				continue
			if _dist_to_curve(pos[id], a, b, amount) < MIN_GAP:
				clear = false
				break
		if clear:
			return amount
	return 0.0


## A point along a road: a quadratic curve bowed sideways by bend.
static func road_point(a: Vector2, b: Vector2, bend: float, t: float) -> Vector2:
	var mid := (a + b) * 0.5
	var d := b - a
	var n := Vector2(-d.y, d.x).normalized() if d.length() > 0.001 else Vector2.ZERO
	var c := mid + n * bend * 2.0   # control point (the curve reaches half of it)
	var u := 1.0 - t
	return a * u * u + c * 2.0 * u * t + b * t * t


static func _dist_to_curve(p: Vector2, a: Vector2, b: Vector2, bend: float) -> float:
	var best := INF
	for i in range(2, 19):
		best = minf(best, p.distance_to(road_point(a, b, bend, i / 20.0)))
	return best
