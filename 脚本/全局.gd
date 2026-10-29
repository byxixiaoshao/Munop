class_name GlobalData
## 全局状态：跨场景共享（静态类）
## 历史评分: 每首歌一个 评分.json 存其歌文件夹内; 模组设置: 数据/设置.json

const ChartGen := preload("res://脚本/谱面生成.gd")

static var library: Library = Library.new()
static var selected_chart := ""
static var selected_music := ""
static var selected_name := ""
static var difficulty := 1          # 0简单 1普通 2困难
static var tutorial := false

static var result_name := ""
static var result_score := 0
static var result_max_combo := 0
static var result_caught := 0
static var result_total := 0
static var result_judgements: Dictionary = {}

static var mods := {"shield_span_deg": 90.0, "note_span_deg": 90.0,
	"中心低频跃动": true,   # 游戏内中心蓝圆随低频能量跃动
	"动态暗光": true,        # 游戏内模糊背景 darken 随低频在 0.2~0.7 间跃动
	"虚拟摇杆": true}        # 移动端触屏生成虚拟摇杆控制挡板
static var _history_cache: Dictionary = {}   # 歌名 -> [分数...]

const 设置文件 := "user://数据/设置.json"
const MAX_SCORE := 1000000



## 评级体系: 10万一档, D 兜底; X 仅满分; 0分0命中彩蛋X
static func rank_of(score: int, caught := -1, total := -1) -> String:
	if score >= MAX_SCORE:
		return "X"
	if caught == 0 and total > 0 and score == 0:
		return "X"   # 刻意避开一切正确答案的嘉奖
	if score >= 900000: return "S"
	if score >= 800000: return "A"
	if score >= 700000: return "B"
	if score >= 600000: return "C"
	return "D"


static func load_save() -> void:
	library.load_all()
	_history_cache.clear()
	# 模组设置
	var f := FileAccess.open(设置文件, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			var m: Dictionary = d.get("mods", {})
			for k in m:
				mods[k] = m[k]


## 手柄支持: 给默认 UI 导航动作补手柄绑定(十字键+左摇杆+A, 幂等, 不动键盘默认)
static var _gamepad_done := false
static func ensure_gamepad_ui() -> void:
	if _gamepad_done:
		return
	_gamepad_done = true
	_ui_add_event(_joy_btn(JOY_BUTTON_DPAD_UP), "ui_up")
	_ui_add_event(_joy_btn(JOY_BUTTON_DPAD_DOWN), "ui_down")
	_ui_add_event(_joy_btn(JOY_BUTTON_DPAD_LEFT), "ui_left")
	_ui_add_event(_joy_btn(JOY_BUTTON_DPAD_RIGHT), "ui_right")
	_ui_add_event(_joy_motion(JOY_AXIS_LEFT_Y, -1.0), "ui_up")
	_ui_add_event(_joy_motion(JOY_AXIS_LEFT_Y, 1.0), "ui_down")
	_ui_add_event(_joy_motion(JOY_AXIS_LEFT_X, -1.0), "ui_left")
	_ui_add_event(_joy_motion(JOY_AXIS_LEFT_X, 1.0), "ui_right")
	_ui_add_event(_joy_btn(JOY_BUTTON_A), "ui_accept")


static func _joy_btn(idx: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	return e


static func _joy_motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


## 动作未含同类同值事件时才添加(避免重复绑定)
static func _ui_add_event(ev: InputEvent, action: String) -> void:
	if not InputMap.has_action(action):
		return
	for old in InputMap.action_get_events(action):
		if old.get_class() != ev.get_class():
			continue
		if ev is InputEventJoypadButton and (old as InputEventJoypadButton).button_index == ev.button_index:
			return
		if ev is InputEventJoypadMotion and (old as InputEventJoypadMotion).axis == ev.axis \
				and (old as InputEventJoypadMotion).axis_value == ev.axis_value:
			return
	InputMap.action_add_event(action, ev)


static func save_settings() -> void:
	var f := FileAccess.open(设置文件, FileAccess.WRITE)
	f.store_string(JSON.stringify({"mods": mods}))
	f.close()


static func _评分路径(song_name: String) -> String:
	return "%s/%s/评分.json" % [library.库目录, library.safe_name(song_name)]


## 某首歌某难度的历史成绩(载入过的走缓存) — 各难度相互独立
static func get_history(song_name: String, diff: int) -> Array:
	var key := "%s|%d" % [song_name, diff]
	if _history_cache.has(key):
		return _history_cache[key]
	var arr: Array = []
	var f := FileAccess.open(_评分路径(song_name), FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			var scores: Dictionary = d.get("scores", {})
			if scores.has(str(diff)):
				arr = scores[str(diff)]
			elif d.has("history"):  # 旧格式(无难度区分)迁移为普通难度
				arr = d["history"]
			arr.sort_custom(func(a, b): return a > b)
	_history_cache[key] = arr
	return arr


## 记录成绩到该歌的 评分.json(按难度分桶)
static func record(song_name: String, score: int, diff: int) -> void:
	var all := _load_all_scores(song_name)
	var arr: Array = all.get(str(diff), [])
	arr.append(score)
	arr.sort_custom(func(a, b): return a > b)
	all[str(diff)] = arr.slice(0, 5)
	_write_scores(song_name, all)
	for d in 3:
		_history_cache.erase("%s|%d" % [song_name, d])


## 清空某首歌全部难度的历史成绩(数据重置)
static func clear_history(song_name: String) -> void:
	for d in 3:
		_history_cache.erase("%s|%d" % [song_name, d])
	var p := _评分路径(song_name)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func _load_all_scores(song_name: String) -> Dictionary:
	var f := FileAccess.open(_评分路径(song_name), FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary and d.has("scores"):
			return d.get("scores", {})
		if d is Dictionary and d.has("history"):  # 旧格式
			return {"1": d["history"]}
	return {}


static func _write_scores(song_name: String, scores: Dictionary) -> void:
	var f := FileAccess.open(_评分路径(song_name), FileAccess.WRITE)
	f.store_string(JSON.stringify({"scores": scores}))
	f.close()
