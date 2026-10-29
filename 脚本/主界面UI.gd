extends Control
## 主界面：歌曲轮盘（扫描 资源/ 下的谱面 JSON）+ 开始游戏

const 资源目录 := "res://资源"
const _AudioLoader := preload("res://脚本/音频加载.gd")

# 通知条停靠/藏匿位与挡板行程: 停靠/藏匿位在 notify() 里按当前宽度加法推导, 不写死分辨率
const 挡板行程 := 480.0                  # 挡板擦出距离(=文本宽)
# 评价颜色: 与结算页同源(HDR 值, 泛光下会更亮)
const 评价颜色 := {
	"X": Color(1.4, 0.22, 0.16), "S": Color(1.6, 1.25, 0.45), "A": Color(0.5, 1.1, 1.4),
	"B": Color(0.55, 1.3, 0.7), "C": Color(1.4, 0.9, 0.45), "D": Color(1.4, 0.5, 0.5),
}

var chart_files := []  # 轮盘索引 → json 文件名
var wheel: Control     # 歌曲轮盘
var diff_box: HBoxContainer  # 难度分段按钮组

# 背景交叉淡化 & 试听
var bg_fade: TextureRect          # 叠在背景之上, 持旧封面淡出
var preview: AudioStreamPlayer    # 高潮片段试听
var loop_timer: Timer             # 片段循环计时
var preview_gen := 0              # 快速切歌时作废旧的淡入淡出协程
var current_lv := ""
var climax_cache: Dictionary = {}  # 关卡名 -> {offset, len}
var preview_tweens: Array[Tween] = []  # 自建的试听 tween, 停止时统一杀掉
var _notify_tween: Tween            # 通知条专用 tween, 新通知直接打断旧的
var _rank_tween: Tween              # 评价入场动画
var _best_tween: Tween              # 分数流式增长动画
var _rank_home := Vector2(-1, -1)   # 评价 label 原位缓存(首次记录, 之后仅此函数移动它)
var _nav_cd := 0.0                  # 手柄摇杆导航冷却(防连发过快)


func _ready() -> void:
	if GlobalData.library.songs.is_empty():
		GlobalData.load_save()  # 子节点 ready 先于父节点(场景集成), 库可能还没载入
	_setup_preview()
	_build_difficulty_button()
	_build_song_wheel()
	$开始游戏.pressed.connect(_on_start)
	$边缘/下/底部按钮排布/导入.pressed.connect(_on_import)
	$边缘/下/底部按钮排布/模组.pressed.connect(_open_popup.bind("res://场景/模组弹窗.tscn"))
	$边缘/下/底部按钮排布/管理.pressed.connect(_open_popup.bind("res://场景/管理弹窗.tscn"))
	$边缘/下/底部按钮排布/规则.pressed.connect(_open_popup.bind("res://场景/规则弹窗.tscn"))
	$边缘/下/底部按钮排布/设置.pressed.connect(_open_settings)
	$边缘/下/底部按钮排布/退出.pressed.connect(_open_exit)
	# 按钮悬停/按压动效: 轻微缩放 + 提亮
	_bind_button_fx($开始游戏)
	for b in $边缘/下/底部按钮排布.get_children():
		_bind_button_fx(b)


