extends Node
## Проверка фактического фонового пути и доступности изображений с настоящим рендерером.

func _ready() -> void:
	var method := RenderingServer.get_current_rendering_method()
	print("RENDER PREFETCH: display=%s method=%s adapter=%s" % [DisplayServer.get_name(), method, RenderingServer.get_video_adapter_name()])
	AssetCache.finish()
	ScreenArt.prefetch_between_runs()
	var speakers := PackedStringArray(["odin", "thor", "sif", "loki", "freya", "hild", "hugin", "jarl"])
	Portrait.prefetch(speakers)
	var screen_pending := ScreenArt._requested.size()
	var portrait_pending := Portrait._pending.size()
	print("REQUESTS: screen=%d portrait=%d" % [screen_pending, portrait_pending])
	var body_path := ScreenArt.body_path("thrall")
	var body := ScreenArt.tex(body_path)
	var body_image: Image = body.get_image() if body else null
	Portrait.prefetch(speakers) # Дожидаемся всех запрошенных портретов.
	var portrait_path := Portrait.texture_path("odin", "smug")
	var portrait_tex := Portrait._held.get(portrait_path) as Texture2D
	var portrait_image: Image = portrait_tex.get_image() if portrait_tex else null
	print("BODY: %s size=%s image=%s" % [body_path, str(body.get_size()) if body else "none", str(body_image != null)])
	print("PORTRAIT: %s size=%s image=%s" % [portrait_path, str(portrait_tex.get_size()) if portrait_tex else "none", str(portrait_image != null)])
	var portrait := Portrait.new()
	add_child(portrait)
	portrait.set_speaker("odin", "smug", Dialogue.speakers.get("odin", {}), 0.0)
	var shown := portrait._tex_rect.texture != null
	portrait.free()
	var ok := DisplayServer.get_name() != "headless" and method == "gl_compatibility" and screen_pending > 0 and portrait_pending > 0
	ok = ok and body != null and body_image != null and body.get_width() > 0 and body.get_height() > 0
	ok = ok and portrait_tex != null and portrait_image != null and portrait_tex.get_width() > 0 and portrait_tex.get_height() > 0 and shown
	Portrait.prefetch(PackedStringArray())
	ScreenArt.shutdown()
	print("RENDER PREFETCH RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
