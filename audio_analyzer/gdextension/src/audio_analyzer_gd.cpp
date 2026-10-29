// minimp3 实现只在本 TU 展开一次, 必须在 include 之前定义
#define MINIMP3_IMPLEMENTATION
#define MINIMP3_FLOAT_OUTPUT
#include "audio_analyzer_gd.hpp"

#include "../third_party/minimp3.h"
#include "../third_party/minimp3_ex.h"

// 多格式解码: WAV / FLAC (dr_libs), OGG Vorbis (stb_vorbis)
#define DR_WAV_IMPLEMENTATION
#include "dr_wav.h"
#define DR_FLAC_IMPLEMENTATION
#include "dr_flac.h"
#define STB_VORBIS_HEADER_ONLY   // 声明; 实现编译自 third_party/stb_vorbis.c
#include "../third_party/stb_vorbis.c"

#include <memory>

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>
#include <vector>

namespace godot {

AudioAnalyzer::AudioAnalyzer() = default;
AudioAnalyzer::~AudioAnalyzer() = default;

void AudioAnalyzer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("analyze_file", "path", "opts"), &AudioAnalyzer::analyze_file);
	ClassDB::bind_method(D_METHOD("analyze_bytes", "data", "opts"), &AudioAnalyzer::analyze_bytes);
	ClassDB::bind_method(D_METHOD("decode_pcm", "path"), &AudioAnalyzer::decode_pcm);
	ClassDB::bind_method(D_METHOD("get_default_opts"), &AudioAnalyzer::get_default_opts);
}

analyzer::Options AudioAnalyzer::parse_opts(const Dictionary &opts) {
	analyzer::Options opt;
	if (opts.has("min_gap")) opt.min_gap = (double)opts["min_gap"];
	if (opts.has("quiet_ratio")) opt.quiet_ratio = (double)opts["quiet_ratio"];
	if (opts.has("threads")) opt.threads = (int)opts["threads"];
	if (opts.has("k_std")) opt.k_std = (double)opts["k_std"];
	if (opts.has("prom_win_sec")) opt.prom_win_sec = (double)opts["prom_win_sec"];
	if (opts.has("snap_floor")) opt.snap_floor = (double)opts["snap_floor"];
	if (opts.has("long_win_sec")) opt.long_win_sec = (double)opts["long_win_sec"];
	if (opts.has("band_cap")) opt.band_cap = (double)opts["band_cap"];
	if (opts.has("section_min_len")) opt.section_min_len = (double)opts["section_min_len"];
	if (opts.has("section_bin_sec")) opt.section_bin_sec = (double)opts["section_bin_sec"];
	if (opts.has("beat_strong")) opt.beat_strong = (double)opts["beat_strong"];
	if (opts.has("p90_frac")) opt.p90_frac = (double)opts["p90_frac"];
	if (opts.has("prom_frac")) opt.prom_frac = (double)opts["prom_frac"];
	if (opts.has("easy_frac")) opt.easy_frac = (double)opts["easy_frac"];
	if (opts.has("normal_frac")) opt.normal_frac = (double)opts["normal_frac"];
	return opt;
}

Dictionary AudioAnalyzer::to_dict(const analyzer::Result &r) {
	Dictionary d;
	d["version"] = 3;
	d["duration"] = r.duration;
	d["sample_rate"] = r.sample_rate;
	Dictionary tempo;
	tempo["bpm"] = r.bpm;
	tempo["period"] = r.bpm > 0 ? 60.0 / r.bpm : 0.0;
	d["tempo"] = tempo;

	Array tempo_map;
	for (const auto &s : r.tempo_map) {
		Dictionary e;
		e["start"] = s.start;
		e["end"] = s.end;
		e["bpm"] = s.bpm;
		tempo_map.push_back(e);
	}
	d["tempo_map"] = tempo_map;

	PackedFloat64Array beats;
	for (double b : r.beats) beats.push_back(b);
	d["beats"] = beats;

	Array onsets;
	for (const auto &o : r.onsets) {
		Dictionary e;
		e["time"] = o.time;
		e["strength"] = o.strength;
		e["band"] = o.band;
		e["confidence"] = o.confidence;
		e["tier"] = o.tier;  // 0=简单核心拍 1=普通 2=困难
		onsets.push_back(e);
	}
	d["onsets"] = onsets;

	Array sections;
	for (const auto &s : r.sections) {
		Dictionary e;
		e["start"] = s.start;
		e["end"] = s.end;
		e["energy"] = s.energy;
		e["level"] = s.level;
		sections.push_back(e);
	}
	d["sections"] = sections;
	return d;
}

