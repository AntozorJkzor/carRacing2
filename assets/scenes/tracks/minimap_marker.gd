extends Control

@export var marker_color: Color = Color(1.0, 0.35, 0.2, 1.0)
@export var outline_color: Color = Color(0.05, 0.06, 0.08, 0.9)

var _heading: float = 0.0


func _ready() -> void:
	_update_pivot()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_pivot()


func set_heading(yaw: float) -> void:
	_heading = yaw
	rotation = yaw
	queue_redraw()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _draw() -> void:
	var c := size * 0.5
	var tip := c + Vector2(0.0, -9.0)
	var left := c + Vector2(-7.0, 7.0)
	var right := c + Vector2(7.0, 7.0)
	var tri := PackedVector2Array([tip, left, right])
	draw_colored_polygon(tri, marker_color)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), outline_color, 2.0, true)
