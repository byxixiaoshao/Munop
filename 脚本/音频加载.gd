class_name AudioLoader
const _AnalyzerBridge := preload("res://脚本/分析器桥.gd")
## 音频热加载: 不经过 Godot 资源导入系统, 直接从文件字节构造可播放流
## mp3 → AudioStreamMP3 | ogg → AudioStreamOggVorbis | wav/flac → 插件解码 PCM → AudioStreamWAV
## 导入新歌后无需重启即可播放

static func load_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var ext := path.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(path)
	match ext:
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = bytes
			return s
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav", "flac":
			# 插件解码为 16bit 单声道 PCM, 包装成 WAV 流
			var pcm: Dictionary = AnalyzerBridge.decode_pcm(ProjectSettings.globalize_path(path))
			if pcm.is_empty() or not pcm.has("pcm16"):
				return null
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = int(pcm.get("rate", 44100))
			w.stereo = false
			w.data = pcm["pcm16"]
			return w
		_:
			return null
