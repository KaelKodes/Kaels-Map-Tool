class_name MapLayer
extends RefCounted

var id: String = ""
var name: String = "Layer"
var visible: bool = true
var color: Color = Color(0.9, 0.3, 0.3)


func _init(
	p_id: String = "",
	p_name: String = "Layer",
	p_visible: bool = true,
	p_color: Color = Color(0.9, 0.3, 0.3)
) -> void:
	id = p_id if p_id != "" else _new_id()
	name = p_name
	visible = p_visible
	color = p_color


static func _new_id() -> String:
	return "%d_%d" % [Time.get_ticks_usec(), randi()]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"visible": visible,
		"color": color.to_html(true),
	}


static func from_dict(data: Dictionary) -> MapLayer:
	return MapLayer.new(
		str(data.get("id", "")),
		str(data.get("name", "Layer")),
		bool(data.get("visible", true)),
		Color.html(str(data.get("color", "#e64d4dff")))
	)
