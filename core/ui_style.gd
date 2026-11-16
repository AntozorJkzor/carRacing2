class_name UiStyle
extends RefCounted

## TOUGE 95 menu chrome: full-bleed key art, borderless type, amber only on hover.

const NIGHT_TOP := Color(0.02, 0.027, 0.063)
const NIGHT_BOTTOM := Color(0.075, 0.105, 0.23)
const PANEL := Color(0.012, 0.016, 0.028, 0.62)
const PANEL_FACE := Color(1, 1, 1, 0.045)
const AMBER := Color(1.0, 0.63, 0.24)
const AMBER_HOT := Color(1.0, 0.82, 0.5)
const AMBER_DIM := Color(0.82, 0.48, 0.17)
const RED := Color(0.9, 0.23, 0.21)
const CHROME := Color(0.94, 0.95, 0.97)
const LCD_GREEN := Color(0.62, 0.95, 0.7)
const INK := Color(0.05, 0.06, 0.09)
const MUTED := Color(0.72, 0.76, 0.82)

const ART_PATH := "res://assets/ui/menu_bg.jpg"
const LOGO_PATH := "res://assets/ui/logo.jpg"

static var _theme: Theme
static var _logo_tex: Texture2D
static var _art_tex: Texture2D


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


## Full-bleed key art plus a left-weighted scrim so type stays readable.
static func mount_art(root: Node, veil: float = 0.22) -> void:
	if root.get_node_or_null("MenuArt") != null:
		return
	var old := root.get_node_or_null("Background")
	if old is CanvasItem:
		(old as CanvasItem).visible = false
	var art := TextureRect.new()
	art.name = "MenuArt"
	art.texture = _art()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art)
	root.move_child(art, 0)
	var scrim := TextureRect.new()
	scrim.name = "MenuScrim"
	scrim.texture = _scrim()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)
	root.move_child(scrim, 1)
	var dim := ColorRect.new()
	dim.name = "MenuVeil"
	dim.color = Color(0.01, 0.014, 0.03, clampf(veil, 0.0, 0.85))
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	root.move_child(dim, 2)


## Settings pages: art, then roomier margins than the old form.
static func prepare_page(root: Control, veil: float = 0.5) -> void:
	mount_art(root, veil)
	var margin := root.get_node_or_null("Margin") as MarginContainer
	if margin == null:
		return
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 28)


## Pull a centered card out into a left column and drop its frame.
static func dock_left(panel: PanelContainer, left: float = 72.0, width: float = 0.42, from_top: bool = false) -> void:
	var center := panel.get_parent()
	var host := center.get_parent()
	if host == null:
		return
	panel.reparent(host)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_right = width
	panel.offset_left = left
	panel.offset_top = 72.0 if from_top else 28.0
	panel.offset_right = -8.0
	panel.offset_bottom = -28.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 4.0
	clear.content_margin_top = 8.0
	clear.content_margin_right = 12.0
	clear.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", clear)
	if center is CanvasItem:
		(center as CanvasItem).visible = false
	var box := _first_vbox(panel)
	if box != null:
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.alignment = BoxContainer.ALIGNMENT_BEGIN if from_top else BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 8)
	_align_labels(panel)


static func panel_style(bg: Color = PANEL, border: Color = Color(1, 1, 1, 0.08), radius: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 18
	s.content_margin_left = 22.0
	s.content_margin_top = 16.0
	s.content_margin_right = 22.0
	s.content_margin_bottom = 16.0
	return s


## Borderless row. Compact controls (arrows) stay centered chips.
static func button(b: Button, accent: Color = AMBER, font_size: int = 20) -> void:
	if b is OptionButton:
		return
	var compact := b.custom_minimum_size.x > 0.0 and b.custom_minimum_size.x <= 96.0
	if compact:
		_chip(b, font_size)
		return
	var align := HORIZONTAL_ALIGNMENT_CENTER if b.get_parent() is HBoxContainer else HORIZONTAL_ALIGNMENT_LEFT
	_item(b, accent, font_size, align)


static func set_active(b: Button, on: bool) -> void:
	var normal := _item_box(3 if on else 0, Color(1, 0.72, 0.28, 0.10) if on else Color(0, 0, 0, 0))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_color_override("font_color", AMBER_HOT if on else CHROME)


static func headline(text: String, size: int = 44) -> Label:
	var l := Label.new()
	l.text = text
	headline_style(l, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


static func headline_style(l: Label, size: int = 44) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CHROME)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_size", 8)


static func section_label_style(l: Label, size: int = 22) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CHROME)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_size", 4)


static func section_label(text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", AMBER)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_size", 0)
	return l


static func lcd_label(text: String, size: int = 15) -> Label:
	var l := Label.new()
	l.text = text
	lcd_label_style(l, size)
	return l


