class_name Library
const _AnalyzerBridge := preload("res://脚本/分析器桥.gd")
## 歌曲库: 音频永远留在用户所选原位置(索引记绝对路径), 库只记路径
## 每首歌一个文件夹(user://数据/库/<歌名>/): 封面.png + 谱面_简单/普通/困难.json + 评分.json
## C++ 插件只分析; 三难度谱面由 ChartGen(GDScript) 生成; 无目录扫描, 歌曲只经导入进入
## 非法文件名字符自动过滤

const 库目录 := "user://数据/库"
const 索引文件 := "user://数据/库/索引.json"

const ChartGen := preload("res://脚本/谱面生成.gd")

var songs: Array = []            # [{name, audio, dir}]
var tombstones: Array = []       # 被用户删掉的歌(按音频绝对路径): 重新导入解除


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(库目录)


static func safe_name(song_name: String) -> String:
	var bad := ["\\", "/", ":", "*", "?", '"', "<", ">", "|", "."]
	var out := song_name
	for c in bad:
		out = out.replace(c, "_")
	return out.strip_edges()


static func 歌文件夹(song_name: String) -> String:
	return 库目录 + "/" + safe_name(song_name)


func load_all() -> void:
	songs.clear()
	tombstones.clear()
	var f := FileAccess.open(索引文件, FileAccess.READ)
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			tombstones = data.get("deleted", [])
			var migrated := false
			for e in data.get("songs", []):
				if e is Dictionary:
					var fixed: String = _durable_path(e.get("audio", ""))
					if fixed != "" and fixed != e.get("audio", ""):
						e["audio"] = fixed   # 老库 content:// 授权后迁移为真实路径, 重启不再失效
						migrated = true
					if FileAccess.file_exists(e.get("audio", "")):
						songs.append(e)
			if migrated:
				save_index()


## content:// URI → 真实存储路径(仅 primary: 卷可映射), 非法/读不到返回空串, 普通路径原样返回
## 前提: 已授予 MANAGE_EXTERNAL_STORAGE(所有文件访问), 否则真实路径不可见 → 返回空串
static func _durable_path(path: String) -> String:
	if path == "" or not path.begins_with("content://"):
		return path
	const MARK := "/document/primary:"
	var dec := path.uri_decode()
	var idx := dec.find(MARK)
	if idx < 0:
		return ""
	var real := "/storage/emulated/0/" + dec.substr(idx + MARK.length())
	return real if FileAccess.file_exists(real) else ""


func find(song_name: String) -> Dictionary:
	for e in songs:
		if e.name == song_name:
			return e
	return {}


## 导入: 音频留原位 → 分析 → ChartGen 生成三难度谱面 → 提封面 → 每歌文件夹落盘
func import_file(src_path: String) -> Dictionary:
	var ext := src_path.get_extension().to_lower()
	if not ext in ["mp3", "wav", "ogg", "flac"]:
		return {}
	# 歌名取解码后的源文件名: Android 选择器返回 URL 编码的 content:// URI
	# (…/document/primary%3AMusic%2Fx.mp3 → 解码后按 / 取末段), 桌面普通路径解码为无操作
	var name := src_path.uri_decode().get_file().get_basename()
	var dir := 歌文件夹(name)
	DirAccess.make_dir_recursive_absolute(dir)
	# Android: content:// 授权是临时的(重启失效) → 尽量映射为真实路径持久化
	var audio_abs := _durable_path(ProjectSettings.globalize_path(src_path))
	if audio_abs == "":
		audio_abs = ProjectSettings.globalize_path(src_path)   # 映射失败(未授权/非 primary 卷): 保留 content://, 本次会话仍可读
	var n: int = ChartGen.generate_all(name, audio_abs, ProjectSettings.globalize_path(dir))
	if n == 0:
		return {}
	if ext == "mp3":
		var img := CoverUtil.extract_image(audio_abs)
		if img:
			img.save_png(dir + "/封面.png")
	tombstones.erase(audio_abs)
	remove_from_songs(name)
	songs.append({"name": name, "audio": audio_abs, "dir": dir})
	songs.sort_custom(func(a, b): return a.name < b.name)
	save_index()
	return find(name)


func remove_from_songs(song_name: String) -> void:
	for i in songs.size():
		if songs[i].name == song_name:
			songs.remove_at(i)
			break


## 删除: 歌文件夹整个清掉; 音频原文件一律不动; 墓碑防同路径复活
func remove(song_name: String) -> void:
	var e := find(song_name)
	if e.is_empty():
		return
	if not e.audio in tombstones:
		tombstones.append(e.audio)
	var dir: String = e.get("dir", "")
	if dir != "" and DirAccess.dir_exists_absolute(dir):
		_delete_dir(dir)
	remove_from_songs(song_name)
	save_index()


