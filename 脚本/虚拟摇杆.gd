class_name VirtualJoystick
extends Control
## 移动端虚拟摇杆(floating): 游戏内按下屏幕任意处生成基座, 拖动输出方向, 抬起消失
## 主场景2D._aim_angle 读取 output 控制挡板(优先级: 手柄左摇杆 > 虚拟摇杆 > 鼠标)
## 样式取自 UI.tscn 主题覆盖: normal/pressed_joystick(基座) + normal/pressed_tip(帽)

@export var joystick_size := 256.0
@export var tip_size := 128.0
@export var initial_offset_ratio := Vector2.ZERO   # tscn 属性兼容保留

var output := Vector2.ZERO   # 归一化输出(长度 0~1), 激活期间每帧被主场景读取

var _touch_id := -1          # 跟踪的手指 id(-1 = 未激活)
var _tip := Vector2.ZERO     # 帽相对基座的偏移(绘制用)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不参与 gui 命中, 触摸全走 _input
	visible = false                              # floating: 触摸时才生成


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not GlobalData.mods.get("虚拟摇杆", true):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_id != -1:
				return   # 已有手指在控制, 忽略其余手指
			# 暂停按钮等 gui 控件让路: 命中其全局矩形则不接管也不吞事件
			var pb := get_parent().get_node_or_null("暂停按钮") as Control
			if pb and pb.get_global_rect().has_point(event.position):
				return
			_touch_id = event.index
			position = get_parent().make_canvas_position_local(event.position)
			_tip = Vector2.ZERO
			output = Vector2.ZERO
			visible = true
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.index == _touch_id:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		var max_r := maxf((joystick_size - tip_size) * 0.5, 1.0)
		_tip = make_canvas_position_local(event.position).limit_length(max_r)
		output = _tip / max_r
		queue_redraw()
		get_viewport().set_input_as_handled()


func _release() -> void:
	_touch_id = -1
	output = Vector2.ZERO
	visible = false


func _draw() -> void:
	var base_sb: StyleBox = get_theme_stylebox("pressed_joystick" if _touch_id != -1 else "normal_joystick")
	var tip_sb: StyleBox = get_theme_stylebox("pressed_tip" if _touch_id != -1 else "normal_tip")
	if base_sb:
		base_sb.draw(get_canvas_item(), Rect2(-Vector2(joystick_size, joystick_size) * 0.5, Vector2(joystick_size, joystick_size)))
	if tip_sb:
		tip_sb.draw(get_canvas_item(), Rect2(_tip - Vector2(tip_size, tip_size) * 0.5, Vector2(tip_size, tip_size)))
