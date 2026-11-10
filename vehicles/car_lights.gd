@tool
extends Node3D

const MinimapLayers := preload("res://rendering/minimap_layers.gd")

## Exterior lights.
## Headlights ON → one front SpotLight + one rear OmniLight, plus emission on lamp meshes.
## Brake (day or night) → emission only on taillights and the high-mount repeater. No brake Omni/Spot.

@export var lights_on: bool = false:
	set(value):
		lights_on = value
		_drive_popup()
		_apply_headlights()
		_apply_tail_mats()

@export_group("Headlights")
@export var head_color: Color = Color(1.0, 0.96, 0.85)
@export_range(0.0, 16.0, 0.1) var head_energy: float = 6.0
@export_range(4.0, 40.0, 0.5) var head_range: float = 18.0
@export_range(5.0, 50.0, 0.5) var head_spot_angle: float = 28.0
@export_range(0.0, 8.0, 0.1) var head_emission_energy: float = 2.4

@export_group("Tail / running lights")
@export var tail_color: Color = Color(0.85, 0.08, 0.05)
@export_range(0.0, 8.0, 0.1) var tail_energy: float = 2.2
@export_range(1.0, 20.0, 0.5) var tail_range: float = 6.0
@export_range(0.0, 8.0, 0.1) var tail_emission_energy: float = 1.1
## Wide rear beam for running lights + brake lights. Points straight back,
## so it does not spill under the car or into the cabin.
@export_range(30.0, 120.0, 1.0) var tail_spot_angle: float = 90.0

@export_group("Brake lights")
@export var brake_color: Color = Color(1.0, 0.08, 0.05)
@export_range(0.0, 8.0, 0.1) var brake_emission_energy: float = 3.6
## Brightness of the rear beam while braking (0 = emission only).
@export_range(0.0, 16.0, 0.1) var brake_light_energy: float = 4.5
@export_range(0.0, 1.0, 0.05) var brake_threshold: float = 0.12
@export_range(0.0, 1.0, 0.05) var handbrake_threshold: float = 0.35

@export_group("Reverse lights")
@export var reverse_color: Color = Color(0.95, 0.95, 1.0)
@export_range(0.0, 8.0, 0.1) var reverse_emission_energy: float = 2.0

@export_group("Popup headlights")
## AnimationPlayer is auto-detected under the car when it has both animations.
@export var popup_anim_path: NodePath = ^""
@export var popup_on_anim: StringName = &"light_on"
@export var popup_off_anim: StringName = &"light_off"
@export_range(0.5, 6.0, 0.1) var popup_speed: float = 2.5

@export_group("Input")
@export var toggle_keycode: Key = KEY_L

const GROUP_HEAD := "Headlights"
const GROUP_BRAKE := "BrakeLights"
const GROUP_REVERSE := "ReverseLights"

var _car: CarController
var _head_spot: SpotLight3D
var _tail_light: SpotLight3D
## Effective headlight output. For popup headlights it lags lights_on:
## the beam ignites when the open animation finishes and dies the moment
## the close animation starts.
var _head_beam_on: bool = false
var _head_mats: Array[StandardMaterial3D] = []
var _tail_mats: Array[StandardMaterial3D] = []
var _brake_mats: Array[StandardMaterial3D] = []
var _head_glows: Array[MeshInstance3D] = []
var _brake_glows: Array[MeshInstance3D] = []
var _reverse_glows: Array[MeshInstance3D] = []
var _brake_on: bool = false
var _reverse_on: bool = false
var _body_bound: bool = false
var _popup_ap: AnimationPlayer = null


