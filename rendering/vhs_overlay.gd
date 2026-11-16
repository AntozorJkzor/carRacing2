extends CanvasLayer

## Fullscreen tape grade. Drawn above the game and the menus, clicks pass through.

var _rect: ColorRect


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://rendering/vhs.gdshader")
	_rect.material = mat
	add_child(_rect)
	apply()


func apply() -> void:
	visible = GraphicsConfig.vhs_enabled
