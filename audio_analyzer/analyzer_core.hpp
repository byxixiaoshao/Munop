#pragma once
// 音符载荷 - 音频结构化解析核心 v4（平台无关, 供 CLI 与 GDExtension 共用）
// 管线: PCM → STFT(1024/512, Hann) → 40 对数频段谱通量 → 频段均衡包络
//       → 自适应峰值拾取(长窗统计 + 突出度 + 全曲分位下限)
//       → 能量门限 → 最小间隔 NMS(强度优先)
//       → 滑窗 comb 自相关 BPM(粗+精两段) → 节拍跟踪 → 段落检测
//
// v4 相对 v3 的变化(librosa 交叉验证, 两首歌实测):
//   1. 峰值门限从"局部均值+常数 0.02"改为"3s 长窗均值 + max(2σ, 全曲包络 p90×5%)",
//      并要求峰值达到 ±2s 窗 p98 的 35% —— 安静段精确率 33%→61%/52%→70%(用户痛点)
//   2. 最小间隔从游戏侧"先到先得丢弃"移入核心, 改为强度优先 NMS(保留更强的)
//   3. 段落能量改用原始 RMS(与白化包络解耦): 均衡封顶曾把段落分级压成全 L1
//   4. BPM comb 谐波项(2×/3× lag)实测必要(纯 ACF 节拍大幅变差), period_at 取窗中心
//      最近窗口; FFT 旋转因子预计算 + STFT 多线程, 4 分钟歌 1.7s → 0.87s

#include <cstddef>
#include <vector>

namespace analyzer {

struct Options {
	double min_gap = 0.35;      // onset 最小间隔(秒), 强度优先保留
	double quiet_ratio = 0.08;  // 能量门限: 局部 RMS < 全曲 p95 响度 × 此值 → 丢弃
	int threads = 0;            // STFT 线程数, 0 = 自动
	// 峰值门限调参(扫参定默认值)
	double k_std = 2.0;         // 门限 = 长窗均值 + k·σ
	double p90_frac = 0.05;     // 门限下限 = 全曲包络 p90 × 此值
	double prom_frac = 0.35;    // 突出度: 峰值须达 ±窗 p98 的此比例, 0 = 关闭
	double prom_win_sec = 2.0;  // 突出度窗宽
	double snap_floor = 0.10;   // 节拍吸附弱峰保护(相对 env_raw p90), 0 = 恢复无条件吸附
	// 多难度分层: tier0 = 最强 easy_frac 比例, tier0+1 = normal_frac 比例, 其余 tier2
	double easy_frac = 0.6;
	double normal_frac = 0.85;
	// 段落检测
	double section_min_len = 8.0;   // 段落最小长度(秒)
	double section_bin_sec = 0.5;   // 能量统计粒度(秒)
	// 节拍跟踪
	double beat_strong = 0.35;      // 首拍强度门槛(相对全曲包络最大)
	// 峰值统计窗
	double long_win_sec = 3.0;      // 峰值门限统计窗(秒)
	double band_cap = 8.0;          // 单频段均衡贡献封顶
};

struct Onset { double time; float strength; int band; float confidence; int tier; };
struct TempoSpan { double start, end, bpm; };
struct Section { double start, end; float energy; int level; };

struct Result {
	double duration = 0.0;
	int sample_rate = 0;
	double bpm = 0.0;
	std::vector<TempoSpan> tempo_map;
	std::vector<double> beats;
	std::vector<Onset> onsets;
	std::vector<Section> sections;
};

// mono: 单声道 float PCM(任意线性刻度), 长度 n_samples
Result analyze(const float *mono, size_t n_samples, int sample_rate, const Options &opt = {});

} // namespace analyzer