func _ready() -> void:
	_car = get_parent() as CarController
	add_to_group("car_lights")
	_ensure_groups_and_markers()
	_bind_body_lamps()
	_resolve_popup_player()
	_reset_popup_to_closed()
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
	var want_brake: bool = (
		_car.brake >= brake_threshold
		or _car.handbrake >= handbrake_threshold
	)
	if want_brake != _brake_on:
		_brake_on = want_brake
		_apply_brake_lights(_brake_on)

	var want_rev: bool = _car.current_gear < 0
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

	for legacy_name: String in ["Left", "Right"]:
		var legacy := get_node_or_null(legacy_name)
		if legacy != null and legacy is Marker3D and legacy.get_parent() == self:
			if head.get_node_or_null(legacy_name) == null:
				remove_child(legacy)
				head.add_child(legacy)
				if Engine.is_editor_hint():
					legacy.owner = _edited_root()
			else:
				legacy.queue_free()

	if _markers_in(head).is_empty():
		_add_marker(head, "Center", Vector3(0.0, 0.62, -1.75))
	if _markers_in(brake).is_empty():
		_add_marker(brake, "Center", Vector3(0.0, 0.8, 1.7))
		_add_marker(brake, "High", Vector3(0.0, 1.05, 1.78))
	if _markers_in(rev).is_empty():
		_add_marker(rev, "Center", Vector3(0.0, 0.45, 1.75))


func _markers_in(group: Node) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	if group == null:
		return out
	for child in group.get_children():
		if child is Marker3D:
			out.append(child as Marker3D)
	return out


func _marker_centroid(markers: Array[Marker3D]) -> Vector3:
	if markers.is_empty():
		return Vector3.ZERO
	var mid := Vector3.ZERO
	for marker in markers:
		mid += marker.position
	return mid / float(markers.size())


func _clear_light_children(node: Node) -> void:
	if node == null:
		return
	var doomed: Array[Node] = []
	for old in node.get_children():
		if old is Light3D or old.name == "Glow":
			doomed.append(old)
	for old in doomed:
		node.remove_child(old)
		old.free()


func _bind_body_lamps() -> void:
	if _body_bound or Engine.is_editor_hint():
		return
	_body_bound = true
	_head_mats.clear()
	_tail_mats.clear()
	_brake_mats.clear()
	var car := get_parent()
	if car == null:
		return
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or mesh.name == "Glow":
			continue
		for surface in mesh.mesh.get_surface_count():
			var kind := _lamp_kind(mesh, surface)
			if kind.is_empty():
				continue
			var mat := _override_standard(mesh, surface)
			if mat == null:
				continue
			match kind:
				"head":
					_head_mats.append(mat)
				"tail":
					_tail_mats.append(mat)
				"brake":
					_brake_mats.append(mat)


func _lamp_kind(mesh: MeshInstance3D, surface: int) -> String:
	var mat := mesh.get_active_material(surface)
	var blob := mesh.name.to_lower()
	if mat != null and not mat.resource_name.is_empty():
		blob += " " + mat.resource_name.to_lower()
	if (
		"housing" in blob
		or "корпус" in blob
		or "поворот" in blob
		or "turnsignal" in blob
		or "turn_signal" in blob
		or "amber" in blob
		or "trim" in blob
		or "body |" in blob
	):
		return ""

	var is_repeater := (
		"backdouble" in blob
		or "doublelight" in blob
		or "third" in blob
		or "chmsl" in blob
		or "highmount" in blob
		or "high_mount" in blob
		or "повторител" in blob
	)
	var is_tail_mat := (
		"taillight" in blob
		or "tail_light" in blob
		or "tail-light" in blob
		or "mat_taillight" in blob
	)
	var is_tail_mesh := (
		"backlight" in blob
		or "back_light" in blob
		or "фонар" in blob
	)
	var is_head := (
		"фар" in blob
		or "headlight" in blob
		or "head_light" in blob
		or "frontlight" in blob
		or "front_light" in blob
	)

	if is_repeater and (is_tail_mat or "red" in blob):
		return "brake"
	if is_head and ("glass" in blob or "стекл" in blob or "headlight" in blob):
		return "head"
	if is_tail_mat or is_tail_mesh:
		return "tail"
	return ""


