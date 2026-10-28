extends Node
## Звук владельца (блок Б6): файлы грузятся, слои музыки одной длины и в петле, подмена синтеза по
## data/owner_audio.json, озвучка реплик (клип есть, реплика есть, текст совпадает), один голос за раз,
## Odin.say и пузырь Тора играют клип.
## godot --headless --path . --fixed-fps 60 res://tests/audio_test.tscn

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  [OK] ", what)
	else:
		_fails.append(what)
		print("  [FAIL] ", what)

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame

func _owner_json() -> Dictionary:
	var f := FileAccess.open(Audio.OWNER_MAP, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}

func _run() -> void:
	print("=== AUDIO TEST ===")
	Music.auto = false
	var data := _owner_json()
	check(not data.is_empty(), "data/owner_audio.json читается")
	_check_sfx(data)
	await _check_sfx_play()
	_check_sfx_conditional_queue()
	await _check_music()
	_check_voice_data(data)
	await _check_voice_player()
	_finish()

# --- Эффекты ---

func _check_sfx(data: Dictionary) -> void:
	print("-- Эффекты")
	var sfx: Dictionary = data.get("sfx", {})
	var used := {}
	var missing: Array = []
	for k in sfx:
		var e: Variant = sfx[k]
		var file := str((e as Dictionary).get("file", k)) if e is Dictionary else str(e)
		var path := Audio.OWNER_SFX_DIR + file + ".ogg"
		used[file] = true
		if not ResourceLoader.exists(path) or not load(path) is AudioStreamOggVorbis:
			missing.append(path)
	check(missing.is_empty(), "все файлы владельца из карты есть и грузятся (%d записей) %s" % [sfx.size(), missing])
	var unused: Array = []
	var count := 0
	for f in ResourceLoader.list_directory(Audio.OWNER_SFX_DIR):
		if f.get_extension() == "ogg":
			count += 1
			if not used.has(f.get_basename()):
				unused.append(f)
	check(count >= 20 and unused.is_empty(), "все %d звуков владельца в карте (лишние: %s)" % [count, unused])
	var r := Audio.resolve("res://sounds/sfx/axe_swing_1.wav")
	check(str(r.path).ends_with("owner/sfx/axe_swing.ogg"), "синтез axe_swing_1 → файл владельца (%s)" % r.path)
	r = Audio.resolve("res://sounds/sfx/super_jump.wav")
	check(str(r.path) == "res://sounds/sfx/super_jump.wav", "звук без версии владельца — синтез (%s)" % r.path)
	for synth in ["axe_hit_1", "hammer_throw", "hammer_hit", "hammer_catch", "slam", "dash", "lightning", "crossbow_fire",
			"coin_pickup", "rune_pick", "door_open", "barrel_break"]:
		check(Audio.has_owner("sounds/sfx/%s.wav" % synth), "у «%s» есть версия владельца" % synth)
	for synth_only in ["super_jump", "perfect_catch", "player_hurt", "wall_splat", "gun_pistol", "trial_start"]:
		check(not Audio.has_owner(synth_only), "«%s» остаётся синтезом" % synth_only)
	# Синтез на месте (запасной вариант): make_sfx.py пишет в sounds/sfx/, не в sounds/owner/
	check(ResourceLoader.exists("res://sounds/sfx/axe_swing_1.wav"), "синтез-запаска axe_swing_1.wav на месте")

func _playing_with(suffix: String) -> AudioStreamPlayer:
	for c in Audio.get_children():
		var p := c as AudioStreamPlayer
		if p and p.bus == Audio.bus and p.stream and p.stream.resource_path.ends_with(suffix):
			return p
	return null

func _check_sfx_play() -> void:
	Audio.play("sounds/sfx/axe_swing_3.wav")
	await wait(0.05)
	var p := _playing_with("owner/sfx/axe_swing.ogg")
	check(p != null, "Audio.play(синтез) играет файл владельца")
	if p:
		check(p.pitch_scale > 0.84 * 0.89 and p.pitch_scale < 0.84 * 1.11, "pitch варианта из карты (%.2f)" % p.pitch_scale)
	Audio.sfx("critical_hit")
	await wait(0.05)
	check(_playing_with("owner/sfx/critical_hit.ogg") != null, "Audio.sfx: новое событие (крит) — звук владельца")
	Audio.sfx("нет_такого", "sounds/sfx/reflect.wav")
	await wait(0.05)
	check(_playing_with("sfx/reflect.wav") != null, "Audio.sfx: нет звука владельца — запасной путь")

