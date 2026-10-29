extends Control
## 歌曲轮盘：滚轮或上下拖动切换歌曲, 居中项为选中, 歌名保持水平
## 用法: set_items(列表) → 信号 selection_changed(歌名)

signal selection_changed(index: int)

const SPACING := 92.0        # 相邻项间距
const MAX_VISIBLE := 2       # 中心上下各显示几项
const SNAP_SPEED := 12.0     # 吸附速度

var items: Array = []
var scroll := 0.0            # 当前滚动位置（浮点索引）
var target := 0.0            # 目标索引
var dragging := false
var drag_start_y := 0.0
var drag_start_target := 0.0
var labels: Array[Label] = []
var indicator: Panel         # 居中选中指示条
var _t := 0.0                # 呼吸动画时钟


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# 居中高亮条: 先于歌名创建垫底, 微微呼吸
	indicator = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.6, 1.0, 0.10)
	style.border_color = Color(0.3, 0.8, 1.0, 0.35)
	style.border_width_left = 2
	style.border_width_right = 2
	style.set_corner_radius_all(10)
	indicator.add_theme_stylebox_override("panel", style)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(indicator)


func set_items(list: Array, select_index: int) -> void:
	items = list
	target = clampf(select_index, 0, items.size() - 1)
	scroll = target
	_last_sel = int(target)  # 同步选中标记: 列表重建后索引漂移会使 sel!=_last_sel 判断失效
	for l in labels:
		l.queue_free()
	labels.clear()
	for i in items.size():
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
		add_child(l)
		labels.append(l)
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	if indicator:
		indicator.modulate.a = 0.8 + 0.2 * sin(_t * 2.5)  # 呼吸
	if absf(scroll - target) > 0.001:
		scroll = lerpf(scroll, target, 1.0 - exp(-SNAP_SPEED * delta))
		_refresh()


func _refresh() -> void:
	var half := size.y / 2.0
	if indicator:
		indicator.position = Vector2(0, half - 38.0)
		indicator.size = Vector2(size.x, 76.0)
	for i in items.size():
		var l := labels[i]
		var rel := i - scroll  # 相对中心的偏移(项数)
		if absf(rel) > MAX_VISIBLE + 0.5:
			l.visible = false
			continue
		l.visible = true
		l.text = items[i]
		l.position = Vector2(0, half + rel * SPACING - SPACING * 0.4)
		l.size = Vector2(size.x, SPACING * 0.8)
		# 中心项: 大而亮; 越远越小越暗
		var f := absf(rel)
		var font := int(lerpf(52.0, 30.0, clampf(f / MAX_VISIBLE, 0.0, 1.0)))
		l.add_theme_font_size_override("font_size", font)
		l.modulate = Color(1, 1, 1, lerpf(1.0, 0.35, clampf(f / MAX_VISIBLE, 0.0, 1.0)))


func _gui_input(event: InputEvent) -> void:
	if items.is_empty():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			target = clampf(target - 1.0, 0, items.size() - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			target = clampf(target + 1.0, 0, items.size() - 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_start_y = event.position.y
				drag_start_target = target
			else:
				dragging = false
				target = clampf(round(target), 0, items.size() - 1)
	elif event is InputEventMouseMotion and dragging:
		target = clampf(drag_start_target - (event.position.y - drag_start_y) / SPACING, 0, items.size() - 1)
	# 滚动/拖动到位后若选中项变化则通知
	var sel := int(round(clampf(target, 0, items.size() - 1)))
	if sel != _last_sel:
		_last_sel = sel
		selection_changed.emit(sel)
		_pop_sel(sel)


## 手柄/程序步进选中项(与手动滚动同路径发信号)
func move_selection(step: int) -> void:
	if items.is_empty():
		return
	target = clampf(target + float(step), 0.0, items.size() - 1)
	var sel := int(round(target))
	if sel != _last_sel:
		_last_sel = sel
		selection_changed.emit(sel)
		_pop_sel(sel)


## 选中项弹跳一下
func _pop_sel(i: int) -> void:
	if i < 0 or i >= labels.size():
		return
	var l := labels[i]
	l.pivot_offset = l.size / 2.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.12, 0.08)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


var _last_sel := -1
