extends Control
## 结算：填入成绩数据 + 历史成绩记录 + 点击任意处返回主界面

const MAX_SCORE := 1000000

var rank_loop: Tween          # 评级呼吸/闪光循环(重复结算时杀掉重建)
var _music: AudioStreamPlayer # 高潮试听(与主界面同一片段来源 info.json)
var _music_timer: Timer       # 片段循环计时
var _music_tween: Tween       # 淡入 tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 子节点(Panel/Label)不吞鼠标, 保证点任意处都能触发继续
	_set_ignore_mouse(self)
	# 高潮试听: 片段循环
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_music_timer = Timer.new()
	_music_timer.one_shot = true
	_music_timer.timeout.connect(func():
		_music.play(_music.get_meta("offset", 0.0))
		_music_timer.start(_music.get_meta("len", 10.0))
	)
	add_child(_music_timer)
	# "点击任意处继续"呼吸提示
	var hint: Label = $边缘/下/Label
	var tw := hint.create_tween().set_loops()
	tw.tween_property(hint, "modulate:a", 0.45, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(hint, "modulate:a", 1.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_ignore_mouse(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_ignore_mouse(c)


func refresh() -> void:
	var score := mini(GlobalData.result_score, MAX_SCORE)  # 满分封顶: X 只属于 100 万
	var rank := GlobalData.rank_of(score)

	# 记录历史成绩（每关保留前 5）
	var key := GlobalData.result_name
	GlobalData.record(key, score, GlobalData.difficulty)

	_build_chart()
	$左侧/整体评价.text = rank
	$左侧/分数.text = "%d" % score
	$左侧/音符块数.text = "%d/%d" % [GlobalData.result_caught, GlobalData.result_total]
	$右侧/歌名.text = key

	# --- 展示动画: 评级弹入 + 分数滚动计数 + 次级信息延迟浮现 ---
	var rank_col: Color = {
		"X": Color(1.4, 0.22, 0.16), "S": Color(1.6, 1.25, 0.45), "A": Color(0.5, 1.1, 1.4),
		"B": Color(0.55, 1.3, 0.7), "C": Color(1.4, 0.9, 0.45), "D": Color(1.4, 0.5, 0.5),
	}[rank]
	var rank_l: Label = $左侧/整体评价
	rank_l.add_theme_color_override("font_color", rank_col)
	rank_l.pivot_offset = rank_l.size / 2.0
	rank_l.scale = Vector2(2.6, 2.6)
	rank_l.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rank_l, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(rank_l, "modulate:a", 1.0, 0.18)
	var score_l: Label = $左侧/分数
	tw.tween_method(func(v: float): score_l.text = "%d" % int(round(v)), 0.0, float(score), 0.9) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for path in ["左侧/音符块数", "右侧/歌名", "右侧/列表背景", "右侧/判定统计"]:
		var c := get_node(path) as Control
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, 0.4).set_delay(0.35)

	_start_rank_fx(rank_l, rank)

	# 历史成绩列表
	var no_box: VBoxContainer = $右侧/列表背景/纵向排布/横向排布/序号
	var score_box: VBoxContainer = $右侧/列表背景/纵向排布/横向排布/分数排布
	for c in no_box.get_children():
		c.queue_free()
	for c in score_box.get_children():
		c.queue_free()
	var rows: Array = GlobalData.get_history(key, GlobalData.difficulty)
	for i in rows.size():
		no_box.add_child(_row_label("%d." % (i + 1)))
		score_box.add_child(_row_label("%d" % rows[i]))

	_start_climax_music()


## 高潮试听: 播放 info.json 记录的高潮片段并循环, 淡入
func _start_climax_music() -> void:
	stop_music()
	var entry: Dictionary = GlobalData.library.find(GlobalData.result_name)
	if entry.is_empty():
		return
	var stream := GlobalData.library.load_stream(entry)
	if stream == null:
		return
	var info: Dictionary = GlobalData.library.climax_of(GlobalData.result_name)
	_music.stream = stream
	_music.set_meta("offset", float(info.offset))
	_music.set_meta("len", float(info.len))
	_music.volume_db = -40.0
	_music.play(info.offset)
	_music_timer.start(info.len)
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", 0.0, 0.5)


## 离开结算时停掉试听(点击任意处继续前调用)
func stop_music() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_timer.stop()
	_music.stop()


## 评级特效: X = 暗红色呼吸发光(HDR 触发泛光), 其他 = 原色亮度闪光呼吸
func _start_rank_fx(rank_l: Label, rank: String) -> void:
	if rank_loop and rank_loop.is_valid():
		rank_loop.kill()
	var col_bright: Color
	var col_dim: Color
	if rank == "X":
		col_dim = Color(0.75, 0.12, 0.09)
		col_bright = Color(1.8, 0.35, 0.24)   # HDR 峰值, 泛光红晕
	else:
		col_dim = rank_l.get_theme_color("font_color")
		col_bright = col_dim * 1.5 + Color(0.25, 0.25, 0.25)
	rank_loop = rank_l.create_tween().set_loops()
	var period := 1.4 if rank == "X" else 1.0
	rank_loop.tween_method(
		func(k: float): rank_l.add_theme_color_override("font_color", col_dim.lerp(col_bright, k)),
		0.0, 1.0, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rank_loop.tween_method(
		func(k: float): rank_l.add_theme_color_override("font_color", col_bright.lerp(col_dim, k)),
		0.0, 1.0, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 判定频率统计柱状图(挂在 历史成绩 面板下方, 右缘与面板对齐)
func _build_chart() -> void:
	for c in $右侧.get_children():
		if c.name == "判定统计":
			c.queue_free()
	var chart := Control.new()
	chart.set_script(load("res://脚本/判定统计.gd"))
	chart.name = "判定统计"
	chart.position = Vector2(-350, 305)   # 列表背景 offset_bottom=285, 留 20px 间距
	chart.custom_minimum_size = Vector2(350, 190)
	chart.size = Vector2(350, 190)
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$右侧.add_child(chart)
	chart.counts = GlobalData.result_judgements
	chart.queue_redraw()


func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	return l


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		stop_music()
		var sc := get_tree().current_scene
		if sc and sc.has_method("back_to_menu"):
			sc.back_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	# 兜底: 被 UI 层吞掉的点击也能继续; 手柄任意按键同效
	if not visible:
		return
	var go := false
	if event is InputEventMouseButton and event.pressed:
		go = true
	if event is InputEventJoypadButton and event.pressed:
		go = true   # 手柄任意按键继续
	if go:
		stop_music()
		var sc := get_tree().current_scene
		if sc and sc.has_method("back_to_menu"):
			sc.back_to_menu()
