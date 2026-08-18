@tool
extends Node3D

## Car exterior lights. Place Marker3D under Headlights / BrakeLights / ReverseLights
## and move them in the inspector. Headlights: L. Brake/reverse follow pedals / gear.

@export var lights_on: bool = false:
	set(value):
		lights_on = value
		_apply_headlights()

@export_group("Headlights")
@export var head_color: Color = Color(1.0, 0.96, 0.85)
@export_range(0.0, 40.0, 0.1) var head_energy: float = 12.0
@export_range(5.0, 80.0, 0.5) var head_range: float = 35.0
@export_range(5.0, 70.0, 0.5) var head_spot_angle: float = 32.0
@export var head_fill_omni: bool = true
@export_range(0.0, 8.0, 0.1) var head_fill_energy: float = 1.2
@export_range(0.2, 4.0, 0.1) var head_fill_range: float = 1.6

@export_group("Brake lights")
@export var brake_color: Color = Color(1.0, 0.08, 0.05)
@export_range(0.0, 20.0, 0.1) var brake_energy: float = 6.0
@export_range(0.3, 8.0, 0.1) var brake_omni_range: float = 2.8
@export_range(0.0, 1.0, 0.05) var brake_threshold: float = 0.12
@export_range(0.0, 1.0, 0.05) var handbrake_threshold: float = 0.35

@export_group("Reverse lights")
@export var reverse_color: Color = Color(0.95, 0.95, 1.0)
@export_range(0.0, 16.0, 0.1) var reverse_energy: float = 4.5
@export_range(0.3, 8.0, 0.1) var reverse_omni_range: float = 2.4

@export_group("Input")
@export var toggle_keycode: Key = KEY_L

const GROUP_HEAD := "Headlights"
const GROUP_BRAKE := "BrakeLights"
const GROUP_REVERSE := "ReverseLights"

var _car: CarController
var _head_spots: Array[SpotLight3D] = []
var _head_fills: Array[OmniLight3D] = []
var _brake_lights: Array[OmniLight3D] = []
var _reverse_lights: Array[OmniLight3D] = []
var _brake_on: bool = false
var _reverse_on: bool = false


func _ready() -> void:
	_car = get_parent() as CarController
	add_to_group("car_lights")
	_ensure_groups_and_markers()
	_rebuild_all()
	_apply_headlights()
	_apply_brake_lights(false)
	_apply_reverse_lights(false)
	if not Engine.is_editor_hint():
		set_process_unhandled_input(true)
		set_physics_process(true)
	else:
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _car == null:
		return
	var want_brake := (
		_car.brake >= brake_threshold
		or _car.handbrake >= handbrake_threshold
	)
	if want_brake != _brake_on:
		_brake_on = want_brake
		_apply_brake_lights(_brake_on)

	var want_rev := _car.current_gear < 0
	if want_rev != _reverse_on:
		_reverse_on = want_rev
		_apply_reverse_lights(_reverse_on)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _car != null and not _car.occupied:
		return
	if not _is_toggle_pressed(event):
		return
	lights_on = not lights_on
	get_viewport().set_input_as_handled()


func toggle() -> void:
	lights_on = not lights_on


func _is_toggle_pressed(event: InputEvent) -> bool:
	if event.is_action_pressed("toggle_lights"):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).keycode == toggle_keycode
	return false


func _edited_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return self
	return tree.edited_scene_root if tree.edited_scene_root else self


func _ensure_group(group_name: String) -> Node3D:
	var node := get_node_or_null(group_name) as Node3D
	if node != null:
		return node
	node = Node3D.new()
	node.name = group_name
	add_child(node)
	if Engine.is_editor_hint():
		node.owner = _edited_root()
	return node


func _add_marker(parent: Node3D, marker_name: String, pos: Vector3) -> void:
	if parent.get_node_or_null(marker_name) != null:
		return
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	m.gizmo_extents = 0.18
	parent.add_child(m)
	if Engine.is_editor_hint():
		m.owner = _edited_root()


