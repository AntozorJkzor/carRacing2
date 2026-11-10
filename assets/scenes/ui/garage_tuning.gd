extends CanvasLayer

const TuningParts := preload("res://vehicles/tuning_parts.gd")

## Garage tuning panel — retro JDM gauge-cluster style (80s-90s Toyota):
## amber backlit labels, dark dial faces, green LCD readouts, chrome rings.

const AMBER := Color(1.0, 0.63, 0.24)
const AMBER_DIM := Color(0.85, 0.5, 0.16)
const DIAL_BG := Color(0.043, 0.051, 0.063)
const DIAL_FACE := Color(0.086, 0.098, 0.114)
const LCD_GREEN := Color(0.55, 0.95, 0.6)
const INK := Color(0.06, 0.07, 0.08)

var _category_buttons: Dictionary = {}
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
	dim.color = Color(0.01, 0.012, 0.016, 0.72)
	add_child(dim)

	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.offset_left = -560.0
	_root.offset_top = -330.0
	_root.offset_right = 560.0
	_root.offset_bottom = 330.0
	_root.add_theme_stylebox_override("panel", _chrome_panel())
	add_child(_root)

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	_root.add_child(layout)

	# Left: category stack, like a column of gauge pods.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230.0, 0.0)
	left.add_theme_constant_override("separation", 8)
	layout.add_child(left)

	_title = _label(Lang.t("garage.tuning"), 26, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_title)
	_subtitle = _label("", 14, LCD_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_subtitle)

	for cat: String in TuningParts.CATEGORIES:
		var b := Button.new()
		b.text = Lang.t("part.%s" % cat)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", AMBER)
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.8, 0.5))
		b.add_theme_color_override("font_pressed_color", INK)
		b.add_theme_stylebox_override("normal", _pod_style(DIAL_FACE, Color(0.2, 0.22, 0.26)))
		b.add_theme_stylebox_override("hover", _pod_style(Color(0.12, 0.13, 0.16), AMBER_DIM))
		b.add_theme_stylebox_override("pressed", _pod_style(AMBER, AMBER))
		b.pressed.connect(_on_category.bind(cat))
		left.add_child(b)
		_category_buttons[cat] = b

	var back := Button.new()
	back.text = Lang.t("tuning.back")
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_color_override("font_color", AMBER_DIM)
	back.add_theme_stylebox_override("normal", _pod_style(DIAL_BG, Color(0.2, 0.22, 0.26)))
	back.add_theme_stylebox_override("hover", _pod_style(Color(0.12, 0.13, 0.16), AMBER))
	back.pressed.connect(close_panel)
	left.add_child(back)

	# Right: level cards row + stats.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	layout.add_child(right)

	_level_desc = _label("", 20, Color(0.92, 0.93, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	right.add_child(_level_desc)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 12)
	right.add_child(cards)
	for level in 4:
		var card := Button.new()
		card.text = ""
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0.0, 150.0)
		card.add_theme_font_size_override("font_size", 15)
		card.add_theme_color_override("font_color", AMBER)
		card.add_theme_color_override("font_hover_color", Color(1.0, 0.8, 0.5))
		card.add_theme_color_override("font_pressed_color", INK)
		card.add_theme_stylebox_override("normal", _pod_style(DIAL_FACE, Color(0.2, 0.22, 0.26)))
		card.add_theme_stylebox_override("hover", _pod_style(Color(0.12, 0.13, 0.16), AMBER_DIM))
		card.add_theme_stylebox_override("pressed", _pod_style(AMBER, Color(1.0, 0.85, 0.5)))
		card.pressed.connect(_on_level.bind(level))
		cards.add_child(card)
		_level_cards.append(card)

	_stat_line = _label("", 15, LCD_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	right.add_child(_stat_line)


static func _label(text: String, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_size", 6)
	return l


static func _chrome_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = DIAL_BG
	s.border_color = AMBER_DIM
	s.set_border_width_all(3)
	s.corner_radius_top_left = 18
	s.corner_radius_top_right = 18
	s.corner_radius_bottom_right = 18
	s.corner_radius_bottom_left = 18
	s.shadow_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.22)
	s.shadow_size = 18
	return s


static func _pod_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_right = 10
	s.corner_radius_bottom_left = 10
	s.content_margin_left = 14.0
	s.content_margin_top = 10.0
	s.content_margin_right = 14.0
	s.content_margin_bottom = 10.0
	return s


func _refresh_all() -> void:
	_subtitle.text = String(TuningStore.active_car_id).to_upper()
	_refresh_categories()
	_refresh_levels()


func _refresh_categories() -> void:
	for cat: String in _category_buttons:
		var level := int(TuningStore.parts_levels.get(cat, 0))
		var pips := ""
		for i in 3:
			pips += "●" if i < level else "○"
		var b: Button = _category_buttons[cat]
		b.text = "%s   %s" % [Lang.t("part.%s" % cat), pips]


func _refresh_levels() -> void:
	_level_desc.text = Lang.t("part.%s" % _active_category)
	var selected := int(TuningStore.parts_levels.get(_active_category, 0))
	for level in 4:
		var card: Button = _level_cards[level]
		card.text = "%s\n\n%s" % [
			TuningParts.level_label(_active_category, level),
			TuningParts.stat_line(_active_category, level),
		]
		var is_installed := level == selected
		card.add_theme_color_override("font_color", INK if is_installed else AMBER)
		card.add_theme_stylebox_override("normal", _pod_style(
			AMBER if is_installed else DIAL_FACE,
			Color(1.0, 0.85, 0.5) if is_installed else Color(0.2, 0.22, 0.26),
		))
	var cur := TuningParts.level_label(_active_category, selected)
	_stat_line.text = "%s: %s" % [Lang.t("part.%s" % _active_category), cur]


func _on_category(cat: String) -> void:
	_active_category = cat
	_refresh_levels()


func _on_level(level: int) -> void:
	TuningStore.set_part_level(_active_category, level)
	_refresh_categories()
	_refresh_levels()