func _check_sfx_conditional_queue() -> void:
	print("-- Очередь с ограниченным ожиданием")
	var was_processing := Audio.is_processing()
	Audio.set_process(false)
	Audio.queue.clear()
	Audio.available.clear()
	for n in Audio.get_children():
		if n is AudioStreamPlayer and n.bus == Audio.bus:
			n.stop()
			n.stream = null
			Audio.available.append(n)
	var one: AudioStreamPlayer = Audio.available[0]
	var two: AudioStreamPlayer = Audio.available[1]
	Audio.play("sounds/sfx/super_jump.wav")
	Audio.sfx_while("несуществующее_событие", "sounds/sfx/enemy_growl.wav", func() -> bool: return false)
	Audio.play("sounds/sfx/gun_pistol.wav")
	Audio._process(0.0)
	check(one.stream != null and one.stream.resource_path.ends_with("/super_jump.wav") and Audio.queue.size() == 2,
		"обычный звук сохранил FIFO и один запуск за кадр")
	Audio._process(0.0)
	check(two.stream != null and two.stream.resource_path.ends_with("/gun_pistol.wav") and Audio.queue.is_empty(),
		"устаревший сигнал пропущен, следующий обычный звук сохранил порядок")
	var original := {"path": "res://sounds/sfx/super_jump.wav", "pitch": 1.0, "db": 0.0, "min_interval": 0.0}
	Audio._owner_sfx["test_conditional_override"] = original
	Audio.sfx_while("test_conditional_override", "sounds/sfx/enemy_growl.wav", func() -> bool: return true)
	check(not original.has("_valid_while") and Audio.queue.size() == 1
		and Audio.queue[0].path == original.path,
		"событие использует вариант владельца, не изменяя общую карту")
	var three: AudioStreamPlayer = Audio.available[0]
	Audio._process(0.0)
	check(three.stream != null and three.stream.resource_path == original.path,
		"своевременный сигнал действительно воспроизводится")
	Audio._owner_sfx.erase("test_conditional_override")
	var origin := Node.new()
	var dead_condition: Callable = origin.is_inside_tree
	origin.free()
	var four: AudioStreamPlayer = Audio.available[0]
	Audio.sfx_while("несуществующее_событие", "sounds/sfx/enemy_growl.wav", dead_condition)
	Audio.play("sounds/sfx/gun_pistol.wav")
	Audio._process(0.0)
	check(four.stream != null and four.stream.resource_path.ends_with("/gun_pistol.wav") and Audio.queue.is_empty(),
		"сигнал удалённого источника пропущен без сбоя и задержки обычного звука")
	Audio.queue.clear()
	Audio.set_process(was_processing)

# --- Музыка ---

