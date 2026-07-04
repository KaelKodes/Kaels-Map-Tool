extends Node

## Central map document state. UI and network both talk to this.

signal map_image_changed(texture: Texture2D)
signal layers_changed
signal markers_changed
signal marker_selected(marker: MapMarker)
signal selection_cleared
signal status_message(text: String)
signal pings_changed

const PING_DURATION_MS := 4000

var map_texture: Texture2D = null
var map_image_png: PackedByteArray = PackedByteArray()
var layers: Array[MapLayer] = []
var markers: Array[MapMarker] = []
var selected_marker_id: String = ""
var active_layer_id: String = ""
var current_project_path: String = ""
var active_pings: Array[Dictionary] = []

## When true, local edits are applied and then broadcast by NetworkManager.
var suppress_network: bool = false


func _ready() -> void:
	_ensure_default_layers()


func _ensure_default_layers() -> void:
	if layers.is_empty():
		add_layer("Enemy Bases", Color(0.9, 0.25, 0.25), false)
		add_layer("Rare Loot", Color(0.95, 0.8, 0.2), false)
		add_layer("Notes", Color(0.3, 0.7, 1.0), false)
		if layers.size() > 0:
			active_layer_id = layers[0].id


func clear_document(keep_default_layers: bool = true) -> void:
	map_texture = null
	map_image_png = PackedByteArray()
	markers.clear()
	selected_marker_id = ""
	current_project_path = ""
	if keep_default_layers:
		layers.clear()
		_ensure_default_layers()
	else:
		layers.clear()
		active_layer_id = ""
	map_image_changed.emit(null)
	layers_changed.emit()
	markers_changed.emit()
	selection_cleared.emit()


func save_project(path: String) -> Error:
	var err := ProjectIO.save(path, export_state(), map_image_png)
	if err != OK:
		status_message.emit("Save failed.")
		return err
	current_project_path = path
	status_message.emit("Saved %s" % path.get_file())
	return OK


func load_project(path: String, broadcast: bool = true) -> void:
	var result := ProjectIO.load(path)
	if not bool(result.get("ok", false)):
		status_message.emit(str(result.get("error", "Load failed.")))
		return

	suppress_network = true
	import_state(result["state"])
	var map_png: PackedByteArray = result["map_png"]
	if map_png.size() > 0:
		await set_map_from_png_bytes(map_png)
	else:
		map_texture = null
		map_image_png = PackedByteArray()
		map_image_changed.emit(null)
	suppress_network = false

	current_project_path = path
	status_message.emit("Loaded %s" % path.get_file())

	if broadcast and not suppress_network:
		NetworkManager.broadcast_full_document()


func set_map_from_source_image(source: Image, broadcast: bool = true) -> void:
	if source == null:
		return
	# Keep a compact source for network sync; upscale only for display.
	var source_copy: Image = source.duplicate()
	if source_copy.get_format() != Image.FORMAT_RGBA8:
		source_copy.convert(Image.FORMAT_RGBA8)
	map_image_png = source_copy.save_png_to_buffer()

	status_message.emit("Upscaling map…")
	await get_tree().process_frame
	var display_img := ImageUpscaler.upscale(source_copy)
	var tex := ImageTexture.create_from_image(display_img)
	map_texture = tex
	map_image_changed.emit(tex)
	status_message.emit("Map loaded (%dx%d display)" % [display_img.get_width(), display_img.get_height()])
	if broadcast and not suppress_network:
		NetworkManager.broadcast_map_image()


func set_map_from_path(path: String) -> void:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		status_message.emit("Failed to load image.")
		return
	await set_map_from_source_image(img)


func set_map_from_png_bytes(bytes: PackedByteArray) -> void:
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		status_message.emit("Failed to apply shared map image.")
		return
	map_image_png = bytes
	status_message.emit("Upscaling shared map…")
	await get_tree().process_frame
	var display_img := ImageUpscaler.upscale(img)
	map_texture = ImageTexture.create_from_image(display_img)
	map_image_changed.emit(map_texture)
	status_message.emit("Received shared map (%dx%d display)" % [display_img.get_width(), display_img.get_height()])


func get_layer(layer_id: String) -> MapLayer:
	for layer in layers:
		if layer.id == layer_id:
			return layer
	return null


func get_marker(marker_id: String) -> MapMarker:
	for marker in markers:
		if marker.id == marker_id:
			return marker
	return null


func get_active_layer() -> MapLayer:
	return get_layer(active_layer_id)


func set_active_layer(layer_id: String) -> void:
	if get_layer(layer_id) == null:
		return
	active_layer_id = layer_id
	layers_changed.emit()


func add_layer(layer_name: String, color: Color = Color(0.9, 0.3, 0.3), broadcast: bool = true) -> MapLayer:
	var layer := MapLayer.new("", layer_name, true, color)
	layers.append(layer)
	if active_layer_id == "":
		active_layer_id = layer.id
	layers_changed.emit()
	if broadcast and not suppress_network:
		NetworkManager.broadcast_layer_upsert(layer)
	return layer


func upsert_layer_from_dict(data: Dictionary) -> void:
	var incoming := MapLayer.from_dict(data)
	var existing := get_layer(incoming.id)
	if existing:
		existing.name = incoming.name
		existing.visible = incoming.visible
		existing.color = incoming.color
	else:
		layers.append(incoming)
		if active_layer_id == "":
			active_layer_id = incoming.id
	layers_changed.emit()
	markers_changed.emit()


