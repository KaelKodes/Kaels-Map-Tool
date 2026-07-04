class_name RelayCodec
extends RefCounted

## JSON-safe encoding for WebSocket relay RPC args.


static func encode_args(args: Array) -> Array:
	var out: Array = []
	for arg in args:
		out.append(encode_var(arg))
	return out


static func decode_args(encoded: Array) -> Array:
	var out: Array = []
	for item in encoded:
		out.append(decode_var(item))
	return out


static func encode_var(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_DICTIONARY:
			return value
		TYPE_ARRAY:
			var arr: Array = []
			for item in value:
				arr.append(encode_var(item))
			return {"__t": "array", "v": arr}
		TYPE_PACKED_BYTE_ARRAY:
			return {"__t": "bytes", "v": Marshalls.raw_to_base64(value)}
		TYPE_VECTOR2:
			return {"__t": "v2", "x": value.x, "y": value.y}
		TYPE_COLOR:
			return {"__t": "color", "v": value.to_html(true)}
		_:
			return str(value)


static func decode_var(value: Variant) -> Variant:
	if value == null:
		return null
	if typeof(value) != TYPE_DICTIONARY:
		return value
	var data: Dictionary = value
	if not data.has("__t"):
		return data
	match str(data["__t"]):
		"array":
			var arr: Array = []
			for item in data.get("v", []):
				arr.append(decode_var(item))
			return arr
		"bytes":
			return Marshalls.base64_to_raw(str(data.get("v", "")))
		"v2":
			return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		"color":
			return Color.html(str(data.get("v", "#ffffffff")))
		_:
			return data
