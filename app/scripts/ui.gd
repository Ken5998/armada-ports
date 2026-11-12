class_name UI
## Colours, fonts and small builders shared by every screen.

const BG := Color("0b0d12")
const PANEL := Color(0.075, 0.086, 0.118, 0.94)
const PANEL_LIGHT := Color(0.13, 0.145, 0.19, 0.96)
const TEXT := Color("f2f4f8")
const MUTED := Color("a3abbd")
const FAINT := Color("6b7386")
const ACCENT := Color("5aa9ff")
const ACCENT_DARK := Color("2f6fc0")
const GREEN := Color("4ade80")
const AMBER := Color("fbbf24")
const RED := Color("f87171")

static var _fonts := {}
static var theme: Theme


static func setup() -> void:
	theme = Theme.new()
	theme.default_font = font(450)
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "Button", button_box(state))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_focus_color", "Button", Color.BLACK)
	theme.set_color("font_pressed_color", "Button", Color.BLACK)
	theme.set_color("font_hover_pressed_color", "Button", Color.BLACK)
	theme.set_color("font_disabled_color", "Button", FAINT)
	theme.set_font("font", "Button", font(600, true))
	theme.set_font_size("font_size", "Button", 19)
	theme.set_constant("h_separation", "Button", 12)
	theme.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.1), 6))
	theme.set_stylebox("fill", "ProgressBar", box(ACCENT, 6))
	theme.set_stylebox("panel", "PanelContainer", box(PANEL, 18))
	var scroll := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", scroll)
	theme.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.06), 3))
	theme.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.25), 3))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.4), 3))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(Color(1, 1, 1, 0.4), 3))


## Outfit for headings and buttons (display = true), Inter for text.
static func font(weight: int, display := false) -> Font:
	var key := "%s%d" % ["d" if display else "t", weight]
	if _fonts.has(key):
		return _fonts[key]
	var base: FontFile = load("res://fonts/Outfit.ttf" if display else "res://fonts/Inter.ttf")
	var v := FontVariation.new()
	v.base_font = base
	var ts := TextServerManager.get_primary_interface()
	v.variation_opentype = {ts.name_to_tag("wght"): weight}
	_fonts[key] = v
	return v


static func box(color: Color, radius := 12, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.corner_detail = 6
	if border_width > 0:
		b.border_color = border
		b.set_border_width_all(border_width)
	b.anti_aliasing = true
	return b


static func button_box(state: String) -> StyleBox:
	var b: StyleBoxFlat
	match state:
		"focus":
			b = box(TEXT, 14)
			b.shadow_color = Color(ACCENT, 0.55)
			b.shadow_size = 14
		"pressed":
			b = box(Color(0.85, 0.88, 0.95), 14)
		"disabled":
			b = box(Color(1, 1, 1, 0.04), 14)
		"hover":
			b = box(Color(1, 1, 1, 0.16), 14)
		_:
			b = box(Color(1, 1, 1, 0.09), 14)
	b.content_margin_left = 22
	b.content_margin_right = 22
	b.content_margin_top = 12
	b.content_margin_bottom = 12
	return b


static func label(text: String, size := 17, color := TEXT, weight := 450, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, display))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrapped(text: String, size := 17, color := TEXT, weight := 450) -> Label:
	var l := label(text, size, color, weight)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 10
	return l


static func button(text: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 54)
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.add_theme_stylebox_override("normal", _primary_box())
		b.add_theme_color_override("font_color", Color.BLACK)
	return b


static func _primary_box() -> StyleBox:
	var b := box(ACCENT, 14)
	b.content_margin_left = 22
	b.content_margin_right = 22
	b.content_margin_top = 12
	b.content_margin_bottom = 12
	return b


## A filled pill with a dot and a short text, for a port's state.
static func pill(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var b := box(Color(color, 0.16), 99, Color(color, 0.45), 1)
	b.content_margin_left = 12
	b.content_margin_right = 14
	b.content_margin_top = 4
	b.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	row.add_child(label(text, 15, color.lightened(0.25), 600))
	p.add_child(row)
	return p


## A full-rect control: anchors on all sides.
static func fill(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## A vertical gradient texture (top colour to bottom colour), or horizontal.
static func gradient(from: Color, to: Color, horizontal := false, stops := PackedFloat32Array([0.0, 1.0])) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = stops
	g.colors = PackedColorArray([from, to])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256 if horizontal else 4
	t.height = 4 if horizontal else 256
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	return t


## The button glyph drawn in the hint bar: a round badge with the face button's letter.
static func glyph(letter: String) -> Control:
	var c := Glyph.new()
	c.letter = letter
	return c


## A button-hint in a bar ("(A) Open"); tapping it does what the button does.
static func hint(letter: String, text: String, action: String) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.add_child(glyph(letter))
	var l := label(text, 15, TEXT, 500)
	row.add_child(l)
	b.add_child(row)
	b.custom_minimum_size.x = 26 + 8 + l.get_minimum_size().x
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.pressed.connect(func() -> void:
		for pressed in [true, false]:
			var ev := InputEventAction.new()
			ev.action = action
			ev.pressed = pressed
			Input.parse_input_event(ev))
	return b


static func human_size(bytes: float) -> String:
	if bytes >= 1024.0 * 1024 * 1024:
		return "%.1f GB" % (bytes / (1024.0 * 1024 * 1024))
	return "%d MB" % int(bytes / (1024.0 * 1024))


## A port's colour when it has no artwork yet, stable for its id.
static func tint(id: String) -> Color:
	var h := float(abs(id.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.55)


class Glyph:
	extends Control
	var letter := "A"
	const COLORS := {"A": Color("4ade80"), "B": Color("f87171"), "X": Color("60a5fa"), "Y": Color("fbbf24")}

	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c: Color = COLORS.get(letter, Color(1, 1, 1))
		var r := size.y * 0.5
		draw_circle(Vector2(r, r), r, Color(1, 1, 1, 0.12))
		draw_arc(Vector2(r, r), r - 1, 0, TAU, 32, Color(c, 0.9), 2.0, true)
		var f := UI.font(700, true)
		var fs := 14
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(r - w * 0.5, r + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
