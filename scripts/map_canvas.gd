extends Control

const MarkerIconsLib = preload("res://scripts/marker_icons.gd")

## Pan/zoom map view with clickable markers and pings.

signal marker_clicked(marker_id: String)
signal map_clicked_empty

const MARKER_RADIUS := 10.0
const ZOOM_MIN := 0.15
const ZOOM_MAX := 12.0
const ZOOM_STEP := 0.1
const PING_MIN_RADIUS := 12.0
const PING_MAX_RADIUS := 110.0

var _texture: Texture2D = null
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _dragging_map: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_pan: Vector2 = Vector2.ZERO
var _placing_marker: bool = false
var _hover_marker_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)
	MapSession.map_image_changed.connect(_on_map_image_changed)
	MapSession.markers_changed.connect(queue_redraw)
	MapSession.layers_changed.connect(queue_redraw)
	MapSession.marker_selected.connect(func(_m): queue_redraw())
	MapSession.selection_cleared.connect(queue_redraw)
	MapSession.pings_changed.connect(queue_redraw)
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if MapSession.active_pings.is_empty():
		return
	if MapSession.prune_pings():
		queue_redraw()
	elif not MapSession.active_pings.is_empty():
		queue_redraw()


func set_placing_marker(enabled: bool) -> void:
	_placing_marker = enabled
	mouse_default_cursor_shape = Control.CURSOR_CROSS if enabled else Control.CURSOR_ARROW


func _on_map_image_changed(texture: Texture2D) -> void:
	_texture = texture
	_fit_map()
	queue_redraw()


func _fit_map() -> void:
	if _texture == null or size.x <= 0.0 or size.y <= 0.0:
		_zoom = 1.0
		_pan = Vector2.ZERO
		return
	var tex_size := _texture.get_size()
	var scale_x := size.x / tex_size.x
	var scale_y := size.y / tex_size.y
	_zoom = minf(scale_x, scale_y) * 0.95
	var drawn := tex_size * _zoom
	_pan = (size - drawn) * 0.5


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.13, 0.16))
	if _texture == null:
		var msg := "Upload a map screenshot to begin"
		var font := ThemeDB.fallback_font
		var font_size := 18
		var text_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, (size - text_size) * 0.5, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.72, 0.78))
		return

	var tex_size := _texture.get_size()
	var dest := Rect2(_pan, tex_size * _zoom)
	draw_texture_rect(_texture, dest, false)

	_draw_pings()

	for marker in MapSession.get_visible_markers():
		var pos := _uv_to_screen(marker.position)
		var selected := marker.id == MapSession.selected_marker_id
		var hover := marker.id == _hover_marker_id
		var radius := MARKER_RADIUS * marker.size * (1.35 if selected or hover else 1.0)
		var fill := MapSession.get_marker_color(marker)
		var outline := Color.WHITE if selected else Color(0, 0, 0, 0.85)
		MarkerIconsLib.draw_marker(self, marker.icon, pos, radius, fill, outline, selected)

		var label := marker.title
		var font := ThemeDB.fallback_font
		var font_size := 13
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_pos := pos + Vector2(-text_size.x * 0.5, -radius - 8.0)
		draw_rect(Rect2(text_pos - Vector2(4, text_size.y), text_size + Vector2(8, 4)), Color(0, 0, 0, 0.65))
		draw_string(font, text_pos - Vector2(0, 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_pings() -> void:
	var now := Time.get_ticks_msec()
	for ping in MapSession.get_live_pings():
		var start_ms := int(ping.get("start_ms", now))
		var t := clampf(float(now - start_ms) / float(MapSession.PING_DURATION_MS), 0.0, 1.0)
		var pos := _uv_to_screen(ping.get("uv", Vector2.ZERO))
		var radius := lerpf(PING_MIN_RADIUS, PING_MAX_RADIUS, t)
		var base: Color = ping.get("color", Color.WHITE)
		var ring := Color(base.r, base.g, base.b, (1.0 - t) * 0.95)
		var fill := Color(base.r, base.g, base.b, (1.0 - t) * 0.18)
		draw_circle(pos, radius, fill)
		draw_arc(pos, radius, 0.0, TAU, 48, ring, 3.0)
		# Inner pulse
		var inner_t := fmod(t * 2.0, 1.0)
		var inner_radius := lerpf(4.0, PING_MAX_RADIUS * 0.55, inner_t)
		var inner := Color(base.r, base.g, base.b, (1.0 - inner_t) * (1.0 - t) * 0.8)
		draw_arc(pos, inner_radius, 0.0, TAU, 32, inner, 2.0)


func _uv_to_screen(uv: Vector2) -> Vector2:
	if _texture == null:
		return Vector2.ZERO
	return _pan + uv * _texture.get_size() * _zoom


func _screen_to_uv(screen: Vector2) -> Vector2:
	if _texture == null:
		return Vector2.ZERO
	return (screen - _pan) / (_texture.get_size() * _zoom)


func _marker_at(screen_pos: Vector2) -> MapMarker:
	var best: MapMarker = null
	var best_dist := INF
	for marker in MapSession.get_visible_markers():
		var pos := _uv_to_screen(marker.position)
		var hit_radius := MARKER_RADIUS * marker.size * 1.2 + 6.0
		var dist := screen_pos.distance_to(pos)
		if dist <= hit_radius and dist < best_dist:
			best = marker
			best_dist = dist
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.0 + ZOOM_STEP)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 - ZOOM_STEP)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_map = mb.pressed
			_drag_start_mouse = mb.position
			_drag_start_pan = _pan
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_map = mb.pressed
			_drag_start_mouse = mb.position
			_drag_start_pan = _pan
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_left_click(mb.position, mb.ctrl_pressed)
			accept_event()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_map:
			_pan = _drag_start_pan + (mm.position - _drag_start_mouse)
			queue_redraw()
			accept_event()
		else:
			var hovered := _marker_at(mm.position)
			var new_id := hovered.id if hovered else ""
			if new_id != _hover_marker_id:
				_hover_marker_id = new_id
				queue_redraw()


func _handle_left_click(screen_pos: Vector2, ctrl_pressed: bool) -> void:
	if _texture == null:
		return

	if ctrl_pressed:
		var ping_uv := _screen_to_uv(screen_pos)
		if ping_uv.x < 0.0 or ping_uv.y < 0.0 or ping_uv.x > 1.0 or ping_uv.y > 1.0:
			return
		MapSession.issue_ping(ping_uv, NetworkManager.local_color)
		return

	var hit := _marker_at(screen_pos)
	if hit:
		MapSession.select_marker(hit.id)
		marker_clicked.emit(hit.id)
		return

	if _placing_marker:
		var uv := _screen_to_uv(screen_pos)
		if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
			return
		MapSession.add_marker_at_uv(uv)
		_placing_marker = false
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return

	MapSession.clear_selection()
	map_clicked_empty.emit()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	if _texture == null:
		return
	var old_zoom := _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(_zoom, old_zoom):
		return
	var before := (screen_pos - _pan) / old_zoom
	_pan = screen_pos - before * _zoom
	queue_redraw()
