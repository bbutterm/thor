extends Node

# Code adapted from KidsCanCode
## Автозагрузка «Audio» — звуки (пул плееров на шине SFX) и голос (один плеер на шине Voice).
## Звуки владельца (ElevenLabs, блок Б6) — data/owner_audio.json:
##   "sfx": имя синтезированного звука (без пути и расширения) или новое имя события → файл
##   sounds/owner/sfx/<file>.ogg (+ необязательно pitch, db, min_interval). play() сам подменяет синтез
##   на файл владельца; нет файла — играет синтез. Новые события без синтеза — sfx(id, запасной путь).
##   "voice": клип sounds/voice/<id>.ogg → кто говорит и что (текст). Реплика диалога с полем "voice"
##   озвучивается при показе (Dialogue.speak_line); одновременно звучит только один голос.
## Синтез (tools/make_sfx.py) пишет только в sounds/sfx/ и sounds/music/ — файлы владельца не трогает.

const OWNER_MAP := "res://data/owner_audio.json"
const OWNER_SFX_DIR := "res://sounds/owner/sfx/"
const VOICE_DIR := "res://sounds/voice/"
## Приоритеты голоса (один голос за раз): выше — перебивает, ниже или равный — пропускается;
## исключение — реплики окна новеллы: следующая реплика перебивает предыдущую
const VOICE_EFFORT := 0  # кряхтение Тора
const VOICE_BARK := 1  # пузырь, Odin.say
const VOICE_SCENE := 2  # окно новеллы

var num_players = 12
## Шина эффектов (громкость — GameSettings [audio] sfx; шину создаёт GameSettings.bus_index)
var bus = "SFX"
## Шина голоса (GameSettings [audio] voice)
var voice_bus := "Voice"
## Громкость голоса на плеере (дБ); клипы нормализованы к −16 LUFS, как музыка, — шина Music тише на 6 дБ
@export var voice_volume_db: float = 0.0
## Кряхтение Тора «Хха!» на сильном ударе и ударе-приземлении: шанс и кулдаун (с)
@export var grunt_chance: float = 0.3
@export var grunt_cooldown: float = 6.0
## «Ух!» Тора при получении урона: шанс и кулдаун (с)
@export var pain_chance: float = 0.6
@export var pain_cooldown: float = 4.0

var available = []  # The available players.
var queue = []  # The queue of sounds to play.

## Имя звука → {path, pitch, db, min_interval}
var _owner_sfx: Dictionary = {}
## Клип голоса → {speaker, text}
var voice_clips: Dictionary = {}
## Темп петель владельца: трек → {bpm}
var owner_music: Dictionary = {}
var _last_played: Dictionary = {}
var _voice: AudioStreamPlayer
var _voice_priority: int = -1
var _voice_clip: String = ""
var _next_grunt: float = 0.0
var _next_pain: float = 0.0

func _ready():
	GameSettings.bus_index(bus)
	GameSettings.bus_index(voice_bus)
	for i in num_players:
		var p = AudioStreamPlayer.new()
		add_child(p)

		available.append(p)

		p.volume_db = -10
		p.finished.connect(_on_stream_finished.bind(p))
		p.bus = bus
	# Голос звучит и на паузе (сцены-новеллы ставят дерево на паузу)
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = voice_bus
	_voice.volume_db = voice_volume_db
	_voice.process_mode = Node.PROCESS_MODE_ALWAYS
	_voice.finished.connect(stop_voice)
	add_child(_voice)
	load_owner_map()