func remove_layer(layer_id: String, broadcast: bool = true) -> void:
	if layers.size() <= 1:
		status_message.emit("Keep at least one layer.")
		return
	layers = layers.filter(func(l: MapLayer) -> bool: return l.id != layer_id)
	markers = markers.filter(func(m: MapMarker) -> bool: return m.layer_id != layer_id)
	if active_layer_id == layer_id:
		active_layer_id = layers[0].id
	if selected_marker_id != "" and get_marker(selected_marker_id) == null:
		selected_marker_id = ""
		selection_cleared.emit()
	layers_changed.emit()
	markers_changed.emit()
	if broadcast and not suppress_network:
		NetworkManager.broadcast_layer_remove(layer_id)


func set_layer_visible(layer_id: String, visible: bool, broadcast: bool = true) -> void:
	var layer := get_layer(layer_id)
	if layer == null:
		return
	layer.visible = visible
	layers_changed.emit()
	markers_changed.emit()
	if broadcast and not suppress_network:
		NetworkManager.broadcast_layer_upsert(layer)


func rename_layer(layer_id: String, new_name: String, broadcast: bool = true) -> void:
	var layer := get_layer(layer_id)
	if layer == null:
		return
	layer.name = new_name
	layers_changed.emit()
	if broadcast and not suppress_network:
		NetworkManager.broadcast_layer_upsert(layer)


func add_marker_at_uv(uv: Vector2, broadcast: bool = true) -> MapMarker:
	var layer := get_active_layer()
	if layer == null:
		status_message.emit("No active layer.")
		return null
	var marker := MapMarker.new("", layer.id, uv.clamp(Vector2.ZERO, Vector2.ONE))
	markers.append(marker)
	markers_changed.emit()
	select_marker(marker.id)
	if broadcast and not suppress_network:
		NetworkManager.broadcast_marker_upsert(marker)
	return marker


func upsert_marker_from_dict(data: Dictionary) -> void:
	var incoming := MapMarker.from_dict(data)
	var existing := get_marker(incoming.id)
	if existing:
		existing.layer_id = incoming.layer_id
		existing.position = incoming.position
		existing.title = incoming.title
		existing.notes = incoming.notes
		existing.icon = incoming.icon
		existing.size = incoming.size
	else:
		markers.append(incoming)
	markers_changed.emit()
	if selected_marker_id == incoming.id:
		marker_selected.emit(incoming)


func update_marker(marker: MapMarker, broadcast: bool = true) -> void:
	var existing := get_marker(marker.id)
	if existing == null:
		return
	existing.layer_id = marker.layer_id
	existing.position = marker.position
	existing.title = marker.title
	existing.notes = marker.notes
	existing.icon = marker.icon
	existing.size = marker.size
	# Do not emit marker_selected here — resetting LineEdit text breaks typing order.
	markers_changed.emit()
	if broadcast and not suppress_network:
		NetworkManager.broadcast_marker_upsert(existing)


func issue_ping(uv: Vector2, color: Color, broadcast: bool = true) -> void:
	active_pings.append({
		"uv": uv.clamp(Vector2.ZERO, Vector2.ONE),
		"color": color,
		"start_ms": Time.get_ticks_msec(),
	})
	pings_changed.emit()
	if broadcast and not suppress_network:
		NetworkManager.broadcast_ping(uv, color)


func prune_pings() -> bool:
	var now := Time.get_ticks_msec()
	var before := active_pings.size()
	active_pings = active_pings.filter(
		func(p: Dictionary) -> bool: return now - int(p.get("start_ms", 0)) < PING_DURATION_MS
	)
	return active_pings.size() != before


func get_live_pings() -> Array[Dictionary]:
	prune_pings()
	var result: Array[Dictionary] = []
	for ping in active_pings:
		result.append(ping)
	return result


func remove_marker(marker_id: String, broadcast: bool = true) -> void:
	markers = markers.filter(func(m: MapMarker) -> bool: return m.id != marker_id)
	if selected_marker_id == marker_id:
		selected_marker_id = ""
		selection_cleared.emit()
	markers_changed.emit()
	if broadcast and not suppress_network:
		NetworkManager.broadcast_marker_remove(marker_id)


func select_marker(marker_id: String) -> void:
	var marker := get_marker(marker_id)
	if marker == null:
		clear_selection()
		return
	selected_marker_id = marker_id
	marker_selected.emit(marker)


func clear_selection() -> void:
	selected_marker_id = ""
	selection_cleared.emit()


func get_marker_color(marker: MapMarker) -> Color:
	var layer := get_layer(marker.layer_id)
	if layer == null:
		return Color.WHITE
	return layer.color


func get_visible_markers() -> Array[MapMarker]:
	var result: Array[MapMarker] = []
	for marker in markers:
		var layer := get_layer(marker.layer_id)
		if layer != null and layer.visible:
			result.append(marker)
	return result


func export_state() -> Dictionary:
	var layer_dicts: Array = []
	for layer in layers:
		layer_dicts.append(layer.to_dict())
	var marker_dicts: Array = []
	for marker in markers:
		marker_dicts.append(marker.to_dict())
	return {
		"layers": layer_dicts,
		"markers": marker_dicts,
		"active_layer_id": active_layer_id,
	}


func import_state(data: Dictionary) -> void:
	layers.clear()
	markers.clear()
	for layer_data in data.get("layers", []):
		layers.append(MapLayer.from_dict(layer_data))
	for marker_data in data.get("markers", []):
		markers.append(MapMarker.from_dict(marker_data))
	active_layer_id = str(data.get("active_layer_id", ""))
	if active_layer_id == "" and layers.size() > 0:
		active_layer_id = layers[0].id
	selected_marker_id = ""
	layers_changed.emit()
	markers_changed.emit()
	selection_cleared.emit()
