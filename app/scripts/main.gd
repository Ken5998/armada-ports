extends Control
## Armada Ports: the ARM64 ports for ArmadaOS, made to be used from Game Mode with the controller.
## It shows the catalog, installs and updates ports through the backend (armadaports.py, the same
## code the Decky plugin uses) and starts the games.

var backend: Backend
var art: ArtCache
var bridge: Bridge
var home: HomeScreen
var details: DetailsScreen
var picker: Picker
var confirm: ConfirmBox
var toast: Toast
var ports: Array = []
var steam := {}            # port id -> its Steam shortcut id (0: not in the library)
var _jobs := {}            # port id -> last job state seen
var _loading: Label
var _curtain: ColorRect
var _ticks := 0
var _busy := false
var _held := ""
var _held_t := 0.0
var _repeat_t := 0.0
var _version := ""


func _ready() -> void:
	L.setup()
	UI.setup()
	theme = UI.theme
	UI.fill(self)
	_version = str(ProjectSettings.get_setting("application/config/version", ""))
	_setup_input()

	backend = Backend.new()
	add_child(backend)
	art = ArtCache.new()
	art.backend = backend
	add_child(art)
	art.loaded.connect(_on_art)
	bridge = Bridge.new()
	add_child(bridge)

	home = HomeScreen.new()
	home.art = art
	add_child(home)
	home.open_port.connect(_open)
	home.play_port.connect(_play)
	home.check_updates.connect(_check.bind(true))
	home.quit_app.connect(_ask_quit)

	details = DetailsScreen.new()
	details.art = art
	details.visible = false
	add_child(details)
	details.back.connect(_close_details)
	details.action.connect(_on_action)

	picker = Picker.new()
	picker.backend = backend
	picker.visible = false
	add_child(picker)
	confirm = ConfirmBox.new()
	confirm.visible = false
	add_child(confirm)
	toast = Toast.new()
	add_child(toast)

	_loading = UI.label(L.t("loading"), 20, UI.MUTED, 500, true)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_loading)
	_curtain = ColorRect.new()
	_curtain.color = Color.BLACK
	_curtain.modulate.a = 0.0
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.fill(_curtain))

	if OS.get_environment("ARMADA_PORTS_AUTOPILOT") != "":
		add_child(load("res://scripts/autopilot.gd").new())
	if not backend.available():
		_loading.text = "armadaports.py / ports.json not found next to the app."
		return
	_refresh(true)
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)
	_check(false)


func _setup_input() -> void:
	_bind("ui_accept", [JOY_BUTTON_A], [])
	_bind("ui_cancel", [JOY_BUTTON_B], [KEY_BACKSPACE])
	_bind("ui_left", [JOY_BUTTON_DPAD_LEFT], [], [JOY_AXIS_LEFT_X, -1.0])
	_bind("ui_right", [JOY_BUTTON_DPAD_RIGHT], [], [JOY_AXIS_LEFT_X, 1.0])
	_bind("ui_up", [JOY_BUTTON_DPAD_UP], [], [JOY_AXIS_LEFT_Y, -1.0])
	_bind("ui_down", [JOY_BUTTON_DPAD_DOWN], [], [JOY_AXIS_LEFT_Y, 1.0])
	_bind("act_x", [JOY_BUTTON_X], [KEY_X, KEY_P])
	_bind("act_y", [JOY_BUTTON_Y], [KEY_Y, KEY_F5])
	_bind("page_prev", [JOY_BUTTON_LEFT_SHOULDER], [KEY_Q, KEY_PAGEUP])
	_bind("page_next", [JOY_BUTTON_RIGHT_SHOULDER], [KEY_E, KEY_PAGEDOWN])


func _bind(action: String, buttons: Array, keys: Array, axis: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		if not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		if not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)
	if not axis.is_empty():
		var e := InputEventJoypadMotion.new()
		e.axis = axis[0]
		e.axis_value = axis[1]
		if not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)


# --- Data -------------------------------------------------------------------------------------