func _bind_button_fx(b: Button) -> void:
	b.mouse_entered.connect(func():
		b.pivot_offset = b.size / 2.0
		create_tween().tween_property(b, "scale", Vector2.ONE * 1.06, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		b.modulate = Color(1.45, 1.45, 1.5)
	)
	b.mouse_exited.connect(func():
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		b.modulate = Color.WHITE
	)
	b.button_down.connect(func():
		create_tween().tween_property(b, "scale", Vector2.ONE * 0.96, 0.06)
	)
	b.button_up.connect(func():
		create_tween().tween_property(b, "scale", Vector2.ONE * 1.06, 0.1)
	)


## 背景/试听的基础节点
func _setup_preview() -> void:
	# 背景 TextureRect 设为覆盖模式, 上叠一层旧封面淡出
	var bg: TextureRect = $背景
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_fade = TextureRect.new()
	bg_fade.name = "背景淡化"   # 显式命名: 供场景集成的淡入淡出排除(它由交叉淡化自管透明度)
	bg_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_fade.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_sibling(bg_fade)
	bg_fade.modulate.a = 0.0

	preview = AudioStreamPlayer.new()
	preview.volume_db = -40.0
	add_child(preview)
	loop_timer = Timer.new()
	loop_timer.one_shot = true
	loop_timer.timeout.connect(_loop_preview)
	add_child(loop_timer)


## 封面交叉淡化: 新封面立即就位, 旧封面盖在上面淡出
func _crossfade_bg(tex: Texture2D) -> void:
	if tex == null and $背景.texture == null:
		return
	bg_fade.texture = $背景.texture
	$背景.texture = tex
	bg_fade.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(bg_fade, "modulate:a", 0.0, 0.6)


## 试听: 高潮片段循环, 带淡入淡出
func _start_preview(lv: String) -> void:
	current_lv = lv
	preview_gen += 1
	var gen := preview_gen
	var tw := create_tween()
	preview_tweens.append(tw)
	tw.tween_property(preview, "volume_db", -40.0, 0.35)
	await tw.finished
	if gen != preview_gen:
		return
	preview.stream = GlobalData.library.load_stream(GlobalData.library.find(lv))
	if preview.stream == null:
		preview.stop()
		return
	var info: Dictionary = _climax_info(lv)
	preview.volume_db = -40.0
	preview.play(info.offset)
	tw = create_tween()
	preview_tweens.append(tw)
	tw.tween_property(preview, "volume_db", 0.0, 0.5)
	loop_timer.start(info.len)


func _loop_preview() -> void:
	if preview.stream == null or not is_visible_in_tree():
		return
	var info: Dictionary = _climax_info(current_lv)
	preview.play(info.offset)
	loop_timer.start(info.len)


## 停止试听(开始游戏时), 快速淡出
func stop_preview() -> void:
	preview_gen += 1
	loop_timer.stop()
	for tw in preview_tweens:
		tw.kill()  # 杀掉正在进行的淡入淡出, 防止与游戏音乐叠播
	preview_tweens.clear()
	preview.volume_db = 0.0
	preview.stop()


## 返回主界面时恢复试听
func restart_preview() -> void:
	refresh_selection()
	_start_preview(GlobalData.selected_name)


## 返回主界面的校准: 封面/成绩/选中态直接对齐当前歌曲(修复游戏期间可能的状态漂移)
func refresh_selection() -> void:
	var idx := chart_files.find(GlobalData.selected_name)
	if idx < 0:
		return
	wheel.set_items(chart_files, idx)
	var tex: ImageTexture = GlobalData.library.load_cover(GlobalData.library.find(GlobalData.selected_name))
	if tex == null:
		tex = _default_cover()
	bg_fade.modulate.a = 0.0   # 收起交叉淡化层, 直接呈现正确封面
	bg_fade.texture = null     # 清掉残留旧封面, 防止任何途径淡回 alpha=1 时显形
	$背景.texture = tex
	_update_best_label(GlobalData.selected_name)


## 高潮片段: 歌曲库统一提供(info.json → 谱面 sections 回退), 本地缓存
func _climax_info(lv: String) -> Dictionary:
	if climax_cache.has(lv):
		return climax_cache[lv]
	var info: Dictionary = GlobalData.library.climax_of(lv)
	climax_cache[lv] = info
	return info


## 导入本地音频: 选择 mp3 → 复制进 资源/ → 插件分析生成谱面 → 轮盘刷新
func _on_import() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.mp3 ; MP3 音频", "*.wav ; WAV 音频", "*.ogg ; OGG Vorbis", "*.flac ; FLAC 无损"])
	dlg.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	dlg.use_native_dialog = true
	dlg.file_selected.connect(_import_song)
	add_child(dlg)
	dlg.popup_centered(Vector2i(1000, 700))


func _import_song(path: String) -> void:
	# Android: 未授予"所有文件访问"时先请求(跳系统设置页) — 授权后 content:// 才能映射为真实路径持久化
	# 返回后继续导入: 已授权 → 存真实路径重启不丢; 未授权 → 存 content:// 本次会话有效
	if OS.get_name() == "Android" and DirAccess.open("/storage/emulated/0") == null:
		OS.request_permission("MANAGE_EXTERNAL_STORAGE")
	# 库导入: 音频留原位, 分析谱面/封面入 user 库, 索引记绝对路径
	# Android 文件选择器返回 URL 编码的 content:// URI, 显示前先解码
	notify("正在导入: %s" % path.uri_decode().get_file())
	await get_tree().process_frame
	await get_tree().process_frame   # 先让"正在导入"画出来, 再做阻塞式分析
	var entry: Dictionary = GlobalData.library.import_file(path)
	if entry.is_empty():
		notify("导入失败（格式需为 mp3/wav/ogg/flac，且文件可解析）")
		return
	# 实时刷新轮盘并选中新歌
	_scan_charts()
	var idx := chart_files.find(entry.name)
	if idx < 0:
		idx = chart_files.size() - 1
	wheel.set_items(chart_files, idx)
	_on_level_selected(idx)
	notify("导入完成: %s" % entry.name)


func _open_settings() -> void:
	_open_popup("res://场景/设置弹窗.tscn")


func _open_exit() -> void:
	_open_popup("res://场景/退出弹窗.tscn")


## 弹窗作为当前场景根的覆盖层实例化（独立场景, 任意界面可复用）
func _open_popup(path: String) -> void:
	var popup: Control = load(path).instantiate()
	get_tree().current_scene.add_child(popup)


## 难度分段选择: 三个并排胶囊按钮, 选中者高亮描边
func _build_difficulty_button() -> void:
	var box := HBoxContainer.new()
	box.position = Vector2(120, 150)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var names := ["简单", "普通", "困难"]
	for i in 3:
		var btn := Button.new()
		btn.text = names[i]
		btn.custom_minimum_size = Vector2(108, 58)
		btn.add_theme_font_size_override("font_size", 28)
		var idx := i
		btn.pressed.connect(_set_difficulty.bind(idx))
		box.add_child(btn)
	diff_box = box
	_style_diff_buttons()


## 设置难度(按钮点击/手柄切换共用)
func _set_difficulty(idx: int) -> void:
	GlobalData.difficulty = idx
	_style_diff_buttons()
	_update_best_label(GlobalData.selected_name)  # 切难度: 成绩标签跟着切


## 手柄主界面是否可导航(轮盘可见且无弹窗)
func _menu_gamepad_ok() -> bool:
	return wheel != null and wheel.visible and 弹窗基类.打开数 == 0


## 手柄左摇杆: 上下切歌; LT/RT: 切难度(带冷却防连发)
func _process(delta: float) -> void:
	_nav_cd = maxf(0.0, _nav_cd - delta)
	if not _menu_gamepad_ok():
		return
	var y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if _nav_cd > 0.0 or (absf(y) < 0.5 and lt < 0.5 and rt < 0.5):
		return
	_nav_cd = 0.35
	if lt >= 0.5:
		_diff_move(-1)
	elif rt >= 0.5:
		_diff_move(1)
	else:
		wheel.move_selection(-1 if y < 0.0 else 1)


## 手柄按键: LB/RB 循环选中底部按钮, Start 开始游戏(A 经焦点系统激活选中按钮)
func _unhandled_input(event: InputEvent) -> void:
	if not _menu_gamepad_ok():
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				_cycle_bottom_focus(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				_cycle_bottom_focus(1)
			JOY_BUTTON_START:
				_on_start()


## 手柄 LB/RB: 焦点在底部按钮排布中循环移动(A 即可激活选中项)
func _cycle_bottom_focus(step: int) -> void:
	var btns := $边缘/下/底部按钮排布.get_children()
	if btns.is_empty():
		return
	var idx := btns.find(get_viewport().gui_get_focus_owner())
	idx = 0 if idx < 0 else wrapi(idx + step, 0, btns.size())
	(btns[idx] as Button).grab_focus()


## 手柄左右步进切难度
func _diff_move(step: int) -> void:
	var idx := clampi(GlobalData.difficulty + step, 0, 2)
	if idx != GlobalData.difficulty:
		_set_difficulty(idx)


func _style_diff_buttons() -> void:
	var colors := [Color(0.35, 0.9, 0.6), Color(1.0, 0.8, 0.35), Color(1.0, 0.45, 0.4)]
	for i in diff_box.get_child_count():
		var btn: Button = diff_box.get_child(i)
		var on: bool = i == GlobalData.difficulty
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.09, 0.18) if on else Color(0.04, 0.05, 0.09, 0.8)
		style.border_color = colors[i] if on else Color(0.2, 0.3, 0.45)
		style.set_border_width_all(2 if on else 1)
		style.set_corner_radius_all(29)
		style.content_margin_left = 26
		style.content_margin_right = 26
		btn.add_theme_stylebox_override("normal", style)
		var hover: StyleBoxFlat = style.duplicate()
		hover.border_color = colors[i]
		hover.bg_color = Color(0.03, 0.14, 0.26)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_color_override("font_color", colors[i] if on else Color(0.65, 0.75, 0.9))


func _build_song_wheel() -> void:
	var script := load("res://脚本/歌曲轮盘.gd")
	wheel = Control.new()
	wheel.set_script(script)
	wheel.position = Vector2(120, 240)
	wheel.size = Vector2(520, 600)
	add_child(wheel)

	_scan_charts()
	if chart_files.is_empty():
		return
	var default_idx := chart_files.find(GlobalData.selected_name)
	if default_idx < 0:
		default_idx = 0
	wheel.set_items(chart_files, default_idx)
	wheel.selection_changed.connect(_on_level_selected)
	_on_level_selected(default_idx)


## 从歌曲库刷新轮盘数据
func _scan_charts() -> void:
	chart_files.clear()
	for e in GlobalData.library.songs:
		chart_files.append(e.name)


func _on_level_selected(i: int) -> void:
	i = clampi(i, 0, chart_files.size() - 1)
	var lv: String = chart_files[i]
	GlobalData.selected_name = lv
	# 专辑封面交叉淡化(库: png → 内嵌 → 默认)
	var tex: ImageTexture = GlobalData.library.load_cover(GlobalData.library.find(lv))
	if tex == null:
		tex = _default_cover()
	_crossfade_bg(tex)
	_update_best_label(lv)
	_start_preview(lv)


var _def_cover: ImageTexture

## 默认封面: 无专辑图(wav/ogg/flac 或未内嵌)时的占位
func _default_cover() -> ImageTexture:
	if _def_cover:
		return _def_cover
	var img := Image.load_from_file(ProjectSettings.globalize_path(资源目录 + "/默认封面.png"))
	if img == null:
		return null
	_def_cover = ImageTexture.create_from_image(img)
	return _def_cover


## 当前关卡历史最佳显示: 评级字母 + 最高分, 切歌/切难度时带入场动效
## 评价: 自右向左滑入淡入, 并按评级染色(与结算页同源); 分数: 从 0 流式增长到目标值
func _update_best_label(lv: String) -> void:
	var ranks_l: Label = get_node_or_null("当前关卡成绩")
	var best_l: Label = get_node_or_null("最高成绩")
	var hist: Array = GlobalData.get_history(lv, GlobalData.difficulty)
	for tw in [_rank_tween, _best_tween]:
		if tw and tw.is_valid():
			tw.kill()
	if hist.is_empty():
		if ranks_l:
			ranks_l.text = ""
		if best_l:
			best_l.text = "未游玩"
			best_l.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
		return
	var rank := GlobalData.rank_of(int(hist[0]))
	var best := int(hist[0])
	if ranks_l:
		ranks_l.text = rank
		ranks_l.add_theme_color_override("font_color", 评价颜色[rank])
		if _rank_home.x < 0.0:
			_rank_home = ranks_l.position   # 首次记录原位, 之后不再变
		ranks_l.position = _rank_home + Vector2(72, 0)
		ranks_l.modulate.a = 0.0
		_rank_tween = create_tween().set_parallel(true)
		_rank_tween.tween_property(ranks_l, "position", _rank_home, 0.38)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)   # 向左位移淡入
		_rank_tween.tween_property(ranks_l, "modulate:a", 1.0, 0.3).set_delay(0.05)
	if best_l:
		best_l.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
		best_l.text = "0"
		_best_tween = create_tween()
		_best_tween.tween_method(
			func(v: float): best_l.text = "%d" % int(roundf(v)),
			0.0, float(best), 0.7
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)   # 越接近目标增长越慢


