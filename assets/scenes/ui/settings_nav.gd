extends RefCounted
class_name SettingsNav

## Shared navigation for settings screens.
## From main menu: change_scene. From pause overlay: push/pop page stack.


static func host(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group("settings_overlay_host")


static func go(from: Node, path: String) -> void:
	var h := host(from)
	if h != null and h.has_method("push_page"):
		h.call("push_page", path)
		return
	from.get_tree().change_scene_to_file(path)


static func back(from: Node, fallback_scene: String) -> void:
	var h := host(from)
	if h != null and h.has_method("pop_page"):
		h.call("pop_page")
		return
	from.get_tree().change_scene_to_file(fallback_scene)


static func is_overlay(from: Node) -> bool:
	return host(from) != null
