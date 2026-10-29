class_name 弹窗基类
extends Control
## 弹窗统一基类: 暗层 + 面板, 弹出/收回动画统一在此
## 子类 extends 此脚本, 在 _build() 里往 panel 填内容（可先改 panel 位置/尺寸）, 关闭调 close_popup()

signal 已关闭

static var 打开数 := 0   # 当前打开的弹窗数(手柄主界面导航用它让位)

var dim: ColorRect
var panel: Panel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 根不拦点击, 暗层负责吞
	打开数 += 1
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	panel = Panel.new()
	panel.position = Vector2(660, 320)
	panel.custom_minimum_size = Vector2(600, 340)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12)
	style.border_color = Color(0, 0.5, 1)
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_build()

	# keep_height 拉伸下逻辑宽随屏幕变化: 面板按 1920 设计宽定位, 这里整体平移回屏幕中心
	panel.position += Vector2((get_viewport_rect().size.x - 1920.0) * 0.5, 0.0)

	# 手柄: 默认聚焦面板内第一个按钮, 十字键/摇杆导航, A 确认
	var btns := panel.find_children("*", "Button", true, false)
	if btns.size() > 0:
		(btns[0] as Button).grab_focus()

	# 打开: 整体淡入 + 面板从中心弹出
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	panel.pivot_offset = panel.custom_minimum_size / 2.0
	panel.scale = Vector2(0.85, 0.85)
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _exit_tree() -> void:
	打开数 = maxi(0, 打开数 - 1)


## B/Esc 关闭弹窗(子类可重写 _cancelled 改变行为)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancelled()


## 取消时的行为, 默认直接关闭
func _cancelled() -> void:
	close_popup()


## 子类重写: 构建面板内容
func _build() -> void:
	pass


## 统一关闭: 面板收回 + 整体淡出, 完成后发信号并释放
func close_popup() -> void:
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_property(panel, "scale", Vector2(0.88, 0.88), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		已关闭.emit()
		queue_free()
	)


## 便捷加按钮（panel 内坐标）
func _add_button(text: String, pos: Vector2, btn_size: Vector2, font_size := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = btn_size
	b.add_theme_font_size_override("font_size", font_size)
	panel.add_child(b)
	return b
