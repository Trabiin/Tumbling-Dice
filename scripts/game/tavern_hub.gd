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
const Patrons := preload("res://scripts/rules/patrons.gd")
const Mood := preload("res://scripts/rules/mood.gd")
const Tales := preload("res://scripts/rules/tales.gd")
const Mats := preload("res://scripts/materials.gd")

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
	var line := tr("Coin %d   ·   Rune shards: %s") % [g.campaign.coin, ", ".join(shards) if not shards.is_empty() else "none"]
	if not g.campaign.materials.is_empty():
		line += "   ·   Materials: " + Forge.materials_text(g.campaign)
	return line


func _calendar() -> String:
	var c = g.campaign
	var nxt: int = c.renown_to_next()
	var ren := tr("Renown %d (Pouch weight %d%s)") % [c.renown, c.pouch.weight_limit, (tr(", %d to the next") % nxt) if nxt > 0 else ""]
	var w := ("   ·   Wounds: " + ", ".join(c.wounds)) if not c.wounds.is_empty() else ""
	return "%s   ·   %s%s" % [c.calendar_text().capitalize(), ren, w]


## Tell what happened while the nights passed.
func _tell(lines: Array) -> void:
	for l in lines:
		g._on_said(l.text, l.style)


# ------------------------------------------------------------------ the room

func show_room() -> void:
	var c = g.campaign
	Mats.set_window_season(c.season())
	var offers: Array = Patrons.offers(c)
	if place == "":
		g.log_text.clear()
		g._on_said("The tavern", "scene")
		g._on_said(_room_text(offers), "teller")
		_tell(g.night_lines)
		g.night_lines = []
	place = "room"
	sel = null
	_clear_display()
	_shelf_display()
	g._set_view("room")
	_header("The tavern", c.calendar_text())
	var box: VBoxContainer = g.card_box
	box.add_child(UI.label(_calendar(), 14, UI.INK_SOFT))
	box.add_child(UI.label(_purse(), 13, UI.INK_SOFT))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	var snap: Dictionary = g._read_tale_save()
	if not snap.is_empty():
		var cb := UI.seal_button(tr("Continue the tale: %s") % snap.get("scene_title", ""), 16)
		cb.pressed.connect(func():
			close()
			g._continue_tale(snap))
		flow.add_child(cb)
	for h in offers:
		var who: Dictionary = Patrons.patron_of(h)
		var tb := UI.seal_button("%s: %s" % [who.get("place", ""), h.title], 16 if snap.is_empty() else 13)
		var note := Patrons.offer_note(c, h)
		tb.tooltip_text = String(h.pitch) + ("\n" + note if note != "" else "") + "\nA tale takes the night."
		tb.disabled = not snap.is_empty()
		var path: String = h.path
		tb.pressed.connect(func():
			close()
			g._begin_tale(path))
		flow.add_child(tb)
	var sb := UI.seal_button("Hollis's shelf", 14, Color("#2a5a6a"))
	sb.tooltip_text = "Your dice, on display behind the bar. Buy plain dice, sell the ones you don't need."
	sb.pressed.connect(show_shelf)
	flow.add_child(sb)
	var bb := UI.seal_button("Brannoc's bench", 14, Color("#2a5a6a"))
	bb.tooltip_text = "The Dicewright: recarve, inscribe, load, rebind, mend, melt."
	bb.pressed.connect(show_bench)
	flow.add_child(bb)
	var mb := UI.seal_button("Sister Maud's corner", 14, Color("#2a5a6a"))
	mb.tooltip_text = "The healer: she treats Wounds for Coin and a night, and knows a curse when she sees one."
	mb.pressed.connect(show_maud)
	flow.add_child(mb)
	var hb2 := UI.seal_button("The hearth: the Teller's Mood", 14, Color("#2a5a6a"))
	hb2.tooltip_text = "How kindly the Teller tells it: an optional challenge ladder, or Story mode. Table felts you have earned."
	hb2.pressed.connect(show_hearth)
	flow.add_child(hb2)
	var wn: int = Patrons.nights_to_next_season(c)
	var wb := UI.seal_button("Sit by the fire tonight", 13, Color("#5a4a3a"))
	wb.tooltip_text = "Let a night pass. Tales that are waiting may not wait for ever."
	wb.disabled = not snap.is_empty()
	wb.pressed.connect(func(): _pass(1))
	flow.add_child(wb)
	if wn > 1 and not c.year_over():
		var ws := UI.seal_button(tr("Wait for %s (%d nights)") % [Campaign_next_season(c), wn], 13, Color("#5a4a3a"))
		ws.disabled = not snap.is_empty()
		ws.tooltip_text = "Let the nights go by until the season turns."
		ws.pressed.connect(func(): _pass(wn))
		flow.add_child(ws)
	var cb2 := UI.seal_button("The Chronicle", 13, Color("#5a4a3a"))
	cb2.pressed.connect(func():
		close()
		g._show_chronicle())
	flow.add_child(cb2)
	var xb := UI.seal_button("Title", 13, Color("#5a4a3a"))
	xb.pressed.connect(func():
		close()
		g._show_title())
	flow.add_child(xb)