func _delete_dir(path: String) -> void:
	for _pass in 3:  # 多轮清空: 防单次遗漏(写入句柄/缓存列表)
		var d := DirAccess.open(path)
		if d == null:
			return
		var files := d.get_files()
		var subs := d.get_directories()
		if files.is_empty() and subs.is_empty():
			break
		for f in files:
			DirAccess.remove_absolute(path + "/" + f)
		for sub in subs:
			_delete_dir(path + "/" + sub)
	DirAccess.remove_absolute(path)


## 全难度谱面重置
func reset_one(song_name: String) -> int:
	var e := find(song_name)
	if e.is_empty() or not FileAccess.file_exists(e.audio):
		return 0
	return ChartGen.generate_all(song_name, e.audio, e.dir)


func save_index() -> void:
	var f := FileAccess.open(索引文件, FileAccess.WRITE)
	f.store_string(JSON.stringify({"songs": songs, "deleted": tombstones}, "  "))
	f.close()


## 播放流(热加载: mp3/ogg 原生, wav/flac 插件解码 PCM)
func load_stream(entry: Dictionary) -> AudioStream:
	if entry.is_empty():
		return null
	var path: String = entry.get("audio", "")
	if path == "" or not FileAccess.file_exists(path):
		return null
	var ext := path.get_extension().to_lower()
	match ext:
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(path)
			return s
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path))
		"wav", "flac":
			var pcm: Dictionary = AnalyzerBridge.decode_pcm(ProjectSettings.globalize_path(path))
			if pcm.is_empty() or not pcm.has("pcm16"):
				return null
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = int(pcm.get("rate", 44100))
			w.stereo = false
			w.data = pcm["pcm16"]
			return w
	return null


## 封面纹理: 歌文件夹 封面.png/jpg → mp3 内嵌 → 默认封面
func load_cover(entry: Dictionary) -> ImageTexture:
	if entry.is_empty():
		return null
	var dir: String = entry.get("dir", "")
	if dir != "":
		for name in ["封面.png", "封面.jpg"]:
			if FileAccess.file_exists(dir + "/" + name):
				var img := Image.load_from_file(ProjectSettings.globalize_path(dir + "/" + name))
				if img:
					return ImageTexture.create_from_image(img)
	if entry.get("audio", "").get_extension().to_lower() == "mp3":
		var img2 := CoverUtil.extract_image(ProjectSettings.globalize_path(entry.audio))
		if img2:
			return ImageTexture.create_from_image(img2)
	var def := Image.load_from_file(ProjectSettings.globalize_path("res://资源/默认封面.png"))
	return ImageTexture.create_from_image(def) if def else null


## 搜索: 名字包含关键字(空关键字返回全部)
func search(query: String) -> Array:
	if query.strip_edges() == "":
		return songs
	var q := query.to_lower()
	return songs.filter(func(e): return e.name.to_lower().contains(q))


## 高潮片段: info.json 优先 → 旧库回退读谱面 json 的 sections 现算 → 默认开头 10 秒
func climax_of(song_name: String) -> Dictionary:
	var dir: String = find(song_name).get("dir", "")
	if dir != "":
		var f := FileAccess.open(dir + "/info.json", FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary and d.get("climax") is Dictionary:
				var c: Dictionary = d["climax"]
				return {"offset": float(c.get("offset", 0.0)), "len": clampf(float(c.get("len", 10.0)), 1.0, 60.0)}
		for cn in ["谱面_普通.json", "谱面_简单.json", "谱面_困难.json"]:
			var f2 := FileAccess.open(dir + "/" + cn, FileAccess.READ)
			if f2:
				var d2: Variant = JSON.parse_string(f2.get_as_text())
				if d2 is Dictionary:
					var best := _best_section(d2.get("sections", []))
					if not best.is_empty():
						return best
	return {"offset": 0.0, "len": 10.0}


## sections 里挑能量最高且 ≥8s 的段落
static func _best_section(sections: Array) -> Dictionary:
	var best_e := -1.0
	var out := {}
	for sec in sections:
		if sec is not Dictionary:
			continue
		var length := float(sec.get("end", 0.0)) - float(sec.get("start", 0.0))
		if length < 8.0:
			continue
		var en := float(sec.get("energy", 0.0))
		if en > best_e:
			best_e = en
			out = {"offset": float(sec["start"]), "len": clampf(length, 8.0, 15.0)}
	return out
