extends VirtualJoystick
## 移动端虚拟摇杆适配层(Godot 4.7+ 原生 VirtualJoystick 节点)
## 原生节点负责触摸/绘制/主题; 本脚本只做三件事:
##   1. 全屏命中: 触摸屏幕任意处即可生成(落在暂停按钮上时让路)
##   2. 模式: 按下处生成基座(DYNAMIC) + 触摸时才显示(WHEN_TOUCHED)
##   3. 开关门卫: 设置里的"虚拟摇杆"开关(关闭时不接收触摸)
## 挡板角度由主场景2D 经 Input.get_vector("ui_left","ui_right","ui_up","ui_down") 读取
## (原生节点激活期间持续模拟这四个方向动作)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)   # 覆盖全屏接收触摸(实际命中由 _has_point 决定)
	joystick_mode = JOYSTICK_DYNAMIC               # 按下处生成基座, 松开归位
	visibility_mode = VISIBILITY_WHEN_TOUCHED      # 松手即隐
	mouse_filter = Control.MOUSE_FILTER_PASS       # 自身处理后放行, 下层控件(暂停按钮)与点击特效仍可收到


func _has_point(point: Vector2) -> bool:
	# 开关关闭: 不接收任何触摸; 落在暂停按钮全局矩形内: 让给按钮
	if not GlobalData.mods.get("虚拟摇杆", true):
		return false
	var pb := get_parent().get_node_or_null("暂停按钮") as Control
	if pb and pb.get_global_rect().has_point(get_global_transform() * point):
		return false
	return true