func _override_standard(mesh: MeshInstance3D, surface: int) -> StandardMaterial3D:
	var active := mesh.get_active_material(surface)
	if active == null or not (active is StandardMaterial3D):
		return null
	var copy := (active as StandardMaterial3D).duplicate() as StandardMaterial3D
	## Keep lamp glass in the opaque pass so particles (smoke) can cover them.
	copy.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var albedo := copy.albedo_color
	albedo.a = 1.0
	copy.albedo_color = albedo
	copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	copy.no_depth_test = false
	mesh.set_surface_override_material(surface, copy)
	return copy


func _rebuild_all() -> void:
	_head_spot = null
	_tail_light = null
	_head_glows.clear()
	_brake_glows.clear()
	_reverse_glows.clear()

	var use_head_quads := _head_mats.is_empty()
	var use_tail_quads := _tail_mats.is_empty() and _brake_mats.is_empty()

	var head_group := get_node_or_null(GROUP_HEAD) as Node3D
	var head_markers := _markers_in(head_group)
	for marker in head_markers:
		_clear_light_children(marker)
		if use_head_quads:
			_head_glows.append(_make_glow(marker, head_color, Vector2(0.28, 0.12), true))
	if head_group != null:
		_clear_light_children(head_group)
		var spot := SpotLight3D.new()
		spot.name = "Spot"
		spot.layers = MinimapLayers.LIGHTS
		spot.shadow_enabled = false
		spot.position = _marker_centroid(head_markers)
		head_group.add_child(spot)
		_head_spot = spot

	var brake_group := get_node_or_null(GROUP_BRAKE) as Node3D
	var brake_markers := _markers_in(brake_group)
	for marker in brake_markers:
		_clear_light_children(marker)
		if use_tail_quads:
			_brake_glows.append(_make_glow(marker, brake_color, Vector2(0.22, 0.1), false))
	if brake_group != null:
		_clear_light_children(brake_group)
		var rear_spot := SpotLight3D.new()
		rear_spot.name = "RearSpot"
		rear_spot.layers = MinimapLayers.LIGHTS
		rear_spot.shadow_enabled = false
		rear_spot.rotation.y = PI
		rear_spot.spot_angle = tail_spot_angle
		rear_spot.position = _marker_centroid(brake_markers)
		brake_group.add_child(rear_spot)
		_tail_light = rear_spot

	for marker in _markers_in(get_node_or_null(GROUP_REVERSE)):
		_clear_light_children(marker)
		if use_tail_quads:
			_reverse_glows.append(_make_glow(marker, reverse_color, Vector2(0.16, 0.08), false))


func _make_glow(marker: Marker3D, color: Color, size: Vector2, face_forward: bool) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Glow"
	mesh_node.mesh = quad
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh_node.layers = MinimapLayers.EFFECTS
	if face_forward:
		mesh_node.rotation.y = PI
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.albedo_color = color
	mat.emission_energy_multiplier = head_emission_energy
	mesh_node.material_override = mat
	mesh_node.visible = false
	marker.add_child(mesh_node)
	return mesh_node


func _set_emission(mat: StandardMaterial3D, color: Color, energy: float, on: bool) -> void:
	if mat == null:
		return
	mat.emission_enabled = on
	mat.emission = color
	mat.emission_energy_multiplier = energy if on else 0.0


func _apply_headlights() -> void:
	if _head_spot == null and not _markers_in(get_node_or_null(GROUP_HEAD)).is_empty():
		_rebuild_all()
	if is_instance_valid(_head_spot):
		_head_spot.light_color = head_color
		_head_spot.light_energy = head_energy if _head_beam_on else 0.0
		_head_spot.spot_range = head_range
		_head_spot.spot_angle = head_spot_angle
		_head_spot.light_specular = 0.25
		_head_spot.light_volumetric_fog_energy = 0.0
		_head_spot.shadow_enabled = false
		_head_spot.distance_fade_enabled = true
		_head_spot.distance_fade_begin = 12.0
		_head_spot.distance_fade_length = 8.0
		_head_spot.visible = _head_beam_on
	for mat in _head_mats:
		_set_emission(mat, head_color, head_emission_energy, _head_beam_on)
	for glow in _head_glows:
		if is_instance_valid(glow):
			glow.visible = _head_beam_on
	_apply_rear_light()


