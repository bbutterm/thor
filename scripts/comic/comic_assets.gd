extends RefCounted
class_name ComicAssets
## Данные и ресурсы слов: data/comic_words.json, общие материалы растра, шрифт, пул узлов слов, прогрев глифов.
## Компонент ComicWords (этап 5 рефакторинга): числа и состояние — поля ComicWords (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — ComicFX.assets; нужные снаружи функции есть и на ComicWords.

var cf: ComicWords

func _init(owner_node: ComicWords) -> void:
	cf = owner_node

func _load_data() -> void:
	var f := FileAccess.open(ComicWords.WORDS_PATH, FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				if parsed[k] is Dictionary:
					cf._data[k] = parsed[k]
	if cf._data.is_empty():
		push_warning("ComicFX: не прочитан %s" % ComicWords.WORDS_PATH)
		cf._data = {"slam": {"words": ["KA-BOOM!"], "priority": 60}}
	for ev in cf._data.keys():
		var path: String = ComicWords.SPRITE_DIR + ev + ".png"
		if ResourceLoader.exists(path):
			cf._textures[ev] = load(path)
	if ResourceLoader.exists(ComicWords.SPRITE_DIR + "burst.png"):
		cf._generic_texture = load(ComicWords.SPRITE_DIR + "burst.png")
	for i in ComicWords.KIT_BURST_COUNT:
		var kp := ComicWords.KIT_BURST_PATH % (i + 1)
		if ResourceLoader.exists(kp):
			cf._kit_bursts.append(load(kp))

func _build_resources() -> void:
	var font: Font = load(ComicWords.FONT_PATH)
	cf._ls = _label_settings(font, cf.font_size)
	cf._ls_big = _label_settings(font, cf.big_font_size)
	cf._text_mat = _halftone(false, cf.font_size * 1.2, 9.0)
	cf._text_mat_big = _halftone(false, cf.big_font_size * 1.2, 14.0)
	cf._burst_mat = _halftone(true, 1.0, 11.0)
	cf._kit_mat = ShaderMaterial.new()
	cf._kit_mat.shader = ComicWords.KIT_BURST
	cf._kit_mat.set_shader_parameter("tint_strength", cf.kit_tint_strength)

## Одна настройка трёх существующих материалов, без новых материалов на слово.
func set_room_halftone_multiplier(multiplier: float) -> void:
	var m := clampf(multiplier, 0.0, 2.0)
	if cf._text_mat:
		cf._text_mat.set_shader_parameter("dot_strength", clampf(0.22 * m, 0.0, 1.0))
	if cf._text_mat_big:
		cf._text_mat_big.set_shader_parameter("dot_strength", clampf(0.22 * m, 0.0, 1.0))
	if cf._burst_mat:
		cf._burst_mat.set_shader_parameter("dot_strength", clampf(0.4 * m, 0.0, 1.0))

func _label_settings(font: Font, size: int) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = Color.WHITE
	var k := float(size) / float(cf.font_size)
	ls.outline_size = int(round(cf.outline_px * k))
	ls.outline_color = Color.BLACK
	ls.shadow_size = int(round(cf.outline_px * k))
	ls.shadow_color = Color(0, 0, 0, 0.9)
	ls.shadow_offset = cf.shadow_offset * k
	return ls

func _halftone(radial: bool, text_height: float, spacing: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ComicWords.HALFTONE
	m.set_shader_parameter("radial", radial)
	m.set_shader_parameter("text_height", text_height)
	m.set_shader_parameter("dot_spacing", spacing)
	if radial:
		m.set_shader_parameter("dot_strength", 0.4)
		m.set_shader_parameter("highlight", 0.22)
	else:
		m.set_shader_parameter("dot_strength", 0.22)
		m.set_shader_parameter("highlight", 0.5)
		m.set_shader_parameter("dot_max", 0.34)
	return m

func _new_word() -> ComicWords.ComicWord:
	var w := ComicWords.ComicWord.new()
	w.visible = false
	w.shadow = Polygon2D.new()
	w.shadow.color = Color(0, 0, 0, 0.85)
	w.shadow.antialiased = true
	w.add_child(w.shadow)
	w.outline = Polygon2D.new()
	w.outline.color = Color.BLACK
	w.outline.antialiased = true
	w.add_child(w.outline)
	w.burst = Polygon2D.new()
	w.burst.material = cf._burst_mat
	w.burst.antialiased = true
	w.add_child(w.burst)
	w.sprite_shadow = Sprite2D.new()
	w.sprite_shadow.visible = false
	w.add_child(w.sprite_shadow)
	w.sprite = Sprite2D.new()
	w.sprite.visible = false
	w.add_child(w.sprite)
	w.label = Label.new()
	w.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	w.label.label_settings = cf._ls
	w.label.material = cf._text_mat
	w.add_child(w.label)
	cf._layer.add_child(w)
	return w

## Растеризация всех букв словаря в обоих размерах заранее: первый глиф шрифта на 160 px с обводкой —
## заметная работа CPU в кадре появления слова.
func _warm_glyphs() -> void:
	var chars := {}
	for ev in cf._data:
		for word in (cf._data[ev] as Dictionary).get("words", []):
			for ch in String(word):
				chars[ch] = true
	var text := "".join(PackedStringArray(chars.keys()))
	if cf._glyph_warm.is_empty():
		for big in [false, true]:
			var l := Label.new()
			l.label_settings = cf._ls_big if big else cf._ls
			l.material = cf._text_mat_big if big else cf._text_mat
			l.modulate = Color(1, 1, 1, 0.02)
			l.position = Vector2(0, 0)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cf._layer.add_child(l)
			cf._glyph_warm.append(l)
	for l in cf._glyph_warm:
		l.text = text
		l.visible = true
	cf._glyph_warm_frames = 4
