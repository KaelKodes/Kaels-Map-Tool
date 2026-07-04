extends Node

## Host spins up an embedded WebSocket lobby server.
## Joiners connect with the host's IP address.

signal connection_changed(connected: bool, is_host: bool)
signal peer_status(text: String)
signal user_colors_changed

const CHUNK_SIZE := 60000

const USER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0),
	Color(0.95, 0.25, 0.25),
	Color(0.25, 0.85, 0.35),
	Color(0.95, 0.85, 0.2),
]

var is_host: bool = false
var lobby_connected: bool = false
var public_ip: String = ""
var local_ip: String = ""
var local_color: Color = USER_COLORS[0]
var peer_colors: Dictionary = {}

var _host_relay: HostRelay
var _http: HTTPRequest
var _image_chunks: Dictionary = {}

var _ws: WebSocketPeer = null
var _my_peer_id: int = 0
var _room_peers: Array[int] = []
var _relay_sender_id: int = 0
var _ws_connecting: bool = false


func _ready() -> void:
	_host_relay = HostRelay.new()
	add_child(_host_relay)
	_host_relay.client_joined.connect(_on_embedded_client_joined)
	_host_relay.client_left.connect(_on_embedded_client_left)
	_host_relay.rpc_received.connect(_on_embedded_rpc)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_public_ip_response)

	set_process(true)


func _process(_delta: float) -> void:
	if _host_relay.is_running:
		_host_relay.poll()
	_poll_ws_client()


func host_lobby() -> Error:
	close_session()
	var err := _host_relay.start()
	if err != OK:
		peer_status.emit("Failed to start lobby (port %d in use?)." % HostRelay.PORT)
		return err

	is_host = true
	lobby_connected = true
	_my_peer_id = 1
	_room_peers = [1]
	local_ip = _detect_local_ip()
	_assign_peer_colors()
	_fetch_public_ip()
	connection_changed.emit(true, true)
	peer_status.emit("Hosting — share your IP with friends (LAN: %s)." % local_ip)
	return OK


func join_lobby(host_ip: String) -> void:
	host_ip = host_ip.strip_edges()
	if host_ip.is_empty():
		peer_status.emit("Enter the host's IP address.")
		return
	close_session()
	_connect_ws_client(host_ip)


func close_session() -> void:
	_ws_connecting = false
	public_ip = ""
	local_ip = ""
	_host_relay.stop()
	_close_ws_client()
	is_host = false
	lobby_connected = false
	_image_chunks.clear()
	peer_colors.clear()
	_my_peer_id = 0
	_room_peers.clear()
	local_color = USER_COLORS[0]
	user_colors_changed.emit()
	connection_changed.emit(false, false)


func get_color_for_peer(peer_id: int) -> Color:
	if peer_colors.has(peer_id):
		return peer_colors[peer_id]
	return USER_COLORS[0]


func get_host_address_hint() -> String:
	if local_ip != "" and public_ip != "" and local_ip != public_ip:
		return "LAN: %s · Internet: %s" % [local_ip, public_ip]
	if public_ip != "":
		return public_ip
	if local_ip != "":
		return local_ip
	return ""


# --- Embedded host server ----------------------------------------------------


func _on_embedded_client_joined(peer_id: int, _peers: Array) -> void:
	_room_peers = _host_relay.get_logical_peers()
	_on_peer_connected(peer_id)


func _on_embedded_client_left(peer_id: int, _peers: Array) -> void:
	_room_peers = _host_relay.get_logical_peers()
	_on_peer_disconnected(peer_id)


func _on_embedded_rpc(from_id: int, method: String, args: Array) -> void:
	_relay_sender_id = from_id
	if has_method(method):
		callv(method, args)


# --- WebSocket client (joiners) ----------------------------------------------


func _connect_ws_client(address: String) -> void:
	_ws = WebSocketPeer.new()
	var url := "ws://%s:%d" % [address.strip_edges(), HostRelay.PORT]
	var err := _ws.connect_to_url(url)
	if err != OK:
		_ws = null
		peer_status.emit("Could not connect to %s." % address)
		return
	_ws_connecting = true
	peer_status.emit("Connecting to %s…" % address)


func _close_ws_client() -> void:
	if _ws != null:
		_ws.close()
		_ws = null


