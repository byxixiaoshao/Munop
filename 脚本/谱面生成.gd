class_name ChartGen
const _AnalyzerBridge := preload("res://脚本/分析器桥.gd")
## 谱面生成器(Godot 原生): C++ 插件只负责分析音频, 本类根据分析结果生成三难度曲谱
## 每首歌生成 谱面_简单/谱面_普通/谱面_困难 三份, 难度越高音符越多

const MIN_NOTE_GAP := [0.30, 0.25, 0.18]        # 分难度最小间隔
const DIFF_CONF_GATE := [[0.85, 0.6, 0.4], [0.7, 0.5, 0.35], [0.5, 0.4, 0.25]]  # 分难度段落可信度门槛
const DIFF_LEVEL0_HALF := [true, true, false]   # 弱段减半: 简单/普通开, 困难关
const DIFF_TOP_FRAC := [1.0, 0.95, 1.0]         # 强度分位数保留比例(简单=原困难逻辑, 不裁)
const HOLD_MAX := 3.5
const DIFF_GREEN := [0.20, 0.35, 0.40]   # 绿(正向漂移)概率
const DIFF_PASS := [0.0, 0.07, 0.10]     # 紫(放行)概率
const DIFF_NAMES := ["简单", "普通", "困难"]
const DRIFT_SPEED := 1.2


## 对一首歌生成全部三难度谱面, 返回成功生成的数量
## 分析用灵敏参数(更全的 onset 池), 难度差异由本类的分布算法控制
static func generate_all(song_name: String, audio_path: String, out_dir: String) -> int:
	# 双池: 标准池(简单=原困难逻辑) + 灵敏池(普通/困难的更大原料)
	var analysis: Dictionary = AnalyzerBridge.analyze(ProjectSettings.globalize_path(audio_path), {})
	var analysis_hi: Dictionary = AnalyzerBridge.analyze(ProjectSettings.globalize_path(audio_path),
		{"min_gap": 0.18, "quiet_ratio": 0.05, "k_std": 1.7, "p90_frac": 0.03, "prom_frac": 0.22})
	if analysis.is_empty():
		return 0
	var n := 0
	for d in 3:
		var pool: Dictionary = analysis if d == 0 else analysis_hi
		var chart := build(pool, d, song_name)
		if chart.is_empty():
			continue
		var f := FileAccess.open("%s/谱面_%s.json" % [out_dir, DIFF_NAMES[d]], FileAccess.WRITE)
		f.store_string(JSON.stringify(chart, "  "))
		f.close()
		n += 1
	# info.json: 记录高潮片段(能量最高且 ≥8s 的段落), 供主界面/结算试听
	var info := FileAccess.open(out_dir + "/info.json", FileAccess.WRITE)
	if info:
		var best_e := -1.0
		var climax := {"offset": 0.0, "len": 10.0}
		for sec in analysis.get("sections", []):
			var length := float(sec.get("end", 0.0)) - float(sec.get("start", 0.0))
			if length < 8.0:
				continue
			var en := float(sec.get("energy", 0.0))
			if en > best_e:
				best_e = en
				climax = {"offset": float(sec["start"]), "len": clampf(length, 8.0, 15.0)}
		info.store_string(JSON.stringify({"name": song_name, "climax": climax}, "  "))
		info.close()
	return n


