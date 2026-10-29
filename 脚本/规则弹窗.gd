extends "res://脚本/弹窗基类.gd"
## 规则弹窗: 音符处理方式 / 判定条件与倍率 / 分值与评价标准
## 数值与 主场景2D.gd 判定逻辑、全局.gd 评级体系保持一致

const RULE_TEXT := """[b][color=#5cf0ff][font_size=38]规 则[/font_size][/color][/b]

[b][color=#5cf0ff]■ 音符处理[/color][/b]
[color=#7eb6ff]蓝[/color] — 静止直落: 转动挡板对准即可接住
[color=#00ffff]青[/color] — 长音: 接住后保持贴合随挡板缓转直到尾巴结束, 贴合期间持续得分(2×音符分值×贴合比例), 贴满收尾记 PERFECT; 中途脱开记 BREAK(断连击, 已得部分保留)
[color=#bf8cff]紫[/color] — 放行: 千万不要接! 完全避开让它坠入中心才得全额分, 沾到一点即为 MISS

[b][color=#5cf0ff]■ 判定条件与倍率[/color][/b]  [color=#8a97b0](角差 d, 重合度 q=弧重叠/音符弧宽, 接住窗口 d<100°)[/color]
[color=#e6ffff]PERFECT[/color] ×1.0 — 面接触 q ≥ 80%
[color=#d8ffcc]GREAT[/color] ×0.7 — 面接触 q ≥ 60%
[color=#bfe9f5]GOOD[/color] ×0.4 — 面接触 q ≥ 20%
[color=#80c9ff]EXTREME[/color] ×1.0 — 极限擦边 0 < q < 20%
[color=#ffd180]ATTACK[/color] ×1.0 — 仅挡板边缘侧碰(无弧重叠, 不计入命中)
[color=#b39cff]PASS[/color] ×1.0 — 紫音符零接触放行成功
[color=#ff9c9c]MISS[/color] — 角差 ≥100° / 音符坠入中心 / 紫音符被沾到
[color=#ff9c9c]BREAK[/color] — 长音贴合中断(断连击, 已得部分保留)

[b][color=#5cf0ff]■ 分值与评价[/color][/b]
每关满分 1,000,000 = 音符池 950,000 + 全清奖励 50,000(全部音符载出)
[color=#ff6659]X[/color] 满分(另有彩蛋: 0分且0命中 — 刻意避开一切正确答案的嘉奖)
[color=#ffef86]S[/color] ≥ 900,000    [color=#9ff3ff]A[/color] ≥ 800,000    [color=#a3ffc9]B[/color] ≥ 700,000    [color=#ffe9a3]C[/color] ≥ 600,000    [color=#ff9c9c]D[/color] 其余"""


func _build() -> void:
	panel.position = Vector2(310, 40)
	panel.custom_minimum_size = Vector2(1300, 1000)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.position = Vector2(36, 20)
	rt.size = Vector2(1228, 890)
	rt.add_theme_font_size_override("normal_font_size", 25)
	rt.add_theme_font_size_override("bold_font_size", 30)
	rt.add_theme_color_override("default_color", Color(0.85, 0.92, 1.0))
	rt.text = RULE_TEXT
	panel.add_child(rt)
	var btn := _add_button("知道了", Vector2(585, 922), Vector2(130, 54), 32)
	btn.pressed.connect(close_popup)