## 删除关卡后刷新轮盘(供管理弹窗调用)
func rebuild_levels() -> void:
	_scan_charts()
	if chart_files.is_empty():
		return
	var keep := chart_files.find(GlobalData.selected_name)
	if keep < 0:
		keep = 0
	wheel.set_items(chart_files, keep)
	_on_level_selected(keep)


## 通知条: 右上滑入(双挡板依次擦出揭示文本) → 停留 → 收起
## 展开/收起共用同一组关键帧: 展开正放(三次贝塞尔 ease-out, 减速入场),
## 收起倒放(同样的位移轨迹反向回放, ease-in 加速离场, 挡板顺序也相反)
## 所有提示(导入中/导入完成/导入失败/其他)一律走这里; 新通知直接打断旧的
func notify(msg: String, hold := 2.4) -> void:
	var label: Label = $通知/文本
	var s1: Panel = $通知/文本/挡板1
	var s2: Panel = $通知/文本/挡板2
	if _notify_tween and _notify_tween.is_valid():
		_notify_tween.kill()
	label.text = msg
	# 位置加法推导: 停靠位 = 右缘收进一个文本宽(贴边), 藏匿位 = 停靠位再加一个文本宽(完全屏外)
	# 文本锚点在屏幕右缘, 各分辨率自适应, 不写死 1920
	var docked := Vector2($通知.size.x - label.size.x, 72.0)
	var hidden := docked + Vector2(label.size.x, 0.0)
	# 复位到藏匿态: 文本屏外, 双挡板盖住
	label.position = hidden
	s1.position = Vector2.ZERO
	s2.position = Vector2.ZERO
	label.modulate.a = 1.0
	var tw := create_tween()
	_notify_tween = tw
	# — 展开(正放): 文本滑入停靠 → 挡板2(蓝)先擦出 → 挡板1(白)收尾 —
	tw.tween_property(label, "position", docked, 0.5).from(hidden)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s2, "position:x", 挡板行程, 0.3).set_delay(0.45)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s1, "position:x", 挡板行程, 0.4).set_delay(0.5)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	# — 收起(倒放): 挡板1先吸回盖住文本 → 挡板2盖上 → 整条加速滑出屏外 —
	tw.tween_property(s1, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(s2, "position:x", 0.0, 0.3).set_delay(0.15)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(label, "position", hidden, 0.45).set_delay(0.45)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _on_start() -> void:
	stop_preview()
	var sc := get_tree().current_scene
	if sc and sc.has_method("start_game"):
		sc.start_game()
