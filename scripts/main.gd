extends Control

const MarkerIconsLib = preload("res://scripts/marker_icons.gd")

@onready var map_canvas: Control = %MapCanvas
@onready var layer_list: VBoxContainer = %LayerList
@onready var status_label: Label = %StatusLabel
@onready var version_label: Label = %VersionLabel
@onready var notes_panel: PanelContainer = %NotesPanel
@onready var notes_title: LineEdit = %NotesTitle
@onready var notes_body: TextEdit = %NotesBody
@onready var notes_empty: Label = %NotesEmpty
@onready var notes_editor: VBoxContainer = %NotesEditor
@onready var marker_layer_color: ColorRect = %MarkerLayerColor
@onready var marker_icon: OptionButton = %MarkerIcon
@onready var marker_size: HSlider = %MarkerSize
@onready var marker_size_value: Label = %MarkerSizeValue
@onready var join_host_ip: LineEdit = %JoinHostIp
@onready var host_address_label: Label = %HostAddressLabel
@onready var user_color_swatch: ColorRect = %UserColorSwatch
@onready var place_marker_btn: Button = %PlaceMarkerBtn
@onready var upload_dialog: FileDialog = %UploadDialog
@onready var open_dialog: FileDialog = %OpenDialog
@onready var save_dialog: FileDialog = %SaveDialog
@onready var new_layer_name: LineEdit = %NewLayerName

var _notes_marker_id: String = ""
var _updating_notes_ui: bool = false
var _layer_rclick_ms: Dictionary = {}  # layer_id -> last right-click time (msec)

const LAYER_RCLICK_WINDOW_MS := 400