static func Campaign_next_season(c) -> String:
	return Patrons.Campaign.SEASONS[c.season_index() + 1] if c.season_index() < 3 else "the year's end"


func _pass(n: int) -> void:
	var lines := Patrons.pass_nights(g.campaign, n)
	g._on_said(tr("You sit by the fire while %s.") % ("the night goes by" if n == 1 else tr("%d nights go by") % n), "system")
	_tell(lines)
	_after_change()
	show_room()


## Who is in tonight, by the season and by what you have done.
func _room_text(offers: Array) -> String:
	var c = g.campaign
	var bits: Array[String] = []
	match c.season():
		"spring": bits.append("Rain on the shutters, and the first warm night of the year.")
		"summer": bits.append("The door's propped open to the summer night, and moths are at the lanterns.")
		"autumn": bits.append("Wind in the chimney, and wet cloaks steaming by the fire.")
		"winter": bits.append("Snow against the window, and the whole room crowded round the hearth.")
	if c.year_over():
		bits = ["The year has turned. The same fire, the same faces, older."]
	bits.append("Your dice wait on Hollis's shelf behind the bar, and old Brannoc squints at a half-carved die by the window.")
	var arcs := offers.map(func(h): return String(h.arc))
	for arc in Patrons.PATRONS:
		var p: Dictionary = Patrons.PATRONS[arc]
		if arcs.has(arc):
			for h in offers:
				if h.arc == arc:
					bits.append(String(h.pitch))
		elif (c.told("drowned_bell") or arc != "wren") and String(p.get("idle", "")) != "":
			bits.append(p.idle)
	if c.has_mark("marrowmere_flooded"):
		bits.append("A woman from Marrowmere sits nearest the fire, and won't look at you.")
	if c.ending_of("drowned_bell") == "rest":
		bits.append("Wren nods to you when you come in. She does that now.")
	if c.missed.has("siege_holloway") and c.told("pretender_road"):
		bits.append("Nobody sits at the captain's table any more.")
	return "[i]%s[/i]" % " ".join(bits)


# ------------------------------------------------------------------ the hearth: the Teller's Mood

func show_hearth() -> void:
	place = "hearth"
	g._set_view("room")
	_clear_display()
	_render_hearth()


