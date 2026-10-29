extends "res://脚本/弹窗基类.gd"
## 管理弹窗: 搜索框 + 关卡列表(每行: 删除 / 重置)
## 重置弹窗: 数据重置=清该关历史成绩 | 全量重置=清成绩+重新生成谱面(封面不动) | 取消

var list_box: VBoxContainer
var search_edit: LineEdit
var _pending_del: String = ""   # 删除的两次确认目标


func _build() -> void:
	panel.position = Vector2(560, 160)
	panel.custom_minimum_size = Vector2(800, 760)

	var title := Label.new()
	title.text = "关卡管理"
	title.position = Vector2(40, 24)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
	panel.add_child(title)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "搜索关卡…"
	search_edit.position = Vector2(40, 92)
	search_edit.custom_minimum_size = Vector2(720, 52)
	search_edit.add_theme_font_size_override("font_size", 28)
	search_edit.text_changed.connect(func(_t): _rebuild_list())
	panel.add_child(search_edit)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 160)
	scroll.custom_minimum_size = Vector2(720, 540)
	panel.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 10)
	list_box.custom_minimum_size = Vector2(700, 0)
	scroll.add_child(list_box)

	var close := _add_button("关闭", Vector2(300, 720), Vector2(200, 64), 30)
	close.pressed.connect(close_popup)

	_rebuild_list()


func _rebuild_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var shown := GlobalData.library.search(search_edit.text)
	if shown.is_empty():
		var empty := Label.new()
		empty.text = "（没有匹配的关卡）"
		empty.add_theme_font_size_override("font_size", 28)
		list_box.add_child(empty)
		return
	for e in shown:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var name_l := Label.new()
		name_l.text = str(e.name)
		name_l.custom_minimum_size = Vector2(360, 52)
		name_l.add_theme_font_size_override("font_size", 26)
		name_l.add_theme_color_override("font_color", Color(0.8, 0.88, 1))
		name_l.clip_text = true
		row.add_child(name_l)

		var reset := Button.new()
		reset.text = "重置"
		reset.custom_minimum_size = Vector2(120, 52)
		reset.add_theme_font_size_override("font_size", 26)
		var lv_r: String = e.name
		reset.pressed.connect(_open_reset_popup.bind(lv_r))
		row.add_child(reset)

		var del := Button.new()
		del.text = "删除"
		del.custom_minimum_size = Vector2(120, 52)
		del.add_theme_font_size_override("font_size", 26)
		var lv: String = e.name
		del.pressed.connect(_on_delete.bind(del, lv))
		row.add_child(del)
		list_box.add_child(row)


## 单关重置弹窗: 数据重置 / 全量重置 / 取消
func _open_reset_popup(level_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "重置 " + level_name
	dialog.dialog_text = "数据重置：清空该关卡历史成绩\n全量重置：清空成绩 + 删除曲谱并重新生成（封面不受影响）"
	dialog.ok_button_text = "全量重置"
	dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func():
		GlobalData.clear_history(level_name)
		GlobalData.library.reset_one(level_name)
		dialog.queue_free()
		_menu_rebuild()
	)
	# 第三个按钮: 仅数据重置
	var data_btn := dialog.add_button("数据重置", true, "data_only")
	dialog.custom_action.connect(func(action: String):
		if action == "data_only":
			GlobalData.clear_history(level_name)
			dialog.queue_free()
			_menu_rebuild()
	)
	dialog.popup_centered()


func _on_delete(btn: Button, level_name: String) -> void:
	if _pending_del != level_name:
		_pending_del = level_name
		btn.text = "确认删除?"
		btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		var t := get_tree().create_timer(3.0)
		t.timeout.connect(func():
			_pending_del = ""
			if is_instance_valid(btn):
				btn.text = "删除"
				btn.add_theme_color_override("font_color", Color.WHITE)
		)
		return
	GlobalData.library.remove(level_name)  # 索引移除, 重启不会复活
	_pending_del = ""
	_menu_rebuild()
	_rebuild_list()


func _menu_rebuild() -> void:
	var menu := get_tree().current_scene.get_node_or_null("主界面ui")
	if menu and menu.has_method("rebuild_levels"):
		menu.rebuild_levels()
