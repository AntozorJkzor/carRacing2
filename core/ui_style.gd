class_name UiStyle
extends RefCounted

## TOUGE 95 — night-touge UI theme: indigo night, amber lanterns, red accent.
## Shared palette + style factories; every screen restyles through here.

const NIGHT_TOP := Color(0.02, 0.027, 0.063)
const NIGHT_BOTTOM := Color(0.075, 0.105, 0.23)
const PANEL := Color(0.045, 0.055, 0.095, 0.94)
const PANEL_FACE := Color(0.07, 0.085, 0.13)
const AMBER := Color(1.0, 0.63, 0.24)
const AMBER_HOT := Color(1.0, 0.8, 0.47)
const AMBER_DIM := Color(0.82, 0.48, 0.17)
const RED := Color(0.9, 0.23, 0.21)
const CHROME := Color(0.93, 0.94, 0.97)
const LCD_GREEN := Color(0.55, 0.95, 0.6)
const INK := Color(0.05, 0.06, 0.09)


## Vertical night-sky gradient texture (deep indigo, slightly lighter low).
static func night_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([NIGHT_TOP, NIGHT_BOTTOM])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 4
	t.height = 512
	return t


## Swap a ColorRect for a TextureRect with the night gradient, in place.
static func night_sky(rect: ColorRect) -> void:
	var parent := rect.get_parent()
	if parent == null:
		return
	var idx := rect.get_index()
	var tr := TextureRect.new()
	tr.name = rect.name
	tr.texture = night_gradient()
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.remove_child(rect)
	parent.add_child(tr)
	parent.move_child(tr, idx)
	rect.free()


static func panel_style(bg: Color = PANEL, border: Color = AMBER_DIM, radius: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_right = radius
	s.corner_radius_bottom_left = radius
	s.shadow_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.16)
	s.shadow_size = 14
	return s


## One call restyles a Button into a lantern-lit touge control.
static func button(b: Button, accent: Color = AMBER, font_size: int = 20) -> void:
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", AMBER_HOT)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", AMBER_HOT)
	b.add_theme_stylebox_override("normal", pod_style(PANEL_FACE, Color(0.22, 0.24, 0.3)))
	b.add_theme_stylebox_override("hover", pod_style(Color(0.11, 0.13, 0.19), AMBER_DIM))
	b.add_theme_stylebox_override("pressed", pod_style(accent, AMBER_HOT))
	b.add_theme_stylebox_override("focus", pod_style(PANEL_FACE, accent))


## Flat pod (gauge-face look) used by buttons, cards and category rows.
static func pod_style(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_right = radius
	s.corner_radius_bottom_left = radius
	s.content_margin_left = 14.0
	s.content_margin_top = 10.0
	s.content_margin_right = 14.0
	s.content_margin_bottom = 10.0
	return s


## Headline label: chrome fill, dark outline, soft amber shadow.
static func headline(text: String, size: int = 44) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CHROME)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04))
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_shadow_color", Color(AMBER.r, AMBER.g, AMBER.b, 0.4))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Restyle an existing Label into a headline (chrome + dark outline + glow).
static func headline_style(l: Label, size: int = 44) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CHROME)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04))
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_shadow_color", Color(AMBER.r, AMBER.g, AMBER.b, 0.4))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_size", 10)


## Amber section header style for an existing label.
static func section_label_style(l: Label, size: int = 22) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", AMBER)
	l.add_theme_color_override("font_shadow_color", Color(AMBER.r, AMBER.g, AMBER.b, 0.4))
	l.add_theme_constant_override("shadow_size", 6)


## Amber section label (menu titles, group headers).
static func section_label(text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", AMBER)
	l.add_theme_color_override("font_shadow_color", Color(AMBER.r, AMBER.g, AMBER.b, 0.4))
	l.add_theme_constant_override("shadow_size", 6)
	return l


## Small green LCD readout.
static func lcd_label(text: String, size: int = 15) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", LCD_GREEN)
	return l


## Restyle an existing label into a green LCD readout.
static func lcd_label_style(l: Label, size: int = 15) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", LCD_GREEN)
