import json, sys
import librosa
import numpy as np

def check(mp3, chart_path):
    y, sr = librosa.load(mp3, sr=44100, mono=True)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    tempo = librosa.feature.tempo(onset_envelope=onset_env, sr=sr)
    onset_frames = librosa.onset.onset_detect(y=y, sr=sr, units='time', backtrack=False)
    chart = json.load(open(chart_path, encoding='utf-8'))
    my_bpm = chart['tempo']['bpm']
    # 与最接近的倍率比较
    ref = float(tempo[0])
    ratio = my_bpm / ref
    for k in (0.5, 1, 2):
        if abs(ratio - k) < 0.07: ratio_ok = k; break
    else: ratio_ok = None
    # onset 时序吻合度：C++ onset 中与 librosa onset 距离<50ms 的比例
    mine = np.array([o['time'] for o in chart['onsets']])
    ref_o = onset_frames
    matched = sum(1 for t in mine if len(ref_o) and np.min(np.abs(ref_o - t)) < 0.05)
    precision = matched / max(1, len(mine))
    coverage = matched / max(1, len(ref_o))
    print(f"{chart_path}: librosa BPM={ref:.1f} vs C++ BPM={my_bpm} (比例 {ratio:.2f} {'OK' if ratio_ok else '不一致'})")
    print(f"  onset: C++ {len(mine)} 个, librosa {len(ref_o)} 个; 50ms 内匹配率: 精确率 {precision:.0%}, 覆盖率 {coverage:.0%}")

check(r"E:\Video_素材\AVIV\元力QQ@325294908@Head In The Clouds@Hayd.mp3", "head_in_the_clouds.json")
check(r"E:\桌面\Jacoo - Towards the Light.mp3", "towards_the_light.json")

def check_beats(mp3, chart_path):
    y, sr = librosa.load(mp3, sr=44100, mono=True)
    oe = librosa.onset.onset_strength(y=y, sr=sr)
    _, ref_beats = librosa.beat.beat_track(onset_envelope=oe, sr=sr)
    ref_beats = librosa.frames_to_time(ref_beats, sr=sr)
    chart = json.load(open(chart_path, encoding='utf-8'))
    mine = np.array(chart['beats'])
    devs = np.array([np.min(np.abs(ref_beats - t)) for t in mine])
    print(f"{chart_path}: beats C++ {len(mine)} vs librosa {len(ref_beats)}; 偏差中位数 {np.median(devs)*1000:.0f}ms, <30ms 占比 {(devs<0.03).mean():.0%}")
    secs = chart['sections']
    print(f"  段落 {len(secs)} 个: " + ", ".join(f"[{s['start']:.0f}-{s['end']:.0f}s L{s['level']}]" for s in secs[:8]) + " ...")

check_beats(r"E:\Video_素材\AVIV\元力QQ@325294908@Head In The Clouds@Hayd.mp3", "head_in_the_clouds.json")
check_beats(r"E:\桌面\Jacoo - Towards the Light.mp3", "towards_the_light.json")