## Brake-aware rear beam: bright wide beam while braking, dim when running
## lights are on, off otherwise. Shares one SpotLight3D pointing backwards.
func _apply_rear_light() -> void:
	if not is_instance_valid(_tail_light):
		return
	var braking := _brake_on or _reverse_on
	var energy := 0.0
	var color := tail_color
	if _brake_on:
		energy = brake_light_energy
		color = brake_color
	elif _reverse_on:
		energy = tail_energy * 0.6
		color = reverse_color
	elif lights_on:
		energy = tail_energy
	_tail_light.light_color = color
	_tail_light.light_energy = energy
	_tail_light.spot_range = tail_range
	_tail_light.spot_angle = tail_spot_angle
	_tail_light.light_specular = 0.15
	_tail_light.shadow_enabled = false
	_tail_light.distance_fade_enabled = true
	_tail_light.distance_fade_begin = 8.0
	_tail_light.distance_fade_length = 5.0
	_tail_light.visible = energy > 0.0


func _resolve_popup_player() -> void:
	_popup_ap = null
	var car := get_parent()
	if car == null:
		return
	if popup_anim_path != ^"":
		var ap := car.get_node_or_null(popup_anim_path) as AnimationPlayer
		if ap != null:
			_popup_ap = ap
			return
	for node in car.find_children("*", "AnimationPlayer", true, false):
		var candidate := node as AnimationPlayer
		if candidate.has_animation(popup_on_anim) and candidate.has_animation(popup_off_anim):
			_popup_ap = candidate
			if not candidate.animation_finished.is_connected(_on_popup_animation_finished):
				candidate.animation_finished.connect(_on_popup_animation_finished)
			return


## Headlights start closed: snap the hinge to the end of the close animation.
func _reset_popup_to_closed() -> void:
	if Engine.is_editor_hint() or _popup_ap == null:
		return
	if not _popup_ap.has_animation(popup_off_anim):
		return
	_popup_ap.play(popup_off_anim)
	_popup_ap.seek(_popup_ap.get_animation(popup_off_anim).length, true)
	_popup_ap.pause()


## Popup timing: turning ON ignites the beam only when the cover is fully
## open; turning OFF kills the beam the instant the cover starts closing.
func _drive_popup() -> void:
	if Engine.is_editor_hint() or _popup_ap == null:
		_head_beam_on = lights_on
		return
	var anim: StringName = popup_on_anim if lights_on else popup_off_anim
	if not _popup_ap.has_animation(anim):
		_head_beam_on = lights_on
		return
	_head_beam_on = false
	_play_popup(lights_on)


func _play_popup(on: bool) -> void:
	if Engine.is_editor_hint() or _popup_ap == null:
		return
	var anim: StringName = popup_on_anim if on else popup_off_anim
	if _popup_ap.has_animation(anim):
		_popup_ap.play(anim, -1.0, popup_speed)


func _on_popup_animation_finished(anim_name: StringName) -> void:
	if anim_name == popup_on_anim and lights_on:
		_head_beam_on = true
		_apply_headlights()


func _apply_brake_lights(on: bool) -> void:
	for glow in _brake_glows:
		if is_instance_valid(glow):
			glow.visible = on
	_apply_tail_mats()
	_apply_rear_light()


func _apply_reverse_lights(on: bool) -> void:
	for glow in _reverse_glows:
		if is_instance_valid(glow):
			glow.visible = on
	_apply_tail_mats()
	_apply_rear_light()


func _apply_tail_mats() -> void:
	## Running tails glow with headlights; brake/repeater are emission-only (brighter when braking).
	for mat in _tail_mats:
		if _brake_on:
			_set_emission(mat, brake_color, brake_emission_energy, true)
		elif _reverse_on:
			_set_emission(mat, reverse_color, reverse_emission_energy, true)
		elif lights_on:
			_set_emission(mat, tail_color, tail_emission_energy, true)
		else:
			_set_emission(mat, tail_color, 0.0, false)

	for mat in _brake_mats:
		_set_emission(mat, brake_color, brake_emission_energy, _brake_on)