func _refresh(first := false) -> void:
	if _busy and not first:
		return
	_busy = true
	backend.run(["overview"], func(ok: bool, result: Variant, err: String) -> void:
		_busy = false
		if not ok:
			if first:
				_loading.text = err
			else:
				toast.say(err, UI.RED)
			return
		_loading.visible = false
		_apply(result.get("ports", []), first)
	)


func _apply(list: Array, first: bool) -> void:
	for p in list:
		var job: Variant = p.get("job")
		var state := str(job.get("state", "")) if job is Dictionary else ""
		var before := str(_jobs.get(p["id"], ""))
		if before == "running" and state == "done":
			toast.say(L.t("done", p["name"]), UI.GREEN)
		elif before == "running" and state == "failed":
			toast.say(L.t("failed", p["name"]), UI.RED)
		_jobs[p["id"]] = state
	ports = list
	if first:
		home.set_ports(ports)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--focus="):
				home.focus_id(arg.substr(8))
		_steam_status()
	else:
		home.update_ports(ports)
	if details.visible:
		var p := _port(details.port.get("id", ""))
		if not p.is_empty():
			details.refresh(p, _in_steam(p["id"]))


func _in_steam(id: String) -> bool:
	return int(steam.get(id, 0)) != 0


func _port(id: String) -> Dictionary:
	for p in ports:
		if p["id"] == id:
			return p
	return {}


func _tick() -> void:
	_ticks += 1
	var running := ports.any(func(p): return PortInfo.job_running(p))
	if running or _ticks % 5 == 0:
		_refresh()
	if details.visible and PortInfo.job_running(details.port):
		var id: String = details.port["id"]
		backend.run(["tail", id], func(ok: bool, result: Variant, _e: String) -> void:
			if ok and details.visible and details.port.get("id") == id:
				details.set_log(result.get("lines", []))
		)
	if _ticks % 15 == 0:
		_steam_status()


func _steam_status() -> void:
	if not bridge.alive():
		return
	bridge.send("steam_status", {}, func(ok: bool, result: Variant, _e: String) -> void:
		if ok and result is Dictionary:
			steam = result
			if details.visible:
				details.refresh(_port(details.port.get("id", "")), _in_steam(details.port.get("id", "")))
	)


func _check(refresh: bool) -> void:
	if refresh:
		toast.say(L.t("checking"))
	var args := ["check", "--current", _version]
	if refresh:
		args.insert(1, "--refresh")
	backend.run(args, func(ok: bool, result: Variant, err: String) -> void:
		if not ok:
			if refresh:
				toast.say(err, UI.RED)
			return
		var news: Array = result.get("news", [])
		if not news.is_empty():
			toast.say(L.t("news", ", ".join(news.map(func(n): return "%s %s" % [n["name"], PortInfo.version_text(str(n["version"]))]))), UI.AMBER)
		elif refresh:
			toast.say(L.t("up_to_date"), UI.GREEN)
		var plugin: Variant = result.get("plugin")
		if plugin is Dictionary and plugin.get("version"):
			toast.say(L.t("app_update", PortInfo.version_text(str(plugin["version"]))), UI.ACCENT)
		_refresh()
	)


func _on_art(id: String) -> void:
	home.art_ready(id)
	details.art_ready(id)


# --- Screens ----------------------------------------------------------------------------------

func _open(id: String) -> void:
	var p := _port(id)
	if p.is_empty():
		return
	details.show_port(p, _in_steam(id))
	details.visible = true
	details.modulate.a = 0.0
	details.position.x = 40
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(details, "modulate:a", 1.0, 0.22)
	tw.tween_property(details, "position:x", 0.0, 0.22)
	details.focus_first.call_deferred()
	_steam_status()


func _close_details() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	home.focus_id(details.port.get("id", ""))
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(details, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func(): details.visible = false)


func _ask_quit() -> void:
	confirm.ask(L.t("quit_title"), L.t("quit_text"), L.t("quit"), func(ok: bool) -> void:
		if ok:
			get_tree().quit()
	)


