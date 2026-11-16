extends CanvasLayer

const TuningParts := preload("res://vehicles/tuning_parts.gd")

## Bottom sheet over the showroom: category tabs and four level cards.

const AMBER := UiStyle.AMBER
const AMBER_DIM := UiStyle.AMBER_DIM
const DIAL_BG := UiStyle.NIGHT_TOP
const DIAL_FACE := UiStyle.PANEL_FACE
const LCD_GREEN := UiStyle.LCD_GREEN
const INK := UiStyle.INK

var _tab_bar: HBoxContainer
var _level_cards: Array[Button] = []
var _active_category: String = "engine"

var _root: PanelContainer
var _title: Label
var _subtitle: Label
var _stat_line: Label
var _level_desc: Label


func _ready() -> void:
	layer = 40
	visible = false
	_build()


func open_panel() -> void:
	visible = true
	_refresh_all()


func close_panel() -> void:
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.008, 0.016, 0.28)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.anchor_top = 0.52
	_root.offset_left = 36.0
	_root.offset_top = 0.0
	_root.offset_right = -36.0
	_root.offset_bottom = 0.0
	UiStyle.dress(_root)
	_root.add_theme_stylebox_override("panel", _chrome_panel())
	add_child(_root)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	_root.add_child(layout)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	layout.add_child(head)
	_title = _label(Lang.t("garage.tuning"), 26, UiStyle.CHROME, HORIZONTAL_ALIGNMENT_LEFT)
	head.add_child(_title)
	_subtitle = _label("", 15, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_subtitle)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var back := Button.new()
	back.text = Lang.t("tuning.back")
	back.pressed.connect(close_panel)
	head.add_child(back)
	UiStyle.button(back, UiStyle.RED, 16)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END

	_tab_bar = HBoxContainer.new()
	layout.add_child(_tab_bar)

	_level_desc = _label("", 16, UiStyle.CHROME, HORIZONTAL_ALIGNMENT_LEFT)
	layout.add_child(_level_desc)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 14)
	layout.add_child(cards)
	for level in 4:
		var card := Button.new()
		card.text = ""
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0.0, 120.0)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_theme_font_size_override("font_size", 16)
		card.add_theme_color_override("font_color", UiStyle.CHROME)
		card.add_theme_color_override("font_hover_color", UiStyle.AMBER_HOT)
		card.add_theme_color_override("font_pressed_color", UiStyle.CHROME)
		card.add_theme_stylebox_override("normal", _card_style(false))
		card.add_theme_stylebox_override("hover", _card_style(false, true))
		card.add_theme_stylebox_override("pressed", _card_style(true))
		card.pressed.connect(_on_level.bind(level))
		cards.add_child(card)
		_level_cards.append(card)

	_stat_line = _label("", 14, LCD_GREEN, HORIZONTAL_ALIGNMENT_LEFT)
	layout.add_child(_stat_line)


func _on_dim_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		close_panel()


static func _label(text: String, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_size", 0)
	return l


static func _chrome_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.012, 0.016, 0.03, 0.9)
	s.border_color = Color(1, 1, 1, 0.1)
	s.set_border_width_all(1)
	s.set_corner_radius_all(20)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 28
	s.content_margin_left = 22.0
	s.content_margin_top = 20.0
	s.content_margin_right = 22.0
	s.content_margin_bottom = 20.0
	return s


static func _card_style(on: bool, hover: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 0.62, 0.22, 0.14) if on else Color(1, 1, 1, 0.07 if hover else 0.035)
	s.border_color = AMBER if on or hover else Color(1, 1, 1, 0.08)
	s.set_border_width_all(1)
	s.border_width_bottom = 2 if on else 1
	s.set_corner_radius_all(14)
	s.content_margin_left = 16.0
	s.content_margin_top = 18.0
	s.content_margin_right = 16.0
	s.content_margin_bottom = 18.0
	return s


func _refresh_all() -> void:
	_subtitle.text = String(TuningStore.active_car_id).to_upper()
	_refresh_categories()
	_refresh_levels()


func _refresh_categories() -> void:
	var entries: Array = []
	for cat: String in TuningParts.CATEGORIES:
		var level := int(TuningStore.parts_levels.get(cat, 0))
		var pips := ""
		for i in 3:
			pips += "●" if i < level else "○"
		entries.append({
			"id": cat,
			"text": "%s  %s" % [Lang.t("part.%s" % cat), pips],
		})
	if _tab_bar.get_child_count() != entries.size():
		UiStyle.fill_tabs(_tab_bar, entries, _active_category, _on_category)
		return
	for i in entries.size():
		var b := _tab_bar.get_child(i) as Button
		b.text = String(entries[i]["text"])
		UiStyle._paint_tab(b, String(entries[i]["id"]) == _active_category)


func _refresh_levels() -> void:
	var selected := int(TuningStore.parts_levels.get(_active_category, 0))
	var flavor := TuningParts.level_desc(_active_category, selected)
	_level_desc.text = "" if flavor.begins_with("partdesc.") else flavor
	for level in 4:
		var card: Button = _level_cards[level]
		card.text = "%s\n\n%s" % [
			TuningParts.level_label(_active_category, level),
			TuningParts.stat_line(_active_category, level),
		]
		var is_installed := level == selected
		card.add_theme_color_override("font_color", UiStyle.AMBER_HOT if is_installed else UiStyle.CHROME)
		card.add_theme_stylebox_override("normal", _card_style(is_installed))
	var cur := TuningParts.level_label(_active_category, selected)
	_stat_line.text = "%s: %s" % [Lang.t("part.%s" % _active_category), cur]


func _on_category(cat: String) -> void:
	_active_category = cat
	_refresh_categories()
	_refresh_levels()


func _on_level(level: int) -> void:
	TuningStore.set_part_level(_active_category, level)
	_refresh_categories()
	_refresh_levels()
