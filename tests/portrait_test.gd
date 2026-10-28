extends Node
## Портреты из комплекта владельца: у каждого персонажа с артом находятся все 5 базовых эмоций,
## нет эмоции — neutral, нет арта — процедурная заглушка (пустой путь).
## godot --headless --path . res://tests/portrait_test.tscn

class WarmupGameStub extends Node:
	var tutorial: Tutorial
	var room: Node

func _ready() -> void:
	var fails := 0
	var ok := 0
	var warmup_results := _test_room_speakers()
	ok += warmup_results[0]
	fails += warmup_results[1]
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
	# Два ворона на одном спрайте: для каждого нужен собственный центр лица.
	for bird in [["hugin", [380.0, 410.0]], ["munin", [730.0, 420.0]]]:
		if Portrait.face_of(bird[0]).get("eye_center", []) != bird[1]:
			fails += 1
			print("  [FAIL] неправильный центр лица ворона: ", bird[0])
		else:
			ok += 1
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
	# Ярл использует эту эмоцию перед боем, во второй фазе и после победы.
	var jarl_emb := Portrait.texture_path("jarl", "embarrassed")
	var jarl_tex := load(jarl_emb) as Texture2D if jarl_emb != "" else null
	var jarl_img: Image = jarl_tex.get_image() if jarl_tex else null
	if not jarl_emb.ends_with("jarl_embarrassed.webp") or jarl_tex == null or jarl_tex.get_height() > 768 or jarl_img == null or jarl_img.get_pixel(0, 0).a > 0.01:
		fails += 1
		print("  [FAIL] портрет смущённого Ярла не загрузился, велик или не прозрачен")
	else:
		ok += 1
	for emo in Portrait.EMOTIONS:
		var path := Portrait.texture_path("jarl", emo)
		if path != "":
			load(path)
	Portrait.prefetch(PackedStringArray(["jarl"]))
	if not jarl_emb in Portrait.prefetched():
		fails += 1
		print("  [FAIL] смущённый Ярл не прогрет")
	else:
		ok += 1
	Portrait.prefetch(PackedStringArray())
	# Портреты гномов сделаны для ларька; отсутствующие эмоции используют neutral.
	for pair in [["brokk", ["neutral", "happy", "angry", "shocked", "smug", "embarrassed"]],
			["eitri", ["neutral", "happy", "embarrassed", "smug"]]]:
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

## Изолированная проверка выбора реальных говорящих: reward, пул диалога и загрузка портрета.
func _test_room_speakers() -> Array[int]:
	var totals: Array[int] = [0, 0]
	var previous_rewards := Run.room_rewards.duplicate()
	var previous_order := Run.room_order.duplicate()
	var previous_index := Run.room_index
	var previous_minibosses := Run.miniboss_rooms.duplicate()
	Run.room_index = 0
	Run.room_order.assign(["res://rooms/room_01.tscn"])
	Run.room_rewards.assign(["anvil"])
	Run.miniboss_rooms = PackedInt32Array()
	var warmup := ShaderWarmup.new()

	# Эти данные реально использует RewardFlow._offer_anvil; имя пула отличается от имени говорящего.
	var lines := Dialogue.pool_lines("dwarves.eitri")
	_room_speaker_check(not lines.is_empty() and str(lines[0].get("speaker", "")) == "eitri",
		"реплика наковальни говорит голосом Эйтри", totals)
	var speakers := warmup._room_speakers()
	_room_speaker_check(speakers.size() == 2 and "thor" in speakers and "eitri" in speakers,
		"наковальня: прогреваются Тор и Эйтри", totals)
	Portrait.prefetch(speakers)
	for emotion in ["neutral", "happy", "embarrassed"]:
		var path := Portrait.texture_path("eitri", emotion)
		_room_speaker_check(path.ends_with("eitri_%s.webp" % emotion) and path in Portrait.prefetched(),
			"наковальня: портрет Эйтри %s запрошен" % emotion, totals)

	# Бой и остальные награды не должны держать портрет Эйтри; старые хозяева сохраняются.
	for pair in [["combat", ""], ["elite", ""], ["trial", ""],
			["rest", "odin"], ["loki", "loki"], ["freya", "freya"]]:
		Run.room_rewards[0] = pair[0]
		speakers = warmup._room_speakers()
		var host: String = pair[1]
		var expected_size := 1 if host == "" else 2
		_room_speaker_check(speakers.size() == expected_size and "thor" in speakers
			and not "eitri" in speakers and (host == "" or host in speakers),
			"награда %s: нужный ведущий без лишнего Эйтри" % pair[0], totals)
	Run.room_rewards[0] = "combat"
	Portrait.prefetch(warmup._room_speakers())
	_room_speaker_check(not Portrait.texture_path("eitri", "neutral") in Portrait.prefetched(),
		"после выхода из наковальни портрет Эйтри освобождён", totals)

	# Не ломаем ни стандартные, ни переопределённые пулы испытания при добавлении хозяина награды.
	var game := WarmupGameStub.new()
	var room := Node.new()
	game.room = room
	game.add_child(room)
	var trial := TrialRunner.new()
	trial.name = "Trial"
	trial.def = TrialDef.new()
	trial.def.host = "loki"
	room.add_child(trial)
	warmup.game_node = game
	speakers = warmup._room_speakers()
	_room_speaker_check(speakers.count("loki") == 1 and not "eitri" in speakers,
		"стандартные пулы Локи дают одного ведущего и не добавляют Эйтри", totals)
	trial.def.win_pool = "freya.blessing"
	trial.def.fail_pool = "hild.trial_fail"
	speakers = warmup._room_speakers()
	_room_speaker_check("loki" in speakers and "freya" in speakers and "hild" in speakers
		and not "eitri" in speakers, "стандартный и переопределённые пулы испытания прогреваются", totals)
	Run.room_rewards[0] = "anvil"
	speakers = warmup._room_speakers()
	_room_speaker_check("eitri" in speakers and "loki" in speakers and "freya" in speakers and "hild" in speakers,
		"ведущий наковальни не вытесняет ведущих пулов испытания", totals)

	warmup.free()
	game.free()
	Portrait.prefetch(PackedStringArray())
	Run.room_rewards.assign(previous_rewards)
	Run.room_order.assign(previous_order)
	Run.room_index = previous_index
	Run.miniboss_rooms = previous_minibosses
	return totals

func _room_speaker_check(condition: bool, description: String, totals: Array[int]) -> void:
	if condition:
		totals[0] += 1
		print("  [OK] ", description)
	else:
		totals[1] += 1
		print("  [FAIL] ", description)