# --- Actions ----------------------------------------------------------------------------------

func _on_action(id: String, what: String) -> void:
	var p := _port(id)
	if p.is_empty():
		return
	match what:
		"play":
			_play(id)
		"install":
			_install(p, "install")
		"resume":
			_install(p, "install")
		"update":
			_install(p, "update")
		"steam":
			_add_to_steam(p)
		"remove":
			confirm.ask(L.t("remove_title", p["name"]), L.t("remove_text"), L.t("remove"), func(ok: bool) -> void:
				if ok:
					_uninstall(p))
		"stop":
			confirm.ask(L.t("stop_title"), L.t("stop_text"), L.t("stop"), func(ok: bool) -> void:
				if ok:
					backend.run(["cancel", id], func(_ok: bool, _r: Variant, _e: String) -> void: _refresh()))


## Install, finish or update: asks for the disc image (and BIOS) only when the port needs it and
## the game files are not extracted yet, then confirms with the build time.
func _install(p: Dictionary, action: String) -> void:
	var needs: Array = p.get("needs", [])
	var have_files := bool(PortInfo.installed(p).get("game_files", false))
	var after_iso := func(iso: String) -> void:
		var after_bios := func(bios: String) -> void:
			var title := L.t("update_title" if action == "update" else "install_title", p["name"])
			var text := L.t("update_text") if action == "update" else L.t("install_text", PortInfo.build_time(p))
			confirm.ask(title, text, L.t("install") if action == "install" else L.t("update_to", PortInfo.version_text(PortInfo.latest_version(p))),
				func(ok: bool) -> void:
					if ok:
						_start(p, action, iso, bios))
		if "bios" in needs and not have_files:
			_pick("bios", after_bios)
		else:
			after_bios.call("")
	if "iso" in needs and not have_files:
		_pick("iso", after_iso)
	else:
		after_iso.call("")


func _pick(kind: String, then: Callable) -> void:
	for c in picker.picked.get_connections():
		picker.picked.disconnect(c["callable"])
	picker.picked.connect(func(path: String) -> void: then.call(path), CONNECT_ONE_SHOT)
	picker.open(kind)


func _start(p: Dictionary, action: String, iso: String, bios: String) -> void:
	var args := ["start", p["id"], action]
	if iso != "":
		args += ["--iso", iso]
	if bios != "":
		args += ["--bios", bios]
	backend.run(args, func(ok: bool, _r: Variant, err: String) -> void:
		if ok:
			toast.say(L.t("started"), UI.ACCENT)
		else:
			toast.say(err, UI.RED)
		_refresh()
	)


func _uninstall(p: Dictionary) -> void:
	var ids := []
	for key in ["steam_appid", "legacy_appid"]:
		if p.get(key) != null:
			ids.append(int(p[key]))
	backend.run(["uninstall", p["id"]], func(ok: bool, _r: Variant, err: String) -> void:
		if not ok:
			toast.say(err, UI.RED)
			return
		toast.say(L.t("removed", p["name"]))
		if not ids.is_empty() and bridge.alive():
			bridge.send("remove_shortcut", {"port": p["id"], "appids": ids}, func(_a: bool, _b: Variant, _c: String) -> void:
				_steam_status())
		_refresh()
	)


func _add_to_steam(p: Dictionary) -> void:
	bridge.send("add_shortcut", {"port": p["id"]}, func(ok: bool, result: Variant, err: String) -> void:
		if ok:
			steam[p["id"]] = int(result.get("appid", 1)) if result is Dictionary else 1
			toast.say(L.t("added", p.get("steam_name", p["name"])), UI.GREEN)
			_refresh()
			_steam_status()
		elif err == "no_bridge":
			toast.say(L.t("no_bridge"), UI.AMBER, 6.0)
		else:
			toast.say(L.t("steam_failed", err), UI.RED)
	)