func _render_hearth() -> void:
	var c = g.campaign
	_header("The hearth", "the Teller's Mood")
	var box: VBoxContainer = g.card_box
	box.add_child(UI.wrap_label("[i]How shall I tell them, then? Kindly, or the way they really went?[/i]", 15, UI.INK_SOFT, "italic"))
	var mood_now: int = Mood.level(c)
	box.add_child(UI.wrap_label(tr("Now: %s. %s") % ["Story mode" if Mood.story(c) else Mood.LEVELS[mood_now].name, "Grit doubled, and every Fail can be Defied for free." if Mood.story(c) else Mood.describe(mood_now)], 14, UI.INK))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	var locked_tale: bool = not g._read_tale_save().is_empty()
	for i in Mood.MAX_LEVEL + 1:
		var b := UI.seal_button("%d. %s" % [i, Mood.LEVELS[i].name], 13, Color("#6a1010") if i == mood_now and not Mood.story(c) else Color("#5a4a3a"))
		b.tooltip_text = Mood.describe(i) + ("" if i <= Mood.max_choosable(c) else "\nWin a tale at the level below first.")
		b.disabled = locked_tale or i > Mood.max_choosable(c)
		var lvl: int = i
		b.pressed.connect(func():
			c.mood = lvl
			c.story_mode = false
			_after_change()
			_render_hearth())
		flow.add_child(b)
	var sb := UI.seal_button(tr("Story mode: %s") % ("on" if Mood.story(c) else "off"), 13, Color("#2a5a6a"))
	sb.tooltip_text = "For the tales above all: Grit doubled, and a Fail can always be Defied into a Mixed for free. The dice and odds stay honest."
	sb.disabled = locked_tale
	sb.pressed.connect(func():
		c.story_mode = not c.story_mode
		if c.story_mode:
			c.mood = 0
		_after_change()
		_render_hearth())
	flow.add_child(sb)
	if locked_tale:
		box.add_child(UI.wrap_label("A tale is half told. Finish it before changing how it's told.", 13, UI.INK_SOFT, "italic"))
	box.add_child(UI.label("Table felts", 15, UI.INK))
	var ff := HFlowContainer.new()
	ff.add_theme_constant_override("h_separation", 6)
	box.add_child(ff)
	for i in Mood.FELTS.size():
		var fb := UI.seal_button(Mood.FELTS[i].name, 13, Mood.FELTS[i].color.lightened(0.15))
		fb.disabled = i > int(c.mood_best)
		fb.tooltip_text = "Yours." if i <= int(c.mood_best) else "Win a tale at the Teller's Mood %d (%s) to earn it." % [i, Mood.LEVELS[i].name]
		var fi: int = i
		fb.pressed.connect(func():
			c.felt = fi
			g.tavern.set_felt(Mood.FELTS[fi].color)
			_after_change()
			_render_hearth())
		ff.add_child(fb)
	_back_row(box)


# ------------------------------------------------------------------ Sister Maud's corner

func show_maud() -> void:
	place = "maud"
	g._set_view("room")
	_clear_display()
	_render_maud()


func _render_maud() -> void:
	var c = g.campaign
	_header("Sister Maud's corner", "the healer")
	var box: VBoxContainer = g.card_box
	box.add_child(UI.wrap_label(_calendar(), 14, UI.INK_SOFT))
	if c.wounds.is_empty():
		box.add_child(UI.wrap_label("Maud looks you up and down. \"Nothing wrong with you that sleep won't fix. Off you go.\"", 15, UI.INK_SOFT, "italic"))
	else:
		box.add_child(UI.wrap_label("Maud has you sit on the bench and pokes at you until you say ow. \"Which one first?\"", 15, UI.INK_SOFT, "italic"))
		for i in c.wounds.size():
			var w: String = c.wounds[i]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			box.add_child(row)
			var lab := UI.wrap_label("%s: %s" % [w, TaleStateWounds().get(w, "")], 14, UI.INK)
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lab)
			var cp := Patrons.can_heal(c, true)
			var pb := UI.seal_button(tr("Pay %d Coin (a night)") % Patrons.heal_cost(c), 13)
			pb.disabled = not cp.ok or not g._read_tale_save().is_empty()
			pb.tooltip_text = cp.text if not cp.ok else "Abbey standing makes her cheaper or dearer."
			var wi: int = i
			pb.pressed.connect(func(): _heal(true, wi))
			row.add_child(pb)
			var hb := UI.seal_button("Work it off (two nights)", 13, Color("#5a4a3a"))
			hb.disabled = not g._read_tale_save().is_empty()
			hb.pressed.connect(func(): _heal(false, wi))
			row.add_child(hb)
	for d in c.pouch.collection:
		if d.get("cursed", false):
			box.add_child(UI.wrap_label("%s: %s" % [d.name, Patrons.curse_advice(d)], 14, UI.INK, "italic"))
	_back_row(box)


static func TaleStateWounds() -> Dictionary:
	return load("res://scripts/rules/tale_state.gd").WOUNDS


