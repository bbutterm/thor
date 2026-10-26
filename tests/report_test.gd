extends Node
## «Сообщить о лаге»: zip с логом фризов, сведениями о системе (и сохранением, если есть).
## godot --headless --path . res://tests/report_test.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var fails := 0
	Perf.mark("test_event")
	await get_tree().process_frame
	var path := Perf.report_lag()
	var ok := path != "" and FileAccess.file_exists(path)
	print("[%s] архив создан: %s" % ["OK" if ok else "FAIL", path])
	if not ok:
		fails += 1
	else:
		var z := ZIPReader.new()
		z.open(path)
		var files := z.get_files()
		var has := "system.txt" in files and "hitches.log" in files
		print("[%s] в архиве system.txt и hitches.log (%s)" % ["OK" if has else "FAIL", files])
		if not has:
			fails += 1
		var info := z.read_file("system.txt").get_string_from_utf8()
		var gpu := info.contains("Видеокарта:")
		print("[%s] сведения о системе" % ("OK" if gpu else "FAIL"))
		if not gpu:
			fails += 1
		z.close()
		DirAccess.remove_absolute(path)
	print("=== ИТОГ REPORT: %d FAIL ===" % fails)
	get_tree().quit(0 if fails == 0 else 1)
