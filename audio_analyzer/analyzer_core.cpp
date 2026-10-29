#include "analyzer_core.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <thread>

namespace analyzer {
namespace {

constexpr int FFT_SIZE = 1024;
constexpr int HOP = 512;
constexpr int N_BANDS = 40;
constexpr int PEAK_RADIUS = 10;       // 局部极大检测半径 ~0.12s
constexpr double LONG_WIN_SEC = 3.0;  // 峰值门限统计窗
constexpr double WIN_SEC = 10.0;      // 局部 BPM 窗口
constexpr double STEP_SEC = 2.0;      // 窗口步进
constexpr double PI = 3.14159265358979323846;

// 预计算旋转因子的 radix-2 FFT(v3 每蝶形重算三角函数, 是最大热点)
struct Fft {
	int n = 0;
	std::vector<std::vector<float>> wr, wi; // 每级 len/2 个
	void init(int n_) {
		n = n_;
		int stages = 0;
		while ((1 << stages) < n) ++stages;
		wr.assign(stages, {});
		wi.assign(stages, {});
		for (int s = 0; s < stages; ++s) {
			int len = 1 << (s + 1);
			wr[s].resize(len / 2);
			wi[s].resize(len / 2);
			for (int k = 0; k < len / 2; ++k) {
				double ang = -2.0 * PI * k / len;
				wr[s][k] = float(std::cos(ang));
				wi[s][k] = float(std::sin(ang));
			}
		}
	}
	void run(float *re, float *im) const {
		for (int i = 1, j = 0; i < n; ++i) {
			int bit = n >> 1;
			for (; j & bit; bit >>= 1) j ^= bit;
			j ^= bit;
			if (i < j) { std::swap(re[i], re[j]); std::swap(im[i], im[j]); }
		}
		for (int s = 0, len = 2; len <= n; ++s, len <<= 1) {
			int half = len / 2;
			const float *wr_s = wr[s].data(), *wi_s = wi[s].data();
			for (int i = 0; i < n; i += len) {
				float cr = 1.0f, ci = 0.0f;
				for (int k = 0; k < half; ++k) {
					float ur = re[i + k], ui = im[i + k];
					float vr = re[i + k + half] * cr - im[i + k + half] * ci;
					float vi = re[i + k + half] * ci + im[i + k + half] * cr;
					re[i + k] = ur + vr; im[i + k] = ui + vi;
					re[i + k + half] = ur - vr; im[i + k + half] = ui - vi;
					float ncr = cr * wr_s[k] - ci * wi_s[k];
					ci = cr * wi_s[k] + ci * wr_s[k];
					cr = ncr;
				}
			}
		}
	}
};

std::vector<float> hann(int n) {
	std::vector<float> w(n);
	for (int i = 0; i < n; ++i)
		w[i] = 0.5f * (1.0f - std::cos(2.0f * float(PI) * i / (n - 1)));
	return w;
}

std::vector<int> band_edges(int n_bins, int fft_size, int sample_rate, int n_bands) {
	double f_min = 30.0, f_max = std::min(16000.0, sample_rate / 2.0);
	std::vector<int> edges;
	for (int b = 0; b <= n_bands; ++b) {
		double f = f_min * std::pow(f_max / f_min, double(b) / n_bands);
		edges.push_back(std::clamp(int(f / sample_rate * fft_size), 1, n_bins));
	}
	edges.front() = 1;
	edges.back() = std::min(n_bins, edges.back());
	return edges;
}

// 包络按 lag(可带小数)线性插值取样
float env_at(const std::vector<float> &env, double pos) {
	int i = int(pos);
	if (i < 0 || i + 1 >= int(env.size())) return 0.0f;
	double frac = pos - i;
	return float(env[i] * (1 - frac) + env[i + 1] * frac);
}

float percentile(std::vector<float> v, double p) {
	if (v.empty()) return 0.0f;
	size_t i = std::min(size_t(v.size() * p), v.size() - 1);
	std::nth_element(v.begin(), v.begin() + i, v.end());
	return v[i];
}

} // namespace

Result analyze(const float *mono, size_t n_samples, int sample_rate, const Options &opt) {
	Result res;
	res.sample_rate = sample_rate;
	if (!mono || n_samples <= size_t(FFT_SIZE) || sample_rate <= 0) return res;
	res.duration = double(n_samples) / sample_rate;
	const double fps = double(sample_rate) / HOP;
	const int n_frames = int((n_samples - FFT_SIZE) / HOP) + 1;

	// --- STFT + 分频段对数幅度(多线程) ---
	std::vector<float> window = hann(FFT_SIZE);
	auto edges = band_edges(FFT_SIZE / 2, FFT_SIZE, sample_rate, N_BANDS);
	std::vector<float> band_log(size_t(n_frames) * N_BANDS);
	{
		Fft fft;
		fft.init(FFT_SIZE);
		int n_threads = opt.threads > 0 ? opt.threads : int(std::thread::hardware_concurrency());
		n_threads = std::clamp(n_threads, 1, 8);
		n_threads = std::min(n_threads, std::max(1, n_frames / 256));
		auto worker = [&](int from, int to) {
			std::vector<float> re(FFT_SIZE), im(FFT_SIZE);
			for (int f = from; f < to; ++f) {
				std::memcpy(re.data(), mono + size_t(f) * HOP, FFT_SIZE * sizeof(float));
				for (int i = 0; i < FFT_SIZE; ++i) { re[i] *= window[i]; im[i] = 0.0f; }
				fft.run(re.data(), im.data());
				float *row = &band_log[size_t(f) * N_BANDS];
				for (int b = 0; b < N_BANDS; ++b) {
					float sum = 0;
					int cnt = std::max(1, edges[b + 1] - edges[b]);
					for (int k = edges[b]; k < edges[b + 1]; ++k) {
						float mag = std::sqrt(re[k] * re[k] + im[k] * im[k]);
						sum += std::log1p(mag * 20.0f);
					}
					row[b] = sum / cnt;
				}
			}
		};
		if (n_threads <= 1 || n_frames < 512) {
			worker(0, n_frames);
		} else {
			std::vector<std::thread> pool;
			int chunk = (n_frames + n_threads - 1) / n_threads;
			for (int t = 0; t < n_threads; ++t) {
				int from = t * chunk, to = std::min(n_frames, from + chunk);
				if (from >= to) break;
				pool.emplace_back(worker, from, to);
			}
			for (auto &th : pool) th.join();
		}
	}

	// --- 谱通量 + 分频段均衡包络(单频段贡献封顶 3.0, 防病态频段主导) ---
	std::vector<float> env(n_frames, 0.0f);      // 均衡包络: onset 检测
	std::vector<float> env_raw(n_frames, 0.0f);  // 原始包络: 节拍跟踪(保低频鼓点主导)
	{
		std::vector<double> band_mean(N_BANDS, 0.0);
		for (int f = 1; f < n_frames; ++f) {
			const float *cur = &band_log[size_t(f) * N_BANDS];
			const float *prev = &band_log[size_t(f - 1) * N_BANDS];
			for (int b = 0; b < N_BANDS; ++b)
				if (cur[b] > prev[b]) band_mean[b] += cur[b] - prev[b];
		}
		for (int b = 0; b < N_BANDS; ++b) band_mean[b] /= std::max(1, n_frames - 1);
		for (int f = 1; f < n_frames; ++f) {
			const float *cur = &band_log[size_t(f) * N_BANDS];
			const float *prev = &band_log[size_t(f - 1) * N_BANDS];
			float e = 0, er = 0;
			for (int b = 0; b < N_BANDS; ++b) {
				float flux = cur[b] > prev[b] ? cur[b] - prev[b] : 0.0f;
				er += flux;
				e += std::min(flux / std::max(0.02f, float(band_mean[b])), float(opt.band_cap));
			}
			env[f] = e;
			env_raw[f] = er;
		}
	}

	// --- 逐帧 RMS(能量门限与段落分级共用; 段落用原始响度, 与白化包络解耦) ---
	std::vector<float> rms(n_frames, 0.0f);
	for (int f = 0; f < n_frames; ++f) {
		double sum = 0;
		size_t from = size_t(f) * HOP, to = std::min(n_samples, from + FFT_SIZE);
		for (size_t i = from; i < to; ++i) sum += double(mono[i]) * mono[i];
		rms[f] = float(std::sqrt(sum / std::max<size_t>(1, to - from)));
	}

	// --- 峰值拾取: 局部极大 + 长窗自适应门限 + 突出度 + 亚帧插值 ---
	struct Cand { double time; float strength; int band; float confidence; };
	std::vector<Cand> cands;
	{
		float env_p90 = percentile(env, 0.90);
		float thr_floor = float(opt.p90_frac) * env_p90;
		const int long_win = int(opt.long_win_sec * fps);
		const int prom_win = int(opt.prom_win_sec * fps);
		for (int f = PEAK_RADIUS + 1; f < n_frames - PEAK_RADIUS; ++f) {
			float v = env[f];
			if (v <= 0) continue;
			bool is_max = true;
			for (int k = f - PEAK_RADIUS; k <= f + PEAK_RADIUS; ++k)
				if (env[k] > v) { is_max = false; break; }
			if (!is_max) continue;
			int lo = std::max(0, f - long_win), hi = std::min(n_frames, f + long_win + 1);
			double mean = 0;
			for (int i = lo; i < hi; ++i) mean += env[i];
			mean /= hi - lo;
			double var = 0;
			for (int i = lo; i < hi; ++i) var += (env[i] - mean) * (env[i] - mean);
			double sd = std::sqrt(var / (hi - lo));
			if (v <= mean + std::max(opt.k_std * sd, double(thr_floor))) continue;
			// 突出度: 达到 ±窗 p98 峰值的 prom_frac —— 安静段底噪小起伏在此被滤除;
			// 用 p98 而非最大值, 单个大鼓填充不会压掉周围真拍
			if (opt.prom_frac > 0) {
				int plo = std::max(0, f - prom_win), phi = std::min(n_frames - 1, f + prom_win);
				float pref = percentile(std::vector<float>(env.begin() + plo, env.begin() + phi + 1), 0.98);
				if (v < float(opt.prom_frac) * pref) continue;
			}
			double denom = double(env[f - 1]) - 2 * v + env[f + 1];
			double shift = denom != 0 ? 0.5 * (env[f - 1] - env[f + 1]) / denom : 0.0;
			shift = std::clamp(shift, -1.0, 1.0);
			int best_band = 0;
			float best_flux = -1;
			const float *cur = &band_log[size_t(f) * N_BANDS];
			const float *prev = &band_log[size_t(f - 1) * N_BANDS];
			for (int b = 0; b < N_BANDS; ++b) {
				float flux = cur[b] - prev[b];
				if (flux > best_flux) { best_flux = flux; best_band = b; }
			}
			float conf = sd > 0 ? float(std::clamp((v - mean) / (6 * sd), 0.0, 1.0)) : 0.5f;  // 6σ: 门限即 2σ, 分母拉宽让可信度有分布
			cands.push_back({(f + shift) * HOP / double(sample_rate), v, best_band, conf});
		}
	}

	// --- 能量门限: 近乎无声段的误检丢弃(局部 RMS < 全曲 p95 × quiet_ratio) ---
	{
		float p95 = percentile(rms, 0.95);
		std::vector<Cand> kept;
		kept.reserve(cands.size());
		for (const auto &o : cands) {
			int f = std::clamp(int(o.time * fps), 0, n_frames - 1);
			int lo = std::max(0, f - 10), hi = std::min(n_frames - 1, f + 10);
			double sum = 0;
			for (int k = lo; k <= hi; ++k) sum += rms[k];
			if (sum / (hi - lo + 1) >= p95 * float(opt.quiet_ratio)) kept.push_back(o);
		}
		cands.swap(kept);
	}

	// --- 最小间隔 NMS: 强度优先保留(v3 由游戏侧先到先得, 会误删更强的后到峰) ---
	{
		std::sort(cands.begin(), cands.end(),
			[](const Cand &a, const Cand &b) { return a.strength > b.strength; });
		std::vector<Cand> kept;
		kept.reserve(cands.size());
		for (const auto &o : cands) {
			bool clash = false;
			for (const auto &k : kept)
				if (std::abs(k.time - o.time) < opt.min_gap) { clash = true; break; }
			if (!clash) kept.push_back(o);
		}
		std::sort(kept.begin(), kept.end(),
			[](const Cand &a, const Cand &b) { return a.time < b.time; });

		// --- 多难度分层: 按强度排序, 最强 easy_frac 比例为 tier0(简单), 到 normal_frac 为 tier1(普通), 其余 tier2(困难) ---
		std::vector<int> order(kept.size());
		for (size_t i = 0; i < kept.size(); ++i) order[i] = int(i);
		std::sort(order.begin(), order.end(),
			[&](int a, int b) { return kept[a].strength > kept[b].strength; });
		const size_t n_easy = std::min(kept.size(), size_t(kept.size() * opt.easy_frac));
		const size_t n_norm = std::min(kept.size(), size_t(kept.size() * opt.normal_frac));
		std::vector<int> tier_of(kept.size(), 2);
		for (size_t rank = 0; rank < order.size(); ++rank) {
			if (rank < n_easy) tier_of[order[rank]] = 0;
			else if (rank < n_norm) tier_of[order[rank]] = 1;
			else tier_of[order[rank]] = 2;
		}
		res.onsets.reserve(kept.size());
		for (size_t i = 0; i < kept.size(); ++i)
			res.onsets.push_back({kept[i].time, kept[i].strength, kept[i].band, kept[i].confidence, tier_of[i]});
	}

	// --- 滑窗局部 BPM → tempo map(comb 谐波项稳倍频, 粗搜 0.25 + 精搜 0.05) ---
	auto acf = [&](const std::vector<float> &e, int from, int to, double lag) {
		double s = 0;
		for (int f = from; f < to; ++f) s += double(e[f]) * env_at(e, f + lag);
		return s;
	};
	auto bpm_score = [&](const std::vector<float> &e, int from, int to, double bpm) {
		double lag = 60.0 / bpm * fps;
		double score = acf(e, from, to, lag) + 0.5 * acf(e, from, to, 2 * lag)
			+ 0.25 * acf(e, from, to, 3 * lag);
		if (bpm < 90 || bpm > 150) score *= 0.85;
		return score;
	};
	auto estimate_bpm = [&](const std::vector<float> &e, int from, int to) {
		double best = 0, best_s = -1;
		for (double bpm = 60.0; bpm <= 200.0 + 1e-9; bpm += 0.25) {
			if (from + 3 * (60.0 / bpm) * fps + 2 >= to) break;
			double s = bpm_score(e, from, to, bpm);
			if (s > best_s) { best_s = s; best = bpm; }
		}
		if (best <= 0) return 0.0;
		for (double bpm = std::max(60.0, best - 0.5); bpm <= best + 0.5 + 1e-9; bpm += 0.05) {
			double s = bpm_score(e, from, to, bpm);
			if (s > best_s) { best_s = s; best = bpm; }
		}
		return best;
	};
	for (double t = 0; t + WIN_SEC <= res.duration + STEP_SEC; t += STEP_SEC) {
		int from = std::max(0, int(t * fps));
		int to = std::min(n_frames, int((t + WIN_SEC) * fps));
		if (to - from < int(fps * 4)) break;
		double bpm = estimate_bpm(env_raw, from, to);
		if (bpm > 0) {
			res.tempo_map.push_back({t, std::min(t + STEP_SEC, res.duration), bpm});
		}
	}
	std::vector<double> local_bpms;
	for (const auto &s : res.tempo_map) local_bpms.push_back(s.bpm);
	std::sort(local_bpms.begin(), local_bpms.end());
	res.bpm = local_bpms.empty() ? 0 : local_bpms[local_bpms.size() / 2];
	for (auto &s : res.tempo_map) // 偏离中位数 >25% 的窗口按中位数回退(误检保护)
		if (res.bpm > 0 && std::abs(s.bpm - res.bpm) / res.bpm > 0.25) s.bpm = res.bpm;

	// --- 节拍跟踪: 首个强 onset 定相位, 逐拍吸附包络峰并按局部周期推进 ---
	{
		auto period_at = [&](double t) {
			// 取窗中心(WIN_SEC/2 处)最接近 t 的窗口: 10s 窗 2s 步进, 覆盖 t 的窗口有多个
			const TempoSpan *best = nullptr;
			double best_d = 1e18;
			for (const auto &s : res.tempo_map) {
				double d = std::abs(s.start + WIN_SEC / 2 - t);
				if (d < best_d) { best_d = d; best = &s; }
			}
			return 60.0 / (best ? best->bpm : (res.bpm > 0 ? res.bpm : 120.0));
		};
		const float STRONG = float(opt.beat_strong);
		float raw_max = 0;
		for (float v : env_raw) raw_max = std::max(raw_max, v);
		float raw_p90 = percentile(env_raw, 0.90);
		double period0 = 60.0 / (res.bpm > 0 ? res.bpm : 120.0);
		double sum_sin = 0, sum_cos = 0;
		for (const auto &o : res.onsets)
			if (o.strength > raw_max * STRONG && o.confidence > 0.3f) {
				double ph = o.time / period0 * 2 * PI;
				sum_sin += o.strength * std::sin(ph);
				sum_cos += o.strength * std::cos(ph);
			}
		double phase = sum_cos != 0 || sum_sin != 0 ? std::atan2(sum_sin, sum_cos) / (2 * PI) : 0.0;
		if (phase < 0) phase += 1.0;
		double t = phase * period0;
		while (t < 0) t += period0;

		const double max_snap_frac = 0.10; // 吸附窗口 = ±10% 周期
		while (t < res.duration) {
			double period = period_at(t);
			double w = period * max_snap_frac;
			int lo = std::max(0, int((t - w) * fps)), hi = std::min(n_frames - 1, int((t + w) * fps));
			int best = std::clamp(int(t * fps), lo, hi);
			for (int i = lo; i <= hi; ++i)
				if (env_raw[i] > env_raw[best]) best = i;
			// 弱峰保护: 吸附窗内最大能量过低时保持网格(防漂向噪声)
			double beat = env_raw[best] >= float(opt.snap_floor) * raw_p90 ? best / fps : t;
			if (res.beats.empty() || beat - res.beats.back() > period * 0.5)
				res.beats.push_back(beat);
			t = res.beats.back() + period_at(res.beats.back());
		}
		// 半拍校验: 反拍能量不低即平移半拍(防整体锁反拍)
		double on_beat = 0, off_beat = 0;
		double half = period0 / 2;
		for (double b : res.beats) {
			int i = std::clamp(int(b * fps), 0, n_frames - 1);
			int j = std::clamp(int((b + half) * fps), 0, n_frames - 1);
			on_beat += env_raw[i];
			off_beat += env_raw[j];
		}
		if (off_beat > on_beat)
			for (auto &b : res.beats) b += half;
	}

	// --- 段落检测: 按粒度 sec_bin 统计 RMS 响度 → novelty 边界 ---
	{
		const double sec_bin = opt.section_bin_sec;
		int n_bins = int(res.duration / sec_bin) + 1;
		std::vector<float> energy(n_bins, 0.0f);
		std::vector<int> counts(n_bins, 0);
		for (int f = 0; f < n_frames; ++f) {
			int b = int(f / fps / sec_bin);
			if (b < n_bins) { energy[b] += rms[f]; counts[b]++; }
		}
		for (int b = 0; b < n_bins; ++b)
			if (counts[b] > 0) energy[b] /= counts[b];
		std::vector<float> novelty(n_bins, 0.0f);
		const int nov_win = int(4.0 / sec_bin); // ±4s
		for (int b = 0; b < n_bins; ++b) {
			float sum = 0;
			for (int k = std::max(1, b - nov_win); k <= std::min(n_bins - 1, b + nov_win); ++k)
				sum += std::abs(energy[k] - energy[k - 1]);
			novelty[b] = sum;
		}
		std::vector<double> bounds;
		const int min_gap = int(opt.section_min_len / sec_bin);
		for (int b = min_gap; b < n_bins - min_gap; ++b) {
			if (novelty[b] != *std::max_element(novelty.begin() + b - min_gap / 2,
					novelty.begin() + b + min_gap / 2 + 1))
				continue;
			if (bounds.empty() || b * sec_bin - bounds.back() >= opt.section_min_len)
				bounds.push_back(b * sec_bin);
		}
	float med_e = percentile(energy, 0.5);
		std::vector<double> sec_bounds = bounds;
		sec_bounds.insert(sec_bounds.begin(), 0.0);
		sec_bounds.push_back(res.duration);
		for (size_t i = 0; i + 1 < sec_bounds.size(); ++i) {
			int b0 = int(sec_bounds[i] / sec_bin), b1 = std::min(n_bins, int(sec_bounds[i + 1] / sec_bin));
			double e = 0;
			int cnt = 0;
			for (int b = b0; b < b1; ++b) { e += energy[b]; ++cnt; }
			if (!cnt) continue;
			float rel = float(e / cnt / (med_e > 0 ? med_e : 1));
			res.sections.push_back({sec_bounds[i], sec_bounds[i + 1], rel,
				rel > 1.25f ? 2 : rel < 0.75f ? 0 : 1});
		}
	}
	return res;
}

} // namespace analyzer
