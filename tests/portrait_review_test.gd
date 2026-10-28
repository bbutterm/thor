extends Node
## Проверка новых путей, импорта и прозрачности семи эмоций.
## Перед запуском скопировать эту пару .gd/.tscn в res://tests/ интеграционного worktree.

const CASES := [
	{"speaker": "sif", "emotion": "embarrassed", "file": "sif"},
	{"speaker": "eitri", "emotion": "smug", "file": "eitri"},
	{"speaker": "munin", "emotion": "embarrassed", "file": "hugin"},
	{"speaker": "skadi", "emotion": "embarrassed", "file": "skadi"},
	{"speaker": "hel", "emotion": "embarrassed", "file": "hel"},
	{"speaker": "hild", "emotion": "embarrassed", "file": "hild"},
	{"speaker": "brokk", "emotion": "embarrassed", "file": "brokk"},
]

var ok := 0
var fails := 0

func check(condition: bool, what: String) -> void:
	if condition:
		ok += 1
	else:
		fails += 1
		print("  [FAIL] ", what)

func _ready() -> void:
	for item: Dictionary in CASES:
		var speaker := str(item.speaker)
		var emotion := str(item.emotion)
		var expected := "res://sprites/portraits/%s_%s.webp" % [item.file, emotion]
		var path := Portrait.texture_path(speaker, emotion)
		check(path == expected, "%s/%s: ожидался %s, получен %s" % [speaker, emotion, expected, path])
		var fallback := "res://sprites/portraits/%s_neutral.webp" % item.file
		check(Portrait.texture_path(speaker, "not_an_emotion") == fallback, speaker + ": neutral-fallback")
		check(not Portrait.face_of(speaker).is_empty(), speaker + ": нет координат лица")
		var tex := load(path) as Texture2D if path == expected else null
		check(tex != null and tex.get_height() <= 768, speaker + ": импорт не загрузился или выше 768 px")
		var img: Image = tex.get_image() if tex else null
		if img == null or img.is_empty():
			check(false, speaker + ": не прочитан alpha-канал")
		else:
			var w := img.get_width() - 1
			var h := img.get_height() - 1
			var corners_clear := img.get_pixel(0, 0).a <= 0.01 and img.get_pixel(w, 0).a <= 0.01
			corners_clear = corners_clear and img.get_pixel(0, h).a <= 0.01 and img.get_pixel(w, h).a <= 0.01
			check(corners_clear, speaker + ": непрозрачный угол")
	Portrait.prefetch(PackedStringArray(["eitri", "hild", "munin"]))
	for speaker in ["eitri", "hild", "munin"]:
		var emotion := "smug" if speaker == "eitri" else "embarrassed"
		var path := Portrait.texture_path(speaker, emotion)
		check(path in Portrait.prefetched(), speaker + ": новая эмоция не подхвачена prefetch")
	check(Portrait.texture_path("munin", "embarrassed") == Portrait.texture_path("hugin", "embarrassed"), "Мунин и Хугин не используют общий файл")
	var hugin_face := Portrait.face_of("hugin")
	var munin_face := Portrait.face_of("munin")
	check(hugin_face.get("eye_center", []) == [380.0, 410.0], "центр лица Хугина должен быть [380, 410], получено %s" % str(hugin_face))
	check(munin_face.get("eye_center", []) == [730.0, 420.0], "центр лица Мунина должен быть [730, 420], получено %s" % str(munin_face))
	Portrait.prefetch(PackedStringArray())
	print("=== ИТОГ НОВЫХ ПОРТРЕТОВ: %d OK, %d FAIL ===" % [ok, fails])
	get_tree().quit(0 if fails == 0 else 1)