func _poll_ws_client() -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if _ws_connecting:
			_ws_connecting = false
			_send_ws({"op": "join"})
		while _ws.get_available_packet_count() > 0:
			_handle_ws_text(_ws.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		if lobby_connected or _ws_connecting:
			peer_status.emit("Disconnected from lobby.")
		close_session()


func _send_ws(payload: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify(payload))


func _handle_ws_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	match str(data.get("op", "")):
		"joined":
			_my_peer_id = int(data.get("peer_id", 0))
			_room_peers = _parse_peer_list(data.get("peers", []))
			is_host = false
			lobby_connected = true
			_assign_peer_colors()
			connection_changed.emit(true, false)
			peer_status.emit("Connected — syncing map…")
		"peer_connected":
			_room_peers = _parse_peer_list(data.get("peers", _room_peers))
		"peer_disconnected":
			_room_peers = _parse_peer_list(data.get("peers", _room_peers))
			_on_peer_disconnected(int(data.get("peer_id", 0)))
		"error":
			peer_status.emit(str(data.get("msg", "Could not join lobby.")))
			close_session()
		"rpc":
			_relay_sender_id = int(data.get("from", 0))
			var method := str(data.get("method", ""))
			var args: Array = RelayCodec.decode_args(data.get("args", []))
			if has_method(method):
				callv(method, args)


func _parse_peer_list(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(int(item))
	return out


func _local_peer_id() -> int:
	return _my_peer_id if lobby_connected else 0


func _remote_sender_id() -> int:
	return _relay_sender_id


func _get_peer_ids() -> Array:
	var ids: Array = []
	if is_host:
		for peer_id in _host_relay.get_logical_peers():
			if int(peer_id) != 1:
				ids.append(int(peer_id))
	else:
		for peer_id in _room_peers:
			if int(peer_id) != _my_peer_id:
				ids.append(int(peer_id))
	return ids


func _emit_rpc(method: String, args: Array, targets: Array = []) -> void:
	if is_host:
		if targets.is_empty():
			_host_relay.send_rpc_to_all(method, args)
		else:
			for peer_id in targets:
				_host_relay.send_rpc_to_peer(int(peer_id), 1, method, args)
	elif _ws != null:
		_send_ws({
			"op": "rpc",
			"method": method,
			"args": RelayCodec.encode_args(args),
			"targets": targets,
		})


func _detect_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		if addr.contains(":"):
			continue
		if addr.begins_with("127."):
			continue
		return addr
	return "127.0.0.1"


func _fetch_public_ip() -> void:
	_http.request("https://api.ipify.org")


func _on_public_ip_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		return
	public_ip = body.get_string_from_utf8().strip_edges()
	if is_host:
		var hint := get_host_address_hint()
		peer_status.emit("Hosting — friends join with IP: %s (port %d open)." % [hint, HostRelay.PORT])
		connection_changed.emit(true, true)


# --- Session sync ------------------------------------------------------------


func _assign_peer_colors() -> void:
	peer_colors.clear()
	peer_colors[1] = USER_COLORS[0]
	var idx := 1
	if is_host:
		for peer_id in _get_peer_ids():
			peer_colors[int(peer_id)] = USER_COLORS[idx % USER_COLORS.size()]
			idx += 1
		local_color = USER_COLORS[0]
	else:
		var my_id := _local_peer_id()
		if peer_colors.has(my_id):
			local_color = peer_colors[my_id]
	user_colors_changed.emit()


func _broadcast_color_assignments() -> void:
	if not is_host:
		return
	var payload: Dictionary = {}
	for peer_id in peer_colors.keys():
		payload[str(peer_id)] = (peer_colors[peer_id] as Color).to_html(true)
	_emit_rpc("_rpc_set_peer_colors", [payload])


func _on_peer_connected(id: int) -> void:
	peer_status.emit("Player joined.")
	if is_host:
		_assign_peer_colors()
		_broadcast_color_assignments()
		_send_full_state_to(id)


func _on_peer_disconnected(id: int) -> void:
	peer_status.emit("Player left.")
	_image_chunks.erase(id)
	if is_host:
		_assign_peer_colors()
		_broadcast_color_assignments()


func _send_full_state_to(peer_id: int) -> void:
	var state := MapSession.export_state()
	_emit_rpc("_rpc_apply_state", [state], [peer_id])
	if MapSession.map_image_png.size() > 0:
		_send_image_to(peer_id, MapSession.map_image_png)


func _send_image_to(peer_id: int, bytes: PackedByteArray) -> void:
	var total := ceili(float(bytes.size()) / float(CHUNK_SIZE))
	if total == 0:
		return
	_emit_rpc("_rpc_image_begin", [bytes.size(), total], [peer_id])
	for i in total:
		var start := i * CHUNK_SIZE
		var end := mini(start + CHUNK_SIZE, bytes.size())
		_emit_rpc("_rpc_image_chunk", [i, bytes.slice(start, end)], [peer_id])


func broadcast_map_image() -> void:
	if not lobby_connected or MapSession.map_image_png.is_empty():
		return
	if is_host:
		for peer_id in _get_peer_ids():
			_send_image_to(int(peer_id), MapSession.map_image_png)
	else:
		_send_image_to(1, MapSession.map_image_png)


func broadcast_full_document() -> void:
	if not lobby_connected:
		return
	var state := MapSession.export_state()
	if is_host:
		for peer_id in _get_peer_ids():
			_emit_rpc("_rpc_apply_state", [state], [peer_id])
			if MapSession.map_image_png.size() > 0:
				_send_image_to(int(peer_id), MapSession.map_image_png)
	else:
		_emit_rpc("_rpc_apply_state", [state], [1])
		if MapSession.map_image_png.size() > 0:
			_send_image_to(1, MapSession.map_image_png)


func broadcast_layer_upsert(layer: MapLayer) -> void:
	if not lobby_connected:
		return
	_emit_rpc("_rpc_layer_upsert", [layer.to_dict()])


func broadcast_layer_remove(layer_id: String) -> void:
	if not lobby_connected:
		return
	_emit_rpc("_rpc_layer_remove", [layer_id])


func broadcast_marker_upsert(marker: MapMarker) -> void:
	if not lobby_connected:
		return
	_emit_rpc("_rpc_marker_upsert", [marker.to_dict()])


func broadcast_marker_remove(marker_id: String) -> void:
	if not lobby_connected:
		return
	_emit_rpc("_rpc_marker_remove", [marker_id])


func broadcast_ping(uv: Vector2, color: Color) -> void:
	if not lobby_connected:
		return
	_emit_rpc("_rpc_ping", [uv, color.to_html(true)])


func _apply_remote_image(bytes: PackedByteArray) -> void:
	MapSession.suppress_network = true
	await MapSession.set_map_from_png_bytes(bytes)
	MapSession.suppress_network = false


@rpc("any_peer", "reliable")
func _rpc_set_peer_colors(payload: Dictionary) -> void:
	peer_colors.clear()
	for key in payload.keys():
		peer_colors[int(key)] = Color.html(str(payload[key]))
	var my_id := _local_peer_id()
	if peer_colors.has(my_id):
		local_color = peer_colors[my_id]
	elif peer_colors.has(1):
		local_color = peer_colors[1]
	user_colors_changed.emit()


@rpc("any_peer", "reliable")
func _rpc_apply_state(state: Dictionary) -> void:
	MapSession.suppress_network = true
	MapSession.import_state(state)
	MapSession.suppress_network = false
	if is_host:
		var sender := _remote_sender_id()
		for peer_id in _get_peer_ids():
			if int(peer_id) != sender:
				_emit_rpc("_rpc_apply_state", [state], [int(peer_id)])


@rpc("any_peer", "reliable")
func _rpc_image_begin(_byte_size: int, _total_chunks: int) -> void:
	var sender := _remote_sender_id()
	_image_chunks[sender] = {"total": _total_chunks, "parts": {}}
	MapSession.status_message.emit("Receiving map image…")


@rpc("any_peer", "reliable")
func _rpc_image_chunk(index: int, chunk: PackedByteArray) -> void:
	var sender := _remote_sender_id()
	if not _image_chunks.has(sender):
		return
	var entry: Dictionary = _image_chunks[sender]
	entry["parts"][index] = chunk
	if entry["parts"].size() < int(entry["total"]):
		return
	var bytes := PackedByteArray()
	for i in int(entry["total"]):
		bytes.append_array(entry["parts"][i])
	_image_chunks.erase(sender)
	await _apply_remote_image(bytes)
	if is_host and sender != _local_peer_id():
		for peer_id in _get_peer_ids():
			if int(peer_id) != sender:
				_send_image_to(int(peer_id), bytes)


@rpc("any_peer", "reliable")
func _rpc_layer_upsert(data: Dictionary) -> void:
	MapSession.suppress_network = true
	MapSession.upsert_layer_from_dict(data)
	MapSession.suppress_network = false
	if is_host:
		_relay_except_sender("_rpc_layer_upsert", data)


@rpc("any_peer", "reliable")
func _rpc_layer_remove(layer_id: String) -> void:
	MapSession.suppress_network = true
	MapSession.remove_layer(layer_id, false)
	MapSession.suppress_network = false
	if is_host:
		_relay_except_sender("_rpc_layer_remove", layer_id)


@rpc("any_peer", "reliable")
func _rpc_marker_upsert(data: Dictionary) -> void:
	MapSession.suppress_network = true
	MapSession.upsert_marker_from_dict(data)
	MapSession.suppress_network = false
	if is_host:
		_relay_except_sender("_rpc_marker_upsert", data)


@rpc("any_peer", "reliable")
func _rpc_marker_remove(marker_id: String) -> void:
	MapSession.suppress_network = true
	MapSession.remove_marker(marker_id, false)
	MapSession.suppress_network = false
	if is_host:
		_relay_except_sender("_rpc_marker_remove", marker_id)


@rpc("any_peer", "reliable")
func _rpc_ping(uv: Vector2, color_html: String) -> void:
	MapSession.suppress_network = true
	MapSession.issue_ping(uv, Color.html(color_html), false)
	MapSession.suppress_network = false
	if is_host:
		var sender := _remote_sender_id()
		for peer_id in _get_peer_ids():
			if int(peer_id) != sender:
				_emit_rpc("_rpc_ping", [uv, color_html], [int(peer_id)])


func _relay_except_sender(method: String, payload: Variant) -> void:
	var sender := _remote_sender_id()
	for peer_id in _get_peer_ids():
		if int(peer_id) == sender:
			continue
		_emit_rpc(method, [payload], [int(peer_id)])