func _ensure_groups_and_markers() -> void:
	var head := _ensure_group(GROUP_HEAD)
	var brake := _ensure_group(GROUP_BRAKE)
	var rev := _ensure_group(GROUP_REVERSE)

	# Migrate legacy flat Left/Right markers into Headlights.
	for legacy_name: String in ["Left", "Right"]:
		var legacy := get_node_or_null(legacy_name)
		if legacy != null and legacy is Marker3D and legacy.get_parent() == self:
			var dest_name := legacy_name
			if head.get_node_or_null(dest_name) == null:
				remove_child(legacy)
				head.add_child(legacy)
				if Engine.is_editor_hint():
					legacy.owner = _edited_root()
			else:
				legacy.queue_free()

	if _markers_in(head).is_empty():
		_add_marker(head, "Left", Vector3(-0.72, 0.62, -1.85))
		_add_marker(head, "Right", Vector3(0.72, 0.62, -1.85))
	if _markers_in(brake).is_empty():
		_add_marker(brake, "Left", Vector3(-0.7, 0.7, 1.9))
		_add_marker(brake, "Right", Vector3(0.7, 0.7, 1.9))
	if _markers_in(rev).is_empty():
		_add_marker(rev, "Center", Vector3(0.0, 0.45, 1.95))


func _markers_in(group: Node) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	if group == null:
		return out
	for child in group.get_children():
		if child is Marker3D:
			out.append(child as Marker3D)
	return out


func _clear_light_children(marker: Marker3D) -> void:
	for old in marker.get_children():
		if old is Light3D:
			old.queue_free()


func _rebuild_all() -> void:
	_head_spots.clear()
	_head_fills.clear()
	_brake_lights.clear()
	_reverse_lights.clear()

	for marker in _markers_in(get_node_or_null(GROUP_HEAD)):
		_clear_light_children(marker)
		var spot := SpotLight3D.new()
		spot.name = "Spot"
		spot.shadow_enabled = false
		marker.add_child(spot)
		_head_spots.append(spot)
		if head_fill_omni:
			var fill := OmniLight3D.new()
			fill.name = "Fill"
			fill.shadow_enabled = false
			fill.position = Vector3(0.0, 0.0, 0.05)
			marker.add_child(fill)
			_head_fills.append(fill)

	for marker in _markers_in(get_node_or_null(GROUP_BRAKE)):
		_clear_light_children(marker)
		var omni := OmniLight3D.new()
		omni.name = "Brake"
		omni.shadow_enabled = false
		marker.add_child(omni)
		_brake_lights.append(omni)

	for marker in _markers_in(get_node_or_null(GROUP_REVERSE)):
		_clear_light_children(marker)
		var omni := OmniLight3D.new()
		omni.name = "Reverse"
		omni.shadow_enabled = false
		marker.add_child(omni)
		_reverse_lights.append(omni)


func _apply_headlights() -> void:
	if _head_spots.is_empty() and not _markers_in(get_node_or_null(GROUP_HEAD)).is_empty():
		_rebuild_all()
	for spot in _head_spots:
		if not is_instance_valid(spot):
			continue
		spot.light_color = head_color
		spot.light_energy = head_energy if lights_on else 0.0
		spot.spot_range = head_range
		spot.spot_angle = head_spot_angle
		spot.light_volumetric_fog_energy = 0.0
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = 20.0
		spot.distance_fade_length = 16.0
		spot.visible = lights_on
	for fill in _head_fills:
		if not is_instance_valid(fill):
			continue
		fill.light_color = head_color
		fill.light_energy = head_fill_energy if lights_on else 0.0
		fill.omni_range = head_fill_range
		fill.light_volumetric_fog_energy = 0.0
		fill.visible = lights_on


func _apply_brake_lights(on: bool) -> void:
	for omni in _brake_lights:
		if not is_instance_valid(omni):
			continue
		omni.light_color = brake_color
		omni.light_energy = brake_energy if on else 0.0
		omni.omni_range = brake_omni_range
		omni.visible = on


func _apply_reverse_lights(on: bool) -> void:
	for omni in _reverse_lights:
		if not is_instance_valid(omni):
			continue
		omni.light_color = reverse_color
		omni.light_energy = reverse_energy if on else 0.0
		omni.omni_range = reverse_omni_range
		omni.visible = on
