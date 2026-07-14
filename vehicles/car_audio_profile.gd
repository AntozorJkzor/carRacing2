## Spatial + baked engine loop banks for EngineAudio.
## Bake with EngineSoundBaker (waveguide offline) into assets/audio/engines/<car>/.
class_name CarAudioProfile
extends Resource

@export var idle_stream: AudioStream
@export var low_stream: AudioStream
@export var mid_stream: AudioStream
@export var max_stream: AudioStream
@export var master_volume_db: float = -9.1
@export var max_distance: float = 80.0
@export var unit_size: float = 12.0
