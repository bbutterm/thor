extends Node
## Кадры диалогов с портретами (комплект владельца): Тор слева, собеседник справа, пузырь реплики.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/portrait_shots.tscn -- <папка>

var out_dir := "user://shots_portraits"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _run() -> void:
	var pairs := [["odin", "angry"], ["loki", "smug"], ["freya", "happy"], ["jarl", "shocked"], ["hugin", "neutral"], ["brokk", "happy"]]
	for i in pairs.size():
		var sp: String = pairs[i][0]
		Dialogue.play_lines([
			{"speaker": "thor", "emotion": "shocked", "text": "Кадр портретов: Тор слева."},
			{"speaker": sp, "emotion": pairs[i][1], "text": "А это %s справа, эмоция %s." % [sp, pairs[i][1]]},
		], "", "couch" if i % 2 == 0 else "run")
		await wait(0.8)
		var box := Dialogue.box()
		box.advance()
		await wait(0.2)
		box.advance()
		await wait(0.9)
		await shot("dlg_%02d_%s" % [i, sp])
		box.skip()
		await wait(0.4)
	Dialogue.bark({"speaker": "loki", "emotion": "smug", "text": "Пузырь в бою: крупный план лица."})
	await wait(0.8)
	await shot("bark_loki")
	get_tree().quit(0)
