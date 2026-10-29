extends Node2D
## 音符载荷 2D 环形 — 谱面驱动版（挂在 场景集成 下运行, UI 为同级兄弟节点）
## 音符类型:
##   蓝 = 静止直落   绿 = 正向漂移   红 = 反向漂移
##   紫 = 放行音符: 不能接! 挡板躲开让它进中心才得分, 接到则断连击
## 计分: 每关满分 100 万, 单音符分值 = 满分/总音符数 × 完成质量

const SPAN := PI / 2
const R_CENTER := 55.0
const R_SHIELD := 95.0
const R_SPAWN := 440.0
const NOTE_SPEED := 130.0
const EASE_EXP := 2.0           # 普通音符缓动指数：先慢后快
const LEAD_TIME := 3.2          # 直落音符提前出生时间（确保压线=重音时刻且可预判）
const DRIFT_SPEED := 1.2        # 漂移音符环向角速度 rad/s
const MIN_NOTE_GAP := 0.35      # 音符最小间隔（秒）
const MAX_SCORE := 1000000      # 每关满分
const BASE_SCORE := 950000      # 音符平分池
const CLEAR_BONUS := 50000      # 全部载出奖励
const PASS_NOTE_RATE := 0.07    # 放行音符占比
const CENTER := Vector2(960, 540)
const _AudioLoader := preload("res://脚本/音频加载.gd")  # preload 显式引用, 不依赖类名缓存
# 难度参数: [简单, 普通, 困难] — tier 过滤 + 放行比例 + 绿漂移概率
const DIFF_NAME := ["简单", "普通", "困难"]
const DIFF_PASS := [0.0, 0.07, 0.10]
const DIFF_GREEN := [0.20, 0.35, 0.40]
const HOLD_MIN_GAP := 2.2      # 长音要求与下一音符的最小间隔
const HOLD_MAX := 3.5          # 长音最长持续
const TAIL_PX_PER_SEC := 110.0 # 长音尾长 = 持续时间 × 此值(尾巴即时值)
const SPECTRUM_BANDS := 32    # 频谱柱数(对称镜像成 64 根)

var active := false             # 是否运行中（集成场景显隐控制）
var shield_angle := 0.0
var _joy_aim := false       # 手柄左摇杆接管挡板(动鼠标即交还)
var _joy_angle := 0.0       # 摇杆最后有效角度(松开摇杆保持不动)
var shield_span := PI / 2      # 挡板弧度(模组可调 15~120°)
var note_span := PI / 2        # 音符弧度(模组可调 15~120°)
var notes := []                 # {ang, r, drift, born, eased, passnote, released}
var score := 0.0
var display_score := 0.0        # 滚动显示的分数
var note_value := 0.0           # 单个音符分值 = 满分/总音符数
var duration := 1.0
var level_name := ""
var combo := 0
var max_combo := 0
var caught := 0                 # 命中音符数（含成功放行）
var total_notes := 0
var flash := 0.0
var ring_flash := 0.0
var game_over := false
var all_clear_t := -1.0      # 结束演出计时(<0 不在演出中)
var celeb_mode := 0          # 1=全接(冰蓝) 2=全漏(暗红故障)
var countdown := -1.0        # 开局倒计时(>=0 时游戏未开始, 挡板可动)
var spectrum: AudioEffectSpectrumAnalyzerInstance  # 实时频谱
var band_energy := PackedFloat32Array()            # 平滑后的各频段能量(0~1)

# --- 特效状态（纯绘制层, 不参与判定）---
var fx_sparks: Array = []   # {pos, vel, t, dur, size, col}
var fx_rings: Array = []    # {center, r0, r1, t, dur, col, w0, arc, ang}
var fx_texts: Array = []    # {text, pos, vel, t, dur, col, size}
var shield_draw := -PI / 4  # 挡板平滑跟随的绘制角
var spawn_glow := 0.0       # 音符出生时生成环脉冲
var purple_flash := 0.0     # 放行入核时中心紫色闪光
var shake := 0.0            # miss 屏震强度
var fx_time := 0.0          # 常驻时钟（呼吸/旋转动画相位）
var _combo_tier := -1
var _pops: Dictionary = {}      # label -> 进行中的弹跳 Tween（防快速连击叠加）
var _score_tween: Tween

var spawn_queue := []           # [{time, ang, drift, passnote}]
var spawn_idx := 0
var sections := []
var music_time := 0.0
var judge_counts := {}        # 各判定出现次数(结算频率图用)

var ui: Control                 # 同级的 Ui 实例（场景集成 下）
var pause_popup: Control        # 暂停弹窗实例
@onready var audio: AudioStreamPlayer = $Music
var sfx_catch: AudioStreamPlayer    # 接住: 低音鼓+镲片瞬态(鼓组感)
var sfx_release: AudioStreamPlayer  # 放行进中心: 中频确认音
var sfx_fail: AudioStreamPlayer     # 全漏演出: 低频嗡鸣


func _ready() -> void:
	ui = get_parent().get_node_or_null("Ui")
	_apply_glow()
	_init_spectrum()
	band_energy.resize(SPECTRUM_BANDS)
	_init_sfx()
	if ui:
		ui.process_mode = Node.PROCESS_MODE_ALWAYS
		ui.get_node("暂停按钮").pressed.connect(_toggle_pause)


## 音频可视化: Master 总线挂频谱计, 外环柱状实时反映各频段能量
func _init_spectrum() -> void:
	var fx := AudioEffectSpectrumAnalyzer.new()
	AudioServer.add_bus_effect(0, fx)
	spectrum = AudioServer.get_bus_effect_instance(0, AudioServer.get_bus_effect_count(0) - 1)


func _update_spectrum(delta: float) -> void:
	if spectrum == null:
		return
	const F_LO := 50.0
	const F_HI := 11000.0
	var prev_f := F_LO
	for i in SPECTRUM_BANDS:
		var f := F_LO * pow(F_HI / F_LO, float(i + 1) / SPECTRUM_BANDS)
		var mag: Vector2 = spectrum.get_magnitude_for_frequency_range(prev_f, f)
		prev_f = f
		var db := 20.0 * log(maxf(mag.length(), 0.0001)) / log(10.0)
		var target: float = clampf((db + 62.0) / 58.0, 0.0, 1.0)
		# 快起慢落, 有弹性
		var cur := band_energy[i]
		band_energy[i] = cur + (target - cur) * (14.0 if target > cur else 6.0) * delta


## 泛光：HDR 2D 下仅让元素本体略超阈值, 光晕交给 glow 后处理
func _apply_glow() -> void:
	# 参照《几何守塔》: 归一化泛光 + 高强度, 阈值略高于 LDR 上限
	var env := Environment.new()
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 8.0
	env.glow_strength = 2.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.06
	env.glow_hdr_scale = 4.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## 电子合成音效: 程序生成 WAV, 不需要音频文件