static func lcd_label_style(l: Label, size: int = 15) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", LCD_GREEN)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_size", 0)


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var th := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI Variable Display", "Segoe UI"])
	font.font_weight = 500
	th.default_font = font
	th.default_font_size = 16
	th.set_color("font_color", "Label", CHROME)
	th.set_color("font_color", "Button", CHROME)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(1, 1, 1, 0.14)
	slider.set_border_width_all(0)
	slider.set_corner_radius_all(2)
	slider.content_margin_top = 1.0
	slider.content_margin_bottom = 1.0
	var fill := slider.duplicate() as StyleBoxFlat
	fill.bg_color = AMBER
	th.set_stylebox("slider", "HSlider", slider)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var dot := _dot(CHROME, 12)
	var dot_hot := _dot(AMBER_HOT, 14)
	th.set_icon("grabber", "HSlider", dot)
	th.set_icon("grabber_highlight", "HSlider", dot_hot)
	th.set_constant("center_grabber", "HSlider", 1)
	var opt := _field(false)
	var opt_hot := _field(true)
	th.set_stylebox("normal", "OptionButton", opt)
	th.set_stylebox("hover", "OptionButton", opt_hot)
	th.set_stylebox("pressed", "OptionButton", opt_hot)
	th.set_stylebox("focus", "OptionButton", opt_hot)
	th.set_color("font_color", "OptionButton", CHROME)
	th.set_color("font_hover_color", "OptionButton", AMBER_HOT)
	th.set_color("font_pressed_color", "OptionButton", CHROME)
	th.set_color("font_focus_color", "OptionButton", CHROME)
	th.set_stylebox("panel", "PopupMenu", panel_style(Color(0.03, 0.04, 0.07, 0.96), Color(1, 1, 1, 0.08), 10))
	th.set_color("font_color", "PopupMenu", CHROME)
	th.set_color("font_hover_color", "PopupMenu", AMBER_HOT)
	var pop_hover := StyleBoxFlat.new()
	pop_hover.bg_color = Color(1, 1, 1, 0.08)
	pop_hover.set_corner_radius_all(4)
	pop_hover.content_margin_left = 8.0
	pop_hover.content_margin_right = 8.0
	th.set_stylebox("hover", "PopupMenu", pop_hover)
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.12)
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.08)
	bar_bg.set_corner_radius_all(2)
	bar_bg.content_margin_top = 2.0
	bar_bg.content_margin_bottom = 2.0
	var bar_fill := bar_bg.duplicate() as StyleBoxFlat
	bar_fill.bg_color = AMBER
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fill)
	th.set_color("font_color", "ProgressBar", CHROME)
	var on_switch := _switch(true)
	var off_switch := _switch(false)
	for control in ["CheckButton", "CheckBox"]:
		th.set_icon("checked", control, on_switch)
		th.set_icon("unchecked", control, off_switch)
		th.set_icon("checked_disabled", control, on_switch)
		th.set_icon("unchecked_disabled", control, off_switch)
		th.set_color("font_color", control, CHROME)
		th.set_color("font_hover_color", control, AMBER_HOT)
	_theme = th
	return th


static func dress(node: Node) -> void:
	if node is Control:
		(node as Control).theme = theme()
	_dress_panels(node)


static func _dress_panels(node: Node) -> void:
	if node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", panel_style())
	for child in node.get_children():
		_dress_panels(child)


