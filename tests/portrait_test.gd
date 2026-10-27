extends Node
## Портреты из комплекта владельца: у каждого персонажа с артом находятся все 5 эмоций,
## нет эмоции — neutral, нет арта — процедурная заглушка (пустой путь).
## godot --headless --path . res://tests/portrait_test.tscn

func _ready() -> void:
	var fails := 0
	var ok := 0
	for sp in ["thor", "odin", "loki", "sif", "freya", "hild", "hel", "skadi", "heimdall", "jarl", "hugin", "munin"]:
		for emo in ["neutral", "happy", "angry", "shocked", "smug"]:
			var p := Portrait.texture_path(sp, emo)
			if p == "" or not p.contains(emo):
				fails += 1
				print("  [FAIL] нет портрета ", sp, " ", emo)
			else:
				ok += 1
		var emb := Portrait.texture_path(sp, "embarrassed")
		if not emb.contains("neutral"):
			fails += 1
			print("  [FAIL] нет запасного neutral для ", sp)
		var tex := load(Portrait.texture_path(sp, "neutral")) as Texture2D
		if tex == null or tex.get_height() > 1024:
			fails += 1
			print("  [FAIL] текстура не загрузилась или больше 1024 (сжатие при импорте): ", sp)
		if Portrait.face_of(sp).is_empty():
			fails += 1
			print("  [FAIL] нет точки лица для крупного плана: ", sp)
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
	print("=== ИТОГ PORTRAITS: %d OK, %d FAIL ===" % [ok, fails])
	get_tree().quit(0 if fails == 0 else 1)
