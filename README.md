# 音符载荷

一款 360° 环形音乐节奏游戏, 由 Godot 4.7 开发, 支持 Windows 与 Android。

音符从四面八方坠向屏幕中心的圆核, 你旋转环形挡板去迎接它们——蓝接住、青保持、紫避开, 一切跟随节拍。

## 玩法

- **蓝色音符** — 静止直落: 转动挡板对准即可接住
- **青色长音** — 接住后保持贴合随挡板缓转直到尾巴结束, 贴合期间持续得分(2×音符分值×贴合比例); 中途脱开记 BREAK
- **紫色放行** — 千万不要接! 完全避开让它坠入中心才得全额分, 沾到一点即为 MISS

### 判定

| 判定 | 条件 | 倍率 |
|------|------|------|
| PERFECT | 面接触重合度 ≥ 80% | ×1.0 |
| GREAT | 重合度 ≥ 60% | ×0.7 |
| GOOD | 重合度 ≥ 20% | ×0.4 |
| EXTREME | 极限擦边 0 < 重合度 < 20% | ×1.0 |
| ATTACK | 仅挡板边缘侧碰 | ×1.0 |
| PASS | 紫音符零接触放行 | ×1.0 |
| MISS / BREAK | 角差过大 / 坠入中心 / 长音脱开 | — |

每关满分 1,000,000 = 音符池 950,000 + 全清奖励 50,000。评级: X(满分) / S / A / B / C / D。

## 特性

- **本地歌曲导入**: 支持 mp3 / wav / ogg / flac, 导入后自动分析音频生成简单/普通/困难三档谱面, 自动提取 mp3 内嵌封面
- **高潮试听**: 主界面与结算界面优先播放歌曲高潮段落(音频分析持久化到每首歌的 `info.json`)
- **音频分析插件**: 自研 GDExtension(`audio_analyzer/`), 提供 BPM/能量分段/PCM 解码, Windows(x86_64) 与 Android(arm64) 预编译二进制随库附带
- **手柄支持**: 主界面导航/切难度/开始游戏, 游戏内左摇杆控挡板, 全流程无需键盘鼠标
- **移动端适配**: 触屏生成虚拟摇杆控制挡板(设置内可开关), 屏幕居中自适应任意分辨率
- **视觉效果**: 中心低频跃动、动态暗光(随低频能量跳动), 均可在设置中开关
- **新手教程**: 完全静音的引导模式
- **数据持久化**: 歌曲索引/谱面/历史成绩/设置全部存于 `user://数据/`, Android 上通过"所有文件访问"权限将导入歌曲映射为真实路径, 重启不丢

### 手柄按键

| 界面 | 按键 |
|------|------|
| 主界面 | 左摇杆上下切关卡 · LT/RT 切难度 · LB/RB 切底部按钮 · Start 开始 · A 确认 |
| 游戏内 | 左摇杆控制挡板 · Start 暂停 |
| 结算 | 任意键继续 |

## 构建指南

### 环境

- Godot 4.7 (Forward Plus)
- 编译音频插件需要: MSVC / Android NDK、SCons、CMake(可选, 核心库)
- Android 导出需要: JDK 17、Android SDK、Gradle 构建模板(`android/build/`)

### 步骤

```bash
# 1. 克隆仓库
git clone https://github.com/byxixiaoshao/Munop.git
cd Munop

# 2. 用 Godot 4.7 打开 project.godot, 等待导入完成

# 3. (可选) 从源码重新编译音频插件
cd audio_analyzer/gdextension
scons platform=windows target=template_release
scons platform=android arch=arm64 target=template_release

# 4. 运行 / 导出
#    Windows: Godot 编辑器 F5, 或导出预设 ".output/音符载荷.exe"
#    Android: 导出预设 ".output/音符载荷.apk"(需先安装 Android 构建模板)
```

## 项目结构

```
├── addons/audio_analyzer/    # GDExtension 运行时(gdextension 配置 + 预编译二进制)
├── audio_analyzer/           # 插件 C++ 源码与构建脚本
├── 场景/                      # Godot 场景(主界面/游戏/结算/弹窗)
├── 脚本/                      # GDScript(游戏逻辑/谱面生成/歌曲库/弹窗)
├── 着色器/                    # 背景模糊着色器
├── 资源/                      # 字体/封面等静态资源
└── android/build/            # Android 构建模板(含自定义权限)
```

## 声明

- 本项目没有也不会参与任何侵权行为
- 本项目不提供任何互联网服务, 也不会窃取任何用户个人隐私

## 开源许可

本项目以 [AGPL-3.0](LICENSE) 协议开源。

`audio_analyzer/third_party/` 内的单头文件库遵循其自身许可: [dr_libs](https://github.com/mackron/dr_libs)、[minimp3](https://github.com/lieff/minimp3) (公有领域/MIT)、[stb](https://github.com/nothings/stb) (公有领域/MIT)。
