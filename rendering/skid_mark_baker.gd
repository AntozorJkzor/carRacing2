class_name SkidMarkBaker
extends Node

const MinimapLayers := preload("res://rendering/minimap_layers.gd")

## Sparse tiled skid map: allocate R8 tiles only where tires paint.
## Caps RAM via max_tiles LRU eviction instead of one giant 4096² atlas.
## Add to the track scene (e.g. PhysicsTestTrack/SkidMarkBaker).

const GROUP := &"skid_mark_baker"
const OVERLAY_SHADER := "res://assets/materials/track/skid_overlay.gdshader"

@export var ground_mesh_path: NodePath = NodePath("../Ground/Plane")
## World meters covered by one tile (X/Z).
@export_range(16.0, 256.0, 1.0) var tile_world_size: float = 64.0
## Pixels per tile edge. 512 @ 64 m ≈ 0.125 m/px (same density as old 4096/512).
@export_range(128, 1024, 128) var tile_resolution: int = 512
## Hard RAM budget. 48 × 512² R8 ≈ 12 MB worst case (vs 16 MB always for 4096²).
@export_range(4, 128, 1) var max_tiles: int = 48
@export_range(0.01, 0.5, 0.01) var upload_interval: float = 0.05
@export_range(0.5, 3.0, 0.05) var min_radius_px: float = 1.35
@export_range(0.001, 0.05, 0.001) var overlay_height: float = 0.015
@export var rubber_color: Color = Color(0.025, 0.022, 0.02, 1)
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0
@export_range(0.0, 1.0, 0.01) var light_response: float = 0.35

var _tiles: Dictionary = {} # Vector2i -> SkidTile
var _overlay_root: Node3D
var _shader: Shader
var _meters_per_px: float = 0.125
var _upload_left: float = 0.0
var _any_dirty: bool = false


class SkidTile:
	var cx: int
	var cz: int
	var bytes: PackedByteArray
	var image: Image
	var texture: ImageTexture
	var overlay: MeshInstance3D
	var mat: ShaderMaterial
	var dirty: bool = false
	var last_used_msec: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	_meters_per_px = tile_world_size / float(tile_resolution)
	_shader = load(OVERLAY_SHADER) as Shader
	_overlay_root = Node3D.new()
	_overlay_root.name = "SkidTiles"
	add_child(_overlay_root)
	_restore_ground_material()
	set_process(true)


func _process(delta: float) -> void:
	FrameClock.measure("proc:skid_baker", _profiled_process, delta)


func _profiled_process(delta: float) -> void:
	if not _any_dirty:
		return
	_upload_left -= delta
	if _upload_left > 0.0:
		return
	_upload_left = upload_interval
	_flush_dirty_tiles()
	_any_dirty = false


func get_skid_texture() -> Texture2D:
	# Compatibility: return first live tile texture if any.
	for key in _tiles:
		var tile: SkidTile = _tiles[key]
		if tile.texture != null:
			return tile.texture
	return null


func get_tile_count() -> int:
	return _tiles.size()


func clear_marks() -> void:
	for key in _tiles.keys():
		_free_tile(_tiles[key])
	_tiles.clear()
	_any_dirty = false


## Stamp a rubber segment in world space. Strength 0..1 darkens the road.
func stamp_segment(from_world: Vector3, to_world: Vector3, half_width_m: float, strength: float) -> void:
	var ink := clampf(strength, 0.0, 1.0)
	var radius_m := maxf(half_width_m, min_radius_px * _meters_per_px)
	var delta := Vector2(to_world.x - from_world.x, to_world.z - from_world.z)
	var dist := delta.length()
	var step := maxf(radius_m * 0.55, 0.04)
	var steps := maxi(int(ceil(dist / step)), 1)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var wx := lerpf(from_world.x, to_world.x, t)
		var wz := lerpf(from_world.z, to_world.z, t)
		_stamp_world_disk(wx, wz, radius_m, ink)


func _stamp_world_disk(wx: float, wz: float, radius_m: float, ink: float) -> void:
	var r_px := maxf(radius_m / maxf(_meters_per_px, 0.0001), min_radius_px)
	# Tile cx covers [cx * size, (cx+1) * size).
	var min_x := wx - radius_m
	var max_x := wx + radius_m
	var min_z := wz - radius_m
	var max_z := wz + radius_m
	var cx0 := int(floor(min_x / tile_world_size))
	var cx1 := int(floor(max_x / tile_world_size))
	var cz0 := int(floor(min_z / tile_world_size))
	var cz1 := int(floor(max_z / tile_world_size))
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var tile := _acquire_tile(cx, cz)
			if tile == null:
				continue
			_stamp_disk_in_tile(tile, wx, wz, r_px, ink)


