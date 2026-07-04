extends Node
class_name HostRelay

## WebSocket lobby server embedded in the host's game process.
## Uses TCPServer + WebSocketPeer (WebSocketServer is not in all Godot builds).

signal client_joined(peer_id: int, peers: Array)
signal client_left(peer_id: int, peers: Array)
signal rpc_received(from_id: int, method: String, args: Array)

const PORT := 9090
const MAX_CLIENTS := 4

var is_running: bool = false

var _tcp_server: TCPServer = null
var _next_conn_id: int = 1
var _logical_next: int = 2
var _peers: Dictionary = {}  # conn_id (int) -> WebSocketPeer
var _ws_to_logical: Dictionary = {}
var _logical_to_ws: Dictionary = {}


func start() -> Error:
	stop()
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(PORT, "0.0.0.0")
	if err != OK:
		_tcp_server = null
		return err
	is_running = true
	_next_conn_id = 1
	_logical_next = 2
	_peers.clear()
	_ws_to_logical.clear()
	_logical_to_ws.clear()
	return OK


func stop() -> void:
	for conn_id in _peers.keys():
		var ws: WebSocketPeer = _peers[conn_id]
		ws.close()
	_peers.clear()
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null
	is_running = false
	_ws_to_logical.clear()
	_logical_to_ws.clear()


func poll() -> void:
	if _tcp_server == null:
		return

	while _tcp_server.is_connection_available():
		var tcp: StreamPeerTCP = _tcp_server.take_connection()
		var ws := WebSocketPeer.new()
		var err := ws.accept_stream(tcp)
		if err != OK:
			tcp.disconnect_from_host()
			continue
		var conn_id := _next_conn_id
		_next_conn_id += 1
		_peers[conn_id] = ws

	var dead: Array[int] = []
	for conn_id in _peers.keys():
		var ws: WebSocketPeer = _peers[conn_id]
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			dead.append(int(conn_id))
			continue
		if state != WebSocketPeer.STATE_OPEN:
			continue
		while ws.get_available_packet_count() > 0:
			var packet: PackedByteArray = ws.get_packet()
			_handle_packet(int(conn_id), packet.get_string_from_utf8())

	for conn_id in dead:
		_remove_conn(int(conn_id))


func get_logical_peers() -> Array[int]:
	var ids: Array[int] = [1]
	for logical_id in _logical_to_ws.keys():
		ids.append(int(logical_id))
	ids.sort()
	return ids


func send_rpc(from_id: int, method: String, args: Array, targets: Array = []) -> void:
	var payload := {
		"op": "rpc",
		"from": from_id,
		"method": method,
		"args": RelayCodec.encode_args(args),
	}
	if targets.is_empty():
		for logical_id in _logical_to_ws.keys():
			if int(logical_id) == from_id:
				continue
			_send_raw(int(_logical_to_ws[logical_id]), payload)
	else:
		for target in targets:
			var logical_id := int(target)
			if _logical_to_ws.has(logical_id) and logical_id != from_id:
				_send_raw(int(_logical_to_ws[logical_id]), payload)


func send_rpc_to_all(method: String, args: Array, except_logical: int = -1) -> void:
	send_rpc(1, method, args, [] if except_logical < 0 else _all_targets_except(except_logical))


func send_rpc_to_peer(logical_id: int, from_id: int, method: String, args: Array) -> void:
	send_rpc(from_id, method, args, [logical_id])


func _all_targets_except(except_logical: int) -> Array:
	var targets: Array = []
	for logical_id in _logical_to_ws.keys():
		if int(logical_id) != except_logical:
			targets.append(int(logical_id))
	return targets


func _handle_packet(conn_id: int, text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var op := str(data.get("op", ""))

	if op == "join":
		if _logical_to_ws.size() >= MAX_CLIENTS - 1:
			_send_raw(conn_id, {"op": "error", "msg": "Lobby is full."})
			_disconnect_conn(conn_id)
			return
		var logical_id := _logical_next
		_logical_next += 1
		_ws_to_logical[conn_id] = logical_id
		_logical_to_ws[logical_id] = conn_id
		var peers := get_logical_peers()
		_send_raw(conn_id, {"op": "joined", "peer_id": logical_id, "peers": peers})
		for other_logical in _logical_to_ws.keys():
			if int(other_logical) == logical_id:
				continue
			_send_raw(int(_logical_to_ws[other_logical]), {
				"op": "peer_connected",
				"peer_id": logical_id,
				"peers": peers,
			})
		client_joined.emit(logical_id, peers)
		return

	if op == "rpc":
		if not _ws_to_logical.has(conn_id):
			return
		var from_id: int = int(_ws_to_logical[conn_id])
		var method := str(data.get("method", ""))
		var args: Array = RelayCodec.decode_args(data.get("args", []))
		rpc_received.emit(from_id, method, args)
		return


func _send_raw(conn_id: int, payload: Dictionary) -> void:
	if not _peers.has(conn_id):
		return
	var ws: WebSocketPeer = _peers[conn_id]
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	ws.send_text(JSON.stringify(payload))


func _disconnect_conn(conn_id: int) -> void:
	if _peers.has(conn_id):
		_peers[conn_id].close()
		_peers.erase(conn_id)


func _remove_conn(conn_id: int) -> void:
	if _ws_to_logical.has(conn_id):
		var logical_id: int = int(_ws_to_logical[conn_id])
		_ws_to_logical.erase(conn_id)
		_logical_to_ws.erase(logical_id)
		_peers.erase(conn_id)
		var peers := get_logical_peers()
		for other_logical in _logical_to_ws.keys():
			_send_raw(int(_logical_to_ws[other_logical]), {
				"op": "peer_disconnected",
				"peer_id": logical_id,
				"peers": peers,
			})
		client_left.emit(logical_id, peers)
	else:
		_peers.erase(conn_id)
