#pragma once
// 触音律动 - 音频分析器 GDExtension 封装
// 用法(GDScript):
//   var analyzer := AudioAnalyzer.new()
//   var chart := analyzer.analyze_file("res://资源/towards_the_light.mp3", {})
//   print(chart.tempo.bpm, chart.onsets.size())
// 返回字典与 CLI JSON 谱面同构:
//   version/duration/sample_rate/tempo{bpm,period}/tempo_map/beats/onsets/sections

#include "../analyzer_core.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class AudioAnalyzer : public RefCounted {
	GDCLASS(AudioAnalyzer, RefCounted)

protected:
	static void _bind_methods();

private:
	static Dictionary to_dict(const analyzer::Result &r);
	static analyzer::Options parse_opts(const Dictionary &opts);
	Dictionary analyze_buffer(const uint8_t *buf, size_t size, const analyzer::Options &opt);

public:
	AudioAnalyzer();
	~AudioAnalyzer();

	// 分析音频文件(走 FileAccess, 支持 res:///user:///绝对路径; 仅 mp3)
	Dictionary analyze_file(const String &path, const Dictionary &opts);
	// 分析 mp3/wav/ogg/flac 字节流(导出版 PCK 内文件先由 GDScript 读出字节再传入)
	Dictionary analyze_bytes(const PackedByteArray &data, const Dictionary &opts);
	// 解码为原始 PCM(16bit 单声道), 供热加载播放: {"pcm16", "rate", "frames"}
	Dictionary decode_pcm(const String &path);
	// 全部可调分析参数及默认值(GDScript 侧发现接口)
	Dictionary get_default_opts();
};

} // namespace godot
