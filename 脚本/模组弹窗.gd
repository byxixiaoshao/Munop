extends "res://脚本/弹窗基类.gd"
## 模组弹窗: 挡板长度 / 音符块大小 两个滑条(15°~120°), 实时写入 GlobalData.mods 并存档


func _build() -> void:
	panel.position = Vector2(660, 300)
	panel.custom_minimum_size = Vector2(600, 400)

	var title := Label.new()
	title.text = "模组"
	title.position = Vector2(40, 24)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
	panel.add_child(title)

	_add_slider("挡板长度", "shield_span_deg", 110)
	_add_slider("音符块大小", "note_span_deg", 220)

	var close := _add_button("关闭", Vector2(220, 310), Vector2(160, 64), 30)
	close.pressed.connect(close_popup)


func _add_slider(label_text: String, key: String, y: float) -> void:
	var l := Label.new()
	l.text = label_text
	l.position = Vector2(40, y)
	l.add_theme_font_size_override("font_size", 28)
	panel.add_child(l)

	var val_label := Label.new()
	val_label.text = "%d°" % int(float(GlobalData.mods.get(key, 90.0)))
	val_label.position = Vector2(490, y)
	val_label.add_theme_font_size_override("font_size", 28)
	val_label.add_theme_color_override("font_color", Color(0.5, 0.85, 1))
	panel.add_child(val_label)

	var slider := HSlider.new()
	slider.position = Vector2(40, y + 46)
	slider.custom_minimum_size = Vector2(520, 28)
	slider.min_value = 15
	slider.max_value = 120
	slider.step = 1
	slider.value = float(GlobalData.mods.get(key, 90.0))
	slider.value_changed.connect(func(v: float):
		GlobalData.mods[key] = v
		val_label.text = "%d°" % int(v)
		GlobalData.save_settings()
	)
	panel.add_child(slider)
