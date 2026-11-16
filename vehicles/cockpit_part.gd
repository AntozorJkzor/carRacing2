@tool
extends Node2D

## One cockpit picture (wheel or needle).
## Move and scale THIS node. Its origin is the point the picture will spin around.
## pivot_px is the pixel of Art's texture that stays on that origin.

@export var pivot_px: Vector2 = Vector2.ZERO:
	set(value):
		pivot_px = value
		_apply_pivot()


func _ready() -> void:
	_apply_pivot()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_pivot()


func _apply_pivot() -> void:
	var art := get_node_or_null("Art") as Sprite2D
	if art == null:
		return
	if art.centered:
		art.centered = false
	if art.position != Vector2.ZERO:
		art.position = Vector2.ZERO
	if art.rotation != 0.0:
		art.rotation = 0.0
	if art.scale != Vector2.ONE:
		art.scale = Vector2.ONE
	var want := -pivot_px
	if art.offset != want:
		art.offset = want
