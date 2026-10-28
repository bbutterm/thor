extends Node
## Проверка доступности портретов и экранных картинок без фоновых запросов в Dummy.

var _fails: Array[String] = []
var _passes := 0

func check(ok: bool, message: String) -> void:
	if ok:
		_passes += 1
		print("  [OK] ", message)
	else:
		_fails.append(message)
		print("  [FAIL] ", message)

func _ready() -> void:
	print("=== HEADLESS PREFETCH TEST ===")
	check(DisplayServer.get_name() == "headless", "тест запущен с Dummy-рендерером")
	ScreenArt.shutdown()
	Portrait.prefetch(PackedStringArray())
	ScreenArt.prefetch_between_runs()
	check(ScreenArt._cache.is_empty() and ScreenArt._requested.is_empty(), "в headless предзагрузка после забега не читает изображения")
	var paths := [ScreenArt.backdrop_path("couch"), ScreenArt.body_path("thrall")]
	ScreenArt.prefetch(paths)
	check(ScreenArt._cache.is_empty() and ScreenArt._requested.is_empty(), "предзагрузка экранов не читает изображения и не запускает поток")
	for path in paths:
		var texture := ScreenArt.tex(path)
		check(path != "" and texture != null and texture.get_width() > 0 and texture.get_height() > 0,
			"картинка доступна по запросу: %s" % path)
		check(ScreenArt.tex(path) == texture, "картинка сохраняется в кеше: %s" % path)
	Portrait.prefetch(PackedStringArray(["odin"]))
	check(Portrait._pending.is_empty(), "предзагрузка портретов не оставляет фоновых запросов")
	for emotion in ["neutral", "smug"]:
		var path := Portrait.texture_path("odin", emotion)
		var texture: Texture2D = Portrait._held.get(path) as Texture2D
		check(path != "" and texture != null and texture.get_width() > 0 and texture.get_height() > 0,
			"портрет доступен после предзагрузки: %s" % emotion)
	var portrait := Portrait.new()
	add_child(portrait)
	portrait.set_speaker("odin", "smug", Dialogue.speakers.get("odin", {}), 0.0)
	check(portrait._tex_rect.texture != null, "портрет можно показать в интерфейсе")
	portrait.free()
	Portrait.prefetch(PackedStringArray())
	ScreenArt.shutdown()
	print("RESULT: %d OK / %d FAIL" % [_passes, _fails.size()])
	for failure in _fails:
		print("  FAIL: ", failure)
	get_tree().quit(1 if not _fails.is_empty() else 0)
