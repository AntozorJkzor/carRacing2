class_name ConfigStore
extends RefCounted

## Shared ConfigFile helpers: one-line open + dict-driven batch write.

## Returns the loaded ConfigFile, or null if missing/unreadable.
static func open(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	return cfg if cfg.load(path) == OK else null


## Merges sections into the file at path (untouched keys are preserved) and saves.
## sections: { "volume": { "master": 1.0, ... }, ... }
static func save(path: String, sections: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for section: String in sections:
		var values: Dictionary = sections[section]
		for key: String in values:
			cfg.set_value(section, key, values[key])
	cfg.save(path)