func _ready() -> void:
	MapSession.status_message.connect(_set_status)
	MapSession.layers_changed.connect(_queue_rebuild_layers)
	MapSession.layers_changed.connect(_on_layers_changed_for_marker_notes)
	MapSession.marker_selected.connect(_on_marker_selected)
	MapSession.selection_cleared.connect(_on_selection_cleared)
	MapSession.markers_changed.connect(_on_markers_changed_for_notes)
	NetworkManager.peer_status.connect(_set_status)
	NetworkManager.connection_changed.connect(_on_connection_changed)
	NetworkManager.user_colors_changed.connect(_update_user_color_swatch)

	notes_title.text_changed.connect(_on_notes_title_changed)
	notes_body.text_changed.connect(_on_notes_body_changed)
	marker_icon.item_selected.connect(_on_marker_icon_selected)
	marker_size.value_changed.connect(_on_marker_size_changed)

	_populate_marker_icons()

	_rebuild_layers()
	_show_notes_empty()
	_update_user_color_swatch()
	host_address_label.visible = false
	version_label.text = ProjectSettings.get_setting("application/config/version", "A0.0.1")
	_set_status("Ready — open a project, start a new map, or host a lobby.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		match event.keycode:
			KEY_S:
				if event.shift_pressed:
					_on_save_as_pressed()
				else:
					_on_save_pressed()
				get_viewport().set_input_as_handled()
			KEY_O:
				_on_open_pressed()
				get_viewport().set_input_as_handled()


func _populate_marker_icons() -> void:
	marker_icon.clear()
	for entry in MarkerIconsLib.ICONS:
		marker_icon.add_item(str(entry["label"]), marker_icon.get_item_count())
		marker_icon.set_item_metadata(marker_icon.get_item_count() - 1, str(entry["id"]))


func _set_marker_icon_selection(icon_id: String) -> void:
	icon_id = MarkerIconsLib.normalize_icon(icon_id)
	for i in marker_icon.get_item_count():
		if str(marker_icon.get_item_metadata(i)) == icon_id:
			marker_icon.select(i)
			return
	marker_icon.select(0)


func _set_status(text: String) -> void:
	status_label.text = text


func _get_selected_marker_icon() -> String:
	var idx := marker_icon.selected
	if idx < 0:
		return MarkerIconsLib.DEFAULT_ICON
	return str(marker_icon.get_item_metadata(idx))


func _on_connection_changed(connected: bool, is_host: bool) -> void:
	if connected and is_host:
		var hint := NetworkManager.get_host_address_hint()
		host_address_label.visible = hint != ""
		host_address_label.text = hint
	else:
		host_address_label.visible = false
		host_address_label.text = ""
	_update_user_color_swatch()


func _update_user_color_swatch() -> void:
	user_color_swatch.color = NetworkManager.local_color
	user_color_swatch.tooltip_text = "Your ping color"


func _on_new_map_pressed() -> void:
	upload_dialog.popup_centered_ratio(0.6)


func _on_upload_file_selected(path: String) -> void:
	MapSession.set_map_from_path(path)


func _on_open_pressed() -> void:
	open_dialog.popup_centered_ratio(0.6)


func _on_open_file_selected(path: String) -> void:
	MapSession.load_project(path)


func _on_save_pressed() -> void:
	if MapSession.current_project_path != "":
		MapSession.save_project(MapSession.current_project_path)
	else:
		_on_save_as_pressed()


func _on_save_as_pressed() -> void:
	if MapSession.current_project_path != "":
		save_dialog.current_path = MapSession.current_project_path
	save_dialog.popup_centered_ratio(0.6)


func _on_save_file_selected(path: String) -> void:
	if not path.ends_with(".kmap"):
		path += ".kmap"
	MapSession.save_project(path)


func _on_place_marker_pressed() -> void:
	if MapSession.map_texture == null:
		_set_status("Start a new map before placing markers.")
		return
	if MapSession.get_active_layer() == null:
		_set_status("Select a layer first.")
		return
	map_canvas.set_placing_marker(true)
	_set_status("Click the map to place a marker on the active layer.")


func _on_host_pressed() -> void:
	NetworkManager.host_lobby()


func _on_join_pressed() -> void:
	NetworkManager.join_lobby(join_host_ip.text)


func _on_disconnect_pressed() -> void:
	NetworkManager.close_session()
	host_address_label.visible = false
	host_address_label.text = ""
	_set_status("Disconnected.")


func _on_add_layer_pressed() -> void:
	var layer_name := new_layer_name.text.strip_edges()
	if layer_name.is_empty():
		layer_name = "Layer %d" % (MapSession.layers.size() + 1)
	var layer := MapSession.add_layer(layer_name, _next_layer_color())
	MapSession.set_active_layer(layer.id)
	new_layer_name.text = ""


func _next_layer_color() -> Color:
	var palette := [
		Color(0.90, 0.25, 0.25),
		Color(0.95, 0.80, 0.20),
		Color(0.30, 0.70, 1.00),
		Color(0.35, 0.85, 0.45),
		Color(0.80, 0.40, 0.90),
		Color(1.00, 0.55, 0.20),
	]
	return palette[MapSession.layers.size() % palette.size()]


func _queue_rebuild_layers() -> void:
	_rebuild_layers.call_deferred()


func _rebuild_layers() -> void:
	for child in layer_list.get_children():
		child.queue_free()

	for layer in MapSession.layers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var visible_btn := CheckBox.new()
		visible_btn.button_pressed = layer.visible
		visible_btn.tooltip_text = "Show/hide layer"
		visible_btn.toggled.connect(_on_layer_visible_toggled.bind(layer.id))
		row.add_child(visible_btn)

		var color_rect := ColorRect.new()
		color_rect.custom_minimum_size = Vector2(14, 14)
		color_rect.color = layer.color
		color_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(color_rect)

		var select_btn := Button.new()
		select_btn.text = layer.name
		select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_btn.toggle_mode = true
		select_btn.button_pressed = layer.id == MapSession.active_layer_id
		select_btn.tooltip_text = "Select layer · double right-click to rename"
		select_btn.pressed.connect(_on_layer_selected.bind(layer.id))
		select_btn.gui_input.connect(_on_layer_name_gui_input.bind(layer.id, select_btn))
		select_btn.set_meta("layer_id", layer.id)
		if layer.id == MapSession.active_layer_id:
			select_btn.modulate = Color(1.15, 1.15, 1.15)
		row.add_child(select_btn)

		var delete_btn := Button.new()
		delete_btn.text = "×"
		delete_btn.tooltip_text = "Delete layer"
		delete_btn.custom_minimum_size = Vector2(28, 0)
		delete_btn.pressed.connect(_on_layer_delete.bind(layer.id))
		row.add_child(delete_btn)

		layer_list.add_child(row)


func _on_layers_changed_for_marker_notes() -> void:
	if _notes_marker_id == "":
		return
	var marker := MapSession.get_marker(_notes_marker_id)
	if marker == null:
		return
	marker_layer_color.color = MapSession.get_marker_color(marker)


func _on_layer_selected(layer_id: String) -> void:
	MapSession.set_active_layer(layer_id)
	_set_status("Active layer: %s" % MapSession.get_layer(layer_id).name)


func _on_layer_visible_toggled(pressed: bool, layer_id: String) -> void:
	MapSession.set_layer_visible(layer_id, pressed)


func _on_layer_delete(layer_id: String) -> void:
	MapSession.remove_layer(layer_id)


func _on_layer_name_gui_input(event: InputEvent, layer_id: String, btn: Button) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	var now := Time.get_ticks_msec()
	if _layer_rclick_ms.has(layer_id) and now - int(_layer_rclick_ms[layer_id]) <= LAYER_RCLICK_WINDOW_MS:
		_layer_rclick_ms.erase(layer_id)
		_begin_layer_rename(layer_id)
		btn.accept_event()
	else:
		_layer_rclick_ms[layer_id] = now


func _begin_layer_rename(layer_id: String) -> void:
	var layer := MapSession.get_layer(layer_id)
	if layer == null:
		return
	var btn := _find_layer_name_button(layer_id)
	if btn == null:
		return
	var row: HBoxContainer = btn.get_parent()
	var idx := btn.get_index()
	btn.queue_free()

	var edit := LineEdit.new()
	edit.text = layer.name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.select_all_on_focus = true
	edit.tooltip_text = "Enter to save · Esc to cancel"
	row.add_child(edit)
	row.move_child(edit, idx)
	edit.grab_focus()

	var done := [false]
	var finish := func(apply: bool) -> void:
		if done[0]:
			return
		done[0] = true
		if apply:
			var new_name := edit.text.strip_edges()
			if new_name != "":
				MapSession.rename_layer(layer_id, new_name)
			else:
				_queue_rebuild_layers()
		else:
			_queue_rebuild_layers()

	edit.text_submitted.connect(func(_new_text: String) -> void: finish.call(true))
	edit.focus_exited.connect(func() -> void: finish.call(true))
	edit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
			finish.call(false)
			edit.accept_event()
	)


