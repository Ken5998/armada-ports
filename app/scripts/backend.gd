class_name Backend
extends Node
## Runs `python3 armadaports.py cli ...` off the main thread and hands back its JSON answer.
## armadaports.py and ports.json sit next to the app (the Decky plugin copies them there), or
## where ARMADA_PORTS_BACKEND points (a folder with both, for development).

var python := "python3"
var script_path := ""
var catalog := ""
var _threads: Array[Thread] = []


func _ready() -> void:
	var dir := OS.get_environment("ARMADA_PORTS_BACKEND")
	if dir == "":
		dir = OS.get_executable_path().get_base_dir()
	if not FileAccess.file_exists(dir.path_join("armadaports.py")) and OS.has_feature("editor"):
		dir = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	for candidate in [dir.path_join("armadaports.py"), dir.path_join("py_modules/armadaports.py")]:
		if FileAccess.file_exists(candidate):
			script_path = candidate
			break
	catalog = dir
	for p in ["/usr/bin/python3", "/usr/local/bin/python3"]:
		if FileAccess.file_exists(p):
			python = p
			break


func available() -> bool:
	return script_path != "" and FileAccess.file_exists(catalog.path_join("ports.json"))


## Calls the backend; done receives (ok: bool, result: Variant, error: String).
func run(args: Array, done: Callable) -> void:
	var t := Thread.new()
	_threads.append(t)
	t.start(_work.bind(args, done, t))


func _work(args: Array, done: Callable, t: Thread) -> void:
	var out: Array = []
	var full: PackedStringArray = [script_path, "cli", "--catalog", catalog]
	for a in args:
		full.append(str(a))
	var code := OS.execute(python, full, out, false)
	var text := "".join(out).strip_edges()
	# The answer is the last line; anything printed before it is noise.
	var last := text.get_slice("\n", text.count("\n"))
	var data: Variant = JSON.parse_string(last)
	_finish.call_deferred(t, done, data, text, code)


func _finish(t: Thread, done: Callable, data: Variant, text: String, code: int) -> void:
	t.wait_to_finish()
	_threads.erase(t)
	if data is Dictionary:
		done.call(bool(data.get("ok", false)), data.get("result"), str(data.get("error", "")))
	elif code == -1 or code == 127:
		done.call(false, null, L.t("python_missing"))
	else:
		done.call(false, null, text.substr(0, 300) if text != "" else "exit %d" % code)


func _exit_tree() -> void:
	for t in _threads:
		t.wait_to_finish()
