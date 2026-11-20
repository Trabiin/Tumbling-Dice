extends PanelContainer
## The text preview inside the game, for writers: the same Preview the console tool uses, on
## paper. Pick choices, force any outcome at a throw, jump to any scene, set flags with a
## command line, and Reload after editing the .tale file to see the change straight away.

const UI := preload("res://scripts/game/ui_kit.gd")
const Preview := preload("res://scripts/rules/preview.gd")
const Tales := preload("res://scripts/rules/tales.gd")

signal closed

var p = Preview.new()
var paths: Array = []
var story: RichTextLabel
var choice_box: VBoxContainer
var scene_pick: OptionButton
var tale_pick: OptionButton
var cmd: LineEdit
var reply: Label
var state_label: Label
var lint_text: RichTextLabel
var cover_label: Label


func _init() -> void:
	add_theme_stylebox_override("panel", UI.paper_box(UI.PAPER, UI.EDGE, 6, 14))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 10
	offset_top = 10
	offset_right = -10
	offset_bottom = -10
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	# ---- left: the story and the choices
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	left.add_child(top)
	top.add_child(UI.label("Tale preview", 20, Color("#6a1010"), "title"))
	tale_pick = OptionButton.new()
	paths = Tales.all_paths()
	for path in paths:
		tale_pick.add_item(path.get_file())
	tale_pick.item_selected.connect(func(i): _open(paths[i]))
	top.add_child(tale_pick)
	top.add_child(UI.label("Jump to", 13, UI.INK_SOFT))
	scene_pick = OptionButton.new()
	scene_pick.item_selected.connect(func(i):
		_say(p.command("goto " + scene_pick.get_item_text(i).get_slice(" ", 0)))
		_refresh())
	top.add_child(scene_pick)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	for b in [["Reload file", _reload], ["Restart", _restart], ["Close", func(): closed.emit()]]:
		var btn := UI.seal_button(b[0], 12, Color("#5a4a3a"))
		btn.pressed.connect(b[1])
		top.add_child(btn)
	story = RichTextLabel.new()
	story.bbcode_enabled = true
	story.scroll_following = true
	story.size_flags_vertical = Control.SIZE_EXPAND_FILL
	story.add_theme_font_override("normal_font", UI.font("body"))
	story.add_theme_font_override("italics_font", UI.font("italic"))
	story.add_theme_font_size_override("normal_font_size", 15)
	story.add_theme_font_size_override("italics_font_size", 15)
	story.add_theme_color_override("default_color", UI.INK)
	left.add_child(story)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 4)
	left.add_child(choice_box)
	# ---- right: commands, state, linter, coverage
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	right.add_child(UI.label("Command (type help)", 13, UI.INK_SOFT))
	cmd = LineEdit.new()
	cmd.placeholder_text = "flag climax=freed   goto chamber   check has:lore"
	cmd.text_submitted.connect(func(t):
		_say(p.command(t))
		cmd.clear()
		_fill_scenes()
		_refresh())
	right.add_child(cmd)
	reply = UI.wrap_label("", 13, UI.INK, "ui")
	right.add_child(reply)
	right.add_child(UI.rule())
	state_label = UI.wrap_label("", 13, UI.INK, "ui")
	right.add_child(state_label)
	right.add_child(UI.rule())
	lint_text = RichTextLabel.new()
	lint_text.bbcode_enabled = true
	lint_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lint_text.add_theme_font_size_override("normal_font_size", 13)
	lint_text.add_theme_color_override("default_color", UI.INK)
	right.add_child(lint_text)
	cover_label = UI.wrap_label("", 12, UI.INK_SOFT, "ui")
	right.add_child(cover_label)
	if not paths.is_empty():
		_open(paths[0])


func _reload() -> void:
	_say(p.command("reload"))
	_fill_scenes()
	_refresh()


func _restart() -> void:
	story.clear()
	p.restart()
	_refresh()


func _open(path: String) -> void:
	story.clear()
	p.open(path)
	_fill_scenes()
	_refresh()


func _fill_scenes() -> void:
	scene_pick.clear()
	for id in p.tale.get("scenes", {}):
		scene_pick.add_item("%s  (line %d)" % [id, p.line_of(id)])


func _say(t: String) -> void:
	reply.text = t


func _refresh() -> void:
	var t: String = p.take_text()
	if t != "":
		story.append_text(UI.smart_quotes(t).replace("\n--- ", "\n[b]--- ").replace(" ---\n", " ---[/b]\n") + "\n")
	UI.clear(choice_box)
	if not p.errors.is_empty():
		choice_box.add_child(UI.wrap_label("The file has errors; fix them and press Reload file.", 14, Color("#8a2a1a"), "ui"))
	for c in p.choices():
		if c.get("info", false):
			choice_box.add_child(UI.label(c.label, 12, UI.INK_SOFT, "italic"))
			continue
		var b := UI.card_button("[%s]  %s" % [c.key, c.label], 14)
		var key: String = c.key
		b.pressed.connect(func():
			p.choose(key)
			_refresh())
		choice_box.add_child(b)
	if p.runner != null and p.errors.is_empty():
		state_label.text = p.state_text()
	var lt := ""
	if not p.errors.is_empty():
		lt = "[color=#8a2a1a]Parse errors:[/color]\n" + p.errors_text()
	else:
		lt = p.lint_text()
	lint_text.text = lt
	cover_label.text = p.coverage_text()
