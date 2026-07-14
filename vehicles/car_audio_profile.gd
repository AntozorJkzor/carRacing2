class_name CarAudioProfile
extends Resource

## Pack-local engine loop banks (idle → redline crossfade).
@export var idle_stream: AudioStream
@export var low_stream: AudioStream
@export var mid_stream: AudioStream
@export var max_stream: AudioStream
@export var master_volume_db: float = -9.1
@export var max_distance: float = 80.0
@export var unit_size: float = 12.0