## 根据分析结果构建单难度谱面: {version, difficulty, duration, notes:[{t,ang,drift,pass,hold}], total_slots}
static func build(analysis: Dictionary, diff: int, song_name: String) -> Dictionary:
	var duration := float(analysis.get("duration", 0.0))
	if duration <= 0.0:
		return {}
	var sections: Array = analysis.get("sections", [])
	var onsets: Array = analysis.get("onsets", [])

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(song_name) + diff  # 每歌每难度确定性
	var golden := TAU * 0.618
	var last_accept := -10.0

	# 第一遍A: 分难度段落可信度门槛 + tier 过滤 + 弱段减半(按难度开关)
	var gated := []
	for i in onsets.size():
		var o: Dictionary = onsets[i]
		var t: float = o["time"]
		var level := _level_at(sections, t)
		if float(o.get("confidence", 0.0)) < DIFF_CONF_GATE[diff][level]:
			continue
		if DIFF_LEVEL0_HALF[diff] and level == 0 and i % 2 == 0:
			continue
		gated.append({"t": t, "band": int(o["band"]), "level": level, "strength": float(o.get("strength", 0.0))})

	# 第一遍B: 强度分位数保留
	gated.sort_custom(func(a, b): return a.strength > b.strength)
	var keep_n := int(gated.size() * DIFF_TOP_FRAC[diff])
	gated = gated.slice(0, maxi(keep_n, mini(1, gated.size())))
	gated.sort_custom(func(a, b): return a.t < b.t)

	# 第一遍C: 分难度最小间隔
	var accepted := []
	for g in gated:
		if g.t - last_accept < MIN_NOTE_GAP[diff]:
			continue
		last_accept = g.t
		accepted.append(g)

	# 长音选择: 大空档前音符, 彼此间隔 10s; 不足时兜底最大 3 空档
	var hold_set := {}
	var last_hold_t := -99.0
	for j in accepted.size():
		var cur_t: float = accepted[j].t
		var next_t: float = accepted[j + 1].t if j + 1 < accepted.size() else cur_t + 99.0
		var onset_gap: float = next_t - cur_t
		if onset_gap >= 1.8 and cur_t - last_hold_t >= 10.0:
			hold_set[j] = minf(HOLD_MAX, onset_gap - 0.8)
			last_hold_t = cur_t
	# 结尾保护: 完成时刻超过 音频时长-1s 的长音不生成
	var drop := []
	for j in hold_set:
		var gap_left: float = accepted[j + 1].t - accepted[j].t if j + 1 < accepted.size() else 99.0
		var need: float = accepted[j].t + minf(float(hold_set[j]), gap_left - 0.8) + 0.6
		if need > duration - 1.0:
			drop.append(j)
	for j in drop:
		hold_set.erase(j)
	if hold_set.is_empty():
		var gaps := []
		for j in accepted.size():
			var cur_t: float = accepted[j].t
			var next_t: float = accepted[j + 1].t if j + 1 < accepted.size() else cur_t + 99.0
			gaps.append({"j": j, "gap": next_t - cur_t})
		gaps.sort_custom(func(a, b): return a.gap > b.gap)
		for g in gaps.slice(0, 3):
			if g.gap >= 1.0:
				hold_set[g.j] = clampf(g.gap - 0.5, 1.0, HOLD_MAX)

	# 红(反向)阈值: 本谱面频段前 12%
	var band_sorted: Array = []
	for a in accepted:
		band_sorted.append(a.band)
	band_sorted.sort()
	var red_band_min: int = int(band_sorted[int(band_sorted.size() * 0.88)]) if not band_sorted.is_empty() else 40

	# 第二遍: 类型分配 → notes
	var notes: Array = []
	for idx in accepted.size():
		var a: Dictionary = accepted[idx]
		var t: float = a.t
		var band: int = a.band
		var is_hold: bool = hold_set.has(idx)
		var drift := 0.0
		if not is_hold:
			if band >= red_band_min:
				drift = -DRIFT_SPEED
			elif band >= 14 and rng.randf() < DIFF_GREEN[diff]:
				drift = DRIFT_SPEED
		var passnote: bool = not is_hold and drift == 0.0 and a.level > 0 and rng.randf() < DIFF_PASS[diff]
		var ang := fposmod(band / 40.0 * TAU + idx * golden, TAU)
		notes.append({
			"t": snappedf(t, 0.0001),
			"ang": snappedf(ang, 0.0001),
			"drift": drift,
			"pass": passnote,
			"hold": snappedf(float(hold_set.get(idx, 0.0)), 0.001),
		})

	var total_slots := notes.size()
	for n in notes:
		if n.hold > 0.0:
			total_slots += 1
	return {
		"version": 4,
		"difficulty": diff,
		"duration": duration,
		"bpm": float(analysis.get("tempo", {}).get("bpm", 0.0)),
		"sections": sections,
		"notes": notes,
		"total_slots": total_slots,
	}


static func _level_at(sections: Array, t: float) -> int:
	for s in sections:
		if float(s["start"]) <= t and t < float(s["end"]):
			return int(s["level"])
	return 1
