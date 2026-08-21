class_name SkidMarkBaker
extends Node

## Paints a persistent skid map and shows it on a separate overlay mesh.
## Ground asphalt keeps its own StandardMaterial3D (normal lighting).
## Add to the track scene (e.g. PhysicsTestTrack/SkidMarkBaker).

const GROUP := &"skid_mark_baker"
const OVERLAY_SHADER := "res://assets/materials/track/skid_overlay.gdshader"

@export var ground_mesh_path: NodePath = NodePath("../Ground/Plane")
@export_range(64.0, 4000.0, 1.0) var world_size: float = 512.0
@export_range(256, 4096, 256) var resolution: int = 4096
@export_range(0.01, 0.5, 0.01) var upload_interval: float = 0.05
## Minimum brush half-width in pixels (keeps marks visible without fat blobs).
@export_range(0.5, 3.0, 0.05) var min_radius_px: float = 1.35
@export_range(0.001, 0.05, 0.001) var overlay_height: float = 0.015
@export var rubber_color: Color = Color(0.025, 0.022, 0.02, 1)
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0
@export_range(0.0, 1.0, 0.01) var light_response: float = 0.35

var _image: Image
var _texture: ImageTexture
var _shader_mat: ShaderMaterial
var _overlay: MeshInstance3D
var _bytes: PackedByteArray
var _dirty: bool = false
var _upload_left: float = 0.0
var _half_world: float = 256.0
var _res_f: float = 4096.0
var _meters_per_px: float = 0.125


func _ready() -> void:
	add_to_group(GROUP)
	_half_world = world_size * 0.5
	_res_f = float(resolution)
	_meters_per_px = world_size / _res_f
	_image = Image.create(resolution, resolution, false, Image.FORMAT_R8)
	_image.fill(Color(0, 0, 0, 1))
	_bytes = _image.get_data()
	_texture = ImageTexture.create_from_image(_image)
	_restore_ground_material()
	_setup_overlay()
	set_process(true)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_upload_left -= delta
	if _upload_left > 0.0:
		return
	_upload_left = upload_interval
	_flush_texture()
	_dirty = false


func get_skid_texture() -> Texture2D:
	return _texture


func clear_marks() -> void:
	if _bytes.is_empty():
		return
	_bytes.fill(0)
	_dirty = true
	_upload_left = 0.0


## Stamp a rubber segment in world space. Strength 0..1 darkens the road.
func stamp_segment(from_world: Vector3, to_world: Vector3, half_width_m: float, strength: float) -> void:
	if _bytes.is_empty():
		return
	var a := _world_to_pixel(from_world)
	var b := _world_to_pixel(to_world)
	var radius_px := maxf(half_width_m / maxf(_meters_per_px, 0.0001), min_radius_px)
	var ink := clampf(strength, 0.0, 1.0)
	var delta := b - a
	var dist := delta.length()
	var step := maxf(radius_px * 0.55, 0.35)
	var steps := maxi(int(ceil(dist / step)), 1)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		_stamp_disk(p.x, p.y, radius_px, ink)
	_dirty = true


func _flush_texture() -> void:
	_image.set_data(resolution, resolution, false, Image.FORMAT_R8, _bytes)
	_texture.set_image(_image)


func _world_to_pixel(world: Vector3) -> Vector2:
	var u := (world.x + _half_world) / world_size
	var v := (world.z + _half_world) / world_size
	return Vector2(u * (_res_f - 1.0), v * (_res_f - 1.0))


func _stamp_disk(cx: float, cy: float, radius: float, ink: float) -> void:
	var r_i := int(ceil(radius))
	var x0 := clampi(int(floor(cx)) - r_i, 0, resolution - 1)
	var x1 := clampi(int(ceil(cx)) + r_i, 0, resolution - 1)
	var y0 := clampi(int(floor(cy)) - r_i, 0, resolution - 1)
	var y1 := clampi(int(ceil(cy)) + r_i, 0, resolution - 1)
	var r2 := radius * radius
	var ink_u := int(clampf(ink, 0.0, 1.0) * 255.0)
	for y in range(y0, y1 + 1):
		var row := y * resolution
		var dy := float(y) + 0.5 - cy
		var dy2 := dy * dy
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var d2 := dx * dx + dy2
			if d2 > r2:
				continue
			var falloff := 1.0 - sqrt(d2) / maxf(radius, 0.001)
			falloff = falloff * falloff * (0.35 + 0.65 * falloff)
			var add := int(float(ink_u) * falloff)
			if add <= 0:
				continue
			var idx := row + x
			var cur := int(_bytes[idx])
			var nxt := cur + add - ((cur * add) >> 8)
			if nxt > cur:
				_bytes[idx] = mini(nxt, 255) as int


func _resolve_ground_mesh() -> MeshInstance3D:
	var mesh_inst := get_node_or_null(ground_mesh_path) as MeshInstance3D
	if mesh_inst != null:
		return mesh_inst
	if get_parent() != null:
		mesh_inst = get_parent().get_node_or_null(ground_mesh_path) as MeshInstance3D
		if mesh_inst != null:
			return mesh_inst
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null:
		mesh_inst = scene.get_node_or_null(NodePath("Ground/Plane")) as MeshInstance3D
	return mesh_inst


func _restore_ground_material() -> void:
	var mesh_inst := _resolve_ground_mesh()
	if mesh_inst == null:
		return
	# Previous versions overwrote asphalt with a combined shader — put lighting back.
	mesh_inst.material_override = null


func _setup_overlay() -> void:
	var shader := load(OVERLAY_SHADER) as Shader
	if shader == null:
		push_warning("SkidMarkBaker: missing skid_overlay.gdshader")
		return

	var plane := PlaneMesh.new()
	plane.size = Vector2(world_size, world_size)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("skid_tex", _texture)
	_shader_mat.set_shader_parameter("rubber_color", Vector3(rubber_color.r, rubber_color.g, rubber_color.b))
	_shader_mat.set_shader_parameter("opacity", opacity)
	_shader_mat.set_shader_parameter("light_response", light_response)

	_overlay = MeshInstance3D.new()
	_overlay.name = "SkidOverlay"
	_overlay.mesh = plane
	_overlay.material_override = _shader_mat
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.position = Vector3(0.0, overlay_height, 0.0)
	add_child(_overlay)
