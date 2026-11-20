extends RefCounted
## The tavern between tales, kept minimal for M4: Wren's table (the tale), Hollis's shelf behind
## the bar (your dice on display; buy and sell), old Brannoc's bench (the Dicewright: recarve,
## inscribe, melt) and the hearth (the Chronicle). The camera moves between them; the card in
## front of you holds the choices and the Teller's parchment says what happened.
##
## The rules are in scripts/rules/forge.gd; this only shows them and turns clicks into calls.

const UI := preload("res://scripts/game/ui_kit.gd")
const Dice := preload("res://scripts/rules/dice.gd")
const Forge := preload("res://scripts/rules/forge.gd")
const Table := preload("res://scripts/game/table.gd")
const Die := preload("res://scripts/die.gd")
const Tavern := preload("res://scripts/tavern.gd")

var g                       # the game
var place := ""
var display: Array = []     # dice standing on the shelf or the bench
var sel = null              # the die picked at the shelf or the bench
var sel_face := -1


func _init(game) -> void:
	g = game


func say(text: String) -> void:
	g._on_said(text, "system")


func close() -> void:
	_clear_display()
	place = ""


func _clear_display() -> void:
	for n in display:
		if is_instance_valid(n):
			n.queue_free()
	display.clear()


func _show_die(d: Dictionary, pos: Vector3, rot_y := 0.0, scale := 1.0) -> Node3D:
	var n := Die.new()
	n.setup(Table.spec_for(d))
	n.freeze = true
	g.add_child(n)
	n.global_position = pos
	n.rotation = Vector3(0, rot_y, 0)
	n.scale = Vector3.ONE * scale
	display.append(n)
	return n


func _header(title: String, sub := "") -> void:
	g._card_clear()
	g.card.visible = true
	g._card_title(title, sub)


func _back_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var b := UI.seal_button("Back to the room", 13, Color("#5a4a3a"))
	b.pressed.connect(show_room)
	row.add_child(b)
	return row


func _purse() -> String:
	var shards: Array = g.campaign.shards
	return "Coin %d   ·   Rune shards: %s" % [g.campaign.coin, ", ".join(shards) if not shards.is_empty() else "none"]


# ------------------------------------------------------------------ the room

func show_room() -> void:
	if place == "":
		g.log_text.clear()
		g._on_said("The tavern", "scene")
		g._on_said("[i]The fire's low, the room's half full, and your dice wait on Hollis's shelf behind the bar. Old Brannoc is at his bench by the window, squinting at a half-carved d8. And at the corner table, a girl in an oilskin is waiting for somebody brave.[/i]", "teller")
	place = "room"
	sel = null
	_clear_display()
	_shelf_display()
	g._set_view("room")
	_header("The tavern", "between tales")
	var box: VBoxContainer = g.card_box
	box.add_child(UI.label(_purse(), 14, UI.INK_SOFT))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	var snap: Dictionary = g._read_tale_save()
	var tb := UI.seal_button("Wren's table: The Drowned Bell" if snap.is_empty() else "Wren's table: continue the tale", 16)
	tb.tooltip_text = "A fisherman's daughter, and a bell under the lake."
	tb.pressed.connect(func():
		close()
		if snap.is_empty():
			g._begin_tale()
		else:
			g._continue_tale(snap))
	flow.add_child(tb)
	var sb := UI.seal_button("Hollis's shelf", 14, Color("#2a5a6a"))
	sb.tooltip_text = "Your dice, on display behind the bar. Buy plain dice, sell the ones you don't need."
	sb.pressed.connect(show_shelf)
	flow.add_child(sb)
	var bb := UI.seal_button("Brannoc's bench", 14, Color("#2a5a6a"))
	bb.tooltip_text = "The Dicewright: recarve a face, inscribe a rune from a shard, melt a die for its shards."
	bb.pressed.connect(show_bench)
	flow.add_child(bb)
	var cb := UI.seal_button("The Chronicle", 13, Color("#5a4a3a"))
	cb.pressed.connect(func():
		close()
		g._show_chronicle())
	flow.add_child(cb)
	var xb := UI.seal_button("Title", 13, Color("#5a4a3a"))
	xb.pressed.connect(func():
		close()
		g._show_title())
	flow.add_child(xb)


