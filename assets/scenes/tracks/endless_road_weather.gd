extends Node3D

## Overcast weather: rain and drifting cloud blobs that follow the car.
## Attach to Weather node on endless_road_track.tscn.

@export var follow_path: NodePath
@export var wind: Vector3 = Vector3(5.5, 0.0, 1.2)
@export var cloud_wrap_radius: float = 160.0

@onready var _clouds: Node3D = $Clouds

var _follow: Node3D
var _cloud_bases: Array[Vector3] = []


func _ready() -> void:
	if follow_path != NodePath():
		_follow = get_node_or_null(follow_path) as Node3D
	if _clouds == null:
		return
	for child: Node in _clouds.get_children():
		if child is Node3D:
			_cloud_bases.append((child as Node3D).position)


func _process(delta: float) -> void:
	if _follow == null:
		return
	var base := _follow.global_position
	global_position = Vector3(base.x, 0.0, base.z)
	if _clouds == null:
		return
	var drift := wind * delta
	var i := 0
	for child: Node in _clouds.get_children():
		if not (child is Node3D):
			continue
		var cloud := child as Node3D
		var pos := cloud.position + drift
		if i < _cloud_bases.size():
			var origin := _cloud_bases[i]
			var offset := pos - origin
			if offset.length() > cloud_wrap_radius:
				pos = origin + offset.normalized() * (-cloud_wrap_radius * 0.85)
		cloud.position = pos
		i += 1