namespace {
// 通用解码: 按文件头识别格式, 输出单声道 float + 采样率
bool decode_audio(const uint8_t *buf, size_t size, std::vector<float> &mono, int &sample_rate) {
	if (size < 16) return false;
	// WAV: "RIFF" ... "WAVE"
	if (memcmp(buf, "RIFF", 4) == 0 && memcmp(buf + 8, "WAVE", 4) == 0) {
		unsigned int channels = 0, rate = 0;
		drwav_uint64 frames = 0;
		float *pcm = drwav_open_memory_and_read_pcm_frames_f32(buf, size, &channels, &rate, &frames, nullptr);
		if (!pcm || frames == 0) { drwav_free(pcm, nullptr); return false; }
		mono.resize(size_t(frames));
		for (drwav_uint64 i = 0; i < frames; ++i) {
			float acc = 0;
			for (unsigned int c = 0; c < channels; ++c) acc += pcm[i * channels + c];
			mono[size_t(i)] = acc / channels;
		}
		sample_rate = int(rate);
		drwav_free(pcm, nullptr);
		return true;
	}
	// FLAC: "fLaC"
	if (memcmp(buf, "fLaC", 4) == 0) {
		unsigned int channels = 0, rate = 0;
		drflac_uint64 frames = 0;
		float *pcm = drflac_open_memory_and_read_pcm_frames_f32(buf, size, &channels, &rate, &frames, nullptr);
		if (!pcm || frames == 0) { drflac_free(pcm, nullptr); return false; }
		mono.resize(size_t(frames));
		for (drflac_uint64 i = 0; i < frames; ++i) {
			float acc = 0;
			for (unsigned int c = 0; c < channels; ++c) acc += pcm[i * channels + c];
			mono[size_t(i)] = acc / channels;
		}
		sample_rate = int(rate);
		drflac_free(pcm, nullptr);
		return true;
	}
	// OGG Vorbis: "OggS"
	if (memcmp(buf, "OggS", 4) == 0) {
		int err = 0;
		stb_vorbis *v = stb_vorbis_open_memory(buf, int(size), &err, nullptr);
		if (!v) return false;
		stb_vorbis_info vi = stb_vorbis_get_info(v);
		int total = stb_vorbis_stream_length_in_samples(v);
		if (total <= 0) { stb_vorbis_close(v); return false; }
		std::unique_ptr<float[]> pcm(new float[size_t(total) * vi.channels]);
		int got = stb_vorbis_get_samples_float_interleaved(v, int(vi.channels), pcm.get(), total * int(vi.channels));
		mono.resize(size_t(got));
		for (int i = 0; i < got; ++i) {
			float acc = 0;
			for (int c = 0; c < int(vi.channels); ++c) acc += pcm[size_t(i) * vi.channels + c];
			mono[size_t(i)] = acc / vi.channels;
		}
		sample_rate = int(vi.sample_rate);
		stb_vorbis_close(v);
		return true;
	}
	// 其余按 MP3 处理(ID3 头或帧同步)
	mp3dec_t dec;
	mp3dec_init(&dec);
	mp3dec_file_info_t info;
	if (mp3dec_load_buf(&dec, buf, size, &info, nullptr, nullptr) || !info.buffer) return false;
	size_t n_samples = info.samples / info.channels;
	if (n_samples == 0 || info.hz == 0) { ::free(info.buffer); return false; }
	mono.resize(n_samples);
	for (size_t i = 0; i < n_samples; ++i)
		mono[i] = float(info.buffer[i * info.channels]);
	sample_rate = int(info.hz);
	::free(info.buffer); // Object::free 会遮蔽全局 free, 须显式全局
	return true;
}
} // namespace

