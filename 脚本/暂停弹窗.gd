extends "res://脚本/弹窗基类.gd"
## 游戏暂停弹窗：继续游戏 / 重新开始 / 返回主页（独立场景 场景/暂停弹窗.tscn）

signal 继续
signal 重开
signal 回主页


func _build() -> void:
	panel.position = Vector2(660, 300)
	panel.custom_minimum_size = Vector2(600, 400)

	var title := Label.new()
	title.text = "游戏暂停"
	title.position = Vector2(40, 24)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
	panel.add_child(title)

	var b1 := _add_button("继续游戏", Vector2(70, 110), Vector2(460, 70), 36)
	b1.pressed.connect(func(): 继续.emit())
	var b2 := _add_button("重新开始", Vector2(70, 195), Vector2(460, 70), 36)
	b2.pressed.connect(func(): 重开.emit())
	var b3 := _add_button("返回主页", Vector2(70, 280), Vector2(460, 70), 36)
	b3.pressed.connect(func(): 回主页.emit())


## 手柄 B/Esc: 等同"继续游戏"(直接关窗会卡在暂停态)
func _cancelled() -> void:
	继续.emit()


func _unhandled_input(event: InputEvent) -> void:
	# 手柄 Start: 恢复游戏(本节点 ALWAYS, 游戏节点暂停期间由这里接管)
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		继续.emit()
		return
	super(event)   # B/Esc 走基类关闭逻辑
