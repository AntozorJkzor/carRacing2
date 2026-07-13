class_name EndlessLeaderboard
extends Node

## Persists endless-road player scores. Pinned legends always stay on top.

const SAVE_PATH := "user://endless_leaderboard.json"
const MAX_PLAYER_ENTRIES := 50

## Always rendered first, exactly as written.
const PINNED_ENTRIES: Array[Dictionary] = [
	{
		"pinned": true,
		"display": "КИРА 1000000000 очков время 40 секунд",
	},
	{
		"pinned": true,
		"display": "L 1 очков 10 месяцев",
	},
	{
		"pinned": true,
		"display": "МИСА МИСА - ПОБЕДИЛА",
	},
]


static func add_entry(player_name: String, score: int, duration_sec: float) -> Array:
	var entry_name := player_name.strip_edges()
	if entry_name == "":
		entry_name = "Игрок"
	var entries := load_player_entries()
	entries.append({
		"name": entry_name,
		"score": score,
		"duration_sec": duration_sec,
		"timestamp": Time.get_datetime_string_from_system(false, true),
	})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a.get("score", 0))
		var sb := int(b.get("score", 0))
		if sa == sb:
			return float(a.get("duration_sec", 0.0)) < float(b.get("duration_sec", 0.0))
		return sa > sb
	)
	if entries.size() > MAX_PLAYER_ENTRIES:
		entries = entries.slice(0, MAX_PLAYER_ENTRIES)
	_save_player_entries(entries)
	return get_display_entries()


static func load_player_entries() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		_save_player_entries([])
		return []
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()
	if text.strip_edges() == "":
		return []
	var data = JSON.parse_string(text)
	var raw: Array = []
	if typeof(data) == TYPE_DICTIONARY:
		var players = data.get("players", [])
		if typeof(players) == TYPE_ARRAY:
			raw = players
	elif typeof(data) == TYPE_ARRAY:
		# Legacy flat array — migrate.
		raw = data
	var result: Array = []
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		if bool(d.get("pinned", false)):
			continue
		if d.has("display") and not d.has("name"):
			continue
		result.append(d)
	return result


static func get_display_entries() -> Array:
	var out: Array = []
	for pinned: Dictionary in PINNED_ENTRIES:
		out.append(pinned.duplicate(true))
	for entry in load_player_entries():
		out.append(entry)
	return out


static func format_table(max_rows: int = 30) -> String:
	var entries := get_display_entries()
	if entries.is_empty():
		return "Таблица пуста"
	var lines: PackedStringArray = PackedStringArray(["ТАБЛИЦА ЛИДЕРОВ"])
	var limit := mini(entries.size(), max_rows)
	for i in range(limit):
		lines.append("%d.  %s" % [i + 1, format_entry(entries[i])])
	return "\n".join(lines)


static func format_entry(entry: Dictionary) -> String:
	if bool(entry.get("pinned", false)) and entry.has("display"):
		return str(entry["display"])
	if entry.has("display"):
		return str(entry["display"])
	var entry_name := str(entry.get("name", "Игрок"))
	var score := int(entry.get("score", 0))
	var time_text := format_duration(float(entry.get("duration_sec", 0.0)))
	return "%s — %d очков  время %s" % [entry_name, score, time_text]


static func format_duration(duration_sec: float) -> String:
	var total := maxi(int(round(duration_sec)), 0)
	var hours := int(total / 3600.0)
	var mins := int((total % 3600) / 60.0)
	var secs := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, mins, secs]
	return "%d:%02d" % [mins, secs]


static func _save_player_entries(entries: Array) -> void:
	var payload := {"players": entries}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Leaderboard: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


## Instance helpers so the track Leaderboard node still works.
func add_entry_named(player_name: String, score: int, duration_sec: float) -> Array:
	return EndlessLeaderboard.add_entry(player_name, score, duration_sec)


func get_table_text(max_rows: int = 30) -> String:
	return EndlessLeaderboard.format_table(max_rows)