## Wordmark with the black plate keyed out. Width is the on-screen size.
static func logo_mark(width: float = 460.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(width, width * 0.22)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = _logo()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func logo_block(size: int = 60) -> Control:
	return logo_mark(size * 7.2)


static func fill_tabs(bar: HBoxContainer, entries: Array, active_id: String, on_pick: Callable) -> void:
	# The click that rebuilds the bar is still emitting. free() on that button
	# errors ("object is locked"); drop it from the bar and delete next idle frame.
	for child in bar.get_children():
		bar.remove_child(child)
		child.queue_free()
	bar.add_theme_constant_override("separation", 0)
	for entry in entries:
		var id := String(entry["id"])
		var b := Button.new()
		b.text = String(entry["text"])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_paint_tab(b, id == active_id)
		b.pressed.connect(on_pick.bind(id))
		bar.add_child(b)


static func _paint_tab(b: Button, on: bool) -> void:
	b.add_theme_font_size_override("font_size", 16)
	var idle := _tab_box(AMBER if on else Color(1, 1, 1, 0.0))
	var hover := _tab_box(AMBER_HOT if on else Color(1, 1, 1, 0.28))
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", idle)
	b.add_theme_color_override("font_color", CHROME if on else MUTED)
	b.add_theme_color_override("font_hover_color", AMBER_HOT)
	b.add_theme_color_override("font_pressed_color", CHROME)


static func _tab_box(line: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = line
	s.set_border_width_all(0)
	s.border_width_bottom = 2
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 8.0
	return s


static func _item(b: Button, accent: Color, font_size: int, align: HorizontalAlignment) -> void:
	var bar := AMBER if accent != RED else Color(0.95, 0.38, 0.32)
	b.alignment = align
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", CHROME)
	b.add_theme_color_override("font_hover_color", AMBER_HOT)
	b.add_theme_color_override("font_pressed_color", CHROME)
	b.add_theme_color_override("font_focus_color", AMBER_HOT)
	b.add_theme_stylebox_override("normal", _item_box(0, Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", _item_box(3, Color(1, 1, 1, 0.06), bar))
	b.add_theme_stylebox_override("pressed", _item_box(3, Color(1, 0.7, 0.3, 0.1), bar))
	b.add_theme_stylebox_override("focus", _item_box(3, Color(1, 1, 1, 0.04), bar))


static func _item_box(bar_px: int, bg: Color, bar_color: Color = AMBER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = bar_color
	s.set_border_width_all(0)
	s.border_width_left = bar_px
	s.content_margin_left = 18.0
	s.content_margin_right = 14.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_right = 8
	return s


static func _chip(b: Button, font_size: int) -> void:
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", font_size + 6)
	b.add_theme_color_override("font_color", CHROME)
	b.add_theme_color_override("font_hover_color", AMBER_HOT)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_focus_color", AMBER_HOT)
	b.add_theme_stylebox_override("normal", _pill(Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", _pill(Color(1, 1, 1, 0.08)))
	b.add_theme_stylebox_override("pressed", _pill(Color(1, 0.7, 0.3, 0.16)))
	b.add_theme_stylebox_override("focus", _pill(Color(1, 1, 1, 0.06)))


static func _pill(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(0)
	s.set_corner_radius_all(22)
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


static func _field(hot: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.05 if not hot else 0.08)
	s.border_color = AMBER if hot else Color(1, 1, 1, 0.14)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14.0
	s.content_margin_top = 6.0
	s.content_margin_right = 10.0
	s.content_margin_bottom = 6.0
	return s


static func _switch(on: bool) -> ImageTexture:
	var w := 36
	var h := 18
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var track := AMBER if on else Color(0.22, 0.24, 0.3)
	var knob := INK if on else CHROME
	var knob_x := 22 if on else 4
	for y in h:
		for x in w:
			var cy := y - 8
			var left := x - 8
			var right := x - (w - 9)
			var in_cap := (left * left + cy * cy <= 64 and x < 10) or (right * right + cy * cy <= 64 and x > w - 11)
			var in_body := x >= 8 and x < w - 8 and absi(cy) <= 8
			if in_cap or in_body:
				img.set_pixel(x, y, track)
			var kx := x - knob_x
			if kx * kx + cy * cy <= 25:
				img.set_pixel(x, y, knob)
	return ImageTexture.create_from_image(img)


static func _dot(color: Color, diameter: int) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := diameter * 0.5
	var radius := center - 1.0
	for y in diameter:
		for x in diameter:
			var dx := float(x) + 0.5 - center
			var dy := float(y) + 0.5 - center
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


static func _file_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var loaded := load(path) as Texture2D
		if loaded != null:
			return loaded
	var img := Image.new()
	var abs_path := ProjectSettings.globalize_path(path)
	if img.load(abs_path) != OK:
		push_error("UiStyle: missing %s" % path)
		return null
	return ImageTexture.create_from_image(img)


static func art_texture() -> Texture2D:
	return _art()


static func _art() -> Texture2D:
	if _art_tex == null:
		_art_tex = _file_texture(ART_PATH)
	return _art_tex


static func _logo() -> Texture2D:
	if _logo_tex != null:
		return _logo_tex
	var src := _file_texture(LOGO_PATH)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	img.convert(Image.FORMAT_RGBA8)
	var min_x := img.get_width()
	var min_y := img.get_height()
	var max_x := 0
	var max_y := 0
	var step := 2
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) > 0.07:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x <= min_x or max_y <= min_y:
		_logo_tex = src
		return _logo_tex
	var pad := 12
	var rect := Rect2i(min_x - pad, min_y - pad, max_x - min_x + pad * 2, max_y - min_y + pad * 2)
	rect = rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var cropped := img.get_region(rect)
	for y in cropped.get_height():
		for x in cropped.get_width():
			var c := cropped.get_pixel(x, y)
			var l := maxf(c.r, maxf(c.g, c.b))
			var a := _smooth(0.05, 0.2, l)
			cropped.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	_logo_tex = ImageTexture.create_from_image(cropped)
	return _logo_tex


static func _scrim() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(0.008, 0.012, 0.028, 0.82),
		Color(0.008, 0.012, 0.028, 0.42),
		Color(0.004, 0.008, 0.016, 0.08),
	])
	g.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0.5)
	t.fill_to = Vector2(1, 0.5)
	t.width = 512
	t.height = 4
	return t


static func _smooth(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _first_vbox(n: Node) -> VBoxContainer:
	if n is VBoxContainer:
		return n
	for child in n.get_children():
		var found := _first_vbox(child)
		if found != null:
			return found
	return null


static func _align_labels(n: Node) -> void:
	if n is Label:
		(n as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for child in n.get_children():
		_align_labels(child)
