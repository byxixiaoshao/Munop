class_name AnalyzerBridge
## AudioAnalyzer(GDExtension) 的运行时软桥接
## 扩展未加载(缺 .so/平台不支持)时返回空结果而不是解析报错, 游戏本体仍可运行
## 用 ClassDB.instantiate 规避解析期标识符依赖

static func available() -> bool:
	return ClassDB.class_exists("AudioAnalyzer")


static func _inst() -> Variant:
	if not available():
		return null
	return ClassDB.instantiate("AudioAnalyzer")


## 分析音频文件(失败/不可用返回空字典)
static func analyze(path: String, opts: Dictionary = {}) -> Dictionary:
	var a: Variant = _inst()
	if a == null:
		return {}
	return a.analyze_file(path, opts)


## 解码为 PCM(热加载 wav/flac 用; 不可用返回空)
static func decode_pcm(path: String) -> Dictionary:
	var a: Variant = _inst()
	if a == null:
		return {}
	return a.decode_pcm(path)
