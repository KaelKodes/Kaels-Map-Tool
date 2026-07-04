class_name MarkerIcons
extends RefCounted

## Map marker icon ids and procedural drawing (layer color applied by caller).

const DEFAULT_ICON := "dot"

const ICONS: Array[Dictionary] = [
	{"id": "dot", "label": "Dot"},
	{"id": "house", "label": "House"},
	{"id": "skull", "label": "Skull"},
	{"id": "chest", "label": "Treasure Chest"},
	{"id": "tree", "label": "Tree"},
	{"id": "ingot", "label": "Metal Bar"},
	{"id": "boar", "label": "Boar Head"},
]


static func normalize_icon(icon: String) -> String:
	for entry in ICONS:
		if entry["id"] == icon:
			return icon
	return DEFAULT_ICON


static func get_label(icon: String) -> String:
	for entry in ICONS:
		if entry["id"] == icon:
			return str(entry["label"])
	return "Dot"


static func draw_marker(
	canvas: Control,
	icon_id: String,
	center: Vector2,
	radius: float,
	fill: Color,
	outline: Color,
	selected: bool
) -> void:
	match normalize_icon(icon_id):
		"house":
			_draw_house(canvas, center, radius, fill, outline)
		"skull":
			_draw_skull(canvas, center, radius, fill, outline)
		"chest":
			_draw_chest(canvas, center, radius, fill, outline)
		"tree":
			_draw_tree(canvas, center, radius, fill, outline)
		"ingot":
			_draw_ingot(canvas, center, radius, fill, outline)
		"boar":
			_draw_boar(canvas, center, radius, fill, outline)
		_:
			_draw_dot(canvas, center, radius, fill, outline)

	if selected:
		canvas.draw_arc(center, radius + 5.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.0)


static func _draw_dot(canvas: Control, c: Vector2, r: float, fill: Color, outline: Color) -> void:
	canvas.draw_circle(c, r + 2.0, outline)
	canvas.draw_circle(c, r, fill)


