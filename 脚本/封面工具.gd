class_name CoverUtil
## mp3 内嵌专辑封面提取（ID3v2 APIC）— GDScript 实现, 运行时可用, 无需导入资源

static func extract_image(mp3_path: String) -> Image:
	var buf := FileAccess.get_file_as_bytes(mp3_path)
	if buf.size() < 20:
		return null
	if buf.slice(0, 3) != "ID3".to_utf8_buffer():
		return null
	var ver := buf[3]  # 3=v2.3(帧长普通int32) 4=v2.4(帧长syncsafe)
	var tag_size := (buf[6] << 21) | (buf[7] << 14) | (buf[8] << 7) | buf[9]
	var pos := 10
	var end: int = mini(10 + tag_size, buf.size() - 1)

	while pos < end - 10:
		var fid := buf.slice(pos, pos + 4)
		var c0 := fid[0]
		if c0 < 0x41 or c0 > 0x5A:  # 帧ID须为 A-Z 开头, 否则已到 padding
			break
		var fsize := 0
		if ver >= 4:
			fsize = (buf[pos + 4] << 21) | (buf[pos + 5] << 14) | (buf[pos + 6] << 7) | buf[pos + 7]
		else:
			fsize = (buf[pos + 4] << 24) | (buf[pos + 5] << 16) | (buf[pos + 6] << 8) | buf[pos + 7]
		if fsize <= 0 or pos + 10 + fsize > buf.size():
			break
		if fid == "APIC".to_utf8_buffer():
			return _decode_apic(buf.slice(pos + 10, pos + 10 + fsize))
		pos += 10 + fsize
	return null


static func _decode_apic(frame: PackedByteArray) -> Image:
	if frame.size() < 10:
		return null
	var enc := frame[0]
	var nul := frame.find(0, 1)
	if nul < 0:
		return null
	var p := nul + 1 + 1  # 跳过 mime 结尾 NUL + 图片类型字节
	if enc == 1 or enc == 2:  # UTF-16 描述符
		while p < frame.size() - 1 and not (frame[p] == 0 and frame[p + 1] == 0):
			p += 2
		p += 2
	else:
		var d_nul := frame.find(0, p)
		if d_nul < 0:
			return null
		p = d_nul + 1
	var img_data := frame.slice(p)
	if img_data.size() < 10:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if img_data[0] == 0xFF and img_data[1] == 0xD8:
		err = img.load_jpg_from_buffer(img_data)
	elif img_data.slice(0, 4) == PackedByteArray([0x89, 0x50, 0x4E, 0x47]):
		err = img.load_png_from_buffer(img_data)
	return img if err == OK else null


## 提取并保存为 资源/<歌名>.png（存在则跳过）
static func extract_and_save(mp3_path: String, png_path: String) -> bool:
	if FileAccess.file_exists(png_path):
		return true
	var img := extract_image(mp3_path)
	if img == null:
		return false
	return img.save_png(png_path) == OK


## 运行时直接取纹理（不经过资源导入系统）
static func get_texture(mp3_path: String) -> ImageTexture:
	var img := extract_image(mp3_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)
