extends Node2D
## 全局鼠标点击涟漪: 挂在 场景集成 的 CanvasLayer 上, 菜单/游戏/弹窗通用
## 双层扩散环 + 中心亮斑, 颜色与游戏主色一致, HDR 亮部触发泛光

const DUR := 0.38

var ripples: Array = []  # {pos, t}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时也响应
	set_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		ripples.append({"pos": get_global_mouse_position(), "t": 0.0})
		set_process(true)
		queue_redraw()


func _process(delta: float) -> void:
	for r in ripples:
		r.t += delta
	ripples = ripples.filter(func(r): return r.t < DUR + 0.06)
	if ripples.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for r in ripples:
		# 外环: 扩散并变细变淡
		var p: float = clampf(r.t / DUR, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - p, 3.0)
		draw_arc(r.pos, 6.0 + 44.0 * e, 0, TAU, 40, Color(0.7, 1.05, 1.3, (1.0 - p) * 0.85), 2.5 * (1.0 - p) + 0.5, true)
		# 内环: 短延迟跟进
		var p2: float = clampf((r.t - 0.06) / (DUR - 0.06), 0.0, 1.0)
		if p2 > 0.0:
			var e2 := 1.0 - pow(1.0 - p2, 3.0)
			draw_arc(r.pos, 3.0 + 24.0 * e2, 0, TAU, 32, Color(0.55, 0.9, 1.25, (1.0 - p2) * 0.7), 2.0 * (1.0 - p2) + 0.4, true)
		# 中心亮斑: 快速收缩消失
		if r.t < 0.16:
			var q: float = 1.0 - r.t / 0.16
			draw_circle(r.pos, 8.0 * q, Color(1.6, 1.8, 2.0, q))
