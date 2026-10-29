extends "res://脚本/弹窗基类.gd"
## 设置弹窗：音乐音量调节（独立场景 场景/设置弹窗.tscn）


func _build() -> void:
	panel.position = Vector2(660, 300)
	panel.custom_minimum_size = Vector2(600, 500)

	var title := Label.new()
	title.text = "设置"
	title.position = Vector2(40, 24)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
	panel.add_child(title)

	var vol_label := Label.new()
	vol_label.text = "音乐音量"
	vol_label.position = Vector2(40, 100)
	vol_label.add_theme_font_size_override("font_size", 30)
	panel.add_child(vol_label)

	var slider := HSlider.new()
	slider.position = Vector2(40, 148)
	slider.custom_minimum_size = Vector2(520, 30)
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = int(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100)
	slider.value_changed.connect(func(v: float):
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, v / 100.0)))
	)
	panel.add_child(slider)

	_add_toggle("中心低频跃动", "中心低频跃动", 190)
	_add_toggle("动态暗光", "动态暗光", 245)
	_add_toggle("虚拟摇杆", "虚拟摇杆", 300)

	var tutorial := _add_button("新手教程", Vector2(40, 375), Vector2(160, 70), 28)
	tutorial.pressed.connect(func():
		GlobalData.tutorial = true
		close_popup()
		var sc := get_tree().current_scene
		if sc and sc.has_method("start_game"):
			sc.start_game()
	)

	var close := _add_button("关闭", Vector2(220, 375), Vector2(160, 70), 32)
	close.pressed.connect(close_popup)


## 视觉效果开关: 写入 GlobalData.mods 并存档, 游戏内每帧实时读取
func _add_toggle(label_text: String, key: String, y: float) -> void:
	var cb := CheckButton.new()
	cb.text = label_text
	cb.position = Vector2(40, y)
	cb.add_theme_font_size_override("font_size", 30)
	cb.button_pressed = bool(GlobalData.mods.get(key, true))
	cb.toggled.connect(func(on: bool):
		GlobalData.mods[key] = on
		GlobalData.save_settings()
	)
	panel.add_child(cb)