func _init_sfx() -> void:
	sfx_catch = AudioStreamPlayer.new()
	sfx_catch.stream = _make_drum(0.85)
	add_child(sfx_catch)
	sfx_release = AudioStreamPlayer.new()
	sfx_release.stream = _make_beep(660.0, 0.10, 12.0, 0.35)
	add_child(sfx_release)
	sfx_fail = AudioStreamPlayer.new()
	sfx_fail.stream = _make_beep(52.0, 1.1, 3.0, 0.55)   # 低频嗡鸣
	add_child(sfx_fail)


func _make_beep(freq: float, dur: float, decay: float, vol: float) -> AudioStreamWAV:
	const RATE := 22050
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay)
		phase += TAU * freq / RATE
		var v := int(clampf(sin(phase) * env, -1.0, 1.0) * 32767.0 * vol)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## 鼓组音色: 低音鼓(频率下滑的正弦) + 镲片(白噪声短瞬态)
func _make_drum(vol: float) -> AudioStreamWAV:
	const RATE := 22050
	var dur := 0.16
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025  # 噪声确定性(每次同一个音色)
	for i in n:
		var t := float(i) / RATE
		# 低音鼓: 150Hz 快速滑到 45Hz, 指数衰减
		var f := lerpf(150.0, 45.0, clampf(t / 0.1, 0.0, 1.0))
		phase += TAU * f / RATE
		var kick := sin(phase) * exp(-t * 22.0) * 0.9
		# 镲片: 白噪声 30ms 瞬态
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.5
		var v := int(clampf(kick + noise, -1.0, 1.0) * 32767.0 * vol)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## 挡板目标角: 左摇杆超死区时接管, 松开保持角度; 虚拟摇杆激活时次优先; 动鼠标交还鼠标跟随
func _aim_angle() -> float:
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.length() > 0.35:
		_joy_aim = true
		_joy_angle = stick.angle()
	if _joy_aim:
		return _joy_angle
	# 移动端虚拟摇杆(原生 VirtualJoystick): 激活期间模拟 ui_* 方向动作, 读取合成向量
	var vstick := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if vstick.length() > 0.25:
		return vstick.angle()
	# 舞台水平居中后节点带偏移, 必须用局部坐标换算
	return (get_local_mouse_position() - CENTER).angle()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_joy_aim = false   # 动鼠标: 挡板交还鼠标跟随


func _unhandled_input(event: InputEvent) -> void:
	# 手柄 Start: 暂停(恢复由暂停弹窗处理, 本节点暂停时收不到输入)
	if not active or game_over:
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		_toggle_pause()


## 暂停开关: 暂停时弹出暂停弹窗（继续/重开/回主页）, 恢复时收回
func _toggle_pause() -> void:
	if get_tree().paused:
		_resume_game()
	else:
		_set_paused(true)
		_open_pause_popup()


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	if ui:
		ui.get_node("暂停按钮").text = "▶" if p else "II"


func _open_pause_popup() -> void:
	if pause_popup:
		return
	pause_popup = (load("res://场景/暂停弹窗.tscn") as PackedScene).instantiate()
	get_tree().current_scene.add_child(pause_popup)
	pause_popup.继续.connect(_resume_game)
	pause_popup.重开.connect(func():
		_resume_game()
		start_level()
	)
	pause_popup.回主页.connect(func():
		_resume_game()
		var sc := get_tree().current_scene
		if sc and sc.has_method("game_to_menu"):
			sc.game_to_menu()
	)
	pause_popup.已关闭.connect(func(): pause_popup = null)


func _close_pause_popup() -> void:
	if pause_popup and is_instance_valid(pause_popup):
		pause_popup.close_popup()
	pause_popup = null


func _resume_game() -> void:
	_set_paused(false)
	_close_pause_popup()


func _music_time() -> float:
	if countdown >= 0.0:
		return music_time  # 倒计时期间对局时钟冻结(预生成时钟走 -countdown, 见 _process)
	var t: float = audio.get_playback_position()
	music_time = maxf(music_time, t)
	return music_time


## 出生所有到点的音符(对局主时钟与倒计时预生成共用)
func _spawn_due_notes(t: float) -> void:
	while spawn_idx < spawn_queue.size() and spawn_queue[spawn_idx].time <= t:
		var spec: Dictionary = spawn_queue[spawn_idx]
		# 迟到出生(卡顿掉帧导致错过压线窗口): 直接放弃, 不生成不惩罚, 也不计入总数
		if t > float(spec.arrive) + 0.15:
			spawn_idx += 1
			total_notes = maxi(1, total_notes - 1)
			continue
		notes.append({
			"ang": spec.ang, "r": R_SPAWN,
			"drift": spec.drift,
			"born": spec.time, "arrive": spec.arrive,
			"eased": spec.drift == 0.0,
			"passnote": spec.passnote, "released": false,
			"fade": 0.0,
			"hold": spec.get("hold", 0.0), "holding": false, "hold_t": 0.0, "fx_acc": 0.0,
		})
		spawn_idx += 1
		spawn_glow = 1.0
		if spec.has("tip") and spec.tip != "":
			_fx_text(spec.tip, CENTER + Vector2(0, -330), Vector2.ZERO, 3.4, Color(1.1, 1.9, 2.4), 42)


## 集成调度：进入游戏
func start_level() -> void:
	shield_span = deg_to_rad(clampf(float(GlobalData.mods.get("shield_span_deg", 90.0)), 15.0, 120.0))
	note_span = deg_to_rad(clampf(float(GlobalData.mods.get("note_span_deg", 90.0)), 15.0, 120.0))
	_load_chart()
	audio.stream = GlobalData.library.load_stream(GlobalData.library.find(GlobalData.selected_name))
	if audio.stream == null and ResourceLoader.exists(GlobalData.selected_music):
		audio.stream = _AudioLoader.load_stream(GlobalData.selected_music)  # 兜底旧路径
	if ui:
		ui.get_node("歌名").text = level_name
	game_over = false
	active = true
	countdown = 3.0   # 3 秒倒计时 = 预生成期: 挡板可动, 音符提前出生下落, 音乐延后
	music_time = 0.0
	display_score = 0.0
	_combo_tier = -1
	judge_counts = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "EXTREME": 0, "ATTACK": 0, "MISS": 0, "PASS": 0, "BREAK": 0}
	shield_draw = _aim_angle()
	fx_sparks.clear()
	fx_rings.clear()
	fx_texts.clear()
	spawn_glow = 0.0
	purple_flash = 0.0
	shake = 0.0
	position = Vector2.ZERO
	# 音乐推迟到倒计时结束; 音符在倒计时内预生成下落(虚拟时钟 -3→0), 开局不突脸


## 集成调度：离开游戏（进结算/回主页）
func stop_level() -> void:
	active = false
	countdown = -1.0
	audio.stop()
	notes.clear()
	fx_sparks.clear()
	fx_rings.clear()
	fx_texts.clear()
	position = Vector2.ZERO
	shake = 0.0
	if pause_popup and is_instance_valid(pause_popup):
		pause_popup.queue_free()
	pause_popup = null


