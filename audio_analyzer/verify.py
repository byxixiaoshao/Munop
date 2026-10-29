# 对比基线/优化版谱面与 librosa 的指标
# 用法: python verify.py <chart_dir> [chart_dir2 ...]
import json, sys
import librosa
import numpy as np

SONGS = [
    ("head_in_the_clouds", r"E:\Video_素材\AVIV\元力QQ@325294908@Head In The Clouds@Hayd.mp3"),
    ("towards_the_light", r"E:\桌面\Jacoo - Towards the Light.mp3"),
]

_cache = {}
def load_song(mp3):
    if mp3 not in _cache:
        y, sr = librosa.load(mp3, sr=44100, mono=True)
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        tempo = librosa.feature.tempo(onset_envelope=onset_env, sr=sr)
        onsets = librosa.onset.onset_detect(y=y, sr=sr, units='time', backtrack=False)
        _, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
        _cache[mp3] = (y, sr, float(tempo[0]), onsets, librosa.frames_to_time(beats, sr=sr))
    return _cache[mp3]

def rms_curve(y, sr, hop=512, nfft=1024):
    n = (len(y) - nfft) // hop + 1
    out = np.empty(n)
    for f in range(n):
        seg = y[f*hop:f*hop+nfft]
        out[f] = np.sqrt(np.mean(seg*seg))
    return out

def check(name, mp3, chart_path):
    y, sr, ref_bpm, ref_onsets, ref_beats = load_song(mp3)
    chart = json.load(open(chart_path, encoding='utf-8'))
    my_bpm = chart['tempo']['bpm']
    ratio = my_bpm / ref_bpm
    ratio_ok = next((k for k in (0.5, 1, 2) if abs(ratio - k) < 0.07), None)
    mine = np.array([o['time'] for o in chart['onsets']])
    matched = sum(1 for t in mine if len(ref_onsets) and np.min(np.abs(ref_onsets - t)) < 0.05)
    precision = matched / max(1, len(mine))
    coverage = matched / max(1, len(ref_onsets))
    # 节拍偏差
    devs = np.array([np.min(np.abs(ref_beats - t)) for t in chart['beats']]) if len(ref_beats) else np.array([1.0])
    # 安静段（level 0 段落）onset 密度
    low_onsets = sum(1 for o in chart['onsets']
                     for s in chart['sections']
                     if s['level'] == 0 and s['start'] <= o['time'] < s['end'])
    low_dur = sum(s['end'] - s['start'] for s in chart['sections'] if s['level'] == 0)
    low_density = low_onsets / max(0.1, low_dur)
    high_density = (len(mine) - low_onsets) / max(0.1, chart['duration'] - low_dur)
    print(f"{chart_path}:")
    print(f"  BPM {my_bpm} vs librosa {ref_bpm:.1f} (比例 {ratio:.2f} {'OK' if ratio_ok else '不一致'})")
    print(f"  onset {len(mine)} 个 (librosa {len(ref_onsets)}): 精确率 {precision:.0%}, 覆盖率 {coverage:.0%}")
    print(f"  beats {len(chart['beats'])} (librosa {len(ref_beats)}): 偏差中位 {np.median(devs)*1000:.0f}ms, <30ms {np.mean(devs<0.03):.0%}")
    print(f"  安静段(L0) {low_dur:.0f}s onset密度 {low_density:.2f}/s vs 其他段 {high_density:.2f}/s")
    print(f"  段落 {len(chart['sections'])} 个, tempo_map {len(chart['tempo_map'])} 段")

for d in sys.argv[1:]:
    for name, mp3 in SONGS:
        check(name, mp3, f"{d}/{name}.json")
    print()
