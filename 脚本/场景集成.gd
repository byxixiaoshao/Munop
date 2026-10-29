extends Control
## 场景集成调度：主界面 ↔ 游戏 ↔ 结算 的显隐切换与动画编排
## 切换动画用 Tween 逐元素错峰滑动（替代原 AnimationPlayer 轨道）:
##   滑出 = 加速离场(EASE_IN)  滑入 = 减速停靠, 内容元素带轻微回弹(BACK)

var switching := false

@onready var menu: Control = $主界面ui
@onready var game: Node2D = $主场景2D
@onready var game_ui: Control = $Ui
@onready var result: Control = $结算

var _tweens: Dictionary = {}   # 组名 -> 进行中的 Tween
var _homes: Dictionary = {}    # 节点 -> 常驻位置（首次滑动时捕获, 避开布局未完成）

@onready var _blur_mat: ShaderMaterial = menu.get_node("模糊背景").material

const STAGGER := 0.05          # 组内元素错峰间隔
const 设计宽 := 1920.0         # 游戏/HUD/结算三个舞台的设计宽度(keep_height 下逻辑宽随屏幕变化)


func _process(_delta: float) -> void:
	# 动态暗光: 游戏内模糊背景 darken 随低频在 0.2~0.7 间跃动; 菜单/关设置时保持默认 0.5
	# band_energy[0] 自带快起慢落平滑, 直接映射即有鼓点呼吸感
	var darken := 0.5
	if game.visible and GlobalData.mods.get("动态暗光", true) and game.band_energy.size() > 0:
		darken = lerpf(0.7, 0.2, game.band_energy[0])
	_blur_mat.set_shader_parameter("darken", darken)


func _ready() -> void:
	GlobalData.ensure_gamepad_ui()
	GlobalData.load_save()
	game.visible = false
	game_ui.visible = false
	result.visible = false
	get_viewport().size_changed.connect(_center_stage)
	_center_stage()


## keep_height 拉伸: 高度恒 1080, 宽度随屏幕比例变化; 把 1920 设计宽的舞台水平居中
## (主界面背景/边缘为全屏锚点自适应, 不参与居中)
func _center_stage() -> void:
	var off := (get_viewport_rect().size.x - 设计宽) * 0.5
	game.position = Vector2(off, 0.0)
	game_ui.position = Vector2(off, 0.0)
	result.position = Vector2(off, 0.0)


## 三组切换元素: [节点, 滑出偏移, 滑入回弹?]
func _menu_elems() -> Array:
	return [
		[menu.get_node("边缘/上"), Vector2(0, -121), false],
		[menu.get_node("边缘/下"), Vector2(0, 121), false],
		[menu.get_node("开始游戏"), Vector2(671, 0), true],
	]


func _hud_elems() -> Array:
	return [
		[game_ui.get_node("进度条"), Vector2(0, -25), false],
		[game_ui.get_node("暂停按钮"), Vector2(-165, -165), false],
		[game_ui.get_node("歌名"), Vector2(-341, 132), false],
		[game_ui.get_node("连击数"), Vector2(354, 0), true],
		[game_ui.get_node("分数"), Vector2(268, 109), true],
	]


func _result_elems() -> Array:
	return [
		[result.get_node("边缘/上"), Vector2(0, -121), false],
		[result.get_node("边缘/下"), Vector2(0, 121), false],
		[result.get_node("左侧"), Vector2(-512, 0), true],
		[result.get_node("右侧"), Vector2(512, 0), true],
	]


## 滑出一组元素（out=true 离场）或滑入回位, 返回 Tween 供 await
func _slide(group: String, elems: Array, out: bool, dur := 0.45) -> Tween:
	if _tweens.has(group) and _tweens[group] is Tween and _tweens[group].is_running():
		_tweens[group].kill()
	var tw := create_tween().set_parallel(true)
	for i in elems.size():
		var e: Array = elems[i]
		var node: Control = e[0]
		if not _homes.has(node):
			_homes[node] = node.position
		var target: Vector2 = _homes[node] + (e[1] if out else Vector2.ZERO)
		var tp: PropertyTweener = tw.tween_property(node, "position", target, dur)
		if out:
			tp.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		elif e[2]:
			tp.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tp.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i > 0:
			tp.set_delay(STAGGER * i)
	_tweens[group] = tw
	return tw


## 菜单上不参与滑动的控件（歌曲轮盘等）: 切换时淡入淡出而非瞬间消失
func _menu_extras() -> Array:
	var out: Array = []
	for c in menu.get_children():
		if c is Control and not (c.name in ["背景", "背景淡化", "模糊背景", "边缘", "开始游戏"]):
			out.append(c)
	return out


func _fade_menu_extras(to_a: float, dur: float) -> void:
	for c in _menu_extras():
		create_tween().tween_property(c, "modulate:a", to_a, dur)


## 游戏进行时保留主界面的背景与模糊背景, 隐藏其余菜单控件
func _set_menu_gameplay_only(only_bg: bool) -> void:
	for c in menu.get_children():
		if c.name in ["背景", "模糊背景"]:
			continue
		if c is Control:
			c.visible = not only_bg


## 主界面 → 游戏（由主界面UI的开始游戏按钮调用）
func start_game() -> void:
	if switching:
		return
	switching = true
	# 统一停掉主界面试听: 教程等任意入口进游戏都不得残留音乐(教程须纯静音)
	if menu.has_method("stop_preview"):
		menu.stop_preview()
	_fade_menu_extras(0.0, 0.3)
	await _slide("menu", _menu_elems(), true).finished
	_set_menu_gameplay_only(true)  # 背景+模糊背景保留, 其余菜单控件隐藏
	game.visible = true
	game_ui.visible = true
	_slide("hud", _hud_elems(), false)
	game.start_level()
	switching = false


## 游戏 → 结算（由主场景2D在音乐播完后调用）
func show_result() -> void:
	if switching:
		return
	switching = true
	game.stop_level()
	await _slide("hud", _hud_elems(), true).finished
	game_ui.visible = false
	game.visible = false
	result.visible = true
	result.refresh()
	_slide("result", _result_elems(), false)
	switching = false


## 游戏 → 主界面（暂停弹窗"返回主页"调用）
func game_to_menu() -> void:
	if switching:
		return
	switching = true
	game.stop_level()
	await _slide("hud", _hud_elems(), true).finished
	game_ui.visible = false
	game.visible = false
	_set_menu_gameplay_only(false)
	_fade_menu_extras(1.0, 0.35)
	_slide("menu", _menu_elems(), false)
	if menu.has_method("restart_preview"):
		menu.restart_preview()
	switching = false


## 结算 → 主界面（由结算的"点击任意处继续"调用）
func back_to_menu() -> void:
	if switching:
		return
	switching = true
	await _slide("result", _result_elems(), true).finished
	result.visible = false
	_set_menu_gameplay_only(false)
	_fade_menu_extras(1.0, 0.35)
	_slide("menu", _menu_elems(), false)
	if menu.has_method("restart_preview"):
		menu.restart_preview()
	switching = false
