class_name ImageUpscaler
extends RefCounted

## Upscales a map screenshot so pan/zoom stays sharp.
## Uses Lanczos (high quality) at 2x or 4x depending on source size.


const MIN_LONG_EDGE := 4096
const MAX_LONG_EDGE := 8192


static func upscale(source: Image) -> Image:
	if source == null or source.is_empty():
		return source

	var img: Image = source.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var w: int = img.get_width()
	var h: int = img.get_height()
	var long_edge: int = maxi(w, h)

	if long_edge >= MIN_LONG_EDGE:
		return img

	var scale := 2
	if long_edge * 4 <= MAX_LONG_EDGE:
		scale = 4
	elif long_edge * 2 <= MAX_LONG_EDGE:
		scale = 2
	else:
		return img

	img.resize(w * scale, h * scale, Image.INTERPOLATE_LANCZOS)
	return img


static func load_and_upscale(path: String) -> Image:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_error("Failed to load image: %s (error %d)" % [path, err])
		return null
	return upscale(img)


static func from_bytes_and_upscale(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		err = img.load_jpg_from_buffer(bytes)
	if err != OK:
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		push_error("Failed to decode image bytes (error %d)" % err)
		return null
	return upscale(img)