func _check_music() -> void:
	print("-- Музыка")
	for t in ["midgard", "jarl", "shop", "jotunheim", "helheim"]:
		check(Music.has_track(t) and Music.is_owner_track(t), "трек владельца «%s»" % t)
		var layers: Dictionary = Music._tracks.get(t, {})
		check(layers.size() == 3, "«%s»: три слоя base/drums/full" % t)
		var lens: Array = []
		var loops := true
		for l in Music.LAYERS:
			var s := layers.get(l) as AudioStreamOggVorbis
			if s == null:
				loops = false
				continue
			lens.append(s.get_length())
			loops = loops and s.loop
			var imp := FileAccess.get_file_as_string(Music.OWNER_MUSIC_DIR + t + "/" + l + ".ogg.import")
			if imp != "" and imp.find("loop=true") < 0:
				loops = false
		check(lens.size() == 3 and absf(lens.max() - lens.min()) < 0.002 and lens[0] > 29.0, "«%s»: слои одной длины %s" % [t, lens])
		check(loops, "«%s»: петля включена (и в .import)" % t)
	for t in ["menu", "plan", "miniboss", "boss"]:
		check(Music.has_track(t) and not Music.is_owner_track(t), "«%s» — синтез (у владельца нет)" % t)
	check(Music._stinger.stream != null, "стингер — синтез")
	check(is_equal_approx(60.0 / Music._beat_len(), 120.0) or Music.current_track != "jarl", "темп трека по умолчанию")
	Music.play_track("jarl", true)
	await wait(0.1)
	check(absf(60.0 / Music._beat_len() - 125.0) < 0.01, "темп Ярла из data/owner_audio.json (%.0f BPM)" % (60.0 / Music._beat_len()))
	Music.set_intensity(0)
	await wait(1.2)
	var sync := Music._player.stream as AudioStreamSynchronized
	check(sync != null and sync.get_sync_stream_volume(0) > -1.0 and sync.get_sync_stream_volume(1) < -60.0, "фон — только base")
	Music.set_intensity(1)
	# Середина перекрёстной смены: сумма амплитуд ≈ 1 (слои в фазе — без провала)
	var min_sum := 2.0
	var max_sum := 0.0
	for i in 120:
		await get_tree().process_frame
		var a := 0.0
		for k in 3:
			a += Music._amp(sync.get_sync_stream_volume(k))
		min_sum = minf(min_sum, a)
		max_sum = maxf(max_sum, a)
	check(min_sum > 0.95 and max_sum < 1.05, "перекрёстная смена слоёв без провала (сумма %.2f…%.2f)" % [min_sum, max_sum])
	check(sync.get_sync_stream_volume(1) > -1.0 and sync.get_sync_stream_volume(0) < -60.0, "бой — drums вместо base (слои не складываются)")
	Music.set_intensity(2)
	await wait(1.6)
	check(sync.get_sync_stream_volume(2) > -1.0 and sync.get_sync_stream_volume(1) < -60.0, "Ярость — full")
	Music.set_intensity(0)
	Music.play_track("", true)

# --- Голос ---

func _all_lines() -> Array:
	var out: Array = []
	var walk := func(lines: Array, self_ref: Callable) -> void:
		for l in lines:
			if l is Dictionary:
				out.append(l)
				for ch in (l as Dictionary).get("choices", []):
					self_ref.call(ch.get("lines", []), self_ref)
	for sc in Dialogue.scenes:
		walk.call(sc.get("lines", []), walk)
	for p in Dialogue.pools:
		for it in Dialogue.pools[p]:
			walk.call(it.lines, walk)
	return out

func _norm(t: String) -> String:
	return t.to_lower().replace("ё", "е").replace("…", "...").strip_edges()

func _check_voice_data(data: Dictionary) -> void:
	print("-- Голос: данные")
	var clips: Dictionary = data.get("voice", {})
	check(clips.size() == 24, "в каталоге 24 клипа (%d)" % clips.size())
	var bad_files: Array = []
	for c in clips:
		var p := Audio.voice_path(str(c))
		if p == "" or not load(p) is AudioStreamOggVorbis:
			bad_files.append(c)
	check(bad_files.is_empty(), "все клипы каталога есть в sounds/voice/ и грузятся %s" % [bad_files])
	var used := {}
	var bad_refs: Array = []
	var voiced := 0
	for l in _all_lines():
		if not l.has("voice"):
			continue
		voiced += 1
		var ids: Array = l.voice if l.voice is Array else [l.voice]
		for v in ids:
			var c: Dictionary = clips.get(str(v), {})
			used[str(v)] = true
			if c.is_empty():
				bad_refs.append("%s: нет клипа %s" % [l.get("id", "?"), v])
			elif _norm(str(l.get("text", ""))).find(_norm(str(c.get("text", "")))) < 0:
				bad_refs.append("%s: «%s» ≠ клип «%s»" % [l.get("id", "?"), l.get("text", ""), c.get("text", "")])
			elif str(c.get("speaker", "")) != str(l.get("speaker", "")):
				bad_refs.append("%s: говорит %s, клип %s" % [l.get("id", "?"), l.get("speaker", ""), c.get("speaker", "")])
	check(bad_refs.is_empty(), "каждая озвученная реплика (%d) — клип каталога, текст и говорящий совпадают %s" % [voiced, bad_refs])
	var unused: Array = []
	for c in clips:
		if not used.has(c) and not (clips[c] as Dictionary).has("effort"):
			unused.append(c)
	check(unused.is_empty(), "каждый клип озвучивает хотя бы одну реплику (кроме кряхтения) %s" % [unused])
	var errs := Dialogue.validate()
	check(errs.is_empty(), "Dialogue.validate без ошибок (в т. ч. ссылки на клипы) %s" % [errs.slice(0, 5)])

