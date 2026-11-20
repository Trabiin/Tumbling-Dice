extends Node3D
## The playable table: The Drowned Bell, staged in the tavern. The rules (TaleRunner) decide
## everything; this script only presents what they decide and turns clicks into their calls.
##
## Controls: click the cards and dice. Space throws, Enter confirms or continues,
##           F toggles fast dice (no physics, same odds), Esc quits.
## Command line (after `--`):
##   --new           start a new campaign instead of loading the save
##   --fast          fast dice from the start
##   --seed=<n>      repeatable tale and throws
##   --autoplay      a bot plays through the real UI (physics dice and all); for testing
##   --shots=<dir>   save a screenshot whenever the table changes (needs a renderer)
##   --max-shots=<n> stop after n screenshots (default 40)
##   --quit-at-end   quit when the tale ends
##   --practice      with --autoplay: play the practice table instead of the tale
##   --drag          with --autoplay: throw by simulated mouse drags instead of the button

const Tavern := preload("res://scripts/tavern.gd")
const Table := preload("res://scripts/game/table.gd")
const UI := preload("res://scripts/game/ui_kit.gd")
const Dice := preload("res://scripts/rules/dice.gd")
const S := preload("res://scripts/rules/scoring.gd")
const Runner := preload("res://scripts/rules/tale_runner.gd")
const Campaign := preload("res://scripts/rules/campaign.gd")
const Tale := preload("res://scripts/tale/drowned_bell.gd")
const Practice := preload("res://scripts/tale/practice.gd")
const PracticeLog := preload("res://scripts/game/practice_log.gd")
const Odds := preload("res://scripts/rules/odds.gd")
const Combat := preload("res://scripts/rules/combat.gd")
const Contest := preload("res://scripts/rules/contest.gd")
const Bot := preload("res://scripts/rules/bot.gd")
const Pouch := preload("res://scripts/rules/pouch.gd")
const TaleState := preload("res://scripts/rules/tale_state.gd")

const PANEL_W := 392.0
const CARD_W := 856.0

var tavern: Node3D
var camera: Camera3D
var table: Node3D
var campaign
var runner
var rng := RandomNumberGenerator.new()
var fast_dice := false
var busy := false
var phase_serial := 0

# UI
var layer: CanvasLayer
var status_box: VBoxContainer
var grit_bar: ProgressBar
var grit_label: Label
var fate_pips
var info_label: Label
var log_text: RichTextLabel
var card: PanelContainer
var card_box: VBoxContainer
var hand_panel: PanelContainer
var hand_row: HBoxContainer
var hand_info: Label
var banner: Label
var overlay: Control
var fast_toggle: CheckButton
var _type_tween: Tween

# A throw in progress
var selected: Array = []
var results: Array = []        # physical results, parallel to runner.thrown
var pending: Array = []        # thrown dice being settled (cocked / echo) before submitting
var assign_arr: Array = []
var read_mode := "expose"
var sel_chip := -1
var odds_widget: Control
var odds_text: Label

# Testing
var opt_autoplay := false
var opt_shots := ""
var opt_max_shots := 40
var opt_quit_at_end := false
var opt_new := false
var opt_practice := false
var opt_drag := false
var opt_seed := -1
var shots_taken := 0
var bot = Bot.new()

# practice table
var practice = null              # PracticeLog while at the practice table
var practice_reason := ""
var home_campaign = null         # the real campaign, set aside during practice


func _ready() -> void:
	_parse_args()
	tavern = Tavern.new()
	add_child(tavern)
	camera = Camera3D.new()
	add_child(camera)
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 75.0
	attr.dof_blur_far_transition = 90.0
	attr.dof_blur_amount = 0.05
	camera.attributes = attr
	_frame_camera()
	table = Table.new()
	table.tavern = tavern
	table.font = UI.font("ui")
	add_child(table)
	if opt_seed >= 0:
		rng.seed = opt_seed
		table.rng.seed = opt_seed + 3
		bot.rng.seed = opt_seed + 5
	else:
		rng.randomize()
		table.rng.randomize()
	campaign = Campaign.new()
	if opt_new or not campaign.load_save():
		campaign.new_campaign()
	_build_ui()
	_show_title()
	if opt_autoplay:
		await _wait(10)
		if opt_practice:
			_begin_practice()
		else:
			_begin_tale()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--fast": fast_dice = true
		elif a == "--new": opt_new = true
		elif a == "--autoplay": opt_autoplay = true
		elif a == "--practice": opt_practice = true
		elif a == "--drag": opt_drag = true
		elif a == "--quit-at-end": opt_quit_at_end = true
		elif a.begins_with("--shots="): opt_shots = a.substr(8)
		elif a.begins_with("--max-shots="): opt_max_shots = int(a.substr(12))
		elif a.begins_with("--seed="): opt_seed = int(a.substr(7))
	if opt_shots != "":
		DirAccess.make_dir_recursive_absolute(opt_shots)


# ===================================================================== camera

var _cam_rest := Transform3D()
var _breath := 0.0


func _frame_camera() -> void:
	# The tray sits in the upper left, clear of the Teller's parchment and the cards.
	camera.fov = 52
	camera.position = Vector3(7.0, 21.0, 21.0)
	camera.look_at(Vector3(5.6, -5.0, 1.5))
	_cam_rest = camera.transform


func _process(delta: float) -> void:
	_breath += delta
	var off := Vector3(sin(_breath * 0.37) * 0.12, sin(_breath * 0.29 + 1.0) * 0.07, sin(_breath * 0.21) * 0.08)
	camera.transform = _cam_rest.translated(off).rotated_local(Vector3.FORWARD, sin(_breath * 0.17) * 0.003)
	_process_hold(delta)


# ===================================================================== layout

