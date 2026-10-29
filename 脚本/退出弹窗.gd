extends "res://脚本/弹窗基类.gd"
## 退出弹窗：确认退出游戏 / 取消（独立场景 场景/退出弹窗.tscn）


func _build() -> void:
	panel.position = Vector2(660, 340)
	panel.custom_minimum_size = Vector2(600, 300)

	var title := Label.new()
	title.text = "确认退出游戏？"
	title.position = Vector2(40, 36)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
	panel.add_child(title)

	var ok := _add_button("退出", Vector2(60, 160), Vector2(220, 80), 34)
	ok.pressed.connect(func(): get_tree().quit())

	var cancel := _add_button("取消", Vector2(320, 160), Vector2(220, 80), 34)
	cancel.pressed.connect(close_popup)