func _voice_players_playing() -> int:
	var n := 0
	for c in Audio.get_children():
		var p := c as AudioStreamPlayer
		if p and p.bus == Audio.voice_bus and p.playing:
			n += 1
	return n

func _check_voice_player() -> void:
	print("-- Голос: плеер")
	check(AudioServer.get_bus_index("Voice") >= 0, "шина Voice есть")
	Audio.stop_voice()
	check(Audio.voice("odin_skuf", Audio.VOICE_BARK), "клип играет")
	check(not Audio.voice("thor_rrra", Audio.VOICE_BARK), "второй пузырь, пока звучит голос, — без озвучки")
	check(not Audio.voice("thor_grunt_hha", Audio.VOICE_EFFORT), "кряхтение не перебивает реплику")
	check(Audio.current_voice() == "odin_skuf" and _voice_players_playing() == 1, "звучит один голос (%s)" % Audio.current_voice())
	check(Audio.voice("thor_rrra", Audio.VOICE_SCENE), "реплика новеллы перебивает")
	check(Audio.voice("thor_kto_tut_skuf", Audio.VOICE_SCENE) and Audio.current_voice() == "thor_kto_tut_skuf", "следующая реплика новеллы перебивает предыдущую")
	check(_voice_players_playing() == 1, "голоса не накладываются (%d)" % _voice_players_playing())
	Audio.stop_voice()
	# Кряхтение: шанс 1 — звучит, второй раз — кулдаун; «Ух!» не перебивает «Хха!»
	var chance := Audio.grunt_chance
	Audio.grunt_chance = 1.0
	Audio._next_grunt = 0.0
	Audio.thor_grunt()
	check(Audio.current_voice() == "thor_grunt_hha", "«Хха!» на сильном ударе")
	Audio.stop_voice()
	Audio.thor_grunt()
	check(Audio.current_voice() == "", "«Хха!» — кулдаун, не спамит")
	Audio.grunt_chance = chance
	var pc := Audio.pain_chance
	Audio.pain_chance = 1.0
	Audio._next_pain = 0.0
	Audio.thor_pain()
	check(Audio.current_voice() == "thor_pain_uh", "«Ух!» при уроне")
	Audio.pain_chance = pc
	# Пузырь перебивает кряхтение
	Dialogue.bark({"speaker": "thor", "emotion": "angry", "text": "РРРА!", "id": "test", "voice": "thor_rrra"})
	check(Audio.current_voice() == "thor_rrra", "пузырь Тора с полем voice — клип (перебил «Ух!»)")
	Audio.stop_voice()
	Odin.reset_cooldown()
	var text := Odin.say("room_clear_clean")
	check(text == "Достойно!" and Audio.current_voice() == "odin_dostoyno", "Odin.say: реплика с клипом озвучена («%s», %s)" % [text, Audio.current_voice()])
	Audio.stop_voice()
	Odin.reset_cooldown()
	text = Odin.say("idle")
	var want := {"ДВИГАЙСЯ!": ["odin_dvigaysya"], "Это не диван! ШЕВЕЛИСЬ!": ["odin_eto_ne_divan_a", "odin_eto_ne_divan_b"]}
	if want.has(text):
		check(Audio.current_voice() in want[text], "Odin.say(idle): «%s» — %s" % [text, Audio.current_voice()])
	else:
		check(Audio.current_voice() == "", "Odin.say(idle): реплика без клипа — тишина («%s»)" % text)
	Audio.stop_voice()
	# Свисток Одина (поле sfx реплики)
	Dialogue.speak_line({"text": "Свисток! Бегом, бегом, бегом!", "voice": "odin_begom", "sfx": "coach_whistle"}, Audio.VOICE_BARK)
	await wait(0.05)
	check(_playing_with("owner/sfx/coach_whistle.ogg") != null and Audio.current_voice() == "odin_begom", "«Свисток! Бегом…» — свисток и голос")
	Audio.stop_voice()

func _finish() -> void:
	print("=== ИТОГ AUDIO: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	# Отпускаем потоки и даём AudioServer убрать воспроизведения — иначе «resources still in use at exit»
	for c in Audio.get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null
	Audio.stop_voice()
	await wait(0.1)
	get_tree().quit(0 if _fails.is_empty() else 1)
