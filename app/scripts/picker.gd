class_name Picker
extends Control
## Picking a disc image (or BIOS) with the controller: first the files found in the usual places,
## then, if it is elsewhere, a folder browser.

signal picked(path: String)
signal cancelled

var backend: Backend
var kind := "iso"
var _title: Label
var _where: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _browsing := false
var _folder := ""
var _parent: Variant = null


func _ready() -> void:
	UI.fill(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	add_child(UI.fill(dim))
	var panel := PanelContainer.new()
	var b := UI.box(Color(0.075, 0.085, 0.115, 0.98), 22, Color(1, 1, 1, 0.1), 1)
	b.content_margin_left = 28
	b.content_margin_right = 28
	b.content_margin_top = 24
	b.content_margin_bottom = 20
	b.shadow_color = Color(0, 0, 0, 0.5)
	b.shadow_size = 30
	panel.add_theme_stylebox_override("panel", b)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860, 560)
	panel.position = Vector2(-430, -280)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	_title = UI.label("", 26, UI.TEXT, 700, true)
	col.add_child(_title)
	_where = UI.label("", 14, UI.MUTED, 500)
	_where.clip_text = true
	_where.custom_minimum_size.x = 800
	col.add_child(_where)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	var hints := HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_END
	hints.add_theme_constant_override("separation", 20)
	hints.add_child(UI.hint("A", L.t("select"), "ui_accept"))
	hints.add_child(UI.hint("B", L.t("back"), "ui_cancel"))
	col.add_child(hints)


func open(what: String) -> void:
	kind = what
	_title.text = L.t("pick_bios") if kind == "bios" else L.t("pick_iso")
	show()
	_show_found()


func _show_found() -> void:
	_browsing = false
	_where.text = L.t("searching")
	_clear()
	backend.run(["discs", "--kind", kind], func(ok: bool, result: Variant, err: String) -> void:
		if _browsing or not visible:
			return
		_clear()
		_where.text = L.t("found_here") if ok else err
		if ok and result is Array and not result.is_empty():
			for d in result:
				_entry(str(d["name"]), "%s   ·   %s" % [UI.human_size(float(d["size"])), _short(str(d["folder"]))],
						_pick.bind(str(d["path"])), "file")
		elif ok:
			var l := UI.wrapped(L.t("no_discs"), 15, UI.MUTED)
			_list.add_child(l)
		_entry(L.t("browse"), "", func(): _browse(OS.get_environment("HOME")), "dir")
		_focus_first()
	)


func _browse(path: String) -> void:
	_browsing = true
	_clear()
	backend.run(["folder", path, "--kind", kind], func(ok: bool, result: Variant, err: String) -> void:
		if not visible:
			return
		_clear()
		if not ok:
			_where.text = err
			_entry(L.t("up"), "", func(): _browse(_parent if _parent != null else OS.get_environment("HOME")), "up")
			_focus_first()
			return
		_folder = str(result["path"])
		_parent = result.get("parent")
		_where.text = _folder
		if _parent != null:
			_entry(L.t("up"), "", func(): _browse(str(_parent)), "up")
		for d in result["dirs"]:
			_entry(str(d["name"]), "", _browse.bind(str(d["path"])), "dir")
		for f in result["files"]:
			_entry(str(f["name"]), UI.human_size(float(f["size"])), _pick.bind(str(f["path"])), "file")
		if result["dirs"].is_empty() and result["files"].is_empty():
			_list.add_child(UI.label(L.t("empty_folder"), 15, UI.MUTED))
		_focus_first()
	)


func _short(folder: String) -> String:
	var home := OS.get_environment("HOME")
	return "~" + folder.substr(home.length()) if home != "" and folder.begins_with(home) else folder


func _pick(path: String) -> void:
	hide()
	picked.emit(path)


func _clear() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()


func _entry(text: String, meta: String, cb: Callable, icon: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 50)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("focus", UI.box(UI.TEXT, 12))
	b.add_theme_stylebox_override("normal", UI.box(Color(1, 1, 1, 0.06), 12))
	b.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.12), 12))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	UI.fill(row)
	row.offset_left = 18
	row.offset_right = -18
	var ic := EntryIcon.new()
	ic.kind = icon
	row.add_child(ic)
	var name := UI.label(text, 17, UI.TEXT, 550)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name)
	var m := UI.label(meta, 14, UI.MUTED, 500)
	m.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(m)
	b.add_child(row)
	b.focus_entered.connect(func():
		name.add_theme_color_override("font_color", Color.BLACK)
		m.add_theme_color_override("font_color", Color(0, 0, 0, 0.6))
		ic.dark = true
		ic.queue_redraw())
	b.focus_exited.connect(func():
		name.add_theme_color_override("font_color", UI.TEXT)
		m.add_theme_color_override("font_color", UI.MUTED)
		ic.dark = false
		ic.queue_redraw())
	b.pressed.connect(cb)
	_list.add_child(b)


func _focus_first() -> void:
	for c in _list.get_children():
		if c is Button:
			c.grab_focus.call_deferred()
			return


func handle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		if _browsing:
			_show_found()
		else:
			hide()
			cancelled.emit()
		return true
	return false


class EntryIcon:
	extends Control
	var kind := "file"
	var dark := false

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color(0, 0, 0, 0.75) if dark else UI.MUTED
		match kind:
			"dir":
				draw_rect(Rect2(1, 5, 20, 14), c, false, 2.0)
				draw_rect(Rect2(1, 3, 8, 3), c)
			"up":
				draw_polyline(PackedVector2Array([Vector2(4, 12), Vector2(11, 5), Vector2(18, 12)]), c, 2.2, true)
				draw_line(Vector2(11, 5), Vector2(11, 19), c, 2.2, true)
			_:
				draw_arc(Vector2(11, 11), 9, 0, TAU, 28, c, 2.0, true)
				draw_circle(Vector2(11, 11), 2.5, c)