func _find_layer_name_button(layer_id: String) -> Button:
	for row in layer_list.get_children():
		if row.get_child_count() < 4:
			continue
		var name_btn := row.get_child(2) as Button
		if name_btn != null and str(name_btn.get_meta("layer_id", "")) == layer_id:
			return name_btn
	return null


func _on_marker_selected(marker: MapMarker) -> void:
	var same_marker := _notes_marker_id == marker.id
	_notes_marker_id = marker.id
	notes_empty.visible = false
	notes_editor.visible = true
	_updating_notes_ui = true
	# Avoid resetting text while the user is typing (caret would jump to start).
	if not same_marker or not notes_title.has_focus():
		if notes_title.text != marker.title:
			notes_title.text = marker.title
	if not same_marker or not notes_body.has_focus():
		if notes_body.text != marker.notes:
			notes_body.text = marker.notes
	marker_layer_color.color = MapSession.get_marker_color(marker)
	_set_marker_icon_selection(marker.icon)
	marker_size.value = marker.size
	marker_size_value.text = "%.1fx" % marker.size
	_updating_notes_ui = false


func _on_markers_changed_for_notes() -> void:
	if _notes_marker_id == "":
		return
	var marker := MapSession.get_marker(_notes_marker_id)
	if marker == null:
		return
	if _updating_notes_ui:
		return
	_updating_notes_ui = true
	if not notes_title.has_focus() and notes_title.text != marker.title:
		notes_title.text = marker.title
	if not notes_body.has_focus() and notes_body.text != marker.notes:
		notes_body.text = marker.notes
	marker_layer_color.color = MapSession.get_marker_color(marker)
	_set_marker_icon_selection(marker.icon)
	marker_size.value = marker.size
	marker_size_value.text = "%.1fx" % marker.size
	_updating_notes_ui = false


func _on_selection_cleared() -> void:
	_show_notes_empty()


func _show_notes_empty() -> void:
	_notes_marker_id = ""
	notes_empty.visible = true
	notes_editor.visible = false
	notes_title.text = ""
	notes_body.text = ""


func _on_notes_title_changed(new_text: String) -> void:
	if _updating_notes_ui or _notes_marker_id == "":
		return
	var marker := MapSession.get_marker(_notes_marker_id)
	if marker == null:
		return
	marker.title = new_text
	MapSession.update_marker(marker)


func _on_notes_body_changed() -> void:
	if _updating_notes_ui or _notes_marker_id == "":
		return
	var marker := MapSession.get_marker(_notes_marker_id)
	if marker == null:
		return
	marker.notes = notes_body.text
	MapSession.update_marker(marker)


func _on_marker_icon_selected(_index: int) -> void:
	if _updating_notes_ui or _notes_marker_id == "":
		return
	var marker := MapSession.get_marker(_notes_marker_id)
	if marker == null:
		return
	marker.icon = _get_selected_marker_icon()
	MapSession.update_marker(marker)


func _on_marker_size_changed(value: float) -> void:
	marker_size_value.text = "%.1fx" % value
	if _updating_notes_ui or _notes_marker_id == "":
		return
	var marker := MapSession.get_marker(_notes_marker_id)
	if marker == null:
		return
	marker.size = value
	MapSession.update_marker(marker)


func _on_delete_marker_pressed() -> void:
	if _notes_marker_id == "":
		return
	MapSession.remove_marker(_notes_marker_id)
