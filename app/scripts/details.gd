class_name DetailsScreen
extends Control
## One port's page: its artwork, what it does, the facts that matter before installing, the
## newest release's notes and the buttons to play, install, update, add to Steam or remove it.

signal action(id: String, what: String)
signal back

const LEFT := 56.0
const FADE := HomeScreen.FADE

var art: ArtCache
var port: Dictionary = {}
var in_steam := false
var _hero: TextureRect
var _ambient: TextureRect
var _logo: TextureRect
var _name: Label
var _subtitle: Label
var _about: Label
var _facts: GridContainer
var _notes_title: Label
var _notes: Label
var _status_box: VBoxContainer
var _buttons: VBoxContainer
var _job: VBoxContainer
var _stage: Label
var _bar: ProgressBar
var _lines: Label
var _space: Label
var _actions: Array = []


func _ready() -> void:
	UI.fill(self)
	var base := ColorRect.new()
	base.color = UI.BG
	add_child(UI.fill(base))
	_ambient = TextureRect.new()
	_ambient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ambient.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_ambient.self_modulate = Color(0.3, 0.3, 0.34)
	add_child(UI.fill(_ambient))
	var sh := Shader.new()
	sh.code = FADE
	var fade := ShaderMaterial.new()
	fade.shader = sh
	_hero = TextureRect.new()
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero.material = fade
	add_child(_hero)
	var left := TextureRect.new()
	left.texture = UI.gradient(Color(0.02, 0.025, 0.035, 0.75), Color(0.02, 0.025, 0.035, 0.0), true, PackedFloat32Array([0.0, 0.6]))
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(UI.fill(left))
	var bottom := TextureRect.new()
	bottom.texture = UI.gradient(Color(UI.BG, 0.0), Color(UI.BG, 0.9), false, PackedFloat32Array([0.35, 0.75]))
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(UI.fill(bottom))

	var crumb := UI.hint("B", L.t("back"), "ui_cancel")
	crumb.position = Vector2(LEFT, 22)
	add_child(crumb)

	var head := VBoxContainer.new()
	head.position = Vector2(LEFT, 150)
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(_logo)
	_name = UI.label("", 44, UI.TEXT, 700, true)
	head.add_child(_name)
	_subtitle = UI.label("", 16, UI.MUTED, 500)
	head.add_child(_subtitle)

	var body := VBoxContainer.new()
	body.position = Vector2(LEFT, 326)
	body.custom_minimum_size = Vector2(720, 0)
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	_about = UI.wrapped("", 18, Color(UI.TEXT, 0.94))
	_about.custom_minimum_size.x = 720
	_about.max_lines_visible = 3
	body.add_child(_about)
	_facts = GridContainer.new()
	_facts.columns = 2
	_facts.add_theme_constant_override("h_separation", 22)
	_facts.add_theme_constant_override("v_separation", 7)
	body.add_child(_facts)
	var notes := VBoxContainer.new()
	notes.add_theme_constant_override("separation", 4)
	_notes_title = UI.label("", 15, UI.ACCENT.lightened(0.2), 650, true)
	notes.add_child(_notes_title)
	_notes = UI.wrapped("", 14, UI.MUTED)
	_notes.custom_minimum_size.x = 720
	_notes.max_lines_visible = 4
	notes.add_child(_notes)
	body.add_child(notes)

	var side := PanelContainer.new()
	var sb := UI.box(Color(0.06, 0.07, 0.1, 0.9), 20, Color(1, 1, 1, 0.08), 1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 20
	sb.content_margin_bottom = 22
	side.add_theme_stylebox_override("panel", sb)
	side.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.offset_right = -LEFT
	side.offset_left = -LEFT - 380
	side.offset_top = 196
	add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	side.add_child(col)
	_status_box = VBoxContainer.new()
	_status_box.add_theme_constant_override("separation", 6)
	col.add_child(_status_box)
	_job = VBoxContainer.new()
	_job.add_theme_constant_override("separation", 8)
	_stage = UI.wrapped("", 17, UI.TEXT, 600)
	_stage.add_theme_font_override("font", UI.font(600, true))
	_job.add_child(_stage)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.show_percentage = false
	_job.add_child(_bar)
	_lines = UI.label("", 12, UI.FAINT, 450)
	_lines.clip_text = true
	_lines.custom_minimum_size = Vector2(336, 0)
	_lines.max_lines_visible = 4
	_job.add_child(_lines)
	col.add_child(_job)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	col.add_child(_buttons)
	_space = UI.label("", 13, UI.FAINT, 500)
	col.add_child(_space)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var w := size.x if size.x > 0 else 1280.0
	_hero.size = Vector2(w, w / 3.1)


func show_port(p: Dictionary, steam: bool) -> void:
	port = p
	in_steam = steam
	_actions = []
	_fill(true)


func refresh(p: Dictionary, steam: bool) -> void:
	if p.get("id") != port.get("id"):
		return
	port = p
	in_steam = steam
	_fill(false)


func art_ready(id: String) -> void:
	if id == port.get("id"):
		_fill_art()


func _fill_art() -> void:
	_hero.texture = art.get_tex(port, "hero")
	_ambient.texture = art.get_blur(port)
	var logo := art.get_tex(port, "logo")
	_logo.texture = logo
	_logo.visible = logo != null
	_name.visible = logo == null
	if logo != null:
		var s := Vector2(logo.get_width(), logo.get_height())
		var k: float = min(380.0 / s.x, 120.0 / s.y)
		_logo.custom_minimum_size = s * k


func _fill(first: bool) -> void:
	var p := port
	_fill_art()
	_name.text = str(p.get("name", ""))
	var up: Variant = p.get("upstream", {})
	_subtitle.text = str(p.get("game", "")) + ("   ·   " + str(up.get("name")) if up is Dictionary and up.get("name") else "")
	_about.text = L.pick(p.get("about"))
	var rp6 := L.pick(p.get("rp6"))

	for c in _facts.get_children():
		c.queue_free()
	if rp6 != "":
		_fact(L.t("on_rp6"), rp6)
	_fact(L.t("f_needs"), PortInfo.needs(p))
	if p.get("supported", false):
		_fact(L.t("f_build"), PortInfo.build_time(p))
	if p.get("space_gb") != null:
		_fact(L.t("f_space"), L.t("about_gb", int(p["space_gb"])))
	var latest := PortInfo.latest_version(p)
	if latest != "":
		_fact(L.t("f_latest"), PortInfo.version_text(latest))

	var notes := PortInfo.notes(p, 6)
	_notes_title.visible = not notes.is_empty()
	_notes.visible = not notes.is_empty()
	if not notes.is_empty():
		_notes_title.text = L.t("whats_new", PortInfo.version_text(latest)).to_upper()
		_notes.text = "\n".join(notes.map(func(s): return "•  " + s))

	for c in _status_box.get_children():
		c.queue_free()
	var st := PortInfo.status(p)
	_status_box.add_child(UI.pill(st[0], st[1]))
	if not p.get("supported", false):
		var note := UI.wrapped(L.t("launcher_only"), 14, UI.MUTED)
		note.custom_minimum_size.x = 336
		_status_box.add_child(note)

	var running := PortInfo.job_running(p)
	_job.visible = running
	if running:
		var job: Dictionary = p["job"]
		_stage.text = str(job.get("stage", ""))
		var pct: Variant = job.get("percent")
		if "indeterminate" in _bar:
			_bar.set("indeterminate", pct == null)
		_bar.value = 0.0 if pct == null else float(pct)

	var free: Variant = p.get("free_gb")
	_space.text = L.t("free", str(free)) if free != null else ""
	_set_actions(_wanted_actions(p), first)


func _fact(name: String, value: String) -> void:
	_facts.add_child(UI.label(name.to_upper(), 12, UI.FAINT, 650))
	var v := UI.label(value, 15, UI.TEXT, 500)
	v.custom_minimum_size.x = 560
	v.clip_text = true
	_facts.add_child(v)


func set_log(lines: Array) -> void:
	_lines.text = "\n".join(lines.slice(max(0, lines.size() - 4)))


func _wanted_actions(p: Dictionary) -> Array:
	var out := []
	if PortInfo.job_running(p):
		return [["stop", L.t("stop"), false]]
	if not p.get("supported", false):
		return out
	var info := PortInfo.installed(p)
	if info.is_empty():
		out.append(["install", L.t("install"), true])
		return out
	if not PortInfo.built(p):
		out.append(["resume", L.t("resume"), true])
	else:
		out.append(["play", L.t("play"), true])
		var latest := PortInfo.latest_version(p)
		# An install made with its launcher elsewhere may not tell its version: offer the newest
		# release then too (it rebuilds from the files already extracted).
		if p.get("update", false) or (str(info.get("version", "")) == "" and latest != ""):
			out.append(["update", L.t("update_to", PortInfo.version_text(latest)), false])
		if not in_steam:
			out.append(["steam", L.t("add_steam"), false])
	out.append(["remove", L.t("remove"), false])
	return out


func _set_actions(wanted: Array, grab: bool) -> void:
	var names := wanted.map(func(a): return a[0])
	var old := _actions.map(func(a): return a[0])
	if names == old and not grab:
		return
	var had := ""
	for b in _buttons.get_children():
		if b.has_focus():
			had = b.get_meta("what")
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	_actions = wanted
	var first: Button = null
	var keep: Button = null
	for a in wanted:
		var b := UI.button(a[1], a[2])
		b.set_meta("what", a[0])
		b.custom_minimum_size.x = 336
		b.pressed.connect(func(): action.emit(port["id"], a[0]))
		_buttons.add_child(b)
		if first == null:
			first = b
		if a[0] == had:
			keep = b
	if in_steam and PortInfo.built(port) and not PortInfo.job_running(port):
		var l := UI.label("✓  " + L.t("in_steam"), 14, UI.GREEN.lightened(0.2), 500)
		_buttons.add_child(l)
	var target := keep if keep != null else first
	if target != null and is_visible_in_tree():
		target.grab_focus.call_deferred()


func focus_first() -> void:
	for b in _buttons.get_children():
		if b is Button:
			b.grab_focus()
			return


func handle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		back.emit()
		return true
	if event.is_action_pressed("act_x") and PortInfo.built(port) and not PortInfo.job_running(port):
		action.emit(port["id"], "play")
		return true
	return false
