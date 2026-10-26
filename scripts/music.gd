extends Node
## Автозагрузка «Music» — адаптивная музыка по GDD 21.
## Трек — папка sounds/music/<трек>/ со слоями base / drums / full (.ogg или .wav одной длины, петли).
## Слои играют синхронно (AudioStreamSynchronized), громкость слоёв меняется на ближайшей доле,
## трек — на ближайшем такте. Пауза, диалог и смерть — фильтр низких частот на шине Music.
## Удар-приземление с высоты — стингер и провал музыки на время hit-stop.
## Положить настоящие треки: те же имена файлов — код не меняется.

const MUSIC_DIR := "res://sounds/music/"
const LAYERS := ["base", "drums", "full"]
const BUS := "Music"

## Темп всех петель (нужен для переходов в такт)
@export var bpm: float = 120.0
@export var beats_per_bar: int = 4
## Громкость шины Music (дБ)
@export var volume_db: float = -6.0
## Длительность смены громкости слоя (с)
@export var layer_fade: float = 0.6
## Длительность перекрёстной смены трека (с)
@export var track_fade: float = 1.2
## Частота среза фильтра на паузе / в диалоге / на экране смерти (Гц)
@export var muffle_cutoff_hz: float = 650.0
## Удар-приземление с силой не меньше этой (0.25–1, сигнал Player.slammed) — стингер
@export var stinger_min_power: float = 0.6
## Провал музыки во время стингера (дБ) и его длительность (с)
@export var stinger_duck_db: float = -18.0
@export var stinger_duck_time: float = 0.18
## Выключить автоматический выбор трека по сцене (тесты, ручное управление)
var auto: bool = true
## Поправка громкости из настроек игрока (дБ, GameSettings [audio] music)
var user_volume_db: float = 0.0

var current_track: String = ""
## 0 — фон (бас и пэды), 1 — бой (+ барабаны), 2 — Ярость (полный трек)
var intensity: int = 0
var muffled: bool = false

var _player: AudioStreamPlayer
var _old: AudioStreamPlayer
var _stinger: AudioStreamPlayer
var _lpf: AudioEffectLowPassFilter
var _bus_idx: int = -1
var _tracks: Dictionary = {}  # трек → {layer: AudioStream}
var _pending_track: String = ""
var _pending_intensity: int = -1
var _layer_db: PackedFloat32Array = PackedFloat32Array([0.0, -80.0, -80.0])
var _layer_target: PackedFloat32Array = PackedFloat32Array([0.0, -80.0, -80.0])
var _connected_player: Node = null
var _duck_left: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bus()
	_scan()
	_player = _make_player()
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = BUS
	add_child(_stinger)
	var st := _load_layer("stingers", "slam")
	if st:
		_stinger.stream = st

func _setup_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS)
	if _bus_idx < 0:
		AudioServer.add_bus()
		_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_idx, BUS)
		AudioServer.set_bus_send(_bus_idx, "Master")
	AudioServer.set_bus_volume_db(_bus_idx, volume_db + user_volume_db)
	_lpf = AudioEffectLowPassFilter.new()
	_lpf.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_bus_idx, _lpf)

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = BUS
	add_child(p)
	return p

func _load_layer(track: String, layer: String) -> AudioStream:
	for ext in ["ogg", "wav"]:
		var path: String = MUSIC_DIR + track + "/" + layer + "." + ext
		if ResourceLoader.exists(path):
			var s := load(path) as AudioStream
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			elif s is AudioStreamWAV:
				var w := s as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_end = int(w.get_length() * w.mix_rate)
			return s
	return null

func _scan() -> void:
	for d in ResourceLoader.list_directory(MUSIC_DIR):
		var track := d.trim_suffix("/")
		if track == "stingers" or not d.ends_with("/"):
			continue
		var layers := {}
		for l in LAYERS:
			var s := _load_layer(track, l)
			if s:
				layers[l] = s
		if not layers.is_empty():
			_tracks[track] = layers

func has_track(track: String) -> bool:
	return _tracks.has(track)

func tracks() -> Array:
	return _tracks.keys()

## Включить трек (смена — на ближайшем такте). Пустая строка — тишина.
func play_track(track: String, now: bool = false) -> void:
	if track == current_track and _pending_track == "":
		return
	if track != "" and not _tracks.has(track):
		return
	if now or current_track == "" or not _player.playing:
		_switch_to(track)
	else:
		_pending_track = track

## 0 — фон, 1 — бой, 2 — Ярость. Смена — на ближайшей доле.
func set_intensity(level: int) -> void:
	level = clampi(level, 0, 2)
	if level == intensity and _pending_intensity < 0:
		return
	_pending_intensity = level

## Приглушить музыку фильтром низких частот (пауза, диалог, смерть).
func set_muffled(on: bool) -> void:
	if on == muffled:
		return
	muffled = on
	var tw := create_tween()
	tw.tween_property(_lpf, "cutoff_hz", muffle_cutoff_hz if on else 20000.0, 0.35)

## Стингер (удар-приземление с высоты): провал музыки на время hit-stop и бас-удар.
func stinger() -> void:
	Perf.mark("music_stinger")
	_duck_left = stinger_duck_time
	if _stinger.stream:
		_stinger.play()