Dictionary AudioAnalyzer::analyze_buffer(const uint8_t *buf, size_t size, const analyzer::Options &opt) {
	Dictionary empty;
	if (!buf || size == 0) {
		ERR_FAIL_V_MSG(empty, "audio_analyzer: 输入字节为空");
	}
	std::vector<float> mono;
	int sample_rate = 0;
	if (!decode_audio(buf, size, mono, sample_rate)) {
		ERR_FAIL_V_MSG(empty, "audio_analyzer: 解码失败(支持 mp3/wav/ogg/flac)");
	}

	analyzer::Result r = analyzer::analyze(mono.data(), mono.size(), sample_rate, opt);
	return to_dict(r);
}

Dictionary AudioAnalyzer::analyze_bytes(const PackedByteArray &data, const Dictionary &opts) {
	Dictionary empty;
	if (data.size() <= 0) {
		ERR_FAIL_V_MSG(empty, "audio_analyzer: 字节流为空");
	}
	return analyze_buffer(reinterpret_cast<const uint8_t *>(data.ptr()), size_t(data.size()), parse_opts(opts));
}

Dictionary AudioAnalyzer::get_default_opts() {
	Dictionary d;
	d["min_gap"] = analyzer::Options().min_gap;
	d["quiet_ratio"] = analyzer::Options().quiet_ratio;
	d["threads"] = analyzer::Options().threads;
	d["k_std"] = analyzer::Options().k_std;
	d["p90_frac"] = analyzer::Options().p90_frac;
	d["prom_frac"] = analyzer::Options().prom_frac;
	d["prom_win_sec"] = analyzer::Options().prom_win_sec;
	d["snap_floor"] = analyzer::Options().snap_floor;
	d["easy_frac"] = analyzer::Options().easy_frac;
	d["normal_frac"] = analyzer::Options().normal_frac;
	d["section_min_len"] = analyzer::Options().section_min_len;
	d["section_bin_sec"] = analyzer::Options().section_bin_sec;
	d["beat_strong"] = analyzer::Options().beat_strong;
	d["long_win_sec"] = analyzer::Options().long_win_sec;
	d["band_cap"] = analyzer::Options().band_cap;
	return d;
}

Dictionary AudioAnalyzer::decode_pcm(const String &path) {
	Dictionary out;
	Ref<FileAccess> f = FileAccess::open(path, FileAccess::READ);
	ERR_FAIL_COND_V_MSG(f.is_null(), out, "audio_analyzer: 无法打开文件 " + path);
	PackedByteArray data = f->get_buffer(int64_t(f->get_length()));
	std::vector<float> mono;
	int rate = 0;
	if (!decode_audio(reinterpret_cast<const uint8_t *>(data.ptr()), size_t(data.size()), mono, rate) || mono.empty()) {
		ERR_FAIL_V_MSG(out, "audio_analyzer: 解码失败 " + path);
	}
	PackedByteArray pcm;
	pcm.resize(mono.size() * 2);
	int16_t *p = reinterpret_cast<int16_t *>(pcm.ptrw());
	for (size_t i = 0; i < mono.size(); ++i) {
		float v = mono[i];
		p[i] = int16_t(v > 1.0f ? 32767 : v < -1.0f ? -32768 : int16_t(v * 32767.0f));
	}
	out["pcm16"] = pcm;
	out["rate"] = rate;
	out["frames"] = int64_t(mono.size());
	return out;
}

Dictionary AudioAnalyzer::analyze_file(const String &path, const Dictionary &opts) {
	Dictionary empty;
	Ref<FileAccess> f = FileAccess::open(path, FileAccess::READ);
	ERR_FAIL_COND_V_MSG(f.is_null(), empty, "audio_analyzer: 无法打开文件 " + path);
	uint64_t len = f->get_length();
	PackedByteArray data = f->get_buffer(int64_t(len));
	return analyze_bytes(data, opts);
}

} // namespace godot
