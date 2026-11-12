class_name ArtCache
extends Node
## The ports' SteamGridDB images as textures. The backend downloads them once into
## ~/.local/share/armada-ports/art; here they are decoded off the main thread and kept.

signal loaded(port_id: String)

const MAX_SIZE := {"hero": Vector2i(1920, 620), "grid": Vector2i(600, 900), "wide": Vector2i(920, 430), "logo": Vector2i(800, 400)}

var backend: Backend
var _tex := {}        # path -> Texture2D
var _blur := {}       # path -> small Texture2D for blurred backgrounds
var _loading := {}    # path -> true
var _fetching := {}   # port id -> true
var _mutex := Mutex.new()


func get_tex(port: Dictionary, kind: String) -> Texture2D:
	var path := _path(port, kind)
	if path == "":
		return null
	if _tex.has(path):
		return _tex[path]
	_request(port, kind, path)
	return null


func get_blur(port: Dictionary) -> Texture2D:
	var path := _path(port, "hero")
	if path == "" or not _blur.has(path):
		get_tex(port, "hero")
		return null
	return _blur[path]


func _path(port: Dictionary, kind: String) -> String:
	var art: Variant = port.get("art", {})
	if not art is Dictionary:
		return ""
	var p: Variant = art.get(kind)
	return str(p) if p != null else ""


func _request(port: Dictionary, kind: String, path: String) -> void:
	if _loading.has(path):
		return
	if not FileAccess.file_exists(path):
		_fetch(port)
		return
	_loading[path] = true
	WorkerThreadPool.add_task(_decode.bind(port["id"], kind, path))


## Asks the backend to download the port's missing images, once per run.
func _fetch(port: Dictionary) -> void:
	var id: String = port["id"]
	if _fetching.has(id) or backend == null:
		return
	_fetching[id] = true
	backend.run(["art", id], func(ok: bool, result: Variant, _err: String) -> void:
		if ok and result is Dictionary:
			for kind in result:
				var p := str(result[kind])
				if not _tex.has(p) and not _loading.has(p) and FileAccess.file_exists(p):
					_loading[p] = true
					WorkerThreadPool.add_task(_decode.bind(id, kind, p))
	)


func _decode(id: String, kind: String, path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_done.call_deferred(id, path, null, null)
		return
	if img.is_compressed():
		img.decompress()
	var limit: Vector2i = MAX_SIZE.get(kind, Vector2i(1024, 1024))
	if img.get_width() > limit.x or img.get_height() > limit.y:
		var s: float = min(float(limit.x) / img.get_width(), float(limit.y) / img.get_height())
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
	var small: Image = null
	if kind == "hero":
		# A soft, blurred copy for the background: shrink a lot, then grow back smoothly.
		small = img.duplicate()
		small.resize(48, 16, Image.INTERPOLATE_TRILINEAR if small.has_mipmaps() else Image.INTERPOLATE_BILINEAR)
		small.resize(240, 80, Image.INTERPOLATE_CUBIC)
		small.resize(32, 11, Image.INTERPOLATE_BILINEAR)
		small.resize(320, 104, Image.INTERPOLATE_CUBIC)
	if kind == "grid" or kind == "logo":
		img.generate_mipmaps()
	_done.call_deferred(id, path, img, small)


func _done(id: String, path: String, img: Image, small: Image) -> void:
	_loading.erase(path)
	if img == null:
		return
	_tex[path] = ImageTexture.create_from_image(img)
	if small != null:
		_blur[path] = ImageTexture.create_from_image(small)
	loaded.emit(id)
