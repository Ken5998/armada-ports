class_name HomeScreen
extends Control
## The first screen: the selected port's artwork across the top, what it is on the left, and
## every port as a cover in a row along the bottom.

signal open_port(id: String)
signal play_port(id: String)
signal check_updates
signal quit_app

const STEP := 154.0
const LEFT := 56.0
const ROW_Y := 476.0
const FADE := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = smoothstep(1.0, 0.42, UV.y) * smoothstep(0.0, 0.18, UV.x + 0.12);
	COLOR = vec4(c.rgb, c.a * a);
}
"""

var art: ArtCache
var ports: Array = []
var index := 0
var _cards: Array[PortCard] = []
var _row: Control
var _heroes: Array[TextureRect] = []
var _ambients: Array[TextureRect] = []
var _front := 0
var _shown_hero: Texture2D
var _info: VBoxContainer
var _logo: TextureRect
var _name: Label
var _subtitle: Label
var _status_row: HBoxContainer
var _rp6: Label
var _about: Label
var _clock: Label
var _count: Label
var _hints: HBoxContainer


func _ready() -> void:
	UI.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var base := ColorRect.new()
	base.color = UI.BG
	add_child(UI.fill(base))

	var sh := Shader.new()
	sh.code = FADE
	var fade := ShaderMaterial.new()
	fade.shader = sh
	for i in 2:
		var amb := TextureRect.new()
		amb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		amb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		amb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		amb.self_modulate = Color(0.42, 0.42, 0.46)
		amb.modulate.a = 0.0
		add_child(UI.fill(amb))
		_ambients.append(amb)
	for i in 2:
		var hero := TextureRect.new()
		hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hero.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		hero.material = fade
		hero.modulate.a = 0.0
		add_child(hero)
		_heroes.append(hero)

	# Shade: darker on the left (behind the text) and at the bottom (behind the covers).
	var left := TextureRect.new()
	left.texture = UI.gradient(Color(0.02, 0.025, 0.035, 0.82), Color(0.02, 0.025, 0.035, 0.0), true, PackedFloat32Array([0.0, 0.62]))
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(UI.fill(left))
	var bottom := TextureRect.new()
	bottom.texture = UI.gradient(Color(UI.BG, 0.0), Color(UI.BG, 0.94), false, PackedFloat32Array([0.5, 1.0]))
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(UI.fill(bottom))
	var top := TextureRect.new()
	top.texture = UI.gradient(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), false, PackedFloat32Array([0.0, 0.2]))
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(UI.fill(top))

	_build_header()
	_build_info()

	_row = Control.new()
	_row.position = Vector2(LEFT, ROW_Y)
	add_child(_row)

	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 22)
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hints.offset_right = -LEFT
	_hints.offset_bottom = -14
	add_child(_hints)

	resized.connect(_layout)
	var t := Timer.new()
	t.wait_time = 10.0
	t.autostart = true
	t.timeout.connect(_tick_clock)
	add_child(t)
	_tick_clock()
	_layout()
	for c in get_children():
		if c is Control and c != _hints:
			_pass_mouse(c)


func _pass_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in c.get_children():
		if child is Control:
			_pass_mouse(child)


func _build_header() -> void:
	var mark := HBoxContainer.new()
	mark.position = Vector2(LEFT, 26)
	mark.add_theme_constant_override("separation", 10)
	var dot := Logo.new()
	mark.add_child(dot)
	var name := UI.label("ARMADA PORTS", 17, UI.TEXT, 700, true)
	name.add_theme_constant_override("outline_size", 0)
	mark.add_child(name)
	add_child(mark)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_right = -LEFT
	right.offset_top = 26
	_count = UI.label("", 15, UI.MUTED, 500)
	_clock = UI.label("", 17, UI.TEXT, 600, true)
	right.add_child(_count)
	right.add_child(_clock)
	add_child(right)


func _build_info() -> void:
	_info = VBoxContainer.new()
	_info.position = Vector2(LEFT, 118)
	_info.custom_minimum_size = Vector2(620, 0)
	_info.add_theme_constant_override("separation", 10)
	add_child(_info)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info.add_child(_logo)
	_name = UI.label("", 46, UI.TEXT, 700, true)
	_info.add_child(_name)
	_subtitle = UI.label("", 16, UI.MUTED, 500)
	_info.add_child(_subtitle)
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 12)
	_info.add_child(_status_row)
	_about = UI.wrapped("", 17, Color(UI.TEXT, 0.92))
	_about.max_lines_visible = 3
	_about.custom_minimum_size.x = 600
	_info.add_child(_about)
	_rp6 = UI.label("", 15, UI.MUTED, 500)
	_info.add_child(_rp6)


func _tick_clock() -> void:
	var t := Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [t.hour, t.minute]


func _layout() -> void:
	var w := size.x if size.x > 0 else 1280.0
	for h in _heroes:
		h.size = Vector2(w, w / 3.1)
		h.position = Vector2.ZERO
	_scroll(false)


func set_ports(list: Array) -> void:
	var keep := ""
	if not ports.is_empty() and index < ports.size():
		keep = ports[index]["id"]
	ports = list
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for i in ports.size():
		var card := PortCard.new(ports[i])
		card.position = Vector2(i * STEP, 0)
		card.set_texture(art.get_tex(ports[i], "grid"))
		card.set_focused(false, false)
		_row.add_child(card)
		_cards.append(card)
	_count.text = L.t("ports_count", ports.size())
	index = 0
	for i in ports.size():
		if ports[i]["id"] == keep:
			index = i
	_select(index, false)
	_build_hints()


## New data for the same ports (states, versions, jobs).
func update_ports(list: Array) -> void:
	if list.size() != ports.size():
		set_ports(list)
		return
	ports = list
	for i in ports.size():
		_cards[i].refresh(ports[i])
	_show_info(false)
	_build_hints()


func focus_id(id: String) -> void:
	for i in ports.size():
		if ports[i]["id"] == id:
			_select(i, false)


func current() -> Dictionary:
	return ports[index] if index < ports.size() else {}


func art_ready(id: String) -> void:
	for i in ports.size():
		if ports[i]["id"] == id:
			_cards[i].set_texture(art.get_tex(ports[i], "grid"))
			if i == index:
				_show_art(true)
				_show_info(false)


func _select(i: int, animate := true) -> void:
	if ports.is_empty():
		return
	i = clampi(i, 0, ports.size() - 1)
	for c in range(_cards.size()):
		if c == i or c == index:
			_cards[c].set_focused(c == i, animate)
	index = i
	_scroll(animate)
	_show_art(animate)
	_show_info(animate)
	_build_hints()


func _scroll(animate: bool) -> void:
	if _row == null:
		return
	var w := size.x if size.x > 0 else 1280.0
	var total := ports.size() * STEP - (STEP - PortCard.SIZE.x)
	var lowest: float = min(0.0, (w - LEFT * 2) - total)
	var offset: float = clamp(-max(0, index - 2) * STEP, lowest, 0.0)
	var target := Vector2(LEFT + offset, ROW_Y)
	if animate:
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(_row, "position", target, 0.22)
	else:
		_row.position = target


func _show_art(animate: bool) -> void:
	var p := current()
	if p.is_empty():
		return
	var hero := art.get_tex(p, "hero")
	if hero == _shown_hero and hero != null:
		return
	_shown_hero = hero
	var back := 1 - _front
	_heroes[back].texture = hero
	_ambients[back].texture = art.get_blur(p) if hero != null else null
	if not animate:
		_heroes[back].modulate.a = 1.0
		_ambients[back].modulate.a = 1.0
		_heroes[_front].modulate.a = 0.0
		_ambients[_front].modulate.a = 0.0
	else:
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
		tw.tween_property(_heroes[back], "modulate:a", 1.0, 0.35)
		tw.tween_property(_ambients[back], "modulate:a", 1.0, 0.35)
		tw.tween_property(_heroes[_front], "modulate:a", 0.0, 0.35)
		tw.tween_property(_ambients[_front], "modulate:a", 0.0, 0.35)
	_front = back


func _show_info(animate: bool) -> void:
	var p := current()
	if p.is_empty():
		return
	var logo := art.get_tex(p, "logo")
	_logo.texture = logo
	_logo.visible = logo != null
	_name.visible = logo == null
	_name.text = str(p.get("name", ""))
	if logo != null:
		var s := Vector2(logo.get_width(), logo.get_height())
		var k: float = min(400.0 / s.x, 130.0 / s.y)
		_logo.custom_minimum_size = s * k
	var up: Variant = p.get("upstream", {})
	var sub := str(p.get("game", ""))
	if up is Dictionary and up.get("name"):
		sub += "   ·   " + str(up["name"])
	_subtitle.text = sub
	for c in _status_row.get_children():
		c.queue_free()
	var st := PortInfo.status(p)
	_status_row.add_child(UI.pill(st[0], st[1]))
	_about.text = L.pick(p.get("about"))
	var rp6 := L.pick(p.get("rp6"))
	_rp6.text = (L.t("on_rp6") + ":  " + rp6) if rp6 != "" else ""
	if animate:
		_info.modulate.a = 0.0
		_info.position.x = LEFT + 14
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_info, "modulate:a", 1.0, 0.25)
		tw.tween_property(_info, "position:x", LEFT, 0.25)


func _build_hints() -> void:
	if _hints == null:
		return
	for c in _hints.get_children():
		c.queue_free()
	var p := current()
	_hint("A", L.t("open"))
	if not p.is_empty() and PortInfo.built(p):
		_hint("X", L.t("play"))
	_hint("Y", L.t("check"))
	_hint("B", L.t("quit"))


func _hint(letter: String, text: String) -> void:
	_hints.add_child(UI.hint(letter, text, {"A": "ui_accept", "B": "ui_cancel", "X": "act_x", "Y": "act_y"}[letter]))


## Touch (the RP6 has a touchscreen): tap a cover to pick it, tap it again to open it; drag the
## row to move along it.
var _drag_from := -1.0
var _drag_index := 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_from = event.position.x
			_drag_index = index
		else:
			var moved: float = abs(event.position.x - _drag_from) if _drag_from >= 0 else 0.0
			_drag_from = -1.0
			if moved < 12.0:
				_tap(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _drag_from >= 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var steps := int(round((_drag_from - event.position.x) / STEP))
		if _drag_index + steps != index:
			_select(_drag_index + steps)
		accept_event()


func _tap(at: Vector2) -> void:
	for i in _cards.size():
		if _cards[i].get_global_rect().has_point(get_global_transform() * at):
			if i == index:
				open_port.emit(ports[i]["id"])
			else:
				_select(i)
			return


func handle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_left"):
		_select(index - 1)
	elif event.is_action_pressed("ui_right"):
		_select(index + 1)
	elif event.is_action_pressed("page_prev"):
		_select(index - 4)
	elif event.is_action_pressed("page_next"):
		_select(index + 4)
	elif event.is_action_pressed("ui_accept"):
		if not current().is_empty():
			open_port.emit(current()["id"])
	elif event.is_action_pressed("act_x"):
		var p := current()
		if not p.is_empty():
			if PortInfo.built(p):
				play_port.emit(p["id"])
			else:
				open_port.emit(p["id"])
	elif event.is_action_pressed("act_y"):
		check_updates.emit()
	elif event.is_action_pressed("ui_cancel"):
		quit_app.emit()
	else:
		return false
	return true


## The app's mark: three stacked chevrons, drawn rather than shipped as an image.
class Logo:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var cols := [UI.ACCENT, UI.ACCENT.lightened(0.3), UI.TEXT]
		for i in 3:
			var y := 4.0 + i * 6.0
			draw_polyline(PackedVector2Array([Vector2(2, y), Vector2(11, y + 5), Vector2(20, y)]), cols[i], 2.6, true)
