# Engine Sim Audio (GDExtension)

Physics-based engine sound baker for Godot 4 (`EngineSimBaker`).

## API

```gdscript
var baker := EngineSimBaker.new()
baker.apply_params({
    "name": "i4_2_5L_8v",
    "cylinders": 4,
    "displacement_cc": 2500,
    "valves_per_cylinder": 2,
    "layout": 0, # Inline / V / Boxer
    "min_rpm": 800,
    "max_rpm": 5600,
    "rpm_step": 250,
    "throttle": 1.0,
    "exhaust_length_mm": 500,
    "cam_duration_deg": 220,
    "cam_lift_mm": 9.5,
})
var result: Dictionary = baker.bake_and_save("res://audio/engines/i4_2_5L_8v")
# result.ok, result.paths, result.rpms, result.error
```

Or set properties on the baker, then call `bake_and_save(path)`.

Writes `rpm_XXXX.tres` (AudioStreamWAV, looped) + `meta.cfg`.

## Build

1. CMake Release libs:
```bat
cmake -S . -B build -G "Visual Studio 18 2026" -A x64
cmake --build build --config Release
```

2. Link godot-cpp (junction or clone into `gdextension/godot-cpp`):
```bat
mklink /J gdextension\godot-cpp C:\path\to\godot-cpp
```

3. SCons:
```bat
cd gdextension
scons platform=windows target=template_debug
scons platform=windows target=template_release
```

Copy `addons/engine_sim_audio` into your Godot project.