func _process(delta: float) -> void:
	if all_clear_t >= 0.0:
		all_clear_t += delta
		fx_time += delta
		_update_spectrum(delta)
		_update_fx(delta)
		if all_clear_t > 2.4:
			_finish_to_result()
			var sc := get_tree().current_scene
			if sc and sc.has_method("show_result"):
				sc.show_result()
			return
		queue_redraw()
		return
	if not active or game_over:
		return
	if countdown >= 0.0:
		countdown -= delta
		shield_angle = _aim_angle()
		var gap2 := absf(angle_difference(shield_draw, shield_angle))
		var rate2 := lerpf(30.0, 80.0, clampf(gap2 / 0.6, 0.0, 1.0))
		shield_draw = wrapf(shield_draw + angle_difference(shield_draw, shield_angle) * (1.0 - exp(-rate2 * delta)), 0.0, TAU)
		fx_time += delta
		# 倒计时 = 预生成期: 虚拟时钟从 -3s 走向 0, 音符提前出生下落, 音乐响起时不再突脸
		var t_pre := -countdown
		_spawn_due_notes(t_pre)
		_update_notes(t_pre, delta)
		_update_fx(delta)
		_update_spectrum(delta)
		spawn_glow = maxf(0.0, spawn_glow - delta * 3.0)
		_update_hud(delta)
		queue_redraw()
		if countdown <= 0.0:
			countdown = -1.0
			audio.play()
			fx_rings.append({
				"center": CENTER, "r0": R_SHIELD, "r1": R_SPAWN + 40.0,
				"t": 0.0, "dur": 0.5, "col": Color(0.9, 1.9, 2.3),
				"w0": 8.0, "arc": 0.0, "ang": 0.0,
			})
		return
	flash = maxf(0.0, flash - delta * 3.0)
	ring_flash = maxf(0.0, ring_flash - delta * 4.0)
	fx_time += delta
	_update_spectrum(delta)
	spawn_glow = maxf(0.0, spawn_glow - delta * 3.0)
	purple_flash = maxf(0.0, purple_flash - delta * 2.5)
	_update_fx(delta)
	_update_shake(delta)

	shield_angle = _aim_angle()
	# 挡板自适应平滑: 微抖动丝滑跟随, 大幅甩动即时到达
	# 注意: 判定用视觉角 shield_draw(所见即所判), 用原始角会在快速甩动时出现
	# "看着接住了却 MISS"的错位
	# 注意 angle_difference(from, to) = to - from, 修正方向必须从绘制角指向目标角
	var gap := absf(angle_difference(shield_draw, shield_angle))
	var rate := lerpf(30.0, 80.0, clampf(gap / 0.6, 0.0, 1.0))
	shield_draw = wrapf(shield_draw + angle_difference(shield_draw, shield_angle) * (1.0 - exp(-rate * delta)), 0.0, TAU)

	var t := _music_time()
	_spawn_due_notes(t)
	_update_notes(t, delta)
	_update_hud(delta)
	queue_redraw()


func _music_finished() -> void:
	if not active or game_over or all_clear_t >= 0.0:
		return
	audio.stop()
	notes.clear()
	if total_notes > 0 and caught >= total_notes:
		score += CLEAR_BONUS   # 全部载出奖励
		all_clear_t = 0.0   # 全接: 先演出, 结束后再进结算
		celeb_mode = 1
		_fx_all_clear_burst()
		return
	if total_notes > 0 and caught == 0:
		all_clear_t = 0.0   # 全漏: 暗红故障风演出
		celeb_mode = 2
		sfx_fail.play()
		return
	# 彩蛋: 刻意避开一切正确答案 → 也授予 X(结算判定)
	if total_notes > 0 and caught == 0 and score == 0.0:
		GlobalData.result_score = 0
	_finish_to_result()
	var sc0 := get_tree().current_scene
	if sc0 and sc0.has_method("show_result"):
		sc0.show_result()


func _finish_to_result() -> void:
	game_over = true
	all_clear_t = -1.0
	celeb_mode = 0
	GlobalData.result_name = level_name
	GlobalData.result_score = mini(int(round(score)), MAX_SCORE)  # 满分封顶, X 只属于 100 万
	GlobalData.result_max_combo = max_combo
	GlobalData.result_caught = caught
	GlobalData.result_total = total_notes
	GlobalData.result_judgements = judge_counts
	GlobalData.tutorial = false


func _load_chart() -> void:
	spawn_queue.clear()
	if GlobalData.tutorial:
		_load_tutorial()
		return
	spawn_idx = 0
	notes.clear()
	score = 0.0
	combo = 0
	max_combo = 0
	caught = 0
	flash = 0.0
	ring_flash = 0.0
	if not audio.finished.is_connected(_music_finished):
		audio.finished.connect(_music_finished)

	var entry: Dictionary = GlobalData.library.find(GlobalData.selected_name)
	var diff: int = clampi(GlobalData.difficulty, 0, 2)
	var chart_path: String = "%s/谱面_%s.json" % [entry.get("dir", ""), ["简单", "普通", "困难"][diff]]
	# 谱面缺失(数据被清) → 从音频现场重新生成
	if not FileAccess.file_exists(chart_path):
		GlobalData.library.reset_one(GlobalData.selected_name)
	level_name = GlobalData.selected_name
	var f := FileAccess.open(chart_path, FileAccess.READ)
	if f == null:
		push_error("谱面不存在: " + chart_path)
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	sections = data.get("sections", [])
	for n in data.get("notes", []):
		var drift: float = float(n["drift"])
		var lead := LEAD_TIME if drift == 0.0 else (R_SPAWN - R_SHIELD) / NOTE_SPEED
		spawn_queue.append({
			"time": float(n["t"]) - lead,
			"arrive": float(n["t"]),
			"ang": float(n["ang"]),
			"drift": drift,
			"passnote": bool(n["pass"]),
			"hold": float(n["hold"]),
		})
	duration = float(data.get("duration", 1.0))
	total_notes = int(data.get("total_slots", spawn_queue.size()))
	note_value = BASE_SCORE / maxf(1.0, total_notes)


