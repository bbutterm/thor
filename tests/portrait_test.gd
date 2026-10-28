extends Node
## Портреты из комплекта владельца: у каждого персонажа с артом находятся все 5 базовых эмоций,
## нет эмоции — neutral, нет арта — процедурная заглушка (пустой путь).
## godot --headless --path . res://tests/portrait_test.tscn

func _ready() -> void:
	var fails := 0
	var ok := 0
	for sp in ["thor", "odin", "loki", "sif", "freya", "hild", "hel", "skadi", "heimdall", "jarl", "hugin", "munin", "sven"]:
		for emo in ["neutral", "happy", "angry", "shocked", "smug"]:
			var p := Portrait.texture_path(sp, emo)
			if p == "" or not p.contains(emo):
				fails += 1
				print("  [FAIL] нет портрета ", sp, " ", emo)
			else:
				ok += 1
		var fallback := Portrait.texture_path(sp, "not_an_emotion")
		if not fallback.contains("neutral"):
			fails += 1
			print("  [FAIL] нет запасного neutral для ", sp)
		var tex := load(Portrait.texture_path(sp, "neutral")) as Texture2D
		if tex == null or tex.get_height() > 1024:
			fails += 1
			print("  [FAIL] текстура не загрузилась или больше 1024 (сжатие при импорте): ", sp)
		if Portrait.face_of(sp).is_empty():
			fails += 1
			print("  [FAIL] нет точки лица для крупного плана: ", sp)
	# Частая эмоция Тора раньше падала обратно на neutral; теперь своя и прогревается для боя.
	var thor_emb := Portrait.texture_path("thor", "embarrassed")
	var thor_tex := load(thor_emb) as Texture2D if thor_emb != "" else null
	var thor_img: Image = thor_tex.get_image() if thor_tex else null
	if not thor_emb.ends_with("thor_embarrassed.webp") or thor_tex == null or thor_tex.get_height() > 768 or thor_img == null or thor_img.get_pixel(0, 0).a > 0.01:
		fails += 1
		print("  [FAIL] портрет смущённого Тора не загрузился, велик или не прозрачен")
	else:
		ok += 1
	for emo in Portrait.EMOTIONS:
		var path := Portrait.texture_path("thor", emo)
		if path != "":
			load(path)
	Portrait.prefetch(PackedStringArray(["thor"]))
	if not thor_emb in Portrait.prefetched():
		fails += 1
		print("  [FAIL] смущённый Тор не прогрет для боя")
	else:
		ok += 1
	var warmup := ShaderWarmup.new()
	if not "thor" in warmup._room_speakers():
		fails += 1
		print("  [FAIL] Тор не включён в прогрев портретов зала")
	else:
		ok += 1
	warmup.free()
	Portrait.prefetch(PackedStringArray())
	# Смущённый Локи появляется в сценах, визитах, сделке и испытании.
	var loki_emb := Portrait.texture_path("loki", "embarrassed")
	var loki_tex := load(loki_emb) as Texture2D if loki_emb != "" else null
	var loki_img: Image = loki_tex.get_image() if loki_tex else null
	if not loki_emb.ends_with("loki_embarrassed.webp") or loki_tex == null or loki_tex.get_height() > 768 or loki_img == null or loki_img.get_pixel(0, 0).a > 0.01:
		fails += 1
		print("  [FAIL] портрет смущённого Локи не загрузился, велик или не прозрачен")
	else:
		ok += 1
	for emo in Portrait.EMOTIONS:
		var path := Portrait.texture_path("loki", emo)
		if path != "":
			load(path)
	Portrait.prefetch(PackedStringArray(["loki"]))
	if not loki_emb in Portrait.prefetched():
		fails += 1
		print("  [FAIL] смущённый Локи не прогрет")
	else:
		ok += 1
	Portrait.prefetch(PackedStringArray())
	# Портреты гномов сделаны для ларька; отсутствующие эмоции используют neutral.
	for pair in [["brokk", ["neutral", "happy", "angry", "shocked", "smug"]],
			["eitri", ["neutral", "happy", "embarrassed"]]]:
		var sp: String = pair[0]
		for emo in pair[1]:
			var path := Portrait.texture_path(sp, emo)
			var variant := load(path) as Texture2D if path != "" else null
			var img: Image = variant.get_image() if variant else null
			if not path.ends_with("%s_%s.webp" % [sp, emo]) or variant == null or variant.get_height() > 768 or img == null or img.get_pixel(0, 0).a > 0.01:
				fails += 1
				print("  [FAIL] портрет гнома не загрузился, велик или не прозрачен: ", sp, " ", emo)
			else:
				ok += 1
		var fallback := Portrait.texture_path(sp, "not_an_emotion")
		var tex := load(Portrait.texture_path(sp, "neutral")) as Texture2D
		if not fallback.ends_with("%s_neutral.webp" % sp) or tex == null or tex.get_height() > 768 or Portrait.face_of(sp).is_empty():
			fails += 1
			print("  [FAIL] запасной портрет, импорт или точка лица гнома: ", sp)
		else:
			ok += 1
	# Свен — отдельный персонаж, его эмоции больше не используют общий портрет драугров.
	for emo in ["neutral", "happy", "angry", "shocked", "smug"]:
		var path := Portrait.texture_path("sven", emo)
		var variant := load(path) as Texture2D if path != "" else null
		var img: Image = variant.get_image() if variant else null
		if not path.ends_with("sven_%s.webp" % emo) or variant == null or variant.get_height() > 768 or img == null or img.get_pixel(0, 0).a > 0.01:
			fails += 1
			print("  [FAIL] портрет Свена отсутствует, велик или не прозрачен: ", emo)
		else:
			ok += 1
	Portrait.prefetch(PackedStringArray(["sven"]))
	for emo in ["neutral", "happy", "angry", "shocked", "smug"]:
		if not Portrait.texture_path("sven", emo) in Portrait.prefetched():
			fails += 1
			print("  [FAIL] портрет Свена не прогрет для ", emo)
		else:
			ok += 1
	Portrait.prefetch(PackedStringArray())
	print("=== ИТОГ PORTRAITS: %d OK, %d FAIL ===" % [ok, fails])
	get_tree().quit(0 if fails == 0 else 1)