func _heal(pay: bool, i: int) -> void:
	var r := Patrons.heal(g.campaign, pay, i)
	say(r.text)
	_tell(r.get("lines", []))
	_after_change()
	_render_maud()


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
		var info := UI.label(tr("%s: faces %s") % [sel.name, Dice.faces_text(sel)], 14, UI.INK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var c := Forge.can_sell(g.campaign, sel)
		var sb := UI.seal_button(tr("Sell for %d Coin") % Forge.sell_price(sel), 13)
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
	for item in Forge.stock(g.campaign):
		var proto := Dice.create(item.base)
		var b := UI.seal_button(tr("%s · %d Coin") % [proto.name.replace(" d6 of ", " d6, ").replace("Dwarven ", "").replace("Ancient ", ""), Forge.price(g.campaign, item)], 12, Color("#5a4a3a"))
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
	_gifts(box)
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
			var b := UI.seal_button(tr("Carve it %s (%d Coin)") % ["up 1" if delta > 0 else "down 1", Forge.RECARVE_COST], 13)
			b.disabled = not c.ok
			b.tooltip_text = c.text if not c.ok else tr("Faces may rise by %d in all (this die: %+d so far).") % [Forge.RECARVE_LIMIT, Forge.carved(sel)]
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
			var ib := UI.seal_button(tr("Inscribe %s (%d Coin + shard)") % [r.capitalize(), Forge.INSCRIBE_COST], 13, Color("#2a5a6a"))
			ib.disabled = not c2.ok
			ib.tooltip_text = c2.text if not c2.ok else Dice.RUNES[r]
			ib.pressed.connect(func():
				say(Forge.inscribe(g.campaign, sel, sel_face, r).text)
				_after_change()
				_render_bench())
			acts.add_child(ib)
		if runes.is_empty():
			acts.add_child(UI.label("No rune shards to inscribe with. Melting a rune die gives its shards.", 13, UI.INK_SOFT, "italic"))
		if g.campaign.material_count("lead") > 0 or g.campaign.trust >= Forge.LOAD_TRUST:
			var cl := Forge.can_load(g.campaign, sel, sel_face)
			var lb := UI.seal_button(tr("Load it to favour the %d (%d Coin + Lead)") % [int(sel.faces[sel_face].n), Forge.LOAD_COST], 13, Color("#5a2a4a"))
			lb.disabled = not cl.ok
			lb.tooltip_text = cl.text if not cl.ok else "It will land on that face about three times in four. Card sharps can spot a loaded die."
			lb.pressed.connect(func():
				say(Forge.load_die(g.campaign, sel, sel_face).text)
				_after_change()
				_render_bench())
			acts.add_child(lb)
	else:
		acts.add_child(UI.label("Pick a face to carve, inscribe or load.", 13, UI.INK_SOFT, "italic"))
	for asp in Dice.ASPECTS:
		if g.campaign.material_count("binding_" + asp) < 1 or asp == sel.aspect:
			continue
		var cr := Forge.can_rebind(g.campaign, sel, asp)
		var rb := UI.seal_button(tr("Rebind to %s (%d Coin + binding)") % [Dice.ASPECT_NAMES[asp], Forge.REBIND_COST], 13, Color("#2a5a6a"))
		rb.disabled = not cr.ok
		rb.tooltip_text = cr.text if not cr.ok else "Once in a die's life. It forgets half its notches."
		rb.pressed.connect(func():
			say(Forge.rebind(g.campaign, sel, asp).text)
			_after_change()
			_render_bench())
		acts.add_child(rb)
	if not Dice.cracked_faces(sel).is_empty():
		var cmn := Forge.can_mend(g.campaign, sel)
		var mnb := UI.seal_button(tr("Mend a cracked face (%d Coin)") % Forge.MEND_COST, 13, Color("#2a5a6a"))
		mnb.disabled = not cmn.ok
		mnb.tooltip_text = cmn.text
		mnb.pressed.connect(func():
			say(Forge.mend(g.campaign, sel).text)
			_after_change()
			_render_bench())
		acts.add_child(mnb)
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


## Rare materials can be given to Brannoc for his trust (Load needs 1, Rebind 2).
func _gifts(box: VBoxContainer) -> void:
	var rare: Array = g.campaign.materials.keys().filter(func(m): return Forge.is_rare(m))
	if rare.is_empty() and g.campaign.trust == 0:
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	row.add_child(UI.label(tr("Brannoc's trust: %d") % g.campaign.trust, 14, UI.INK))
	for m in rare:
		var gb := UI.seal_button(tr("Give him %s") % Forge.material_name(m), 13, Color("#5a4a3a"))
		gb.tooltip_text = Forge.MATERIALS[m].text + " Trust lets him Load (1) and Rebind (2) your dice."
		gb.pressed.connect(func():
			say(Forge.give(g.campaign, m).text)
			_after_change()
			_render_bench())
		row.add_child(gb)


func _after_change() -> void:
	g.campaign.save()
	g._refresh_status()