## 新手教程: 脚本化谱面, 分阶段引入四种音符与长音; 音轨为合成静音, 节奏靠音符自身
func _load_tutorial() -> void:
	level_name = "新手教程"
	duration = 78.0
	sections = []
	spawn_idx = 0
	total_notes = 24 + 2   # 教程含 2 个长音(各占 2 槽)
	note_value = MAX_SCORE / float(total_notes)
	if not audio.finished.is_connected(_music_finished):
		audio.finished.connect(_music_finished)

	var seq: Array = []
	var t := 4.0
	var step := 1.7
	# 阶段1: 蓝 (直落)
	seq.append({"t": t, "drift": 0.0, "pass": false, "tip": "移动鼠标，用挡板接住蓝色音符"})
	for i in 5:
		t += step
		seq.append({"t": t, "drift": 0.0, "pass": false, "tip": ""})
	# 阶段2: 绿 (正向漂移)
	t += 2.0
	seq.append({"t": t, "drift": DRIFT_SPEED, "pass": false, "tip": "有的音符会沿环移动——看准它漂移的方向，提前预判"})
	for i in 3:
		t += step
		seq.append({"t": t, "drift": DRIFT_SPEED, "pass": false, "tip": ""})
	# 阶段3: 红 (反向漂移)
	t += 2.0
	seq.append({"t": t, "drift": -DRIFT_SPEED, "pass": false, "tip": "漂移有正反两个方向，这种是反着来的，别被带偏"})
	for i in 3:
		t += step
		seq.append({"t": t, "drift": -DRIFT_SPEED, "pass": false, "tip": ""})
	# 阶段4: 紫 (放行)
	t += 2.5
	seq.append({"t": t, "drift": 0.0, "pass": true, "tip": "紫色不能接！转开挡板，放它落进中心"})
	for i in 3:
		t += step
		seq.append({"t": t, "drift": 0.0, "pass": true, "tip": ""})
	# 阶段5: 长音
	t += 3.0
	seq.append({"t": t, "drift": 0.0, "pass": false, "hold": 3.0, "tip": "带滑球和尾巴的音符：接住后跟着它滑，直到尾巴消失"})
	t += 5.0
	seq.append({"t": t, "drift": 0.0, "pass": false, "hold": 3.0, "tip": ""})
	t += 6.0
	seq.append({"t": t, "drift": 0.0, "pass": false, "tip": "教程完毕，去选一首歌开始吧！", "last": true})

	var golden := TAU * 0.618
	for i in seq.size():
		var e: Dictionary = seq[i]
		var lead := LEAD_TIME if e.drift == 0.0 else (R_SPAWN - R_SHIELD) / NOTE_SPEED
		var entry := {
			"time": float(e.t) - lead,
			"arrive": float(e.t),
			"ang": fmod(0.4 * TAU + i * golden, TAU),
			"drift": e.drift,
			"passnote": e.pass,
			"hold": e.get("hold", 0.0),
		}
		if e.tip != "":
			entry["tip"] = e.tip
		spawn_queue.append(entry)
	spawn_queue.sort_custom(func(a, b): return a.time < b.time)

	# 静音音轨: 教程不需要音乐, 只驱动时钟
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var silence := PackedByteArray()
	silence.resize(int(duration * 22050) * 2)
	wav.data = silence
	audio.stream = wav


func _level_at(t: float) -> int:
	for s in sections:
		if s["start"] <= t and t < s["end"]:
			return int(s["level"])
	return 1


func _update_notes(t: float, _delta: float) -> void:
	var caught_flash := false
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		n.fade = minf(1.0, float(n.fade) + _delta / 0.3)  # 出生淡入
		# 半径统一由音乐时钟驱动(帧率无关, 卡顿不会导致穿越)
		if n.holding:
			n.r = R_SHIELD  # 长音贴合期间钉在判定圈(否则坠落公式会带着它穿过中心)
		elif n.eased and not n.released:
			var p: float = (t - float(n.born)) / LEAD_TIME
			if p < 1.0:
				n.r = R_SHIELD + (R_SPAWN - R_SHIELD) * (1.0 - pow(p, EASE_EXP))
			else:
				n.r = R_SHIELD - EASE_EXP * (R_SPAWN - R_SHIELD) / LEAD_TIME * (t - float(n.born) - LEAD_TIME)
		else:
			# 漂移音符全程 / 放行后的紫音符: 从压线时刻起匀速(以 arrive 为起点,
			# 出生时 t-arrive 为负 → r=R_SPAWN, 刚放行时 r=R_SHIELD, 连续无跳变)
			n.r = R_SHIELD - (t - float(n.arrive)) * NOTE_SPEED
		n.ang = wrapf(n.ang + n.drift * _delta, 0.0, TAU)

		# 长音: 接住后贴在判定圈上缓慢旋转, 保持贴合持续得分
		if n.holding:
			n.ang = wrapf(n.ang + 0.55 * _delta, 0.0, TAU)
			n.hold_t += _delta
			if n.grace > 0.0:
				n.grace = maxf(0.0, float(n.grace) - _delta)
			var hold_d := absf(angle_difference(n.ang, shield_draw))
			# 贴合阈值: 挡板/音符弧度中较小者的 75%; 宽限期内不判脱开
			var hold_ok: bool = hold_d < minf(shield_span, note_span) * 0.75 or n.grace > 0.0
			if n.hold_t >= n.hold:
				judge_counts["PERFECT"] = int(judge_counts.get("PERFECT", 0)) + 1
				caught += 1                  # 第 2 槽: 收尾也算命中
				combo += 1                   # 收尾计连击
				max_combo = maxf(max_combo, combo)
				sfx_catch.play()
				_fx_hold_complete(n.ang)
				fx_texts.append({
					"text": "PERFECT", "pos": CENTER + Vector2.from_angle(n.ang) * (R_SHIELD + 46.0),
					"vel": Vector2(0, -36), "t": 0.0, "dur": 0.6,
					"col": Color(0.9, 1.9, 2.3), "size": 26,
				})
				notes.remove_at(i)
			elif hold_ok:
				score += 2.0 * note_value * _delta / n.hold  # 长音得分 = 2*分值*(贴合长度/总长)
				# 持续特效: 火花沿头块切向持续飞出
				n.fx_acc = float(n.fx_acc) + _delta
				if n.fx_acc > 0.07:
					n.fx_acc = 0.0
					var head_pos := CENTER + Vector2.from_angle(n.ang) * R_SHIELD
					var tang := Vector2.from_angle(n.ang + PI / 2)
					fx_sparks.append({
						"pos": head_pos + tang * rng_spark(), "vel": tang * 90.0 * signf(n.drift if n.drift != 0.0 else 1.0) + Vector2.from_angle(n.ang) * 60.0,
						"t": 0.0, "dur": 0.4, "size": 2.8,
						"col": Color(0.9, 1.9, 2.2),
					})
			else:
				judge_counts["BREAK"] = int(judge_counts.get("BREAK", 0)) + 1
				combo = 0   # 断开: 已得部分保留, 断连击
				flash = 0.7
				shake = 0.6
				fx_texts.append({
					"text": "BREAK", "pos": CENTER + Vector2.from_angle(n.ang) * (R_SHIELD + 46.0),
					"vel": Vector2(0, -30), "t": 0.0, "dur": 0.5,
					"col": Color(1.7, 0.5, 0.4), "size": 22,
				})
				notes.remove_at(i)
			continue

		if t >= float(n.arrive) and not n.released:
			# 判定按 arrive 时刻(与音乐对齐); 角差 <100° 为接住窗口
			var d := absf(angle_difference(n.ang, shield_draw))
			var overlap := (shield_span + note_span) / 2.0 - d
			if n.passnote:
				# 放行音符: 任何重叠 = 失误; 完全避开 = 放行进中心
				if overlap > 0.0:
					notes.remove_at(i)
					combo = 0
					flash = 1.0
					judge_counts["MISS"] = int(judge_counts.get("MISS", 0)) + 1
					_fx_miss(n.ang)
					shake = 1.0
				else:
					n.released = true
				continue
			if d < deg_to_rad(100.0):
				# 重合度 & 判定分级 (面接触=弧有重叠; 侧接触=仅挡板边缘碰到)
				var q: float = clampf(overlap / note_span, 0.0, 1.0)
				var grade: String
				var ratio: float
				if overlap > 0.0 and q >= 0.8:
					grade = "PERFECT"; ratio = 1.0
				elif overlap > 0.0 and q >= 0.6:
					grade = "GREAT"; ratio = 0.7
				elif overlap > 0.0 and q >= 0.2:
					grade = "GOOD"; ratio = 0.4
				elif overlap > 0.0:
					grade = "EXTREME"; ratio = 1.0
				else:
					grade = "ATTACK"; ratio = 1.0
				score += note_value * ratio
				judge_counts[grade] = int(judge_counts.get(grade, 0)) + 1
				caught += 1
				combo += 1
				max_combo = maxf(max_combo, combo)
				caught_flash = true
				if ui:
					_pop(ui.get_node("连击数") as Label)
					_pop_score()
				sfx_catch.play()
				_fx_catch(n.ang, _note_color(n), grade)
				if combo % 25 == 0:
					_fx_milestone(combo)
				if n.hold > 0.0:
					n.holding = true   # 长音: 接住后进入贴合阶段(占第1槽, 按长度比例得分)
					n.hold_t = 0.0
					n.grace = 0.3      # 宽限期
					n.r = R_SHIELD
					_fx_text("保持贴合!", CENTER + Vector2.from_angle(n.ang) * (R_SHIELD + 78.0),
						Vector2.from_angle(n.ang) * 30.0, 0.8, Color(0.7, 1.7, 2.1), 22)
				else:
					notes.remove_at(i)
			else:
				_miss(i)
			continue
		if n.r <= R_CENTER:
			if n.passnote and n.released:
				judge_counts["PASS"] = int(judge_counts.get("PASS", 0)) + 1
				score += note_value  # 成功放行, 得全额分
				caught += 1
				combo += 1
				max_combo = maxf(max_combo, combo)
				if ui:
					_pop(ui.get_node("连击数") as Label)
					_pop_score()
				sfx_release.play()
				purple_flash = 1.0
				_fx_release()
				notes.remove_at(i)
			else:
				_miss(i)
	if caught_flash:
		ring_flash = 1.0


