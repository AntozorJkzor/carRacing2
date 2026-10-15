## Spatial + baked engine loop banks for EngineAudio.
## Prefer `engine_bank_dir` (rpm_XXXX.tres + meta.cfg every 250 rpm).
## Legacy idle/low/mid/max kept as fallback when bank dir is empty.
class_name CarAudioProfile
extends Resource

@export_dir var engine_bank_dir: String = ""
@export var idle_stream: AudioStream
@export var low_stream: AudioStream
@export var mid_stream: AudioStream
@export var max_stream: AudioStream
@export var master_volume_db: float = -2.0
@export var max_distance: float = 80.0
@export var unit_size: float = 12.0