func _build_ui() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# --- status, top left
	var sp := UI.panel(Color(0.12, 0.07, 0.04, 0.78), 10)
	sp.position = Vector2(12, 12)
	sp.add_theme_stylebox_override("panel", UI.paper_box(Color(0.12, 0.07, 0.04, 0.8), Color("#8a5a2a"), 8, 10))
	root.add_child(sp)
	status_box = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	sp.add_child(status_box)
	var grow := HBoxContainer.new()
	status_box.add_child(grow)
	grit_label = UI.label("Grit 20/20", 14, Color("#f4e4c0"))
	grit_label.custom_minimum_size.x = 92
	grow.add_child(grit_label)
	grit_bar = ProgressBar.new()
	grit_bar.custom_minimum_size = Vector2(150, 14)
	grit_bar.show_percentage = false
	var gb := StyleBoxFlat.new()
	gb.bg_color = Color("#2a1608")
	gb.set_corner_radius_all(3)
	var gf := StyleBoxFlat.new()
	gf.bg_color = Color("#c8462a")
	gf.set_corner_radius_all(3)
	grit_bar.add_theme_stylebox_override("background", gb)
	grit_bar.add_theme_stylebox_override("fill", gf)
	grit_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grow.add_child(grit_bar)
	var frow := HBoxContainer.new()
	status_box.add_child(frow)
	var fl := UI.label("Fate", 14, Color("#f4e4c0"))
	fl.custom_minimum_size.x = 92
	frow.add_child(fl)
	fate_pips = UI.Pips.new(Color("#e8b830"), 7.0)
	frow.add_child(fate_pips)
	info_label = UI.label("", 12, Color("#d8c49a"))
	status_box.add_child(info_label)

	# --- the Teller's parchment, right
	var pp := PanelContainer.new()
	pp.add_theme_stylebox_override("panel", UI.paper_box(UI.PAPER, UI.EDGE, 6, 16))
	pp.anchor_left = 1.0
	pp.anchor_right = 1.0
	pp.anchor_bottom = 1.0
	pp.offset_left = -PANEL_W - 12
	pp.offset_right = -12
	pp.offset_top = 12
	pp.offset_bottom = -12
	root.add_child(pp)
	var pv := VBoxContainer.new()
	pp.add_child(pv)
	var head := HBoxContainer.new()
	pv.add_child(head)
	var tl := UI.label("The Teller", 18, Color("#6a1010"), "title")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	fast_toggle = CheckButton.new()
	fast_toggle.text = "Fast dice"
	fast_toggle.add_theme_font_override("font", UI.font("ui"))
	fast_toggle.add_theme_font_size_override("font_size", 11)
	fast_toggle.add_theme_color_override("font_color", UI.INK_SOFT)
	fast_toggle.add_theme_color_override("font_hover_color", UI.INK)
	fast_toggle.add_theme_color_override("font_pressed_color", UI.INK)
	fast_toggle.tooltip_text = "Skip the physics and show results at once. The odds are identical: results come from each die's measured faces."
	fast_toggle.button_pressed = fast_dice
	fast_toggle.toggled.connect(func(on): fast_dice = on)
	fast_toggle.focus_mode = Control.FOCUS_NONE
	head.add_child(fast_toggle)
	pv.add_child(UI.rule())
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_override("normal_font", UI.font("body"))
	log_text.add_theme_font_override("italics_font", UI.font("italic"))
	log_text.add_theme_font_override("bold_font", UI.font("ui"))
	log_text.add_theme_font_override("bold_italics_font", UI.font("italic"))
	log_text.add_theme_font_size_override("normal_font_size", 17)
	log_text.add_theme_font_size_override("italics_font_size", 17)
	log_text.add_theme_font_size_override("bold_font_size", 14)
	log_text.add_theme_color_override("default_color", UI.INK)
	log_text.add_theme_constant_override("line_separation", 2)
	log_text.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_skip_typing())
	pv.add_child(log_text)

	# --- hand, bottom left
	hand_panel = PanelContainer.new()
	hand_panel.add_theme_stylebox_override("panel", UI.paper_box(Color(0.12, 0.07, 0.04, 0.82), Color("#8a5a2a"), 8, 8))
	hand_panel.anchor_top = 1.0
	hand_panel.anchor_bottom = 1.0
	hand_panel.offset_left = 12
	hand_panel.offset_right = 12 + CARD_W
	hand_panel.offset_top = -118
	hand_panel.offset_bottom = -12
	root.add_child(hand_panel)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 10)
	hand_panel.add_child(hh)
	var hv := VBoxContainer.new()
	hv.custom_minimum_size.x = 96
	hh.add_child(hv)
	hv.add_child(UI.label("Hand", 16, Color("#f2c75c")))
	hand_info = UI.label("", 11, Color("#d8c49a"))
	hand_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	hand_info.custom_minimum_size.x = 96
	hv.add_child(hand_info)
	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 8)
	hh.add_child(hand_row)

	# --- the card in front of the tray
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.paper_box(UI.PAPER, UI.EDGE, 6, 12))
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = 12
	card.offset_right = 12 + CARD_W
	card.offset_bottom = -126
	card.offset_top = -126
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(card)
	card_box = VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 6)
	card.add_child(card_box)

	banner = UI.label("", 60, UI.GOLD, "title")
	banner.add_theme_color_override("font_outline_color", Color("#1a0a02"))
	banner.add_theme_constant_override("outline_size", 16)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector2(12, 120)
	banner.size = Vector2(CARD_W, 90)
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	_refresh_status()


func _card_clear() -> void:
	UI.clear(card_box)
	card.visible = true
	odds_widget = null
	odds_text = null


