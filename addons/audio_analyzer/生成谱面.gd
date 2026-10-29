# 用 GDExtension 插件重新生成 资源/ 下所有歌曲的谱面
# Godot --headless --path . --script res://addons/audio_analyzer/生成谱面.gd
extends SceneTree

func _init() -> void:
	var dir := DirAccess.open("res://资源")
	if dir == null:
		printerr("资源目录不存在")
		quit(1)
		return
	var count := 0
	for f in dir.get_files():
		if not f.get_extension() in ["mp3", "wav", "ogg", "flac"]:
			continue
		var name := f.get_basename()
		var json_path := "res://资源/%s.json" % name
		var t0 := Time.get_ticks_msec()
		var chart: Dictionary = AudioAnalyzer.new().analyze_file("res://资源/" + f, {})
		if chart.is_empty():
			printerr("FAIL: ", f)
			continue
		var out := FileAccess.open(json_path, FileAccess.WRITE)
		out.store_string(JSON.stringify(chart, "  "))
		out.close()
		print("OK %s.json: BPM %.1f, onset %d, 耗时 %dms" % [
			name, float(chart.tempo.bpm), chart.onsets.size(), Time.get_ticks_msec() - t0])
		count += 1
	print("完成, 共 %d 首" % count)
	quit(0)
