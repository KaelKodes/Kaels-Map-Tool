class_name MapMarker
extends RefCounted

const _DEFAULT_ICON := "dot"

var id: String = ""
var layer_id: String = ""
var position: Vector2 = Vector2.ZERO  # UV coords 0..1 on the map image
var title: String = "New Marker"
var notes: String = ""
var icon: String = _DEFAULT_ICON
var size: float = 1.0


func _init(
	p_id: String = "",
	p_layer_id: String = "",
	p_position: Vector2 = Vector2.ZERO,
	p_title: String = "New Marker",
	p_notes: String = "",
	p_icon: String = _DEFAULT_ICON,
	p_size: float = 1.0
) -> void:
	id = p_id if p_id != "" else _new_id()
	layer_id = p_layer_id
	position = p_position
	title = p_title
	notes = p_notes
	icon = _normalize_icon(p_icon)
	size = clampf(p_size, 0.4, 4.0)


static func _normalize_icon(icon: String) -> String:
	if icon in ["dot", "house", "skull", "chest", "tree", "ingot", "boar"]:
		return icon
	return _DEFAULT_ICON


static func _new_id() -> String:
	return "%d_%d" % [Time.get_ticks_usec(), randi()]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"layer_id": layer_id,
		"x": position.x,
		"y": position.y,
		"title": title,
		"notes": notes,
		"icon": icon,
		"size": size,
	}


static func from_dict(data: Dictionary) -> MapMarker:
	return MapMarker.new(
		str(data.get("id", "")),
		str(data.get("layer_id", "")),
		Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
		str(data.get("title", "New Marker")),
		str(data.get("notes", "")),
		str(data.get("icon", _DEFAULT_ICON)),
		float(data.get("size", 1.0))
	)


func duplicate_marker() -> MapMarker:
	return MapMarker.new(id, layer_id, position, title, notes, icon, size)
