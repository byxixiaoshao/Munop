# 触音律动 音频分析器 (audio_analyzer)

GDExtension 插件: 把 mp3 解析成音游谱面数据（onset 音符点、BPM/tempo map、节拍、段落强度分级）。
算法核心为 C++（STFT + 分频段谱通量 + 自适应峰值拾取 + comb 自相关 BPM），约 0.9s 分析 4 分钟歌曲。

## 用法

无需在项目设置中启用——放入 `addons/` 后引擎自动加载 GDExtension 类 `AudioAnalyzer`。

```gdscript
var analyzer := AudioAnalyzer.new()

# 方式一: 直接分析文件(支持 res://、user://、绝对路径; 仅 mp3)
var chart: Dictionary = analyzer.analyze_file("res://资源/towards_the_light.mp3", {})

# 方式二: 导出后的 PCK 内文件, 先读字节再分析
var f := FileAccess.open(path, FileAccess.READ)
var chart: Dictionary = analyzer.analyze_bytes(f.get_buffer(f.get_length()), {})

print(chart.tempo.bpm)          # 全局 BPM
print(chart.onsets.size())      # 音符点数
for o in chart.onsets:          # {time, strength, band, confidence}
    print(o.time, " ", o.confidence)
for s in chart.sections:        # {start, end, energy, level} level: 0安静/1中/2激烈
    print(s.start, "-", s.end, " L", s.level)
```

`opts` 可选参数（不传用默认值）:

| 键 | 默认 | 说明 |
|---|---|---|
| `min_gap` | 0.35 | 相邻 onset 最小间隔(秒), 强度优先保留 |
| `quiet_ratio` | 0.08 | 能量门限: 局部 RMS < 全曲 p95 × 此值的误检丢弃 |
| `threads` | 自动 | STFT 线程数 |

返回字典与 CLI 生成的 JSON 谱面完全同构，可直接写入文件当谱面用：

```gdscript
var f := FileAccess.open("user://新歌.json", FileAccess.WRITE)
f.store_string(JSON.stringify(chart, "  "))
```

分析是同步阻塞的（约 0.01×歌长），建议放 Thread 里跑：

```gdscript
var th := Thread.new()
th.start(func(): chart = analyzer.analyze_file(path, {}))
```

## 目录结构

- `audio_analyzer.gdextension` — 库清单（入口符号、平台库映射）
- `bin/` — 预编译 DLL（template_debug 供编辑器运行，template_release 供导出）

## 从源码重编译

源码在 `audio_analyzer/`（本项目根目录，已被 .gdignore 排除扫描）:

1. `git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git`
   到 `E:\build_tools\godot-cpp-4.5`（或改 build_addon.bat 里的 `GDCPP` 路径）
2. 运行 `audio_analyzer\build_addon.bat`（VS2022 MSVC；godot-cpp 走 CMake+Ninja，
   封装层直接 cl——注意不要用 SCons，其 MSVC spawn 在本机会间歇性报"系统找不到指定的文件"）
3. 自动部署 DLL 到本插件 `bin/`

兼容性: 按 GDExtension 前向兼容约定以 godot-cpp 4.5 API 构建（`compatibility_minimum = 4.5`），
可在 4.5 及更新的 Godot 4.x 上运行。
