class_name Bridge
extends Node
## Talks to the Armada Ports Decky plugin, which can add a non-Steam game to Steam at once (from
## inside Steam, no restart). Requests and answers are small JSON files in
## ~/.local/share/armada-ports/bridge; the plugin touches bridge/alive every few seconds.

const ROOT := "user://bridge"
const ALIVE_FOR := 20

var _pending := {}   # id -> {cb, deadline}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("requests"))
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("responses"))
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(_poll)
	add_child(t)


func alive() -> bool:
	var path := ROOT.path_join("alive")
	if not FileAccess.file_exists(path):
		return false
	var age := int(Time.get_unix_time_from_system()) - int(FileAccess.get_modified_time(path))
	return age < ALIVE_FOR


## cb receives (ok: bool, result: Variant, error: String).
func send(op: String, data: Dictionary, cb: Callable, timeout := 25.0) -> void:
	if not alive():
		cb.call(false, null, "no_bridge")
		return
	var id := "%d-%d" % [Time.get_ticks_usec(), randi() % 100000]
	var body := data.duplicate()
	body["id"] = id
	body["op"] = op
	body["time"] = Time.get_unix_time_from_system()
	var final := ROOT.path_join("requests/%s.json" % id)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		cb.call(false, null, "cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(body))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(final))
	_pending[id] = {"cb": cb, "deadline": Time.get_ticks_msec() + int(timeout * 1000)}


func _poll() -> void:
	for id in _pending.keys():
		var path := ROOT.path_join("responses/%s.json" % id)
		var entry: Dictionary = _pending[id]
		if FileAccess.file_exists(path):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			_pending.erase(id)
			if data is Dictionary:
				entry["cb"].call(bool(data.get("ok", false)), data.get("result"), str(data.get("error", "")))
			else:
				entry["cb"].call(false, null, "bad answer")
		elif Time.get_ticks_msec() > int(entry["deadline"]):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("requests/%s.json" % id)))
			_pending.erase(id)
			entry["cb"].call(false, null, "no_bridge")