## Plays a port. Started by armada-ports.sh, the app hands the game over and quits, so the game
## has the screen, the controller and the memory to itself; the script opens the app again on
## this port's page when the game ends. Started any other way, it runs the game alongside.
func _play(id: String) -> void:
	var p := _port(id)
	var info := PortInfo.installed(p)
	var exe := str(info.get("exe", ""))
	if exe == "" or not FileAccess.file_exists(exe):
		toast.say(L.t("error"), UI.RED)
		return
	var dir := str(info.get("start_dir", exe.get_base_dir()))
	toast.say(L.t("starting", p["name"]), UI.ACCENT)
	if OS.get_environment("ARMADA_PORTS_WRAPPER") == "1":
		var f := FileAccess.open("user://launch", FileAccess.WRITE)
		var appid := int(steam.get(id, 0))
		f.store_string("%s\n%s\n%s\n%s\n" % [dir, exe, id, str(appid) if appid != 0 else ""])
		f.close()
		var tw := create_tween()
		tw.tween_property(_curtain, "modulate:a", 1.0, 0.35)
		tw.tween_callback(func(): get_tree().quit())
	else:
		OS.create_process("/bin/sh", ["-c", "cd \"$1\" && exec \"$2\"", "sh", dir, exe])


# --- Input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var top: Control = null
	if confirm.visible:
		top = confirm
	elif picker.visible:
		top = picker
	elif details.visible:
		top = details
	else:
		top = home
	if top.handle(event):
		get_viewport().set_input_as_handled()


## Holding a direction on the controller repeats it, as holding an arrow key does.
func _process(delta: float) -> void:
	var dir := ""
	for a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		if Input.is_action_pressed(a):
			dir = a
			break
	if dir != _held:
		_held = dir
		_held_t = 0.0
		_repeat_t = 0.0
		return
	if dir == "" or _keyboard_held():
		return
	_held_t += delta
	if _held_t < 0.4:
		return
	_repeat_t -= delta
	if _repeat_t <= 0.0:
		_repeat_t = 0.09
		var ev := InputEventAction.new()
		ev.action = dir
		ev.pressed = true
		Input.parse_input_event(ev)


func _keyboard_held() -> bool:
	for k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		if Input.is_physical_key_pressed(k):
			return true
	return false


## A short message at the top of the screen; several queue up.
class Toast:
	extends Control
	var _queue: Array = []
	var _panel: PanelContainer
	var _label: Label
	var _dot: ColorRect
	var _busy := false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel = PanelContainer.new()
		var b := UI.box(Color(0.1, 0.115, 0.155, 0.97), 16, Color(1, 1, 1, 0.12), 1)
		b.content_margin_left = 18
		b.content_margin_right = 20
		b.content_margin_top = 12
		b.content_margin_bottom = 13
		b.shadow_color = Color(0, 0, 0, 0.45)
		b.shadow_size = 18
		_panel.add_theme_stylebox_override("panel", b)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_dot = ColorRect.new()
		_dot.custom_minimum_size = Vector2(4, 22)
		row.add_child(_dot)
		_label = UI.label("", 16, UI.TEXT, 550)
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size.x = 520
		row.add_child(_label)
		_panel.add_child(row)
		_panel.modulate.a = 0.0
		add_child(_panel)

	func say(text: String, color := UI.ACCENT, seconds := 3.5) -> void:
		_queue.append([text, color, seconds])
		if not _busy:
			_next()

	func _next() -> void:
		if _queue.is_empty():
			_busy = false
			return
		_busy = true
		var item: Array = _queue.pop_front()
		_label.text = item[0]
		_dot.color = item[1]
		_panel.reset_size()
		var w := get_viewport_rect().size.x
		_panel.position = Vector2((w - _panel.size.x) * 0.5, -_panel.size.y)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.set_parallel()
		tw.tween_property(_panel, "position:y", 22.0, 0.3)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.3)
		tw.chain().tween_interval(item[2])
		tw.chain().tween_property(_panel, "modulate:a", 0.0, 0.25)
		tw.chain().tween_callback(_next)