## Your Collection stands on Hollis's lower shelf: two rows, best dice to the front.
func _shelf_display() -> void:
	var dice: Array = g.campaign.pouch.collection.duplicate()
	dice.sort_custom(func(a, b): return Dice.mean_n(a) > Dice.mean_n(b))
	var per_row := 10
	for i in mini(dice.size(), 20):
		var row := i / per_row
		var k := i % per_row
		var pos: Vector3 = Tavern.SHELF_TOP + Vector3(-22.5 + k * 5.0, 1.3, 2.0 - row * 4.5)
		_show_die(dice[i], pos, float(i) * 0.7, 1.15)


# ------------------------------------------------------------------ Hollis's shelf

func show_shelf() -> void:
	place = "shelf"
	g._set_view("shelf")
	_clear_display()
	_shelf_display()
	_render_shelf()


func _render_shelf() -> void:
	_header("Hollis's shelf", "your dice, behind the bar")
	var box: VBoxContainer = g.card_box
	box.add_child(UI.label(_purse(), 14, UI.INK_SOFT))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	box.add_child(flow)
	for d in g.campaign.pouch.collection:
		var t = UI.DieTile.new(d, 46.0)
		t.caption = UI.INK
		t.selected = sel == d
		t.dim = d.get("cursed", false)
		t.pressed.connect(func(tile):
			sel = tile.die
			_render_shelf())
		flow.add_child(t)
	if sel != null and g.campaign.pouch.collection.has(sel):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var info := UI.label("%s: faces %s" % [sel.name, Dice.faces_text(sel)], 14, UI.INK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var c := Forge.can_sell(g.campaign, sel)
		var sb := UI.seal_button("Sell for %d Coin" % Forge.sell_price(sel), 13)
		sb.disabled = not c.ok
		sb.tooltip_text = c.text
		sb.pressed.connect(func():
			var r := Forge.sell(g.campaign, sel)
			say(r.text)
			sel = null
			_after_change()
			show_shelf())
		row.add_child(sb)
	box.add_child(UI.label("Hollis has, behind the bar:", 14, UI.INK_SOFT))
	var stock := HFlowContainer.new()
	stock.add_theme_constant_override("h_separation", 6)
	box.add_child(stock)
	for item in Forge.STOCK:
		var proto := Dice.create(item.base)
		var b := UI.seal_button("%s · %d Coin" % [proto.name.replace(" d6 of ", " d6, ").replace("Dwarven ", "").replace("Ancient ", ""), item.price], 12, Color("#5a4a3a"))
		b.tooltip_text = Dice.tooltip(proto)
		b.disabled = not Forge.can_buy(g.campaign, item).ok
		b.pressed.connect(func():
			var r := Forge.buy(g.campaign, item)
			say(r.text)
			_after_change()
			show_shelf())
		stock.add_child(b)
	_back_row(box)


# ------------------------------------------------------------------ Brannoc's bench

func show_bench() -> void:
	place = "bench"
	g._set_view("bench")
	_render_bench()


func _render_bench() -> void:
	_clear_display()
	if sel != null and g.campaign.pouch.collection.has(sel):
		_show_die(sel, Tavern.BENCH_TOP + Vector3(0, 3.0, 3), 0.4, 2.6)
	_header("Brannoc's bench", "the Dicewright")
	var box: VBoxContainer = g.card_box
	box.add_child(UI.label(_purse(), 14, UI.INK_SOFT))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	box.add_child(flow)
	for d in g.campaign.pouch.collection:
		var t = UI.DieTile.new(d, 46.0)
		t.caption = UI.INK
		t.selected = sel == d
		t.dim = Forge.unworkable(d) != ""
		t.pressed.connect(func(tile):
			sel = tile.die
			sel_face = -1
			_render_bench())
		flow.add_child(t)
	if sel == null or not g.campaign.pouch.collection.has(sel):
		box.add_child(UI.wrap_label("Old Brannoc taps the bench. \"Put one down, then. Let's see what it's made of.\"", 15, UI.INK_SOFT, "italic"))
		_back_row(box)
		return
	var why := Forge.unworkable(sel)
	if why != "":
		box.add_child(UI.wrap_label(why, 15, UI.INK_SOFT, "italic"))
	# Faces of the chosen die.
	var faces := HFlowContainer.new()
	faces.add_theme_constant_override("h_separation", 4)
	box.add_child(faces)
	faces.add_child(UI.label("Faces: ", 14, UI.INK))
	for i in sel.faces.size():
		var f: Dictionary = sel.faces[i]
		var txt := "%d%s" % [int(f.n), Dice.RUNE_GLYPH.get(f.rune, "")]
		var fb := UI.card_button(txt, 14)
		fb.custom_minimum_size = Vector2(38, 30)
		fb.tooltip_text = Dice.RUNES.get(String(f.rune), "A plain face.")
		if i == sel_face:
			fb.modulate = Color(1.0, 0.8, 0.5)
		fb.pressed.connect(func():
			sel_face = i
			_render_bench())
		faces.add_child(fb)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 4)
	box.add_child(acts)
	if sel_face >= 0 and sel_face < sel.faces.size():
		for delta in [1, -1]:
			var c := Forge.can_recarve(g.campaign, sel, sel_face, delta)
			var b := UI.seal_button("Carve it %s (%d Coin)" % ["up 1" if delta > 0 else "down 1", Forge.RECARVE_COST], 13)
			b.disabled = not c.ok
			b.tooltip_text = c.text if not c.ok else "Faces may rise by %d in all (this die: %+d so far)." % [Forge.RECARVE_LIMIT, Forge.carved(sel)]
			b.pressed.connect(func():
				say(Forge.recarve(g.campaign, sel, sel_face, delta).text)
				_after_change()
				_render_bench())
			acts.add_child(b)
		var runes := {}
		for s in g.campaign.shards:
			if String(s).to_lower() in Forge.INSCRIBABLE:
				runes[String(s).to_lower()] = true
		for r in runes:
			var c2 := Forge.can_inscribe(g.campaign, sel, sel_face, r)
			var ib := UI.seal_button("Inscribe %s (%d Coin + shard)" % [r.capitalize(), Forge.INSCRIBE_COST], 13, Color("#2a5a6a"))
			ib.disabled = not c2.ok
			ib.tooltip_text = c2.text if not c2.ok else Dice.RUNES[r]
			ib.pressed.connect(func():
				say(Forge.inscribe(g.campaign, sel, sel_face, r).text)
				_after_change()
				_render_bench())
			acts.add_child(ib)
		if runes.is_empty():
			acts.add_child(UI.label("No rune shards to inscribe with. Melting a rune die gives its shards.", 13, UI.INK_SOFT, "italic"))
	else:
		acts.add_child(UI.label("Pick a face to carve or inscribe.", 13, UI.INK_SOFT, "italic"))
	var cm := Forge.can_melt(g.campaign, sel)
	var mb := UI.seal_button("Melt it down", 13, Color("#5a2a1a"))
	mb.disabled = not cm.ok
	mb.tooltip_text = cm.text if not cm.ok else "The die is destroyed with its history. You get a shard of each rune it carried, and a little Coin."
	mb.pressed.connect(func():
		say(Forge.melt(g.campaign, sel).text)
		sel = null
		sel_face = -1
		_after_change()
		_render_bench())
	acts.add_child(mb)
	_back_row(box)


func _after_change() -> void:
	g.campaign.save()
	g._refresh_status()
