# headless 插件验证脚本: Godot --headless --path . --script 测试插件.gd
extends SceneTree

func _init() -> void:
	var songs := [
		"res://资源/towards_the_light.mp3",
		"res://资源/head_in_the_clouds.mp3",
	]
	var ok := true
	for path in songs:
		var t0 := Time.get_ticks_msec()
		var analyzer := AudioAnalyzer.new()
		var chart: Dictionary = analyzer.analyze_file(path, {})
		var ms := Time.get_ticks_msec() - t0
		if chart.is_empty():
			printerr("FAIL: 空结果 ", path)
			ok = false
			continue
		var conf_sum := 0.0
		for o in chart.onsets:
			conf_sum += o.confidence
		var conf_avg: float = conf_sum / maxf(1.0, float(chart.onsets.size()))
		print("OK %s: BPM %.1f, onset %d (平均可信度 %.2f), beats %d, 段落 %d, 耗时 %dms" % [
			path.get_file(), chart.tempo.bpm, chart.onsets.size(), conf_avg,
			chart.beats.size(), chart.sections.size(), ms])
		# 字段完备性检查
		for key in ["version", "duration", "sample_rate", "tempo", "tempo_map", "beats", "onsets", "sections"]:
			if not chart.has(key):
				printerr("FAIL: 缺字段 ", key)
				ok = false
		# bytes 入口
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		var chart2: Dictionary = analyzer.analyze_bytes(f.get_buffer(f.get_length()), {})
		if chart2.is_empty() or int(chart2.onsets.size()) != int(chart.onsets.size()):
			printerr("FAIL: analyze_bytes 结果不一致")
			ok = false
	# 与 资源/ 里的 JSON 谱面比对(应同构)
	var js: Variant = JSON.parse_string(FileAccess.open("res://资源/towards_the_light.json", FileAccess.READ).get_as_text())
	var c: Dictionary = AudioAnalyzer.new().analyze_file("res://资源/towards_the_light.mp3", {})
	if absf(float(js.tempo.bpm) - float(c.tempo.bpm)) > 0.01 or js.onsets.size() != c.onsets.size():
		printerr("FAIL: 与 JSON 谱面不一致: bpm %.2f vs %.2f, onsets %d vs %d" % [
			float(js.tempo.bpm), float(c.tempo.bpm), js.onsets.size(), c.onsets.size()])
		ok = false
	else:
		print("OK 与 JSON 谱面一致 (bpm %.2f, onsets %d)" % [float(c.tempo.bpm), c.onsets.size()])
	print("全部通过" if ok else "存在失败")
	quit(0 if ok else 1)
