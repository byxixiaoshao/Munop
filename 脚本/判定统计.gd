extends Control
## 判定频率统计: 每种判定出现次数的柱状图(结算页用)

const BARS := [
	["PF", "PERFECT", Color(0.9, 1.9, 2.3)],
	["GT", "GREAT", Color(1.2, 1.7, 0.9)],
	["GD", "GOOD", Color(0.85, 1.5, 1.8)],
	["EX", "EXTREME", Color(0.5, 1.3, 2.6)],
	["AT", "ATTACK", Color(2.4, 1.4, 0.5)],
	["MS", "MISS", Color(1.7, 0.45, 0.4)],
	["PS", "PASS", Color(1.5, 0.95, 1.9)],
	["BR", "BREAK", Color(1.4, 1.2, 1.0)],
]

var counts: Dictionary = {}


func _draw() -> void:
	if counts.is_empty():
		return
	var inner := Rect2(Vector2(8, 26), size - Vector2(16, 44))
	# 基线 + 满刻度线
	draw_line(inner.position + Vector2(0, inner.size.y), inner.position + Vector2(inner.size.x, inner.size.y), Color(1, 1, 1, 0.25), 1.0, true)
	var max_c := 1
	for b: Array in BARS:
		max_c = maxi(max_c, int(counts.get(b[1], 0)))
	var slot := inner.size.x / BARS.size()
	var bar_w := slot * 0.55
	var font := ThemeDB.fallback_font
	for i in BARS.size():
		var b: Array = BARS[i]
		var c := int(counts.get(b[1], 0))
		var cx := inner.position.x + slot * (i + 0.5)
		var h := inner.size.y * float(c) / float(max_c)
		var col: Color = b[2]
		# 柱体(HDR 亮色触发泛光, 0 次不画)
		if c > 0:
			draw_rect(Rect2(cx - bar_w / 2, inner.position.y + inner.size.y - h, bar_w, h), col)
		# 顶部数字
		draw_string(font, Vector2(cx - 30, inner.position.y + inner.size.y - h - 6), str(c),
			HORIZONTAL_ALIGNMENT_CENTER, 60.0, 15, Color(0.85, 0.95, 1.1, 0.95))
		# 底部标签
		draw_string(font, Vector2(cx - 30, inner.position.y + inner.size.y + 16), b[0],
			HORIZONTAL_ALIGNMENT_CENTER, 60.0, 14, Color(0.6, 0.72, 0.9, 0.9))