static func _draw_house(canvas: Control, c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var body := PackedVector2Array([
		c + Vector2(-r * 0.75, r * 0.35),
		c + Vector2(r * 0.75, r * 0.35),
		c + Vector2(r * 0.75, r * 0.95),
		c + Vector2(-r * 0.75, r * 0.95),
	])
	var roof := PackedVector2Array([
		c + Vector2(-r * 0.85, r * 0.35),
		c + Vector2(0, -r * 0.95),
		c + Vector2(r * 0.85, r * 0.35),
	])
	canvas.draw_colored_polygon(body, fill)
	canvas.draw_polyline(body + PackedVector2Array([body[0]]), outline, 2.0, true)
	canvas.draw_colored_polygon(roof, fill.lightened(0.08))
	canvas.draw_polyline(roof + PackedVector2Array([roof[0]]), outline, 2.0, true)
	var door := Rect2(c.x - r * 0.18, c.y + r * 0.45, r * 0.36, r * 0.5)
	canvas.draw_rect(door, outline.darkened(0.35))


static func _draw_skull(canvas: Control, c: Vector2, r: float, fill: Color, outline: Color) -> void:
	# Unified skull silhouette — cranium, cheekbones, and jaw in one shape.
	var skull := PackedVector2Array([
		c + Vector2(0, -r * 0.92),
		c + Vector2(r * 0.62, -r * 0.55),
		c + Vector2(r * 0.72, -r * 0.05),
		c + Vector2(r * 0.48, r * 0.42),
		c + Vector2(r * 0.32, r * 0.82),
		c + Vector2(0, r * 0.92),
		c + Vector2(-r * 0.32, r * 0.82),
		c + Vector2(-r * 0.48, r * 0.42),
		c + Vector2(-r * 0.72, -r * 0.05),
		c + Vector2(-r * 0.62, -r * 0.55),
	])
	canvas.draw_colored_polygon(skull, fill)
	canvas.draw_polyline(skull + PackedVector2Array([skull[0]]), outline, 2.0, true)

	var socket := outline.darkened(0.55)
	# Eye sockets
	canvas.draw_circle(c + Vector2(-r * 0.28, -r * 0.12), r * 0.2, socket)
	canvas.draw_circle(c + Vector2(r * 0.28, -r * 0.12), r * 0.2, socket)
	# Nose cavity
	var nose := PackedVector2Array([
		c + Vector2(0, r * 0.02),
		c + Vector2(r * 0.1, r * 0.22),
		c + Vector2(-r * 0.1, r * 0.22),
	])
	canvas.draw_colored_polygon(nose, socket)
	# Teeth
	var mouth_y := r * 0.56
	canvas.draw_line(c + Vector2(-r * 0.26, mouth_y), c + Vector2(r * 0.26, mouth_y), outline.darkened(0.25), 1.5)
	for i in 3:
		var x := -r * 0.18 + i * r * 0.18
		canvas.draw_line(c + Vector2(x, mouth_y), c + Vector2(x, r * 0.78), outline.darkened(0.2), 1.2)


static func _draw_chest(canvas: Control, c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var box := Rect2(c.x - r * 0.8, c.y - r * 0.15, r * 1.6, r * 0.95)
	canvas.draw_rect(box, fill)
	canvas.draw_rect(box, outline, false, 2.0)
	var lid := PackedVector2Array([
		Vector2(box.position.x, box.position.y),
		Vector2(box.end.x, box.position.y),
		Vector2(box.end.x - r * 0.08, box.position.y - r * 0.42),
		Vector2(box.position.x + r * 0.08, box.position.y - r * 0.42),
	])
	canvas.draw_colored_polygon(lid, fill.lightened(0.1))
	canvas.draw_polyline(lid + PackedVector2Array([lid[0]]), outline, 2.0, true)
	var lock := Rect2(c.x - r * 0.12, c.y + r * 0.08, r * 0.24, r * 0.22)
	canvas.draw_rect(lock, outline.darkened(0.2))
	canvas.draw_line(
		Vector2(c.x, box.position.y),
		Vector2(c.x, box.end.y),
		outline.darkened(0.15),
		1.5
	)


static func _draw_tree(canvas: Control, c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var trunk := Rect2(c.x - r * 0.14, c.y + r * 0.05, r * 0.28, r * 0.72)
	canvas.draw_rect(trunk, fill.darkened(0.35))
	canvas.draw_rect(trunk, outline, false, 1.5)
	var foliage := PackedVector2Array([
		c + Vector2(0, -r * 0.95),
		c + Vector2(r * 0.72, r * 0.18),
		c + Vector2(-r * 0.72, r * 0.18),
	])
	canvas.draw_colored_polygon(foliage, fill)
	canvas.draw_polyline(foliage + PackedVector2Array([foliage[0]]), outline, 2.0, true)
	var foliage2 := PackedVector2Array([
		c + Vector2(0, -r * 0.55),
		c + Vector2(r * 0.58, r * 0.42),
		c + Vector2(-r * 0.58, r * 0.42),
	])
	canvas.draw_colored_polygon(foliage2, fill.lightened(0.06))
	canvas.draw_polyline(foliage2 + PackedVector2Array([foliage2[0]]), outline, 1.5, true)


static func _draw_ingot(canvas: Control, c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var ingot := PackedVector2Array([
		c + Vector2(-r * 0.55, -r * 0.25),
		c + Vector2(r * 0.55, -r * 0.25),
		c + Vector2(r * 0.75, r * 0.15),
		c + Vector2(r * 0.45, r * 0.55),
		c + Vector2(-r * 0.45, r * 0.55),
		c + Vector2(-r * 0.75, r * 0.15),
	])
	canvas.draw_colored_polygon(ingot, fill.lightened(0.12))
	canvas.draw_polyline(ingot + PackedVector2Array([ingot[0]]), outline, 2.0, true)
	canvas.draw_line(c + Vector2(-r * 0.35, -r * 0.05), c + Vector2(r * 0.35, -r * 0.05), fill.darkened(0.12), 2.0)


static func _draw_boar(canvas: Control, c: Vector2, r: float, fill: Color, outline: Color) -> void:
	canvas.draw_circle(c + Vector2(0, -r * 0.05), r * 0.72, fill)
	canvas.draw_arc(c + Vector2(0, -r * 0.05), r * 0.72, 0.0, TAU, 32, outline, 2.0)
	var ear_l := PackedVector2Array([
		c + Vector2(-r * 0.55, -r * 0.45),
		c + Vector2(-r * 0.25, -r * 0.95),
		c + Vector2(-r * 0.08, -r * 0.45),
	])
	var ear_r := PackedVector2Array([
		c + Vector2(r * 0.55, -r * 0.45),
		c + Vector2(r * 0.25, -r * 0.95),
		c + Vector2(r * 0.08, -r * 0.45),
	])
	canvas.draw_colored_polygon(ear_l, fill.darkened(0.12))
	canvas.draw_colored_polygon(ear_r, fill.darkened(0.12))
	canvas.draw_polyline(ear_l + PackedVector2Array([ear_l[0]]), outline, 1.5, true)
	canvas.draw_polyline(ear_r + PackedVector2Array([ear_r[0]]), outline, 1.5, true)
	var snout := PackedVector2Array([
		c + Vector2(-r * 0.28, r * 0.18),
		c + Vector2(r * 0.28, r * 0.18),
		c + Vector2(r * 0.18, r * 0.62),
		c + Vector2(-r * 0.18, r * 0.62),
	])
	canvas.draw_colored_polygon(snout, fill.darkened(0.06))
	canvas.draw_polyline(snout + PackedVector2Array([snout[0]]), outline, 2.0, true)
	canvas.draw_circle(c + Vector2(-r * 0.1, r * 0.35), r * 0.05, outline.darkened(0.4))
	canvas.draw_circle(c + Vector2(r * 0.1, r * 0.35), r * 0.05, outline.darkened(0.4))
	canvas.draw_circle(c + Vector2(-r * 0.22, -r * 0.18), r * 0.07, outline.darkened(0.55))
	canvas.draw_circle(c + Vector2(r * 0.22, -r * 0.18), r * 0.07, outline.darkened(0.55))