func _card_title(text: String, sub := "") -> void:
	var row := HBoxContainer.new()
	card_box.add_child(row)
	var t := UI.label(text, 19, Color("#6a1010"), "title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	if sub != "":
		row.add_child(UI.label(sub, 13, UI.INK_SOFT))


func _show_banner(text: String, color: Color) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(banner, "modulate:a", 0.0, 0.6)


# ===================================================================== status

func _refresh_status() -> void:
	if runner == null or runner.state == null:
		grit_label.text = "Grit -"
		grit_bar.max_value = 20
		grit_bar.value = 20
		fate_pips.set_count(0, TaleState.FATE_CAP)
		info_label.text = "Coin %d" % campaign.coin
		return
	var st = runner.state
	grit_label.text = "Grit %d/%d" % [maxi(0, st.grit), st.grit_max]
	grit_bar.max_value = st.grit_max
	grit_bar.value = maxi(0, st.grit)
	fate_pips.set_count(st.fate, TaleState.FATE_CAP)
	var bits: Array[String] = []
	bits.append("Coin %d" % campaign.coin)
	var p = runner.pouch
	bits.append("Fatigue %d" % p.fatigue)
	if not st.wounds.is_empty():
		bits.append("Wounds: " + ", ".join(st.wounds))
	if st.pity():
		bits.append("The Teller's pity: +1")
	info_label.text = "   ".join(bits)
	info_label.tooltip_text = "\n".join(st.wounds.map(func(w): return "%s: %s" % [w, TaleState.WOUNDS.get(w, "")]))


func _refresh_hand(selectable: bool) -> void:
	UI.clear(hand_row)
	if runner == null:
		hand_info.text = ""
		return
	var p = runner.pouch
	for d in p.hand:
		var tile = UI.DieTile.new(d, 66.0)
		tile.selected = selected.has(d)
		tile.dim = not selectable and runner.phase != "approach"
		if selectable:
			tile.pressed.connect(_toggle_die)
		hand_row.add_child(tile)
	hand_info.text = "Pouch %d\nDiscard %d\nHand size %d" % [p.draw_pile.size(), p.discard.size(), p.hand_size()]
	if p.hand.is_empty():
		var l := UI.label("Your Hand is drawn from the Pouch when a challenge begins.", 13, Color("#a8946a"), "italic")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hand_row.add_child(l)


# ===================================================================== the Teller's parchment

func _on_said(raw_text: String, style: String) -> void:
	var text := UI.smart_quotes(raw_text)
	var t := text
	match style:
		"title": t = "[center][font_size=24][color=#6a1010]%s[/color][/font_size][/center]" % text
		"scene": t = "\n[center][b][color=#6a1010]%s[/color][/b][/center]" % text.to_upper()
		"teller": t = "[i][color=#5a3a1c]%s[/color][/i]" % text
		"choice": t = "[color=#8a1e14]» %s[/color]" % text
		"result": t = "[b][color=#3a2210]%s[/color][/b]" % text
		"system": t = "[font_size=14][color=#6a5a40]%s[/color][/font_size]" % text
		"foe": t = "[color=#8a2a1a]%s[/color]" % text
		"gain": t = "[color=#2a6a2a][b]%s[/b][/color]" % text
		"ending": t = "\n[center][font_size=26][color=#6a1010]%s[/color][/font_size][/center]" % text
		_:
			if style.begins_with("tier_"):
				var key := style.substr(5)
				var idx := ["fail", "mixed", "success", "triumph", "caught"].find(key)
				var col: Color = S.TIER_COLORS[mini(idx, 3)] if idx < 4 else Color("#8a1010")
				t = "[center][font_size=22][color=#%s]— %s —[/color][/font_size][/center]" % [col.darkened(0.25).to_html(false), text]
				_show_banner(text, col)
	var before := log_text.get_total_character_count()
	log_text.append_text(t + "\n")
	_type_from(before)


func _type_from(start: int) -> void:
	var total := log_text.get_total_character_count()
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
		start = mini(start, log_text.visible_characters if log_text.visible_characters >= 0 else start)
	log_text.visible_characters = start
	var secs := clampf((total - start) / 90.0, 0.05, 2.5)
	if fast_dice or opt_autoplay:
		secs = 0.05
	_type_tween = create_tween()
	_type_tween.tween_property(log_text, "visible_characters", total, secs)
	_type_tween.tween_callback(func(): log_text.visible_characters = -1)


func _skip_typing() -> void:
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
	log_text.visible_characters = -1


# ===================================================================== title and flow

func _show_title() -> void:
	card.visible = false
	UI.clear(overlay)
	var p := UI.panel(UI.PAPER, 24)
	p.custom_minimum_size = Vector2(520, 0)
	p.position = Vector2(170, 150)
	overlay.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := UI.label("Tales of the Tumbling Dice", 28, Color("#6a1010"), "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := UI.label("The Drowned Bell", 20, UI.INK, "ui")
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	v.add_child(UI.rule())
	var intro := "Pull up a stool by the fire. Your dice are yours: what you carry, what you throw, and what they have been through."
	if campaign.tales_played > 0:
		intro = "You have told %d tale%s at this table. Endings found: %s." % [campaign.tales_played,
			"" if campaign.tales_played == 1 else "s", ", ".join(campaign.endings_seen) if not campaign.endings_seen.is_empty() else "none yet"]
	v.add_child(UI.wrap_label(intro, 17))
	if not campaign.chronicle.is_empty():
		var ch := UI.wrap_label("Chronicle: " + " ".join(campaign.chronicle.slice(-3)), 14, UI.INK_SOFT, "italic")
		v.add_child(ch)
	var b := UI.seal_button("Begin the tale", 18)
	b.pressed.connect(_begin_tale)
	v.add_child(b)
	var pb := UI.seal_button("Practice table: 20 challenges", 14, Color("#2a5a6a"))
	pb.tooltip_text = "No story, no stakes: twenty challenges to learn the dice. Your choices are logged for playtesting."
	pb.pressed.connect(_begin_practice)
	v.add_child(pb)
	if campaign.tales_played > 0:
		var nb := UI.seal_button("Start a new campaign", 13, Color("#5a4a3a"))
		nb.pressed.connect(func():
			campaign.new_campaign()
			campaign.save()
			_show_title())
		v.add_child(nb)
	var help := UI.wrap_label("Click choices and dice. Space throws, Enter continues, F toggles fast dice. Hover a die to read it.", 13, UI.INK_SOFT, "italic")
	v.add_child(help)


func _begin_tale() -> void:
	_start_runner(Tale.tale())


## The practice table runs on a throwaway campaign, so it never touches your save.
func _begin_practice() -> void:
	home_campaign = campaign
	campaign = Campaign.new()
	campaign.new_campaign()
	practice = PracticeLog.new()
	_start_runner(Practice.tale())


func _start_runner(t: Dictionary) -> void:
	UI.clear(overlay)
	log_text.clear()
	runner = Runner.new()
	runner.said.connect(_on_said)
	runner.changed.connect(_on_changed)
	runner.start(t, campaign, opt_seed)
	_refresh_status()


func _on_changed() -> void:
	phase_serial += 1
	call_deferred("_on_phase", phase_serial)


func _on_phase(serial: int) -> void:
	if serial != phase_serial or busy:
		return
	_refresh_status()
	var ph: String = runner.phase
	if ph != "throw" and ph != "assign":
		selected.clear()
	match ph:
		"choose": _show_choices()
		"wager": _show_wager()
		"prepare": _show_pouch_screen("prepare")
		"waystone": _show_pouch_screen("waystone")
		"approach": _show_approaches()
		"foe_throw": _foe_throw()
		"throw":
			# At the practice table nothing is pre-picked: the choice has to be the player's own.
			selected = [] if (opt_autoplay or practice != null) else _default_pick()
			practice_reason = ""
			_show_throw()
		"quake": _quake()
		"assign": _show_assign()
		"push": _show_push()
		"defy": _show_defy()
		"cost":
			if practice != null:
				practice.settle(runner.scene.id, runner.tier)
			_show_costs()
		"outcome":
			if practice != null:
				practice.settle(runner.scene.id, runner.tier)
			_show_continue()
		"ending": _show_ending()
	await _shot(ph)
	if opt_autoplay:
		_autoplay_step(serial)


# ===================================================================== choices

func _show_choices() -> void:
	_card_clear()
	_refresh_hand(false)
	table.clear_foe()
	_card_title(runner.scene.title, "Act %d" % runner.scene.get("act", 1))
	var opts: Array = runner.visible_options()
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := UI.card_button(o.text, 17)
		b.pressed.connect(func(): runner.pick(i))
		card_box.add_child(b)


func _show_continue() -> void:
	_card_clear()
	_refresh_hand(false)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	card_box.add_child(row)
	var note := UI.label("The tale goes on.", 15, UI.INK_SOFT, "italic")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	var b := UI.seal_button("Continue", 16)
	b.pressed.connect(_continue)
	row.add_child(b)


func _continue() -> void:
	table.clear_player()
	table.clear_foe()
	runner.next()


func _show_wager() -> void:
	_card_clear()
	_card_title("Stake a die", "it stays with the tale if you are lost")
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	card_box.add_child(grid)
	for d in runner.pouch.collection:
		var tile = UI.DieTile.new(d, 58.0)
		tile.caption = UI.INK
		tile.pressed.connect(func(t): runner.pick_wager(t.die))
		grid.add_child(tile)
	var b := UI.seal_button("On second thought, no wager", 13, Color("#5a4a3a"))
	b.pressed.connect(func(): runner.pick_wager(null))
	card_box.add_child(b)


func _show_costs() -> void:
	_card_clear()
	_card_title("Mixed: choose the price")
	var cs: Array = runner.costs()
	for i in cs.size():
		var b := UI.card_button(cs[i].label, 16)
		b.pressed.connect(func(): runner.pick_cost(i))
		card_box.add_child(b)


func _show_push() -> void:
	_card_clear()
	var run = runner.active.run
	_card_title("Done, with tries to spare", "%s" % _slots_text(run))
	card_box.add_child(UI.wrap_label("Every slot is met: that is a Success. Throw again for a Triumph (6 over in total), or take it. Pushing costs dice from your Pouch.", 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card_box.add_child(row)
	var a := UI.seal_button("Take the Success", 15, Color("#3f6a2a"))
	a.pressed.connect(func(): runner.stop())
	row.add_child(a)
	var b := UI.seal_button("Push for a Triumph", 15)
	b.pressed.connect(func(): runner.push())
	row.add_child(b)


func _show_defy() -> void:
	_card_clear()
	_card_title("A Fail", "once per tale")
	card_box.add_child(UI.wrap_label("You may Defy it: spend 3 Fate to turn this Fail into a Mixed. The Teller will remember.", 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card_box.add_child(row)
	var a := UI.seal_button("Defy (3 Fate)", 15)
	a.pressed.connect(func(): runner.defy(true))
	row.add_child(a)
	var b := UI.seal_button("Let it stand", 15, Color("#5a4a3a"))
	b.pressed.connect(func(): runner.defy(false))
	row.add_child(b)


# ===================================================================== approaches

func _show_approaches() -> void:
	_card_clear()
	_refresh_hand(false)
	var o: Dictionary = runner.option
	var info := ""
	if o.has("challenge"):
		var def: Dictionary = runner.challenge_def(runner.approaches()[0])
		info = "Trial: clock %d" % def.get("danger", 3) if def.get("kind", "test") == "trial" else ("Test, %d tr%s" % [def.get("tries", 1), "y" if def.get("tries", 1) == 1 else "ies"])
	else:
		info = "Contest"
	_card_title(o.challenge.get("title", "") if o.has("challenge") else o.contest.get("title", ""), info)
	card_box.add_child(UI.label("How do you go about it? Your Hand is drawn below.", 13, UI.INK_SOFT, "italic"))
	var aps: Array = runner.approaches()
	for i in aps.size():
		var ap: Dictionary = aps[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card_box.add_child(row)
		var b := UI.card_button("[%s]  %s" % [Dice.ASPECT_NAMES[ap.aspect], ap.text], 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): runner.pick_approach(i))
		row.add_child(b)
		var odds: Dictionary = runner.approach_odds(i)
		if odds.has("tiers"):
			var bar = UI.OddsBar.new()
			bar.custom_minimum_size = Vector2(270, 30)
			bar.set_tiers(odds.tiers, odds.exact)
			var def2: Dictionary = runner.challenge_def(ap)
			var vb := VBoxContainer.new()
			vb.add_child(UI.label("%s %d%s" % [Dice.ASPECT_NAMES[ap.aspect], def2.target, "  (clock %d)" % def2.danger if def2.get("kind", "") == "trial" else ""], 11, UI.INK_SOFT))
			vb.add_child(bar)
			row.add_child(vb)
		else:
			var txt := "Your best dice: about %d a round\nagainst Resolve %d" % [roundi(odds.expected), odds.resolve]
			if odds.get("catch", 0.0) > 0.0:
				txt += "\nLoaded dice: %d%% caught" % roundi(odds.catch * 100)
			var l := UI.label(txt, 12, UI.INK)
			l.custom_minimum_size.x = 270
			row.add_child(l)


# ===================================================================== throwing

func _toggle_die(tile) -> void:
	if runner.phase != "throw" or busy:
		return
	var d: Dictionary = tile.die
	if selected.has(d):
		selected.erase(d)
	elif selected.size() < runner.max_dice():
		selected.append(d)
	_show_throw()


func _show_throw() -> void:
	_card_clear()
	var a: Dictionary = runner.active
	var max_n: int = runner.max_dice()
	if a.type == "laststand":
		selected = runner.pouch.hand.duplicate()
	else:
		selected = selected.filter(func(d): return runner.pouch.hand.has(d))
	_refresh_hand(a.type != "laststand")
	match a.type:
		"challenge", "laststand", "flee":
			var run = a.run
			var sub := ""
			if run.kind == "trial":
				sub = "Danger %d of %d: %s" % [run.danger, run.danger_size, run.danger_text]
			elif run.tries_total > 1:
				sub = "Try %d of %d" % [run.tries_used + 1, run.tries_total]
			_card_title(run.title if run.title != "" else "Challenge", sub)
			_slot_rows(run, [])
		"contest":
			var c = a.run
			_card_title(c.opponent.name, "Round %d of %d" % [c.round_no, c.rounds_max])
			card_box.add_child(UI.label("Their Resolve %d. Your Nerve %d of %d. They push with %d this round: Hold blocks it, Press wears them down." % [maxi(0, c.resolve), c.nerve, Contest.NERVE, c.pressure], 14))
		"combat":
			var c = a.run
			var sub2 := "Round %d" % c.round_no
			if c.danger_size > 0:
				sub2 += ", %s %d of %d" % [c.danger_text, c.danger, c.danger_size]
			_card_title("%s  (Resolve %d)" % [c.foe.name, maxi(0, c.resolve)], sub2)
			card_box.add_child(UI.label("It throws: %s." % c.intent_text(), 15, Color("#8a2a1a")))
			if runner.pouch.hand.any(func(d): return Dice.trait_of(d) == "clarity"):
				card_box.add_child(UI.label("Clarity (Elven Jade): next round it throws %s." % Odds.foe_throw_odds(c.phase().dice), 12, UI.INK_SOFT, "italic"))
	if practice != null and a.type != "laststand":
		var rrow := HBoxContainer.new()
		rrow.add_theme_constant_override("separation", 6)
		card_box.add_child(rrow)
		rrow.add_child(UI.label("Why these dice? (optional)", 12, UI.INK_SOFT, "italic"))
		for r in PracticeLog.REASONS:
			var rb := UI.seal_button(r, 11, Color("#1f4a5a") if practice_reason == r else Color("#7a6a5a"))
			rb.pressed.connect(func():
				practice_reason = "" if practice_reason == r else r
				_show_throw())
			rrow.add_child(rb)
	# odds
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 12)
	card_box.add_child(orow)
	var lbl := UI.label("Throw %d of up to %d" % [selected.size(), max_n], 14, UI.INK)
	lbl.custom_minimum_size.x = 150
	orow.add_child(lbl)
	if a.type in ["challenge", "laststand", "flee"]:
		odds_widget = UI.OddsBar.new()
		odds_widget.custom_minimum_size = Vector2(330, 30)
		orow.add_child(odds_widget)
	odds_text = UI.label("", 13, UI.INK)
	odds_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	odds_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	orow.add_child(odds_text)
	_update_odds()
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_END
	brow.add_theme_constant_override("separation", 10)
	card_box.add_child(brow)
	var hint := UI.label(("Pick dice from your Hand, then drag across the tray and let go, or press Throw." if a.type != "laststand" else "Last Stand: everything you have. Drag across the tray, or press Throw."), 13, UI.INK_SOFT, "italic")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(hint)
	if runner.can_flee():
		var fb := UI.seal_button("Flee", 14, Color("#5a4a3a"))
		fb.tooltip_text = "A Grace Test against its speed (%d). Escaping routes the tale differently." % a.run.foe.speed
		fb.pressed.connect(func(): runner.flee())
		brow.add_child(fb)
	var tb := UI.seal_button("Throw", 17)
	tb.disabled = selected.is_empty()
	tb.pressed.connect(_do_throw)
	brow.add_child(tb)


## What a sensible player would pick (pre-selected; the player can change it).
func _default_pick() -> Array:
	return bot.choose_dice(runner)


func _update_odds() -> void:
	if odds_text == null:
		return
	var a: Dictionary = runner.active
	var ctx: Dictionary = runner.throw_ctx()
	if selected.is_empty():
		odds_text.text = ""
		if odds_widget:
			odds_widget.set_tiers([0, 0, 0, 0])
		return
	match a.type:
		"challenge", "laststand", "flee":
			var o := Odds.challenge_odds(a.run, selected, ctx, runner.pouch.hand, runner.pouch, 300)
			odds_widget.set_tiers(o.tiers, o.exact)
			var notes: Array[String] = []
			if a.run.is_rushing(selected.size()):
				notes.append("Rushing: the clock ticks twice.")
			if ctx.pity:
				notes.append("The Teller's pity: +1 to your highest die.")
			odds_text.text = " ".join(notes)
		"contest":
			var o := Odds.contest_round(a.run, selected, ctx, 300)
			var t := "Break them this round: %d%%. Nerve lost: about %.1f." % [roundi(o["break"] * 100), o.taken]
			if o.caught > 0.0:
				t += " Chance she spots your loaded die: %d%%." % roundi(o.caught * 100)
			odds_text.text = t
		"combat":
			var o := Odds.combat_round(a.run, selected, ctx, runner.state.grit, 250)
			odds_text.text = "Finish it this round: %d%%. Damage dealt about %.1f, taken about %.1f (of %d coming)." % [roundi(o.kill * 100), o.dealt, o.taken, a.run.incoming()]


## Throw the selected dice. With `release` (a velocity from a drag), the dice already held over
## the tray are let go along it; without, they are tossed in from your side of the table.
func _do_throw(release = null) -> void:
	if busy or selected.is_empty() or runner.phase != "throw":
		return
	if release == null and table.is_holding():
		release = Vector3.ZERO
	var dice := selected.duplicate()
	if practice != null:
		var how := "fast" if fast_dice else ("drag" if release != null else "button")
		practice.record(runner, dice, bot.choose_dice(runner), practice_reason, how)
		practice_reason = ""
	selected.clear()
	busy = true
	_card_clear()
	card_box.add_child(UI.label("The dice tumble...", 16, UI.INK_SOFT, "italic"))
	var ts: Array = []
	if fast_dice:
		table.clear_player()
		ts = Odds.roll(dice, rng)
		results = []
	else:
		var res: Array
		if release != null:
			res = await table.release(release)
		else:
			res = await table.throw_player(dice)
		results = res
		for i in dice.size():
			var t := S.make_thrown(dice[i], res[i].value - 1)
			t.cocked = res[i].cocked
			t.alt = res[i].alt - 1
			ts.append(t)
		await _echoes(ts)
	busy = false
	pending = ts
	_settle_cocked()


## Echo faces: the die is thrown again and the new number added (up to three times).
func _echoes(ts: Array) -> void:
	for chain in Odds.ECHO_CHAIN:
		var idx: Array = []
		for i in ts.size():
			var t: Dictionary = ts[i]
			if not t.cocked and t.get("echo_face", t.face) >= 0 and Dice.face_rune(t.die, t.get("echo_face", t.face)) == "echo":
				idx.append(i)
		if idx.is_empty():
			return
		var nodes: Array = idx.map(func(i): return results[i].node)
		_on_said(runner.teller.line("echo", {"die": ts[idx[0]].die.name}), "teller")
		var res: Array = await table.rethrow(nodes)
		for k in idx.size():
			var t: Dictionary = ts[idx[k]]
			var nf: int = res[k].value - 1
			t.echo += Dice.face_n(t.die, nf)
			t.echo_face = nf if not res[k].cocked else -1
			table.show_tag(results[idx[k]].node, S.raw(t), false, t.die)


## Cocked dice must be decided before the throw counts: take either leaning face (1 Fate,
## free for Bone), or throw it again alone for free.
func _settle_cocked() -> void:
	var idx := -1
	for i in pending.size():
		if pending[i].cocked:
			idx = i
			break
	if idx < 0:
		var ts := pending
		pending = []
		for t in ts:
			t.erase("echo_face")
		runner.submit_throw(ts)
		return
	var t: Dictionary = pending[idx]
	if opt_autoplay:
		_rethrow_cocked(idx)
		return
	_card_clear()
	_card_title("Cocked: %s" % t.die.name, "it leans between two faces")
	card_box.add_child(UI.label(runner.teller.line("cocked", {"die": t.die.name}), 15, UI.INK_SOFT, "italic"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card_box.add_child(row)
	var cost: int = runner.steady_cost(t)
	for f in [t.face, t.alt]:
		var n := Dice.face_n(t.die, f)
		var b := UI.seal_button("Take %d (%s)" % [n, "free" if cost == 0 else "1 Fate"], 15)
		b.disabled = cost > runner.state.fate
		b.pressed.connect(func():
			if runner.pay_steady(t):
				t.face = f
				t.cocked = false
				if results.size() > idx:
					await table.turn_to(results[idx].node, f + 1)
				_refresh_status()
				_settle_cocked())
		row.add_child(b)
	var rb := UI.seal_button("Throw it again (free)", 15, Color("#5a4a3a"))
	rb.pressed.connect(func(): _rethrow_cocked(idx))
	row.add_child(rb)


func _rethrow_cocked(idx: int) -> void:
	busy = true
	var t: Dictionary = pending[idx]
	if results.size() > idx:
		var res: Array = await table.rethrow([results[idx].node])
		t.face = res[0].value - 1
		t.alt = res[0].alt - 1
		t.cocked = res[0].cocked
	else:
		t.face = Dice.sample(t.die, rng)
		t.cocked = false
	busy = false
	_settle_cocked()


func _foe_throw() -> void:
	_card_clear()
	var a: Dictionary = runner.active
	var who: String = a.run.foe.name if a.type == "combat" else a.run.opponent.name
	_card_title(who, "throws first")
	card_box.add_child(UI.label("Watch the tray.", 15, UI.INK_SOFT, "italic"))
	_refresh_hand(false)
	busy = true
	table.clear_player()
	var vals: Array = []
	if fast_dice:
		table.clear_foe()
		for d in runner.foe_dice:
			vals.append(rng.randi_range(1, int(d.sides)))
	else:
		vals = await table.throw_foe(runner.foe_dice)
	busy = false
	runner.set_foe_values(vals)


func _quake() -> void:
	busy = true
	var idx: Array = runner.quake_targets()
	var map := {}
	if fast_dice or results.is_empty():
		for i in idx:
			map[i] = Odds.roll([runner.thrown[i].die], rng)[0]
	else:
		var nodes: Array = idx.map(func(i): return results[i].node)
		var res: Array = await table.rethrow(nodes)
		for k in idx.size():
			var t := S.make_thrown(runner.thrown[idx[k]].die, res[k].value - 1)
			map[idx[k]] = t
	busy = false
	runner.apply_rethrow(map)


# ===================================================================== assigning

func _slot_names() -> Array:
	var a: Dictionary = runner.active
	match a.type:
		"combat":
			return Combat.STANCES.map(func(s): return Combat.STANCE_NAMES[s])
		"contest":
			return ["Press", "Hold"]
	return a.run.slots.map(func(s): return s.get("label", "") if s.get("label", "") != "" else Dice.ASPECT_NAMES[s.aspect])


func _slot_aspects() -> Array:
	var a: Dictionary = runner.active
	match a.type:
		"combat":
			return Combat.STANCES.map(func(s): return Combat.STANCE_ASPECT[s])
		"contest":
			return [a.run.aspect, a.run.aspect]
	return a.run.slots.map(func(s): return s.aspect)


func _show_assign() -> void:
	var a: Dictionary = runner.active
	assign_arr = runner.suggestion.assign.duplicate()
	read_mode = runner.suggestion.get("read_mode", "expose")
	sel_chip = -1
	_render_assign()


func _render_assign() -> void:
	_card_clear()
	_refresh_hand(false)
	var a: Dictionary = runner.active
	var thrown: Array = runner.thrown
	var title := "Place your dice"
	match a.type:
		"combat": title = "%s: Resolve %d, %s" % [a.run.foe.name, maxi(0, a.run.resolve), a.run.intent_text()]
		"contest": title = "%s: Resolve %d, pushing %d" % [a.run.opponent.name, maxi(0, a.run.resolve), a.run.pressure]
		_: title = a.run.title if a.run.title != "" else "Place your dice"
	_card_title(title)
	# combos and notes
	var notes: Array = runner.ev.notes
	if not notes.is_empty():
		card_box.add_child(UI.label(" · ".join(notes), 12, Color("#2a6a2a")))
	# chips
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	card_box.add_child(chips)
	chips.add_child(UI.label("Dice:", 13, UI.INK_SOFT))
	for i in thrown.size():
		var t: Dictionary = thrown[i]
		var tile = UI.DieTile.new(t.die, 52.0)
		tile.caption = UI.INK
		tile.big = str(S.raw(t)) + (("" if S.rune(t) == "" else Dice.RUNE_GLYPH[S.rune(t)]))
		tile.selected = sel_chip == i
		tile.badge = _slot_names()[assign_arr[i]] if assign_arr[i] >= 0 else "-"
		tile.tooltip_text = Dice.tooltip(t.die) + ("\nThis face: %s" % Dice.RUNES.get(S.rune(t), "") if S.rune(t) != "" else "")
		tile.pressed.connect(func(_t): _select_chip(i))
		chips.add_child(tile)
	# slots
	var names := _slot_names()
	var aspects := _slot_aspects()
	var prev: Dictionary = runner.preview(assign_arr, _pair_pick(), read_mode)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	card_box.add_child(srow)
	for s in names.size():
		var b := UI.card_button("", 13, "ui")
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var placed: Array = []
		for i in thrown.size():
			if assign_arr[i] == s:
				placed.append(str(S.raw(thrown[i])))
		var line2 := ""
		match a.type:
			"challenge", "laststand", "flee":
				var sl: Dictionary = a.run.slots[s]
				line2 = "%d / %d  (+%d)" % [prev.progress[s], sl.target, prev.totals[s]]
			"contest":
				line2 = "%d" % (prev.press if s == 0 else prev.hold)
			"combat":
				line2 = Combat.STANCE_TEXT[Combat.STANCES[s]].left(30)
		b.text = "%s [%s]\n%s" % [names[s], Dice.ASPECT_GLYPH[aspects[s]], line2]
		b.tooltip_text = Combat.STANCE_TEXT.get(Combat.STANCES[s] if a.type == "combat" else "", "") + ("\nFull value for %s dice, half for others." % Dice.ASPECT_NAMES[aspects[s]] if aspects[s] != "any" else "\nEvery die counts in full.")
		b.pressed.connect(func(): _place(s))
		srow.add_child(b)
	# preview line
	var pl := UI.label(_preview_text(prev), 14, UI.INK)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD
	card_box.add_child(pl)
	# actions
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 6)
	card_box.add_child(arow)
	var fl := UI.label("Fate %d:" % runner.state.fate, 13, UI.INK)
	arow.add_child(fl)
	var has_sel := sel_chip >= 0
	var nd := UI.seal_button("Nudge -1", 12, Color("#7a5a1a"))
	nd.disabled = not has_sel or runner.state.fate < 1 or (has_sel and thrown[sel_chip].face <= 0)
	nd.tooltip_text = "Turn the selected die one face down (1 Fate)."
	nd.pressed.connect(func(): _nudge(-1))
	arow.add_child(nd)
	var nu := UI.seal_button("Nudge +1", 12, Color("#7a5a1a"))
	nu.disabled = not has_sel or runner.state.fate < 1 or (has_sel and thrown[sel_chip].face >= thrown[sel_chip].die.sides - 1)
	nu.tooltip_text = "Turn the selected die one face up (1 Fate)."
	nu.pressed.connect(func(): _nudge(1))
	arow.add_child(nu)
	var rr := UI.seal_button("Reroll", 12, Color("#7a5a1a"))
	rr.disabled = not has_sel or runner.state.fate < 1
	rr.tooltip_text = "Throw the selected die again; you keep the new result (1 Fate)."
	rr.pressed.connect(_reroll)
	arow.add_child(rr)
	var bp := UI.seal_button("Bump table", 12, Color("#7a5a1a"))
	bp.disabled = runner.state.fate < 2 or runner.bump_targets().is_empty()
	bp.tooltip_text = "Re-throw every die showing its lowest face (2 Fate)."
	bp.pressed.connect(_bump)
	arow.add_child(bp)
	if not runner.bell_targets().is_empty():
		var bell := UI.seal_button("Wren's bell", 12, Color("#2a5a6a"))
		bell.tooltip_text = "Once in the climax: re-throw every die showing 1."
		bell.pressed.connect(_bell)
		arow.add_child(bell)
	if a.type == "combat":
		var rm := UI.seal_button("Read: %s" % read_mode.capitalize(), 12, Color("#1f5a3a"))
		rm.tooltip_text = "What a Read die (3 or more) does: Expose (+50% damage) or Silence one trait."
		rm.pressed.connect(func():
			read_mode = "silence" if read_mode == "expose" else "expose"
			_render_assign())
		arow.add_child(rm)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(sp)
	var best := UI.seal_button("Best", 13, Color("#5a4a3a"))
	best.tooltip_text = "Place every die where it does the most good."
	best.pressed.connect(func():
		assign_arr = runner.suggestion.assign.duplicate()
		read_mode = runner.suggestion.get("read_mode", "expose")
		_render_assign())
	arow.add_child(best)
	var ok := UI.seal_button("Confirm", 16)
	ok.pressed.connect(_confirm)
	arow.add_child(ok)
	for i in results.size():
		if is_instance_valid(results[i].node):
			table.highlight(results[i].node, i == sel_chip)


func _pair_pick() -> int:
	if runner.ev.combos.pair.is_empty():
		return 0
	var a: Dictionary = runner.active
	var best := 0
	var best_v := -INF
	for pp in [0, 1]:
		var p: Dictionary = runner.preview(assign_arr, pp, read_mode)
		var v := 0.0
		match a.type:
			"challenge", "laststand", "flee":
				v = p.totals.reduce(func(x, y): return x + y, 0) + p.tier * 100.0
			"contest":
				v = p.press + p.hold - p.taken * 0.5
			"combat":
				v = p.total_dealt - p.taken * 1.2
		if v > best_v:
			best_v = v
			best = pp
	return best


func _preview_text(p: Dictionary) -> String:
	var a: Dictionary = runner.active
	match a.type:
		"challenge", "laststand", "flee":
			if p.final:
				return "This is the last throw: it will be a %s." % S.TIER_NAMES[p.tier]
			return "Progress carries over to the next try."
		"contest":
			var t := "Press %d against Resolve %d. Hold %d against their %d: you lose %d Nerve." % [p.press, maxi(0, a.run.resolve), p.hold, a.run.pressure, p.taken]
			if p.broken:
				t += " They break!"
			return t
		"combat":
			var bits: Array[String] = ["You deal %d%s" % [p.total_dealt, " (fire %d)" % p.burn if p.burn > 0 else ""]]
			if p.evaded > 0:
				bits.append("dodge %d" % p.evaded)
			if p.blocked > 0:
				bits.append("block %d" % p.blocked)
			if p.tricked > 0:
				bits.append("trick off %d" % p.tricked)
			if p.exposed:
				bits.append("exposed")
			if p.silenced != "":
				bits.append("silence %s" % p.silenced)
			var t := ", ".join(bits) + ". You take %d." % p.taken
			if p.hamstrung:
				t += " Hamstrung!"
			if p.killed:
				t += " It falls!"
			return t
	return ""


func _select_chip(i: int) -> void:
	sel_chip = -1 if sel_chip == i else i
	_render_assign()


func _place(s: int) -> void:
	if sel_chip < 0:
		# No die selected: cycle the first die that isn't here yet into this slot.
		for i in assign_arr.size():
			if assign_arr[i] != s:
				assign_arr[i] = s
				break
	else:
		assign_arr[sel_chip] = s
		sel_chip = -1
	_render_assign()


func _nudge(dir: int) -> void:
	var i := sel_chip
	if i < 0:
		return
	var keep := assign_arr.duplicate()
	if runner.nudge(i, dir):
		if results.size() > i:
			await table.turn_to(results[i].node, runner.thrown[i].face + 1)
		_refresh_status()
		assign_arr = keep
		sel_chip = i
		_render_assign()


func _reroll() -> void:
	var i := sel_chip
	if i < 0 or not runner.pay_reroll(i):
		return
	await _rethrow_indices([i])


func _bump() -> void:
	if not runner.pay_bump():
		return
	await _rethrow_indices(runner.bump_targets())


func _bell() -> void:
	var idx: Array = runner.bell_targets()
	runner.use_bell()
	await _rethrow_indices(idx)


func _rethrow_indices(idx: Array) -> void:
	busy = true
	var map := {}
	if fast_dice or results.is_empty():
		for i in idx:
			map[i] = Odds.roll([runner.thrown[i].die], rng)[0]
	else:
		var res: Array = await table.rethrow(idx.map(func(i): return results[i].node))
		for k in idx.size():
			var t := S.make_thrown(runner.thrown[idx[k]].die, res[k].value - 1)
			if res[k].cocked:
				# Settle a cocked re-throw on the lower face; no second prompt mid-assignment.
				t.face = mini(res[k].value, res[k].alt) - 1
			map[idx[k]] = t
	busy = false
	_refresh_status()
	runner.apply_rethrow(map)


func _confirm() -> void:
	if busy:
		return
	for i in results.size():
		if is_instance_valid(results[i].node):
			table.highlight(results[i].node, false)
	runner.assign(assign_arr.duplicate(), _pair_pick(), read_mode)


func _slots_text(run) -> String:
	var parts: Array[String] = []
	for k in run.slots.size():
		parts.append("%s %d/%d" % [Dice.ASPECT_NAMES[run.slots[k].aspect], run.progress[k], run.slots[k].target])
	return ", ".join(parts)


func _slot_rows(run, _unused) -> void:
	for k in run.slots.size():
		var sl: Dictionary = run.slots[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card_box.add_child(row)
		var name_l := UI.label("%s [%s]" % [Dice.ASPECT_NAMES[sl.aspect] if sl.aspect != "any" else "Stand", Dice.ASPECT_GLYPH[sl.aspect]], 15, Dice.ASPECT_COLOR[sl.aspect].darkened(0.3))
		name_l.custom_minimum_size.x = 110
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.max_value = sl.target
		bar.value = mini(run.progress[k], sl.target)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(380, 16)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color("#2a1608")
		var fg := StyleBoxFlat.new()
		fg.bg_color = Dice.ASPECT_COLOR[sl.aspect]
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		row.add_child(bar)
		row.add_child(UI.label("%d of %d   (Mixed from %d, Triumph at %d)" % [run.progress[k], sl.target, maxi(0, sl.target - S.MIXED_WINDOW), sl.target + S.TRIUMPH_SURPLUS], 13, UI.INK))


# ===================================================================== the Pouch

var _pouch_mode := ""
var _prefilled := false
var _detail: Label


func _show_pouch_screen(mode: String) -> void:
	_pouch_mode = mode
	card.visible = false
	_refresh_hand(false)
	UI.clear(overlay)
	var p := UI.panel(UI.PAPER, 16)
	p.position = Vector2(12, 60)
	p.custom_minimum_size = Vector2(CARD_W, 0)
	overlay.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var pouch = runner.pouch
	if mode == "prepare" and pouch.pouch.is_empty() and campaign.tales_played == 0 and not _prefilled:
		# A first-timer gets a sensible Pouch to start from; every die can be swapped.
		_prefilled = true
		bot.pack(campaign, "balanced")
	if mode == "prepare":
		v.add_child(UI.label("Packing the Pouch", 22, Color("#6a1010"), "title"))
		v.add_child(UI.wrap_label("Click a die on the shelf to pack it; click a packed die to put it back. The Pouch is your deck for the whole tale; the Saddlebag waits at the Waystone, where you may swap up to 2 dice.", 15))
	else:
		v.add_child(UI.label("The Waystone", 22, Color("#6a1010"), "title"))
		v.add_child(UI.wrap_label("Swaps left: %d. Click a die to move it between Pouch and Saddlebag. Cursed dice cannot leave the Pouch." % pouch.swaps_left, 15))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	v.add_child(cols)
	if mode == "prepare":
		_pouch_column(cols, "Shelf", pouch.shelf(), "shelf", -1, -1)
	_pouch_column(cols, "Pouch", pouch.pouch, "pouch", pouch.weight(), pouch.weight_limit)
	_pouch_column(cols, "Saddlebag", pouch.saddlebag, "bag", Pouch.weight_of(pouch.saddlebag), pouch.saddle_limit)
	_detail = UI.wrap_label("Hover a die to read it.", 14, UI.INK_SOFT, "body")
	_detail.custom_minimum_size = Vector2(CARD_W - 40, 66)
	v.add_child(_detail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var ok := UI.seal_button("Set out" if mode == "prepare" else "Rest is over", 16)
	ok.disabled = pouch.pouch.is_empty()
	ok.pressed.connect(func():
		UI.clear(overlay)
		if mode == "prepare":
			runner.done_prepare()
		else:
			runner.done_waystone())
	row.add_child(ok)


func _pouch_column(parent: Control, title: String, dice: Array, where: String, w: int, limit: int) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var head := title
	if limit > 0:
		head += "   weight %d / %d" % [w, limit]
	col.add_child(UI.label(head, 15, UI.INK))
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UI.paper_box(Color(0.15, 0.09, 0.05, 0.9), Color("#8a5a2a"), 6, 6))
	bg.custom_minimum_size = Vector2(0, 210)
	col.add_child(bg)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	bg.add_child(flow)
	for d in dice:
		var tile = UI.DieTile.new(d, 52.0)
		tile.mouse_entered.connect(func(): _detail.text = Dice.tooltip(d).replace("\n", "   "))
		tile.pressed.connect(func(_t): _move_die(d, where))
		flow.add_child(tile)


func _move_die(d: Dictionary, where: String) -> void:
	var pouch = runner.pouch
	if _pouch_mode == "prepare":
		match where:
			"shelf":
				if not pouch.add(d) and not pouch.bag(d):
					_detail.text = "No room for the %s: the Pouch holds weight %d and the Saddlebag %d." % [d.name, pouch.weight_limit, pouch.saddle_limit]
					return
			"pouch":
				if not pouch.remove(d):
					_detail.text = "The %s is cursed. It will not leave your Pouch." % d.name
					return
			"bag":
				pouch.unbag(d)
	else:
		if not pouch.waystone_swap(d):
			_detail.text = "You can't move that: no swaps left, no room, or it is cursed."
			return
	_show_pouch_screen(_pouch_mode)


# ===================================================================== ending

func _show_ending() -> void:
	card.visible = false
	_refresh_hand(false)
	table.clear_player()
	table.clear_foe()
	if practice != null:
		_show_practice_summary()
		return
	campaign.save()
	UI.clear(overlay)
	var st = runner.state
	var p := UI.panel(UI.PAPER, 18)
	p.position = Vector2(12, 60)
	p.custom_minimum_size = Vector2(CARD_W, 0)
	overlay.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var names := {"rest": "Rest", "silence": "Silence", "greed": "Greed", "bargain": "The Bargain", "drowned": "Drowned"}
	v.add_child(UI.label("Ending: %s" % names.get(st.ending, st.ending), 26, Color("#6a1010"), "title"))
	v.add_child(UI.label("Endings found: %d of 5   ·   Tales told: %d   ·   Coin %d" % [campaign.endings_seen.size(), campaign.tales_played, campaign.coin], 14, UI.INK_SOFT))
	if not st.gained.is_empty():
		v.add_child(UI.label("Dice you came home with", 15, UI.INK))
		var row := HBoxContainer.new()
		v.add_child(row)
		for d in st.gained:
			var t = UI.DieTile.new(d, 58.0)
			t.caption = UI.INK
			t.dim = d.ally
			row.add_child(t)
	if not st.lost.is_empty():
		v.add_child(UI.label("Lost: " + ", ".join(st.lost.map(func(d): return d.name)), 14, Color("#8a2a1a")))
	for c in st.chronicle:
		v.add_child(UI.wrap_label("Chronicle: " + c, 15, UI.INK, "italic"))
	var ep: String = st.epithet()
	if ep != "":
		v.add_child(UI.wrap_label("The Teller will remember you as the %s traveller." % ep, 15, UI.INK_SOFT, "italic"))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row2)
	var b := UI.seal_button("Back to the tavern", 16)
	b.pressed.connect(func():
		log_text.clear()
		runner = null
		_refresh_status()
		_refresh_hand(false)
		_show_title())
	row2.add_child(b)
	if opt_quit_at_end:
		print("ENDING: ", st.ending, "  throws: ", st.throws, "  scenes: ", st.visited.size())
		await _wait(20)
		await _shot("ending_final")
		get_tree().quit()


func _show_practice_summary() -> void:
	UI.clear(overlay)
	var sm: Dictionary = practice.summary()
	var path: String = practice.save()
	var p := UI.panel(UI.PAPER, 18)
	p.position = Vector2(12, 60)
	p.custom_minimum_size = Vector2(CARD_W, 0)
	overlay.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UI.label("Practice done", 26, Color("#6a1010"), "title"))
	var tiers: Dictionary = sm.tiers
	var tl: Array[String] = []
	for t in S.TIER_NAMES:
		tl.append("%s %d" % [t, int(tiers.get(t, 0))])
	v.add_child(UI.label("%d challenges, %d throws.   %s" % [sm.challenges, sm.throws, "   ".join(tl)], 15, UI.INK))
	v.add_child(UI.wrap_label("You picked the same dice as the table's own suggestion %d times out of %d, and beat its odds %d times. On average your picks gave up %d points of odds against it." % [sm.same, sm.throws, sm.better, roundi(sm.given_up * 100)], 15, UI.INK))
	var rl: Array[String] = []
	for r in sm.reasons:
		rl.append("%s %d" % [r, sm.reasons[r]])
	v.add_child(UI.wrap_label("Your reasons: " + ", ".join(rl), 14, UI.INK_SOFT, "italic"))
	if path != "":
		v.add_child(UI.wrap_label("The full log is saved at %s" % path, 12, UI.INK_SOFT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var b := UI.seal_button("Back to the tavern", 16)
	b.pressed.connect(func():
		campaign = home_campaign
		home_campaign = null
		practice = null
		log_text.clear()
		runner = null
		_refresh_status()
		_refresh_hand(false)
		_show_title())
	row.add_child(b)
	if opt_quit_at_end:
		print("PRACTICE: ", JSON.stringify(sm), "  log: ", path)
		await _wait(20)
		await _shot("practice_final")
		get_tree().quit()


# ===================================================================== input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_tray_mouse(event)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if runner and runner.phase == "assign" and not busy and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var i: int = event.keycode - KEY_1
		if i < runner.thrown.size():
			_select_chip(i)
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_F:
			fast_dice = not fast_dice
			fast_toggle.button_pressed = fast_dice
		KEY_SPACE:
			if runner and runner.phase == "throw":
				_do_throw()
		KEY_ENTER, KEY_KP_ENTER:
			if runner == null:
				return
			match runner.phase:
				"outcome": _continue()
				"assign": _confirm()
				"throw": _do_throw()


# ===================================================================== hands on the tray

var dragging := false
var drag_samples: Array = []     # [[time, world point]]
const DRAG_WINDOW := 0.12        # seconds of motion that set the throw's velocity
const DRAG_GAIN := 1.15


## Mouse on the tray: drag to throw in the throw phase, click a die to pick it when placing.
func _tray_mouse(event: InputEvent) -> void:
	if runner == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if runner.phase == "throw" and not busy and not selected.is_empty():
				_drag_start(event.position)
			elif runner.phase == "assign" and not busy:
				var n = table.node_at(camera, event.position)
				if n != null:
					for i in results.size():
						if results[i].node == n:
							_select_chip(i)
		elif dragging:
			_drag_end(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and dragging:
		# Right click while holding: put the dice back in the Hand.
		dragging = false
		table.cancel_hold()
		_show_throw()
	elif event is InputEventMouseMotion and dragging:
		# Held dice hover under the cursor: intersect the plane they float in, not the felt.
		var p = Table.table_point(camera, event.position, Table.HOLD_HEIGHT)
		if p != null:
			drag_samples.append([Time.get_ticks_msec() / 1000.0, Table.clamp_hold(p)])
			while drag_samples.size() > 40:
				drag_samples.pop_front()


func _drag_start(screen: Vector2) -> void:
	var p = Table.table_point(camera, screen)
	if p == null:
		return
	# Only over the tray itself (with a little slack), so clicks elsewhere don't pick up dice.
	if absf(p.x) > Tavern.TRAY.x / 2 + 2.0 or absf(p.z) > Tavern.TRAY.y / 2 + 2.0:
		return
	if fast_dice:
		_do_throw()
		return
	dragging = true
	var hp = Table.table_point(camera, screen, Table.HOLD_HEIGHT)
	if hp != null:
		p = hp
	drag_samples = [[Time.get_ticks_msec() / 1000.0, Table.clamp_hold(p)]]
	table.hold_player(selected, p)
	_card_clear()
	card_box.add_child(UI.label("Shake them... and let go. Flick to throw hard. Right-click to put them back.", 15, UI.INK_SOFT, "italic"))


func _drag_end(screen: Vector2) -> void:
	dragging = false
	var p = Table.table_point(camera, screen, Table.HOLD_HEIGHT)
	var now := Time.get_ticks_msec() / 1000.0
	if p != null:
		drag_samples.append([now, Table.clamp_hold(p)])
	# Velocity from the last moment of the gesture (a flick), not the whole drag.
	var vel := Vector3.ZERO
	var last: Array = drag_samples[-1]
	for k in range(drag_samples.size() - 1, -1, -1):
		var s: Array = drag_samples[k]
		if last[0] - s[0] >= DRAG_WINDOW or k == 0:
			var dt: float = maxf(0.016, last[0] - s[0])
			vel = (last[1] - s[1]) / dt * DRAG_GAIN
			break
	if now - last[0] > 0.15:
		vel = Vector3.ZERO   # held still before letting go: a drop
	_do_throw(vel)


func _process_hold(delta: float) -> void:
	if dragging and table.is_holding() and not drag_samples.is_empty():
		table.move_hold(drag_samples[-1][1], delta)


# ===================================================================== testing

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(tag: String) -> void:
	if opt_shots == "" or shots_taken >= opt_max_shots or DisplayServer.get_name() == "headless":
		return
	await _wait(8)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	shots_taken += 1
	var path := "%s/%02d_%s.png" % [opt_shots, shots_taken, tag]
	img.save_png(path)
	print("shot ", path)


## A simulated mouse gesture across the tray, through the same input handler a player uses.
func _autoplay_drag() -> void:
	var a := camera.unproject_position(Vector3(rng.randf_range(-6, -3), 0, rng.randf_range(-2, 3)))
	var b := camera.unproject_position(Vector3(rng.randf_range(2, 6), 0, rng.randf_range(-3, 2)))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = a
	_tray_mouse(down)
	var steps := 12
	for k in steps + 1:
		var m := InputEventMouseMotion.new()
		m.position = a.lerp(b, float(k) / steps)
		_tray_mouse(m)
		await get_tree().process_frame
		if k == steps / 2:
			await _shot("drag")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	_tray_mouse(up)


## A bot plays through the real UI: the same buttons a player presses.
func _autoplay_step(serial: int) -> void:
	await _wait(6)
	if serial != phase_serial or busy or runner == null:
		return
	bot.archetype = "balanced"
	match runner.phase:
		"choose":
			var n: int = runner.visible_options().size()
			runner.pick(bot.rng.randi_range(0, n - 1))
		"wager":
			runner.pick_wager(null)
		"prepare":
			bot.pack(campaign, "balanced")
			UI.clear(overlay)
			runner.done_prepare()
		"waystone":
			UI.clear(overlay)
			runner.done_waystone()
		"approach":
			runner.pick_approach(bot.best_approach(runner))
		"throw":
			selected = bot.choose_dice(runner)
			if opt_drag and not fast_dice:
				await _autoplay_drag()
			else:
				_do_throw()
		"assign":
			if not runner.bell_targets().is_empty():
				_bell()
				return
			if opt_drag and not results.is_empty() and is_instance_valid(results[0].node):
				# Click the first die in the tray, as a player would, and check it gets picked.
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				click.position = camera.unproject_position(results[0].node.global_position)
				var before := sel_chip
				_tray_mouse(click)
				print("TRAYCLICK ", "ok" if sel_chip != before else "missed")
				sel_chip = -1
			_confirm()
		"push":
			runner.stop()
		"defy":
			runner.defy(true)
		"cost":
			runner.pick_cost(0)
		"outcome":
			_continue()
