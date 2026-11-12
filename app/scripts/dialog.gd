class_name ConfirmBox
extends Control
## A yes/no question over the current screen.

var _title: Label
var _text: Label
var _ok: Button
var _no: Button
var _cb: Callable


func _ready() -> void:
	UI.fill(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	add_child(UI.fill(dim))
	var panel := PanelContainer.new()
	var b := UI.box(Color(0.075, 0.085, 0.115, 0.98), 22, Color(1, 1, 1, 0.1), 1)
	b.content_margin_left = 30
	b.content_margin_right = 30
	b.content_margin_top = 26
	b.content_margin_bottom = 24
	b.shadow_color = Color(0, 0, 0, 0.5)
	b.shadow_size = 30
	panel.add_theme_stylebox_override("panel", b)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.position = Vector2(-310, -140)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	_title = UI.wrapped("", 25, UI.TEXT, 700)
	_title.add_theme_font_override("font", UI.font(700, true))
	_title.custom_minimum_size.x = 560
	col.add_child(_title)
	_text = UI.wrapped("", 17, UI.MUTED)
	_text.custom_minimum_size.x = 560
	col.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	_no = UI.button(L.t("cancel"))
	_no.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no.custom_minimum_size.x = 170
	_ok = UI.button("", true)
	_ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ok.custom_minimum_size.x = 170
	row.add_child(_no)
	row.add_child(_ok)
	col.add_child(row)
	_no.pressed.connect(func(): _close(false))
	_ok.pressed.connect(func(): _close(true))


## cb receives true when the player confirms.
func ask(title: String, text: String, ok_text: String, cb: Callable) -> void:
	_title.text = title
	_text.text = text
	_text.visible = text != ""
	_ok.text = ok_text
	_cb = cb
	show()
	_ok.grab_focus.call_deferred()


func _close(ok: bool) -> void:
	hide()
	if _cb.is_valid():
		_cb.call(ok)


func handle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		_close(false)
		return true
	return false
