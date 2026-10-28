extends Node
## «Сообщить о лаге»: zip с логом фризов, сведениями о системе (и сохранением, если есть).
## godot --headless --path . res://tests/report_test.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var fails := _test_engine_logs()
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


func _fixture_write(path: String, bytes: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true

func _fixture_check(failures: Array[String], ok: bool, text: String) -> void:
	print("[%s] %s" % ["OK" if ok else "FAIL", text])
	if not ok:
		failures.append(text)

func _test_engine_logs() -> int:
	var failures: Array[String] = []
	var temp := DirAccess.create_temp("thor-report-logs")
	if temp == null:
		print("[FAIL] временная папка для проверки журналов")
		return 1
	var root := temp.get_current_dir()
	var logs := root.path_join("logs")
	_fixture_check(failures, temp.make_dir("logs") == OK, "изолированная папка журналов")
	_fixture_check(failures, Perf._engine_log_fragments(root.path_join("absent")).is_empty(), "отсутствующие журналы безопасно пропускаются")
	var current := ("PRIVATE_PREFIX_" + "x".repeat(Perf.ENGINE_LOG_MAX_BYTES) + "_CURRENT_END").to_utf8_buffer()
	var previous := ("PRIVATE_PREVIOUS_PREFIX_" + "y".repeat(Perf.ENGINE_LOG_MAX_BYTES) + "_PREVIOUS_END").to_utf8_buffer()
	var previous_tail := previous.slice(previous.size() - Perf.ENGINE_LOG_MAX_BYTES)
	var fixtures := {
		"godot.log": current,
		"godot2026-10-27T11.05.06.log": "OLDER_UNRELATED".to_utf8_buffer(),
		"godot2026-10-28T09.17.05.log": previous,
		"godot2099-10-28T09.17.05.log.backup": "UNRELATED_SECRET".to_utf8_buffer(),
		"private.log": "UNRELATED_SECRET".to_utf8_buffer(),
	}
	for name in fixtures:
		_fixture_check(failures, _fixture_write(logs.path_join(name), fixtures[name]), "создана тестовая фикстура %s" % name)
	# Ссылка с более поздней датой должна быть проигнорирована; если Windows
	# запрещает создание ссылок без прав, отдельный Linux-прогон проверяет путь.
	var secret := root.path_join("private.txt")
	_fixture_check(failures, _fixture_write(secret, "SYMLINK_SECRET".to_utf8_buffer()), "тестовый файл вне папки журналов")
	var log_dir := DirAccess.open(logs)
	var linked_name := "godot2099-10-28T09.17.05.log"
	var linked := log_dir.create_link(secret, logs.path_join(linked_name)) == OK
	# Некоторые реализации (в частности Wine) сообщают OK, но не создают
	# ссылку. Выполняем проверку только для действительно видимой ссылки.
	var link_visible := linked_name in log_dir.get_files() or log_dir.is_link(linked_name) or FileAccess.file_exists(logs.path_join(linked_name))
	var got: Dictionary = Perf._engine_log_fragments(logs)
	var tail: PackedByteArray = got.get("godot-current.log", PackedByteArray())
	var older: PackedByteArray = got.get("godot-previous.log", PackedByteArray())
	_fixture_check(failures, got.size() == 2 and tail.size() == Perf.ENGINE_LOG_MAX_BYTES
		and tail.get_string_from_utf8().ends_with("_CURRENT_END") and not tail.get_string_from_utf8().contains("PRIVATE_PREFIX_"),
		"текущий журнал ограничен последними 256 КиБ")
	_fixture_check(failures, older == previous_tail and older.size() == Perf.ENGINE_LOG_MAX_BYTES, "предыдущий журнал выбран по штатному имени и ограничен последними 256 КиБ")
	if linked and link_visible:
		_fixture_check(failures, older != "SYMLINK_SECRET".to_utf8_buffer(), "символическая ссылка вместо журнала не читается")
	else:
		print("[SKIP] проверка ссылки: ОС не создала видимую ссылку")
	var linked_dir := root.path_join("linked-logs")
	var linked_dir_created := temp.create_link(logs, linked_dir) == OK
	var linked_dir_visible := "linked-logs" in temp.get_directories() or temp.is_link("linked-logs") or DirAccess.dir_exists_absolute(linked_dir)
	if linked_dir_created and linked_dir_visible:
		_fixture_check(failures, Perf._engine_log_fragments(linked_dir).is_empty(), "символическая ссылка вместо папки не читается")
	else:
		print("[SKIP] проверка ссылки на папку: ОС не создала видимую ссылку")
	var windows_path := "C:/Users/Test/logs/godot.log"
	_fixture_check(failures, Perf._windows_resolved_path_matches(windows_path, "c:\\users\\TEST\\logs\\godot.log"), "пути Windows сравниваются без учёта регистра и разделителей")
	_fixture_check(failures, not Perf._windows_resolved_path_matches(windows_path, ""), "пустой разрешённый путь безопасно отклоняется")
	_fixture_check(failures, not Perf._windows_resolved_path_matches(windows_path, "\\\\?\\C:\\Users\\Test\\logs\\godot.log"), "ошибка read_link безопасно отклоняется")
	_fixture_check(failures, not Perf._windows_resolved_path_matches(windows_path, "C:/outside/secret.txt"), "другой конечный путь безопасно отклоняется")
	# Если запуск явно ведёт журнал в другое место, старый godot.log не
	# помечается как текущий. Дату можно подменить порогом без изменения файла.
	var stale: Dictionary = Perf._engine_log_fragments(logs, Time.get_unix_time_from_system() + 60.0)
	_fixture_check(failures, not stale.has("godot-current.log") and stale.get("godot-previous.log", PackedByteArray()) == previous_tail,
		"старый текущий файл не выдаётся за журнал активного запуска")
	var empty_dir := root.path_join("empty-logs")
	_fixture_check(failures, temp.make_dir("empty-logs") == OK and _fixture_write(empty_dir.path_join("godot.log"), PackedByteArray()), "создан пустой текущий журнал")
	var empty: Dictionary = Perf._engine_log_fragments(empty_dir)
	_fixture_check(failures, empty.has("godot-current.log") and (empty["godot-current.log"] as PackedByteArray).is_empty(), "пустой буферизированный журнал допустим")
	# Повреждённый или бинарный журнал переносится как байты, без разбора текста.
	var binary_dir := root.path_join("binary-logs")
	var binary := PackedByteArray([255, 0, 254, 128, 65])
	_fixture_check(failures, temp.make_dir("binary-logs") == OK and _fixture_write(binary_dir.path_join("godot.log"), binary), "создан двоичный тестовый журнал")
	var binary_result: Dictionary = Perf._engine_log_fragments(binary_dir)
	_fixture_check(failures, binary_result.get("godot-current.log", PackedByteArray()) == binary, "повреждённый журнал переносится как байты")
	# Штатная ротация хранит не больше нескольких файлов. Переполненный
	# каталог пропускается, даже если в нём есть файл с правильным именем.
	var busy_dir := root.path_join("busy-logs")
	var busy_ok := temp.make_dir("busy-logs") == OK and _fixture_write(busy_dir.path_join("godot.log"), "unexpected".to_utf8_buffer())
	for i in Perf.ENGINE_LOG_SCAN_LIMIT:
		busy_ok = _fixture_write(busy_dir.path_join("entry_%04d.txt" % i), PackedByteArray()) and busy_ok
	_fixture_check(failures, busy_ok and Perf._engine_log_fragments(busy_dir).is_empty(), "очень большая папка безопасно пропущена")
	var archive := root.path_join("fixture.zip")
	var writer := ZIPPacker.new()
	var write_ok: bool = writer.open(archive) == OK and Perf._append_engine_logs(writer, logs)
	if writer.close() != OK:
		write_ok = false
	var reader := ZIPReader.new()
	if reader.open(archive) != OK:
		write_ok = false
	else:
		var names := reader.get_files()
		write_ok = write_ok and names.size() == 2 and "godot-current.log" in names and "godot-previous.log" in names \
			and reader.read_file("godot-current.log") == tail and reader.read_file("godot-previous.log") == previous_tail
		reader.close()
	_fixture_check(failures, write_ok, "ZIP содержит только два ограниченных журнала с фиксированными именами")
	return failures.size()
