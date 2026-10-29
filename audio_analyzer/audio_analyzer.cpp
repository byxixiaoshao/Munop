// 触音律动 - 音频解析 CLI(v4)
// 输入: mp3 文件路径  输出: JSON 谱面数据
// 算法核心在 analyzer_core.cpp(v4), 本文件只负责 minimp3 解码 + JSON 输出,
// 供离线批量生成谱面与 librosa 交叉验证; 游戏内实时分析走 GDExtension(audio_analyzer/gdextension)。

#define MINIMP3_IMPLEMENTATION
#define MINIMP3_FLOAT_OUTPUT
#define NOMINMAX
#include "third_party/minimp3.h"
#include "third_party/minimp3_ex.h"

#include "analyzer_core.hpp"

#include <chrono>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <windows.h>

// ---------- 解码 MP3 为单声道 float ----------
static bool decode_mp3(const std::string &path, std::vector<float> &mono, int &sample_rate) {
	mp3dec_t dec;
	mp3dec_file_info_t info;
	if (mp3dec_load(&dec, path.c_str(), &info, nullptr, nullptr)) {
		std::cerr << "解码失败: " << path << "\n";
		return false;
	}
	sample_rate = int(info.hz);
	mono.resize(info.samples / info.channels);
	for (size_t i = 0; i < mono.size(); ++i)
		mono[i] = float(info.buffer[i * info.channels]);
	free(info.buffer);
	return sample_rate > 0 && !mono.empty();
}

static std::string json_escape(const std::string &s) {
	int wlen = MultiByteToWideChar(CP_ACP, 0, s.c_str(), -1, nullptr, 0);
	std::wstring wide(size_t(wlen), L'\0');
	MultiByteToWideChar(CP_ACP, 0, s.c_str(), -1, wide.data(), wlen);
	int ulen = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
	std::string utf8(size_t(ulen - 1), '\0');
	WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, utf8.data(), ulen, nullptr, nullptr);
	std::string out;
	for (unsigned char c : utf8) {
		if (c == '\\' || c == '"') { out += '\\'; out += char(c); }
		else if (c < 0x20) { char buf[8]; snprintf(buf, sizeof buf, "\\u%04x", c); out += buf; }
		else out += char(c);
	}
	return out;
}

int main(int argc, char **argv) {
	if (argc < 2) {
		std::cerr << "用法: audio_analyzer <输入.mp3> [输出.json] [--k-std=X] [--p90=X] [--prom=X]"
			" [--prom-win=X] [--snap=X] [--min-gap=X]\n";
		return 1;
	}
	std::string in_path = argv[1];
	std::string out_path = argc > 2 ? argv[2] : in_path + ".chart.json";
	analyzer::Options opt;
	auto set_opt = [&](const char *name, double &dst) {
		std::string flag = std::string("--") + name + "=";
		for (int i = 3; i < argc; ++i) {
			std::string a = argv[i];
			if (a.rfind(flag, 0) == 0) dst = std::stod(a.substr(flag.size()));
		}
	};
	set_opt("k-std", opt.k_std);
	set_opt("p90", opt.p90_frac);
	set_opt("prom", opt.prom_frac);
	set_opt("prom-win", opt.prom_win_sec);
	set_opt("snap", opt.snap_floor);
	set_opt("min-gap", opt.min_gap);

	std::vector<float> mono;
	int sample_rate = 0;
	if (!decode_mp3(in_path, mono, sample_rate)) return 1;
	std::cout << "解码完成: " << double(mono.size()) / sample_rate << "s @ " << sample_rate << "Hz\n";

	auto t0 = std::chrono::steady_clock::now();
	analyzer::Result r = analyzer::analyze(mono.data(), mono.size(), sample_rate, opt);
	double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();

	std::cout << "onset: " << r.onsets.size() << " 个, 全局 BPM " << r.bpm
		<< ", 节拍 " << r.beats.size() << " 个, 段落 " << r.sections.size()
		<< " 个, 耗时 " << ms << "ms\n";

	std::ofstream out(out_path, std::ios::binary);
	out << "{\n";
	out << "  \"version\": 3,\n";
	out << "  \"file\": \"" << json_escape(in_path) << "\",\n";
	out << "  \"duration\": " << r.duration << ",\n";
	out << "  \"sample_rate\": " << r.sample_rate << ",\n";
	out << "  \"analysis\": { \"fft_size\": 1024, \"hop\": 512, \"bands\": 40, \"envelope_fps\": "
		<< double(sample_rate) / 512 << " },\n";
	out << "  \"tempo\": { \"bpm\": " << r.bpm << ", \"period\": " << (r.bpm > 0 ? 60.0 / r.bpm : 0.0) << " },\n";
	out << "  \"tempo_map\": [\n";
	for (size_t i = 0; i < r.tempo_map.size(); ++i)
		out << "    { \"start\": " << r.tempo_map[i].start << ", \"end\": " << r.tempo_map[i].end
			<< ", \"bpm\": " << r.tempo_map[i].bpm << " }" << (i + 1 < r.tempo_map.size() ? "," : "") << "\n";
	out << "  ],\n";
	out << "  \"beats\": [";
	for (size_t i = 0; i < r.beats.size(); ++i) out << (i ? "," : "") << r.beats[i];
	out << "],\n";
	out << "  \"onsets\": [\n";
	for (size_t i = 0; i < r.onsets.size(); ++i) {
		char buf[176];
		snprintf(buf, sizeof buf, "    { \"time\": %.4f, \"strength\": %.3f, \"band\": %d, \"confidence\": %.2f }%s\n",
			r.onsets[i].time, r.onsets[i].strength, r.onsets[i].band, r.onsets[i].confidence,
			i + 1 < r.onsets.size() ? "," : "");
		out << buf;
	}
	out << "  ],\n";
	out << "  \"sections\": [\n";
	for (size_t i = 0; i < r.sections.size(); ++i)
		out << "    { \"start\": " << r.sections[i].start << ", \"end\": " << r.sections[i].end
			<< ", \"energy\": " << r.sections[i].energy << ", \"level\": " << r.sections[i].level
			<< " }" << (i + 1 < r.sections.size() ? "," : "") << "\n";
	out << "  ]\n}\n";
	std::cout << "已写入: " << out_path << "\n";
	return 0;
}