func _miss(i: int) -> void:
	judge_counts["MISS"] = int(judge_counts.get("MISS", 0)) + 1
	_fx_miss(notes[i].ang)
	shake = 1.0
	notes.remove_at(i)
	combo = 0
	flash = 1.0


## 数字跳动: 缩放弹一下（快速连击时重启上一个, 不叠加打架）
func _pop(label: Label) -> void:
	if _pops.has(label) and _pops[label] is Tween and _pops[label].is_running():
		_pops[label].kill()
	label.pivot_offset = label.size / 2.0
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2.ONE * 1.35, 0.06)
	tw.tween_property(label, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pops[label] = tw


## 分数跳动: 小幅弹起 + 金色闪一下, 数字滚动期间给接住反馈
func _pop_score() -> void:
	if not ui:
		return
	var label: Label = ui.get_node("分数")
	if _score_tween and _score_tween.is_running():
		_score_tween.kill()
	label.pivot_offset = label.size / 2.0
	label.modulate = Color(1.2, 1.9, 2.2)
	_score_tween = label.create_tween()
	_score_tween.tween_property(label, "scale", Vector2.ONE * 1.12, 0.05)
	_score_tween.parallel().tween_property(label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_score_tween.parallel().tween_property(label, "modulate", Color.WHITE, 0.3)


## 实心弧块: 内外两圈弧点构成的环段多边形, 边缘加细弧抗锯齿
func _draw_arc_block(radius: float, thickness: float, ang: float, span: float, col: Color) -> void:
	const SEG := 22
	var pts := PackedVector2Array()
	for i in SEG + 1:
		var a := ang - span / 2 + span * i / SEG
		pts.append(CENTER + Vector2.from_angle(a) * (radius + thickness / 2.0))
	for i in SEG + 1:
		var a := ang + span / 2 - span * i / SEG
		pts.append(CENTER + Vector2.from_angle(a) * (radius - thickness / 2.0))
	draw_polygon(pts, PackedColorArray([col]))
	var edge := Color(col.r * 1.25, col.g * 1.25, col.b * 1.25, col.a)
	draw_arc(CENTER, radius + thickness / 2.0, ang - span / 2, ang + span / 2, SEG, edge, 1.5, true)
	draw_arc(CENTER, radius - thickness / 2.0, ang - span / 2, ang + span / 2, SEG, edge, 1.5, true)


var _spark_rng := RandomNumberGenerator.new()

## 统一的判定字发射: 位置=文字中心, 渲染时带暗色描边(无底板)
func _fx_text(text: String, center: Vector2, vel: Vector2, dur: float, col: Color, size: int) -> void:
	fx_texts.append({
		"text": text, "pos": center, "vel": vel,
		"t": 0.0, "dur": dur, "col": col, "size": size,
	})

func rng_spark() -> float:
	return _spark_rng.randf_range(-40.0, 40.0)


func _note_color(n: Dictionary) -> Color:
	const B := 1.1   # 与 _draw 一致的本体亮度
	# 颜色语义固定: 蓝 = 接完就走, 金 = 长音(接住后还要保持贴合!), 紫 = 放行
	if n.passnote:
		return Color(0.75 * B, 0.4 * B, 1.0 * B)      # 紫 = 放行
	if n.hold > 0.0:
		return Color(0.55 * B, 1.05 * B, 1.5 * B)    # 冰青 = 长音
	return Color(0.45 * B, 0.65 * B, 1.0 * B)         # 蓝 = 接


## 接住: 冲击波弧环 + HDR 火花 + 评级字（高质量更大更金）
func _fx_catch(ang: float, col: Color, grade: String) -> void:
	var big := grade in ["PERFECT", "EXTREME", "ATTACK"]
	var pos := CENTER + Vector2.from_angle(ang) * R_SHIELD
	fx_rings.append({
		"center": CENTER, "r0": R_SHIELD - 6.0,
		"r1": R_SHIELD + (95.0 if big else 60.0),
		"t": 0.0, "dur": 0.38, "col": Color(1.5, 1.6, 1.9),
		"w0": 7.0, "arc": note_span, "ang": ang,
	})
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := 18 if big else 11
	for i in count:
		var dir := ang + rng.randf_range(-0.85, 0.85)   # 以音符来向为主喷出
		var hot := rng.randf() < 0.35
		fx_sparks.append({
			"pos": pos, "vel": Vector2.from_angle(dir) * rng.randf_range(110.0, 330.0),
			"t": 0.0, "dur": rng.randf_range(0.3, 0.55),
			"size": rng.randf_range(2.0, 4.5),
			"col": Color(1.5, 2.0, 2.3) if hot else col * 1.9 + Color(0.35, 0.35, 0.35),
		})
	var gcol: Color = {"PERFECT": Color(0.9, 1.9, 2.3), "GREAT": Color(1.2, 1.7, 0.9),
		"GOOD": Color(0.85, 1.5, 1.8), "EXTREME": Color(0.5, 1.3, 2.6), "ATTACK": Color(2.4, 1.4, 0.5)}[grade]
	var gsize := 40 if big else 30 if grade == "GREAT" else 24
	_fx_text(grade, CENTER + Vector2.from_angle(ang) * (R_SHIELD + 46.0),
		Vector2.from_angle(ang) * 46.0, 0.62 if big else 0.5, gcol, gsize)


## 放行入核: 紫色全圆涟漪
func _fx_release() -> void:
	fx_rings.append({
		"center": CENTER, "r0": R_CENTER + 6.0, "r1": 215.0,
		"t": 0.0, "dur": 0.5, "col": Color(1.35, 0.75, 1.9),
		"w0": 6.0, "arc": 0.0, "ang": 0.0,
	})
	fx_texts.append({
		"text": "PASS", "pos": CENTER + Vector2(-160, -96),
		"vel": Vector2(0, -42), "t": 0.0, "dur": 0.55,
		"col": Color(1.5, 0.95, 1.9), "size": 22,
	})


## 长音收尾: 头部方向扇形冲击环 + 径向火花爆发
func _fx_hold_complete(ang: float) -> void:
	fx_rings.append({
		"center": CENTER, "r0": R_SHIELD - 4.0, "r1": R_SHIELD + 150.0,
		"t": 0.0, "dur": 0.45, "col": Color(0.9, 2.0, 2.4),
		"w0": 8.0, "arc": note_span * 0.9, "ang": ang,
	})
	fx_rings.append({
		"center": CENTER, "r0": R_CENTER, "r1": R_SHIELD + 60.0,
		"t": 0.0, "dur": 0.3, "col": Color(1.4, 2.2, 2.6),
		"w0": 5.0, "arc": 0.0, "ang": 0.0,
	})
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 22:
		var a := ang + rng.randf_range(-0.7, 0.7)
		fx_sparks.append({
			"pos": CENTER + Vector2.from_angle(ang) * R_SHIELD,
			"vel": Vector2.from_angle(a) * rng.randf_range(180.0, 460.0),
			"t": 0.0, "dur": rng.randf_range(0.35, 0.7),
			"size": rng.randf_range(2.5, 5.0),
			"col": Color(1.0, 2.0, 2.4) if rng.randf() < 0.7 else Color(0.7, 1.5, 1.9),
		})


## 全接演出: 冰蓝环冲击 + 中心火花喷发
func _fx_all_clear_burst() -> void:
	fx_rings.append({
		"center": CENTER, "r0": R_CENTER + 8.0, "r1": R_SPAWN + 160.0,
		"t": 0.0, "dur": 0.9, "col": Color(0.6, 1.6, 2.0),
		"w0": 10.0, "arc": 0.0, "ang": 0.0,
	})
	fx_rings.append({
		"center": CENTER, "r0": R_CENTER + 8.0, "r1": R_SPAWN + 60.0,
		"t": 0.0, "dur": 0.6, "col": Color(1.4, 2.2, 2.6),
		"w0": 6.0, "arc": 0.0, "ang": 0.0,
	})
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in 44:
		var a := rng.randf() * TAU
		fx_sparks.append({
			"pos": CENTER, "vel": Vector2.from_angle(a) * rng.randf_range(140.0, 520.0),
			"t": 0.0, "dur": rng.randf_range(0.8, 1.8),
			"size": rng.randf_range(2.5, 6.0),
			"col": Color(0.8, 1.8, 2.2) if rng.randf() < 0.6 else Color(1.6, 2.1, 2.5),
		})


## 连击里程碑: 全屏涟漪 + 字样
func _fx_milestone(c: int) -> void:
	fx_rings.append({
		"center": CENTER, "r0": R_CENTER + 10.0, "r1": R_SPAWN + 80.0,
		"t": 0.0, "dur": 0.7, "col": Color(0.6, 1.5, 1.9),
		"w0": 8.0, "arc": 0.0, "ang": 0.0,
	})
	_fx_text("%d COMBO" % c, CENTER + Vector2(0, 150), Vector2(0, -34), 0.9, Color(0.7, 1.8, 2.2), 30)


## miss: 红色碎裂火花 + MISS 字样
func _fx_miss(ang: float) -> void:
	_fx_text("MISS", CENTER + Vector2.from_angle(ang) * (R_SHIELD + 46.0),
		Vector2.from_angle(ang) * 28.0, 0.55, Color(1.7, 0.45, 0.4), 20)
	var pos := CENTER + Vector2.from_angle(ang) * R_SHIELD
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 12:
		var dir := ang + PI + rng.randf_range(-1.1, 1.1)  # 从挡板位置向外炸开
		fx_sparks.append({
			"pos": pos, "vel": Vector2.from_angle(dir) * rng.randf_range(160.0, 380.0),
			"t": 0.0, "dur": rng.randf_range(0.35, 0.6),
			"size": rng.randf_range(2.0, 4.0), "col": Color(1.7, 0.35, 0.3),
		})


func _update_fx(delta: float) -> void:
	for s in fx_sparks:
		s.t += delta
		s.pos += s.vel * delta
		s.vel *= exp(-5.5 * delta)
	fx_sparks = fx_sparks.filter(func(s): return s.t < s.dur)
	for r in fx_rings:
		r.t += delta
	fx_rings = fx_rings.filter(func(r): return r.t < r.dur)
	for x in fx_texts:
		x.t += delta
		x.pos += x.vel * delta
		x.vel *= exp(-2.0 * delta)
	fx_texts = fx_texts.filter(func(x): return x.t < x.dur)


## miss 屏震: 围绕原点的细微抖动
func _update_shake(delta: float) -> void:
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 6.0)
		position = Vector2(sin(fx_time * 91.0), cos(fx_time * 77.0)) * shake * 5.0
	else:
		position = Vector2.ZERO


func _update_hud(delta: float) -> void:
	if not ui:
		return
	ui.get_node("连击数").text = "combo %d" % combo
	# 连击档位变色: 5+ 青 / 15+ 绿 / 30+ 金(带泛光)
	var tier := 3 if combo >= 30 else 2 if combo >= 15 else 1 if combo >= 5 else 0
	if tier != _combo_tier:
		_combo_tier = tier
		(ui.get_node("连击数") as Label).add_theme_color_override("font_color",
			[Color(1, 1, 1), Color(0.6, 0.95, 1), Color(0.55, 1, 0.8), Color(0.7, 1.7, 2.1)][tier])
	display_score = lerpf(display_score, score, 1.0 - exp(-9.0 * delta))
	if score - display_score < 1.0:
		display_score = score
	ui.get_node("分数").text = "%d" % int(round(display_score))
	ui.get_node("进度条").value = clampf(music_time / duration * 100.0, 0.0, 100.0)


func _draw() -> void:
	if not active:
		return
	const B := 1.1   # 本体几乎不增亮, 雾光完全由 glow 阈值触发
	# 背景尘埃: 缓慢旋转的稀疏光点, 给纯黑背景一点纵深
	for i in 26:
		var a := TAU * i / 26.0 + fx_time * 0.05
		var rr := R_SPAWN + 55.0 + 14.0 * sin(fx_time * 0.6 + i * 2.4)
		draw_circle(CENTER + Vector2.from_angle(a) * rr, 1.8, Color(0.4, 0.6, 0.9, 0.13))
	# 生成环: 旋转虚线 + 音符出生脉冲
	var dash_count := 56
	var ring_a := 0.5 + spawn_glow * 0.5
	for i in dash_count:
		var a0 := TAU * i / dash_count + fx_time * 0.1
		draw_arc(CENTER, R_SPAWN, a0, a0 + TAU / dash_count * 0.55, 4, Color(0.45, 0.7, 0.95, ring_a), 2.0 + spawn_glow, true)
	# 音频频谱: 两条 低→高 的半环带(各 180°), 点对称成完整一圈
	for i in SPECTRUM_BANDS:
		var e := band_energy[i]
		if e < 0.03:
			continue
		var a := PI * float(i) / float(SPECTRUM_BANDS - 1) + fx_time * 0.1  # 0..π 低→高
		var len_px := 8.0 + e * 58.0
		var col := Color(0.35 + e * 0.9, 0.65 + e * 0.7, 1.0 + e * 0.8, 0.22 + e * 0.55)
		for mirror in 2:
			var aa := a + PI * mirror
			_draw_arc_block(R_SPAWN + 5.0 + len_px / 2.0, len_px, aa, PI / float(SPECTRUM_BANDS) * 0.6, col)
	# 中心核: 呼吸 + 内亮核 + 双向旋转装饰弧
	var flash_c := Color(0.2 * B, 0.6 * B, 1.0 * B).lerp(Color(1, 0.4, 0.4), flash).lerp(Color(1.1, 0.5, 1.4), purple_flash)
	var r_core := R_CENTER * (1.0 + 0.035 * sin(fx_time * 2.2))
	if GlobalData.mods.get("中心低频跃动", true):
		r_core *= 1.0 + 0.18 * band_energy[0]   # 低频跃动: 随低频能量膨胀(带内建快起慢落平滑)
	draw_circle(CENTER, r_core, flash_c)
	draw_circle(CENTER, r_core * 0.55, Color(0.55, 0.95, 1.35, 0.9).lerp(Color(1.6, 1.2, 1.2), maxf(flash, purple_flash)))
	draw_arc(CENTER, r_core, 0, TAU, 64, Color(1, 1, 1, 0.4), 2.0, true)
	for k in 2:
		var a_rot := fx_time * (0.35 if k == 0 else -0.22) + k * PI
		draw_arc(CENTER, r_core + 9.0, a_rot, a_rot + 0.9, 12, Color(0.5, 0.85, 1.2, 0.35), 2.0, true)
	# 护环 + 挡板: 柔光外晕 + 端点圆帽
	draw_arc(CENTER, R_SHIELD, 0, TAU, 64, Color(1, 1, 1, 0.12 + ring_flash * 0.15), 1.5, true)
	var shield_color := Color(0.3 * B, 0.9 * B, 1.0 * B).lerp(Color(1.2, 1.2, 1.2), ring_flash)
	var w_shield := 9.0 + ring_flash * 4.0
	draw_arc(CENTER, R_SHIELD, shield_draw - shield_span / 2, shield_draw + shield_span / 2, 32, Color(shield_color.r, shield_color.g, shield_color.b, 0.1), w_shield + 14.0, true)
	draw_arc(CENTER, R_SHIELD, shield_draw - shield_span / 2, shield_draw + shield_span / 2, 32, shield_color, w_shield, true)
	draw_circle(CENTER + Vector2.from_angle(shield_draw - shield_span / 2) * R_SHIELD, 4.5 + ring_flash * 2.0, shield_color)
	draw_circle(CENTER + Vector2.from_angle(shield_draw + shield_span / 2) * R_SHIELD, 4.5 + ring_flash * 2.0, shield_color)
	# 音符: 出生淡入, 微呼吸; 放行音符警告脉冲; 放行后收细坠入中心
	for n in notes:
		var color := _note_color(n)
		var pulse := 1.0
		if n.passnote:
			pulse = 0.7 + 0.3 * sin(fx_time * 9.0)  # 放行音符警告脉冲
		color.a = clampf(float(n.fade) * pulse, 0.0, 1.0)
		var width := 10.0 * (1.0 + 0.07 * sin(fx_time * 5.0 + n.ang * 3.0))
		if n.released:
			width = lerpf(3.0, 6.0, clampf((n.r - R_CENTER) / 60.0, 0.0, 1.0))
		if n.hold > 0.0 and not n.released:
			# 长条(主流规范: 头+拖尾, 尾长即时值, 尾判跟到底):
			# 头 = 40px 厚金色大块; 尾 = 径向光带, 长度 = 剩余时长 × TAIL_PX_PER_SEC,
			# 接住后头钉在判定圈, 尾从外端被吃进来, 亮边跟着缩, 滑盾吃到尾端消失为止
			var remain := 1.0
			var head_r: float = n.r
			if n.holding:
				remain = 1.0 - clampf(float(n.hold_t) / n.hold, 0.0, 1.0)
				head_r = R_SHIELD
			var tail_len: float = n.hold * TAIL_PX_PER_SEC * remain
			var ribbon := note_span * 0.4   # 头端细带宽度
			if tail_len > 6.0:
				var mid := head_r + 24.0 + tail_len / 2.0
				var tail_col := Color(color.r, color.g, color.b, color.a * 0.5)
				_draw_arc_block(mid, tail_len, n.ang, note_span, tail_col)  # 尾巴恢复全弧宽
				# 尾端亮边(正在被吃的位置, 盯着它)
				var edge_col := Color(0.7, 1.7, 2.1, color.a)
				draw_arc(CENTER, head_r + 24.0 + tail_len, n.ang - note_span / 2, n.ang + note_span / 2, 24, edge_col, 3.5, true)
				# 贴合中: 头部能量弧在挡板位置呼吸(持续特效之一)
				if n.holding:
					var hpulse := 0.6 + 0.4 * sin(fx_time * 10.0)
					draw_arc(CENTER, R_SHIELD, n.ang - ribbon / 2, n.ang + ribbon / 2, 16,
						Color(0.8, 1.9, 2.3, 0.5 * hpulse), 5.0 + 3.0 * hpulse, true)
			# 头: 与尾巴同宽的细端 + 中央滑球亮点(贴合时盯这颗球)
			_draw_arc_block(head_r, 20.0, n.ang, ribbon, color)
			var head_pos := CENTER + Vector2.from_angle(n.ang) * head_r
			draw_circle(head_pos, 13.0, Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, color.a))
			draw_circle(head_pos, 6.0, Color(1.6, 2.2, 2.5, color.a))
		else:
			draw_arc(CENTER, n.r, n.ang - note_span / 2, n.ang + note_span / 2, 32, color, width, true)
	# 开局倒计时: 中央大数字 + 收缩引导环
	if countdown >= 0.0:
		var n := int(ceilf(countdown))
		var frac: float = fmod(countdown, 1.0)
		var font_c := ThemeDB.fallback_font
		var scale_f := 0.8 + frac * 0.4
		var c_col := Color(0.9, 2.0, 2.4, 0.4 + 0.6 * frac)
		draw_string(font_c, CENTER + Vector2(-500, 60) * scale_f, str(n),
			HORIZONTAL_ALIGNMENT_CENTER, 1000.0, int(220 * scale_f), c_col)
		draw_arc(CENTER, lerpf(R_CENTER + 30.0, R_SHIELD + 60.0, frac), 0, TAU, 64,
			Color(0.5, 1.5, 1.9, 0.35), 3.0, true)
	# 结束演出: 暗幕 + 中央大字(特效层画在其上)
	if all_clear_t >= 0.0 and celeb_mode == 1:
		var dim_a: float = clampf(all_clear_t / 0.4, 0.0, 1.0) * 0.75
		draw_rect(Rect2(Vector2(-100, -100), Vector2(2120, 1280)), Color(0, 0, 0, dim_a))
		var font_big := ThemeDB.fallback_font
		var t_in: float = clampf((all_clear_t - 0.15) / 0.45, 0.0, 1.0)
		if t_in > 0.0:
			var pop: float = 1.0 + (1.0 - t_in) * 0.8
			var big_col := Color(0.9, 2.0, 2.4, t_in)
			draw_string(font_big, CENTER + Vector2(-330, -10) * pop, "全部载出",
				HORIZONTAL_ALIGNMENT_CENTER, 660.0, int(120.0 * pop), big_col)
			if t_in >= 1.0:
				draw_string(font_big, CENTER + Vector2(-250, 70), "所有音符块全部解决",
					HORIZONTAL_ALIGNMENT_CENTER, 500.0, 30, Color(0.9, 1.2, 1.5, 0.9))
	elif all_clear_t >= 0.0 and celeb_mode == 2:
		# 全漏: 暗红故障风 —— 红黑暗幕 + RGB 错位抖动字 + 扫描线
		var dim_r: float = clampf(all_clear_t / 0.4, 0.0, 1.0)
		draw_rect(Rect2(Vector2(-100, -100), Vector2(2120, 1280)), Color(0.06, 0.0, 0.0, dim_r * 0.85))
		var font_g := ThemeDB.fallback_font
		var t_in2: float = clampf((all_clear_t - 0.15) / 0.45, 0.0, 1.0)
		if t_in2 > 0.0:
			# 每 0.12s 换一组故障偏移(确定性抖动)
			var gr := RandomNumberGenerator.new()
			gr.seed = 90000 + int(all_clear_t * 8.0) * 131
			var jx := gr.randf_range(-16.0, 16.0)
			var jy := gr.randf_range(-5.0, 5.0)
			var flick: float = 0.75 + 0.25 * gr.randf()
			var base := CENTER + Vector2(-330 + jx, -10 + jy)
			# 三层错位: 暗红主体 + 亮红残影 + 冷色残影
			draw_string(font_g, base, "全部载入", HORIZONTAL_ALIGNMENT_CENTER, 660.0, 120,
				Color(1.1, 0.16, 0.12, t_in2 * flick))
			draw_string(font_g, base + Vector2(jx * -0.9 - 6.0, 2.0), "全部载入",
				HORIZONTAL_ALIGNMENT_CENTER, 660.0, 120, Color(1.9, 0.35, 0.22, t_in2 * 0.55))
			draw_string(font_g, base + Vector2(jx * 0.7 + 6.0, -2.0), "全部载入",
				HORIZONTAL_ALIGNMENT_CENTER, 660.0, 120, Color(0.3, 1.4, 1.6, t_in2 * 0.35))
			if t_in2 >= 1.0:
				draw_string(font_g, CENTER + Vector2(-250, 70), "一个音符块都没有解决……",
					HORIZONTAL_ALIGNMENT_CENTER, 500.0, 30, Color(1.4, 0.5, 0.45, 0.85 * flick))
			# 扫描线: 随机横条
			for k in 7:
				var ly := CENTER.y - 400.0 + gr.randf() * 800.0
				var lw := 120.0 + gr.randf() * 900.0
				draw_rect(Rect2(CENTER.x - lw / 2.0 + jx, ly, lw, 2.5 + gr.randf() * 3.0),
					Color(1.5, 0.25, 0.2, 0.22 * flick))
	# --- 特效 ---
	for r in fx_rings:
		var p: float = r.t / r.dur
		var e := 1.0 - pow(1.0 - p, 2.6)
		var col: Color = r.col
		col.a = 1.0 - p
		var w: float = r.w0 * (1.0 - p * 0.85)
		if r.arc > 0.0:
			var span: float = r.arc * lerpf(1.0, 0.5, p)  # 弧环扩散时收束
			draw_arc(r.center, lerpf(r.r0, r.r1, e), r.ang - span / 2, r.ang + span / 2, 20, col, w, true)
		else:
			draw_arc(r.center, lerpf(r.r0, r.r1, e), 0, TAU, 64, col, w, true)
	for s in fx_sparks:
		var p: float = s.t / s.dur
		var col: Color = s.col
		col.a = 1.0 - p
		draw_circle(s.pos, s.size * (1.0 - p * 0.55), col)
	var font := ThemeDB.fallback_font
	for x in fx_texts:
		var p: float = x.t / x.dur
		var col: Color = x.col
		col.a = 1.0 - p * p
		var shadow := Color(0.0, 0.0, 0.0, col.a * 0.85)
		draw_string(font, x.pos + Vector2(2, 2), x.text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, x.size, shadow)
		draw_string(font, x.pos, x.text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, x.size, col)