func _switch_to(track: String) -> void:
	_pending_track = ""
	if _old and is_instance_valid(_old):
		_old.queue_free()
	if _player.playing:
		_old = _player
		var tw := _old.create_tween()
		tw.tween_property(_old, "volume_db", -60.0, track_fade)
		tw.tween_callback(_old.queue_free)
		_player = _make_player()
	current_track = track
	if track == "":
		return
	var layers: Dictionary = _tracks[track]
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = LAYERS.size()
	for i in LAYERS.size():
		var s: AudioStream = layers.get(LAYERS[i])
		sync.set_sync_stream(i, s)
		_layer_db[i] = _target_db(i, intensity)
		_layer_target[i] = _layer_db[i]
		sync.set_sync_stream_volume(i, _layer_db[i])
	_player.stream = sync
	_player.volume_db = -30.0 if _old else 0.0
	_player.play()
	_clock = 0.0
	_prev_pos = 0.0
	if _old:
		_player.create_tween().tween_property(_player, "volume_db", 0.0, track_fade * 0.6)
	Perf.mark("music_track")

func _target_db(layer: int, level: int) -> float:
	# Слой без файла в треке — тишина; иначе base всегда, drums с боя, full с Ярости
	return 0.0 if layer <= level else -80.0

## Секунда внутри петли и длина доли/такта — для переходов «в такт».
func _beat_len() -> float:
	return 60.0 / bpm

func _crossed(prev_pos: float, pos: float, unit: float) -> bool:
	return floor(pos / unit) != floor(prev_pos / unit)

var _prev_pos: float = 0.0
var _clock: float = 0.0

func _process(delta: float) -> void:
	if auto:
		_auto_state()
	# Свои часы от старта трека: позиция воспроизведения без звуковой карты стоит на месте,
	# а delta сжимается hit-stop'ом — копим «реальную» delta (FX.real_delta), как и звук
	if _player.playing:
		_clock += FX.real_delta(delta)
	var pos := _clock if _player.playing else 0.0
	var beat := _beat_len()
	if _player.playing:
		if _pending_intensity >= 0 and _crossed(_prev_pos, pos, beat):
			intensity = _pending_intensity
			_pending_intensity = -1
			for i in LAYERS.size():
				_layer_target[i] = _target_db(i, intensity)
		if _pending_track != "" and _crossed(_prev_pos, pos, beat * beats_per_bar):
			_switch_to(_pending_track)
	elif _pending_intensity >= 0:
		intensity = _pending_intensity
		_pending_intensity = -1
		for i in LAYERS.size():
			_layer_target[i] = _target_db(i, intensity)
	_prev_pos = pos
	# Плавная громкость слоёв (линейно в дБ за layer_fade)
	var sync := _player.stream as AudioStreamSynchronized
	if sync:
		var step := 80.0 * FX.real_delta(delta) / maxf(layer_fade, 0.01)
		for i in LAYERS.size():
			if not is_equal_approx(_layer_db[i], _layer_target[i]):
				_layer_db[i] = move_toward(_layer_db[i], _layer_target[i], step)
				sync.set_sync_stream_volume(i, _layer_db[i])
	# Провал под стингер
	_duck_left = maxf(0.0, _duck_left - delta)
	AudioServer.set_bus_volume_db(_bus_idx, volume_db + user_volume_db + (stinger_duck_db if _duck_left > 0.0 else 0.0))

## Выбор трека и слоя по тому, что сейчас на экране (GDD 21: адаптивность).
func _auto_state() -> void:
	var tree := get_tree()
	var scene := tree.current_scene
	if scene == null:
		return
	var dialogue: Node = tree.root.get_node_or_null("Dialogue")
	var in_dialogue: bool = dialogue != null and dialogue.has_method("is_playing") and dialogue.call("is_playing")
	if scene is Game:
		var g := scene as Game
		_connect_player(g.player)
		var dead := g.player.is_dead
		set_muffled((tree.paused or in_dialogue or dead) and not _plan_open())
		if _plan_open() and has_track("plan"):
			play_track("plan")
			set_intensity(0)
			return
		var run: Node = tree.root.get_node_or_null("Run")
		var boss: bool = run != null and run.call("is_boss_room")
		var mini: bool = run != null and run.has_method("is_miniboss_room") and run.call("is_miniboss_room")
		var fighting: bool = g.room != null and is_instance_valid(g.room) and (g.room.alive_count() > 0 or g.room.pending_spawns() > 0)
		var shop: bool = run != null and run.has_method("current_reward") and str(run.call("current_reward")) == "shop"
		if boss and has_track("boss"):
			play_track("boss")
		elif shop and has_track("shop"):
			play_track("shop")
		elif mini and fighting and has_track("miniboss"):
			play_track("miniboss")
		else:
			play_track("midgard")
		var rage: bool = g.player.has_method("is_berserk") and g.player.call("is_berserk")
		# Зал зачищен — спокойная петля без обрыва (слой фона)
		set_intensity(2 if rage else (1 if fighting else 0))
	else:
		set_muffled(in_dialogue)
		set_intensity(0)
		if _plan_open() and has_track("plan"):
			play_track("plan")
		elif has_track("menu"):
			play_track("menu")

func _plan_open() -> bool:
	for n in get_tree().get_nodes_in_group("training_plan"):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return true
		if n is CanvasLayer and (n as CanvasLayer).visible:
			return true
	return false

func _connect_player(p: Node) -> void:
	if p == _connected_player or p == null:
		return
	_connected_player = p
	if p.has_signal("slammed"):
		p.connect("slammed", func(power: float) -> void:
			if power >= stinger_min_power:
				stinger())