func _stamp_disk_in_tile(tile: SkidTile, wx: float, wz: float, radius_px: float, ink: float) -> void:
	var origin_x := float(tile.cx) * tile_world_size
	var origin_z := float(tile.cz) * tile_world_size
	var lx := (wx - origin_x) / _meters_per_px
	var lz := (wz - origin_z) / _meters_per_px
	var r_i := int(ceil(radius_px))
	var x0 := clampi(int(floor(lx)) - r_i, 0, tile_resolution - 1)
	var x1 := clampi(int(ceil(lx)) + r_i, 0, tile_resolution - 1)
	var y0 := clampi(int(floor(lz)) - r_i, 0, tile_resolution - 1)
	var y1 := clampi(int(ceil(lz)) + r_i, 0, tile_resolution - 1)
	if x1 < x0 or y1 < y0:
		return
	var r2 := radius_px * radius_px
	var ink_u := int(clampf(ink, 0.0, 1.0) * 255.0)
	var res := tile_resolution
	var touched := false
	for y in range(y0, y1 + 1):
		var row := y * res
		var dy := float(y) + 0.5 - lz
		var dy2 := dy * dy
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - lx
			var d2 := dx * dx + dy2
			if d2 > r2:
				continue
			var falloff := 1.0 - sqrt(d2) / maxf(radius_px, 0.001)
			falloff = falloff * falloff * (0.35 + 0.65 * falloff)
			var add := int(float(ink_u) * falloff)
			if add <= 0:
				continue
			var idx := row + x
			var cur := int(tile.bytes[idx])
			var nxt := cur + add - ((cur * add) >> 8)
			if nxt > cur:
				tile.bytes[idx] = mini(nxt, 255) as int
				touched = true
	if touched:
		tile.dirty = true
		tile.last_used_msec = Time.get_ticks_msec()
		_any_dirty = true


func _acquire_tile(cx: int, cz: int) -> SkidTile:
	var key := Vector2i(cx, cz)
	if _tiles.has(key):
		var existing: SkidTile = _tiles[key]
		existing.last_used_msec = Time.get_ticks_msec()
		return existing
	while _tiles.size() >= max_tiles:
		if not _evict_lru():
			return null
	var tile := SkidTile.new()
	tile.cx = cx
	tile.cz = cz
	tile.image = Image.create(tile_resolution, tile_resolution, false, Image.FORMAT_R8)
	tile.image.fill(Color(0, 0, 0, 1))
	tile.bytes = tile.image.get_data()
	tile.texture = ImageTexture.create_from_image(tile.image)
	tile.last_used_msec = Time.get_ticks_msec()
	_build_tile_overlay(tile)
	_tiles[key] = tile
	return tile


func _evict_lru() -> bool:
	if _tiles.is_empty():
		return false
	var oldest_key: Vector2i
	var oldest_t := 0x7fffffff
	var found := false
	for key in _tiles:
		var tile: SkidTile = _tiles[key]
		if tile.last_used_msec < oldest_t:
			oldest_t = tile.last_used_msec
			oldest_key = key
			found = true
	if not found:
		return false
	_free_tile(_tiles[oldest_key])
	_tiles.erase(oldest_key)
	return true


func _free_tile(tile: SkidTile) -> void:
	if tile == null:
		return
	if tile.overlay != null and is_instance_valid(tile.overlay):
		tile.overlay.queue_free()
	tile.overlay = null
	tile.mat = null
	tile.texture = null
	tile.image = null
	tile.bytes = PackedByteArray()


func _flush_dirty_tiles() -> void:
	for key in _tiles:
		var tile: SkidTile = _tiles[key]
		if not tile.dirty:
			continue
		tile.image.set_data(tile_resolution, tile_resolution, false, Image.FORMAT_R8, tile.bytes)
		tile.texture.set_image(tile.image)
		tile.dirty = false


func _build_tile_overlay(tile: SkidTile) -> void:
	if _shader == null:
		push_warning("SkidMarkBaker: missing skid_overlay.gdshader")
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(tile_world_size, tile_world_size)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0

	tile.mat = ShaderMaterial.new()
	tile.mat.shader = _shader
	tile.mat.set_shader_parameter("skid_tex", tile.texture)
	tile.mat.set_shader_parameter("rubber_color", Vector3(rubber_color.r, rubber_color.g, rubber_color.b))
	tile.mat.set_shader_parameter("opacity", opacity)
	tile.mat.set_shader_parameter("light_response", light_response)

	tile.overlay = MeshInstance3D.new()
	tile.overlay.name = "SkidTile_%d_%d" % [tile.cx, tile.cz]
	tile.overlay.mesh = plane
	tile.overlay.material_override = tile.mat
	tile.overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.overlay.layers = MinimapLayers.EFFECTS
	# PlaneMesh is centered on its origin; tile covers [cx*s, (cx+1)*s) → center at (cx+0.5)*s
	var cxw := (float(tile.cx) + 0.5) * tile_world_size
	var czw := (float(tile.cz) + 0.5) * tile_world_size
	tile.overlay.position = Vector3(cxw, overlay_height, czw)
	_overlay_root.add_child(tile.overlay)


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
	mesh_inst.material_override = null