## Читает data/owner_audio.json (тесты зовут повторно).
func load_owner_map() -> void:
	_owner_sfx.clear()
	voice_clips.clear()
	owner_music.clear()
	var f := FileAccess.open(OWNER_MAP, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		push_warning("Audio: не разобрать %s" % OWNER_MAP)
		return
	var sfx: Dictionary = (d as Dictionary).get("sfx", {})
	for k in sfx:
		var e: Variant = sfx[k]
		var entry: Dictionary = e if e is Dictionary else {"file": str(e)}
		var path: String = OWNER_SFX_DIR + str(entry.get("file", k)) + ".ogg"
		if not ResourceLoader.exists(path):
			continue
		_owner_sfx[str(k)] = {"path": path, "pitch": float(entry.get("pitch", 1.0)), "db": float(entry.get("db", 0.0)),
			"min_interval": float(entry.get("min_interval", 0.0))}
	voice_clips = (d as Dictionary).get("voice", {})
	owner_music = (d as Dictionary).get("music", {})

func _on_stream_finished(stream):
	available.append(stream)

## Звук по пути (или нескольким через запятую — случайный). Синтез с версией владельца — подменяется.
func play(sound_path):  # Path (or multiple, separated by commas)
	var sounds = sound_path.split(",")
	queue.append(resolve("res://" + sounds[randi() % sounds.size()].strip_edges()))

## Звук владельца по имени события (data/owner_audio.json); нет его — запасной путь (можно пустой).
func sfx(id: String, fallback: String = "") -> void:
	if _owner_sfx.has(id):
		queue.append(_owner_sfx[id])
	elif fallback != "":
		play(fallback)

## Сигнал, который имеет смысл только пока valid() истинна (например, предупреждение до атаки).
## Обычный порядок очереди и общий лимит плееров сохраняются; устаревший сигнал пропускается.
func sfx_while(id: String, fallback: String, valid: Callable) -> void:
	var before := queue.size()
	sfx(id, fallback)
	if queue.size() > before:
		var entry: Dictionary = queue[-1].duplicate()  # не изменяем общую карту звуков владельца
		entry["_valid_while"] = valid
		queue[-1] = entry

## Есть ли у звука (имя или путь) версия владельца.
func has_owner(name_or_path: String) -> bool:
	return _owner_sfx.has(name_or_path.get_file().get_basename())

## Путь → что играть: {path, pitch, db, min_interval} (версия владельца или сам путь).
func resolve(path: String) -> Dictionary:
	var key := path.get_file().get_basename()
	if _owner_sfx.has(key):
		return _owner_sfx[key]
	return {"path": path, "pitch": 1.0, "db": 0.0, "min_interval": 0.0}

## Один звук за кадр (как было); пропущенные по min_interval и без файла — не считаются
func _process(_delta):
	while not queue.is_empty() and not available.is_empty():
		var item: Variant = queue.pop_front()
		var e: Dictionary = item if item is Dictionary else resolve(str(item))
		if e.has("_valid_while"):
			var valid: Callable = e["_valid_while"]
			if not valid.is_valid() or not valid.call():
				continue
		var path: String = e.path
		var now := Time.get_ticks_msec() / 1000.0
		if float(e.min_interval) > 0.0 and now - float(_last_played.get(path, -100.0)) < float(e.min_interval):
			continue
		if not ResourceLoader.exists(path):
			continue
		_last_played[path] = now
		Perf.mark("sfx:" + path.get_file())
		var p: AudioStreamPlayer = available.pop_front()
		p.stream = load(path)
		p.volume_db = -10.0 + float(e.db)
		p.play()
		p.pitch_scale = randf_range(0.9, 1.1) * float(e.pitch)
		break

# --- Голос (шина Voice) ---

## Путь клипа голоса (sounds/voice/<id>.ogg) или пусто.
func voice_path(clip: String) -> String:
	var p := VOICE_DIR + clip + ".ogg"
	return p if ResourceLoader.exists(p) else ""

## Сыграть клип (id или массив id — случайный дубль). Один голос за раз: новый с приоритетом выше
## текущего перебивает его, ниже или равный — пропускается (реплики новеллы сменяют друг друга).
## Возвращает true, если заиграл.
func voice(clip: Variant, priority: int = VOICE_BARK) -> bool:
	var id := ""
	if clip is Array:
		var arr: Array = clip
		if arr.is_empty():
			return false
		id = str(arr[randi() % arr.size()])
	else:
		id = str(clip)
	var path := voice_path(id)
	if path == "":
		return false
	if _voice.playing and (priority < _voice_priority or (priority == _voice_priority and priority < VOICE_SCENE)):
		return false
	_voice.stop()
	_voice.stream = load(path)
	_voice.volume_db = voice_volume_db
	_voice.play()
	_voice_priority = priority
	_voice_clip = id
	Perf.mark("voice:" + id)
	return true

func is_voice_playing() -> bool:
	return _voice.playing

## Какой клип голоса звучит (пусто — тишина).
func current_voice() -> String:
	return _voice_clip if _voice.playing else ""

func stop_voice() -> void:
	_voice.stop()
	_voice_priority = -1
	_voice_clip = ""

## «Хха!» Тора (сильный удар, удар-приземление): редко и с кулдауном, реплики не перебивает.
func thor_grunt() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_grunt or randf() > grunt_chance:
		return
	if voice("thor_grunt_hha", VOICE_EFFORT):
		_next_grunt = now + grunt_cooldown

## «Ух!» Тора при уроне: с кулдауном, реплики не перебивает.
func thor_pain() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_pain or randf() > pain_chance:
		return
	if voice("thor_pain_uh", VOICE_EFFORT):
		_next_pain = now + pain_cooldown

## Останавливаем все звуки при выходе: висящие воспроизведения на выходе изредка роняли
## headless-тесты (abort уже после «ИТОГ ... 0 FAIL»)
func _exit_tree():
	queue.clear()
	for p in get_children():
		if p is AudioStreamPlayer:
			p.stop()
			p.stream = null
