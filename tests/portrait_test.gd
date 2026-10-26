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
	if Portrait.texture_path("brokk", "happy") != "":
		fails += 1
		print("  [FAIL] у Брокка арта нет — ожидалась заглушка")
	print("=== ИТОГ PORTRAITS: %d OK, %d FAIL ===" % [ok, fails])
	get_tree().quit(0 if fails == 0 else 1)
