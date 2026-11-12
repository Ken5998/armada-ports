class_name PortCard
extends Control
## A port's cover in the home row: the SteamGridDB capsule with rounded corners, a glow when
## it is the selected one, and a small badge for its state.

const SIZE := Vector2(132, 198)
const ROUND := """
shader_type canvas_item;
uniform vec2 size = vec2(132.0, 198.0);
uniform float radius = 12.0;
void fragment() {
	vec2 p = UV * size;
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * clamp(0.5 - d, 0.0, 1.0));
}
"""

static var _material: ShaderMaterial

var port: Dictionary
var focused := false
var _cover: TextureRect
var _fallback: Control
var _glow: Panel
var _badge: Badge


func _init(p: Dictionary) -> void:
	port = p
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = Vector2(SIZE.x * 0.5, SIZE.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _material == null:
		var sh := Shader.new()
		sh.code = ROUND
		_material = ShaderMaterial.new()
		_material.shader = sh

	_glow = Panel.new()
	var g := UI.box(Color(0, 0, 0, 0), 15, UI.TEXT, 3)
	g.shadow_color = Color(UI.ACCENT, 0.6)
	g.shadow_size = 22
	g.expand_margin_left = 4
	g.expand_margin_right = 4
	g.expand_margin_top = 4
	g.expand_margin_bottom = 4
	_glow.add_theme_stylebox_override("panel", g)
	UI.fill(_glow)
	_glow.modulate.a = 0.0
	add_child(_glow)

	_fallback = _make_fallback()
	add_child(_fallback)

	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cover.material = _material
	UI.fill(_cover)
	add_child(_cover)

	_badge = Badge.new()
	_badge.position = Vector2(SIZE.x - 30, 8)
	add_child(_badge)
	refresh(p)


func _make_fallback() -> Control:
	var panel := Panel.new()
	var c := UI.tint(port["id"])
	var b := UI.box(c.darkened(0.35), 12)
	b.border_color = c
	b.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", b)
	UI.fill(panel)
	var l := UI.wrapped(str(port.get("name", "")), 20, UI.TEXT, 700)
	l.add_theme_font_override("font", UI.font(700, true))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fill(l)
	l.offset_left = 10
	l.offset_right = -10
	panel.add_child(l)
	return panel


func set_texture(tex: Texture2D) -> void:
	_cover.texture = tex
	_fallback.visible = tex == null


func refresh(p: Dictionary) -> void:
	port = p
	var st := PortInfo.status(p)
	if PortInfo.job_running(p):
		var pct: Variant = p["job"].get("percent")
		_badge.set_state(UI.ACCENT, -1.0 if pct == null else float(pct) / 100.0)
	elif not p.get("supported", false):
		_badge.set_state(Color.TRANSPARENT)
	elif PortInfo.installed(p).is_empty():
		_badge.set_state(Color.TRANSPARENT)
	else:
		_badge.set_state(st[1])


func set_focused(on: bool, animate := true) -> void:
	focused = on
	var target := Vector2.ONE * (1.16 if on else 1.0)
	if animate:
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", target, 0.18)
		tw.tween_property(_glow, "modulate:a", 1.0 if on else 0.0, 0.18)
		tw.tween_property(self, "modulate", Color.WHITE if on else Color(0.78, 0.8, 0.86), 0.18)
	else:
		scale = target
		_glow.modulate.a = 1.0 if on else 0.0
		modulate = Color.WHITE if on else Color(0.78, 0.8, 0.86)


class Badge:
	extends Control
	var color := Color.TRANSPARENT
	var progress := -2.0   # -2 none, -1 busy without percent, 0..1 percent
	var _spin := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(c: Color, prog := -2.0) -> void:
		color = c
		progress = prog
		set_process(prog > -2.0)
		queue_redraw()

	func _process(delta: float) -> void:
		_spin += delta * 4.0
		queue_redraw()

	func _draw() -> void:
		if color.a == 0.0:
			return
		var c := size * 0.5
		draw_circle(c, 11, Color(0.04, 0.05, 0.07, 0.85))
		if progress <= -2.0:
			draw_circle(c, 5.5, color)
		elif progress < 0.0:
			draw_arc(c, 7, _spin, _spin + PI * 1.4, 24, color, 2.5, true)
		else:
			draw_arc(c, 7, 0, TAU, 32, Color(color, 0.25), 2.5, true)
			draw_arc(c, 7, -PI / 2, -PI / 2 + TAU * clamp(progress, 0.0, 1.0), 32, color, 2.5, true)
