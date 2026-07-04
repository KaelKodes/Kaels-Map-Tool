class_name ProjectIO
extends RefCounted

## Saves/loads a .kmap project: zip with manifest.json + optional map.png

const FORMAT_VERSION := 1
const MANIFEST_NAME := "manifest.json"
const MAP_NAME := "map.png"


static func save(path: String, state: Dictionary, map_png: PackedByteArray) -> Error:
	var packer := ZIPPacker.new()
	var err := packer.open(path)
	if err != OK:
		return err

	var manifest := {
		"version": FORMAT_VERSION,
		"layers": state.get("layers", []),
		"markers": state.get("markers", []),
		"active_layer_id": state.get("active_layer_id", ""),
	}
	var manifest_bytes := JSON.stringify(manifest, "\t").to_utf8_buffer()

	err = packer.start_file(MANIFEST_NAME)
	if err != OK:
		packer.close()
		return err
	err = packer.write_file(manifest_bytes)
	if err != OK:
		packer.close()
		return err
	err = packer.close_file()
	if err != OK:
		packer.close()
		return err

	if map_png.size() > 0:
		err = packer.start_file(MAP_NAME)
		if err != OK:
			packer.close()
			return err
		err = packer.write_file(map_png)
		if err != OK:
			packer.close()
			return err
		err = packer.close_file()
		if err != OK:
			packer.close()
			return err

	return packer.close()


static func load(path: String) -> Dictionary:
	## Returns { "ok": bool, "error": String, "state": Dictionary, "map_png": PackedByteArray }
	var reader := ZIPReader.new()
	var err := reader.open(path)
	if err != OK:
		return {"ok": false, "error": "Could not open file.", "state": {}, "map_png": PackedByteArray()}

	if not reader.file_exists(MANIFEST_NAME):
		reader.close()
		return {"ok": false, "error": "Not a valid map project (missing manifest).", "state": {}, "map_png": PackedByteArray()}

	var manifest_bytes := reader.read_file(MANIFEST_NAME)
	var parsed: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		reader.close()
		return {"ok": false, "error": "Project manifest is corrupt.", "state": {}, "map_png": PackedByteArray()}

	var manifest: Dictionary = parsed
	var version := int(manifest.get("version", 0))
	if version > FORMAT_VERSION:
		reader.close()
		return {"ok": false, "error": "Project was saved with a newer version of the tool.", "state": {}, "map_png": PackedByteArray()}

	var map_png := PackedByteArray()
	if reader.file_exists(MAP_NAME):
		map_png = reader.read_file(MAP_NAME)
	reader.close()

	var state := {
		"layers": manifest.get("layers", []),
		"markers": manifest.get("markers", []),
		"active_layer_id": manifest.get("active_layer_id", ""),
	}
	return {"ok": true, "error": "", "state": state, "map_png": map_png}
