extends Node
## Комиксовые слова-удары (onomatopoeia), этап 4. Автозагрузка `ComicFX`.
##
## Вызов из игрового кода: `ComicFX.pop("slam", world_pos, big)` или хуки `ComicFX.on_*` (ниже) —
## они сами решают, достойно ли событие слова. Слова — только на сильных моментах; обычный удар слов не даёт.
##
## Как устроено:
## - запросы за кадр копятся и в конце кадра показывается одно слово — с высшим приоритетом
##   (удар-приземление, который убил троих, даст SMASH!, а не три слова);
## - кулдаун `cooldown` между словами и не больше `max_on_screen` слов (крупные — без кулдауна,
##   при полном экране вытесняют самое старое);
## - рисуется в 2D на CanvasLayer: точка в мире проецируется камерой каждый кадр — размер в пикселях
##   постоянный, стены не загораживают. Пул узлов, два общих материала растра — ни одного нового
##   материала на слово (правило фризов). Цвет — `modulate`/цвет полигона;
## - появление идёт в реальном времени (видно во время hit-stop), дрожь и исчезновение — в игровом:
##   пока длится стоп, слово «стоит» во весь размер;
## - словарь, цвета и приоритеты — `data/comic_words.json`; рисованный «взрыв» —
##   `sprites/comic/<событие>.png` или общий `sprites/comic/burst.png`, иначе — случайный из комплекта
##   `sprites/vfx/comic_burst_01..06.webp`, перекрашенный в цвет события (один общий материал
##   shaders/comic_burst.gdshader); нет и их — процедурный полигон.

const WORDS_PATH := "res://data/comic_words.json"
const SPRITE_DIR := "res://sprites/comic/"
const FONT_PATH := "res://fonts/Bangers-Regular.ttf"
const HALFTONE := preload("res://shaders/comic_halftone.gdshader")
const VIGNETTE := preload("res://shaders/comic_vignette.gdshader")
const KIT_BURST := preload("res://shaders/comic_burst.gdshader")
## Рисованные «взрывы» VFX-комплекта
const KIT_BURST_PATH := "res://sprites/vfx/comic_burst_%02d.webp"
const KIT_BURST_COUNT := 6
const BIG_PRIORITY := 1000

@export_group("Когда показывать")
## Минимум секунд между словами (реальное время)
@export var cooldown: float = 1.1
## Не больше стольких слов на экране одновременно
@export var max_on_screen: int = 3
## Окно мульти-килла, с
@export var multikill_window: float = 0.5
## Сколько убийств в окне дают слово
@export var multikill_count: int = 3
## ...и сколько — крупное слово на весь экран
@export var multikill_big_count: int = 8
## Обычные (не крупные) слова: шанс показать, если событие не «важное» (priority < important_priority) — реже, чтобы не мельтешили
@export_range(0.0, 1.0) var routine_chance: float = 0.45
@export var important_priority: int = 50
## Крупно на весь экран — только эти события (босс, высокий удар-приземление, ДОСТОЙНЕЙШИЙ!); остальные «big» — крупное слово у места удара
@export var fullscreen_events: PackedStringArray = PackedStringArray(["boss_kill", "slam", "rank_4", "combo"])
## Крупное слово в мире (не на весь экран): масштаб относительно обычного
@export var world_big_scale: float = 1.6
## Слово в мире мельче вдали: на этом расстоянии (м) — обычный размер, дальше — меньше (не мельче min_distance_scale)
@export var distance_ref: float = 6.0
@export_range(0.1, 1.0) var min_distance_scale: float = 0.45
## Удар-приземление ниже этой высоты (м) слова не даёт
@export var slam_min_height: float = 0.0
## С этой высоты (м) удар-приземление — крупное слово на весь экран (GDD 7.4)
@export var big_slam_height: float = 10.0
## Hit-stop удара-приземления с большой высоты, с (GDD 7.4/19; работает и при выключенных словах)
@export var big_slam_hitstop: float = 0.15
## Цепная молния даёт слово, только если убила (иначе слово было бы на каждом броске)
@export var lightning_kill_only: bool = true

@export_group("Вид")
@export var font_size: int = 96
@export var big_font_size: int = 160
## Толщина чёрной обводки букв (при font_size; у крупных — пропорционально)
@export var outline_px: int = 22
@export var shadow_offset: Vector2 = Vector2(6, 8)
## Масштаб слова над точкой в мире
@export var world_scale: float = 0.7
## Масштаб слова, привязанного к экрану (по игроку: OOF!)
@export var screen_scale: float = 0.62
## Масштаб крупного слова на весь экран (шрифт big_font_size)
@export var big_scale: float = 1.0
## Добивание финишером — во столько раз крупнее крита
@export var finisher_kill_scale: float = 1.2
## Случайный разброс масштаба ±
@export var scale_jitter: float = 0.12
## Случайный наклон ±, градусы
@export var tilt_deg: float = 15.0
## Лучей у «взрыва» (плюс случайно до 4)
@export var burst_points: int = 13
## Отступ «взрыва» от букв, px
@export var burst_pad: Vector2 = Vector2(22, 26)
## Длина лучей относительно эллипса (мин, макс)
@export var burst_spike: Vector2 = Vector2(1.12, 1.42)
## Чёрная обводка «взрыва», px
@export var burst_outline_px: float = 8.0
## Слово над точкой попадания выше на столько px
@export var world_lift_px: float = 30.0
## Случайный сдвиг слова в мире по экрану ±px
@export var world_jitter_px: float = 45.0
## Отступ от краёв экрана, px
@export var screen_margin_px: float = 24.0
## Сила виньетки под крупным словом (0 — нет)
@export var vignette_alpha: float = 0.85
## Рисованный «взрыв» комплекта: во сколько раз больше букв (с отступом burst_pad)
@export var kit_burst_scale: float = 1.75
## ...и насколько его можно вытянуть по ширине (ширина / высота, не больше)
@export var kit_burst_max_aspect: float = 1.9
## Перекраска в цвет события: 0 — авторский цвет картинки, 1 — полностью цвет события
@export_range(0.0, 1.0) var kit_tint_strength: float = 0.85
## Случайный доворот «взрыва» относительно слова ±, градусы
@export var kit_burst_tilt_deg: float = 10.0
## Тень под «взрывом»: прозрачность (0 — нет)
@export var kit_shadow_alpha: float = 0.55

@export_group("Анимация")
## Появление 0 → overshoot → 1.0 (реальное время, видно во время hit-stop)
@export var pop_in_time: float = 0.1
@export var pop_overshoot: float = 1.3
## Дрожь после появления
@export var shake_time: float = 0.15
@export var shake_px: float = 7.0
@export var shake_deg: float = 3.0
## Пауза перед исчезновением
@export var hold_time: float = 0.05
## Исчезновение с подъёмом
@export var fade_time: float = 0.15
@export var rise_px: float = 40.0
## Крупные слова живут дольше во столько раз
@export var big_time_mult: float = 2.2

## Для тестов и отладки
var stats := {"requested": 0, "shown": 0, "cooldown": 0, "limit": 0, "disabled": 0}
var history: Array[Dictionary] = []

var _data: Dictionary = {}
var _textures: Dictionary = {}
var _generic_texture: Texture2D
var _kit_bursts: Array[Texture2D] = []
var _kit_mat: ShaderMaterial
var _last_kit: int = -1
var _layer: CanvasLayer
var _vignette: ColorRect
var _pool: Array[ComicWord] = []
var _pending: Array[Dictionary] = []
var _clock: float = 0.0
var _last_pop: float = -100.0
var _last_preview: float = -100.0
var _kill_times: Array[float] = []
var _multi_level: int = 0
var _ls: LabelSettings
var _ls_big: LabelSettings
var _text_mat: ShaderMaterial
var _text_mat_big: ShaderMaterial
var _burst_mat: ShaderMaterial
var _glyph_warm: Array[Label] = []
var _glyph_warm_frames: int = 0
var _last_words: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # после игровых узлов: события этого кадра уже собраны
	GameSettings.ensure_loaded()
	_load_data()
	_build_resources()
	_layer = CanvasLayer.new()
	_layer.name = "ComicLayer"
	_layer.layer = 6  # над HUD (5) и репликами Одина, под выбором руны (10) и паузой (20); образец из настроек — 25
	add_child(_layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = VIGNETTE
	_vignette.material = vm
	_vignette.color = Color(0, 0, 0, 0)
	_vignette.visible = false
	_layer.add_child(_vignette)
	for i in max_on_screen:
		_pool.append(_new_word())
	_warm_glyphs()

# --- Хуки из игрового кода (однострочные вызовы) ---

## Показать слово события `event` над точкой мира. big — крупно на весь экран.
func pop(event: String, world_pos: Vector3, big: bool = false) -> void:
	_request(event, world_pos, big)

## Удар-приземление (player.gd → _do_slam_impact). height — высота падения, м.
func on_slam(center: Vector3, height: float) -> void:
	var big := height >= big_slam_height
	if big:
		FX.hitstop(big_slam_hitstop)
	if height < slam_min_height:
		return
	_request("slam", _ahead_of_camera(center), big)

## Попадание по врагу (enemy.gd → take_hit, после вычета здоровья). Слово — только у крита
## (тяжёлый 3-й удар комбо, `*_finisher`) по живому врагу; убийства разбирает on_enemy_killed.
func on_enemy_hit(enemy: Node3D, _damage: float, source: String) -> void:
	if not _is_finisher(source) or float(enemy.get("health")) <= 0.0:
		return
	_request(_melee_style(enemy), _head(enemy), false)

## Смерть врага (enemy.gd → _die): добивание финишером, мульти-килл, босс.
func on_enemy_killed(enemy: Node3D, source: String) -> void:
	var pos := _head(enemy)
	var recent: Array[float] = []
	for t in _kill_times:
		if _clock - t <= multikill_window:
			recent.append(t)
	if recent.is_empty():
		_multi_level = 0
	recent.append(_clock)
	_kill_times = recent
	if enemy.get("kind") == Enemy.Kind.BOSS:
		_request("boss_kill", pos, true)
	if recent.size() >= multikill_big_count and _multi_level < 2:
		_multi_level = 2
		FX.hitstop(FX.cfg().multikill_big_hitstop)
		_request("multikill", pos, true)
	elif recent.size() >= multikill_count and _multi_level < 1:
		_multi_level = 1
		FX.hitstop(FX.cfg().multikill_hitstop)
		_request("multikill", pos, false)
	if _is_finisher(source):
		_request(_melee_style(enemy), pos, false, finisher_kill_scale, 10)

## Мьёльнир попал во врага (mjolnir_projectile.gd → _on_hit). Слово — на возврате или после рикошета.
func on_hammer_hit(_target: Object, pos: Vector3, returning: bool, bounces: int) -> void:
	if returning or bounces > 0:
		_request("hammer", pos + Vector3(0, 0.6, 0), false)

## Цепная молния Мьёльнира ударила врага (mjolnir_projectile.gd → _chain_lightning, после удара).
func on_lightning(target: Node3D) -> void:
	if lightning_kill_only and not target.get("is_dead"):
		return
	_request("lightning", _head(target), false)

## Враг бьёт игрока (enemy.gd, перед player.take_damage). Слово — только от босса и если удар пройдёт.
func on_player_struck(enemy: Node3D, player: Node) -> void:
	if enemy.get("kind") != Enemy.Kind.BOSS or player == null or player.call("is_invulnerable"):
		return
	_request("player_hurt", Vector3.ZERO, false, 1.0, 0, true)

## Образец для настроек: слово вверху экрана, поверх меню (уважает переключатель и размер).
func preview() -> void:
	if _clock - _last_preview < 0.3:
		return
	_last_preview = _clock
	_request("slam", Vector3.ZERO, false, 1.0, BIG_PRIORITY * 2, true)
	_pending[-1]["preview"] = true

## Прогрев шейдеров/глифов (ShaderWarmup при входе в зал): слово в мире перед камерой и крупное на экране.
func warmup() -> void:
	var cam := get_viewport().get_camera_3d()
	var p := Vector3.ZERO
	if cam:
		p = cam.global_position - cam.global_basis.z * 3.0
	for r in [{"event": "slam", "pos": p, "big": false, "screen": cam == null, "scale": 1.0},
			{"event": "boss_kill", "pos": p, "big": true, "screen": true, "scale": 1.0}]:
		var w := _take_word(true)
		_show(w, r)
		w.warm_frames = 10
		w.anim_scale = 1.0
		_place(w, 0.0, Vector2.ZERO, 0.0)
	_vignette.visible = true
	_vignette.color = Color(0, 0, 0, 0.03)
	_warm_glyphs()

## Сбросить слова, кулдаун и счётчики (тесты, смена забега).
func reset_state() -> void:
	_pending.clear()
	_kill_times.clear()
	_multi_level = 0
	_last_pop = -100.0
	for w in _pool:
		_release(w)
	# reset_state может быть вызван между кадрами, пока слово связки ещё в пуле.
	if _layer:
		_layer.layer = 6
	if _vignette:
		_vignette.visible = false
	for k in stats.keys():
		stats[k] = 0
	history.clear()

func active_count() -> int:
	var n := 0
	for w in _pool:
		if w.active:
			n += 1
	return n

## HUD использует это, чтобы реплика и крупное слово связки не закрывали друг друга.
func combo_word_active() -> bool:
	for w in _pool:
		if w.active and w.event == "combo" and not w.preview:
			return true
	return false

# --- Очередь и показ ---

func _request(event: String, pos: Vector3, big: bool, scale_mult: float = 1.0, prio_bonus: int = 0, screen: bool = false) -> void:
	if not _data.has(event):
		push_warning("ComicFX: нет события '%s' в %s" % [event, WORDS_PATH])
		return
	if big and not (event in fullscreen_events):
		big = false
		scale_mult *= world_big_scale
		prio_bonus += important_priority
	var prio := int((_data[event] as Dictionary).get("priority", 0)) + prio_bonus + (BIG_PRIORITY if big else 0)
	_pending.append({"event": event, "pos": pos, "big": big, "scale": scale_mult, "prio": prio, "screen": screen})

func _flush() -> void:
	if _pending.is_empty():
		return
	var best: Dictionary = _pending[0]
	for r in _pending:
		if int(r.prio) > int(best.prio):
			best = r
	_pending.clear()
	stats.requested += 1
	if not GameSettings.comic_enabled:
		stats.disabled += 1
		return
	if not best.big and _clock - _last_pop < cooldown:
		stats.cooldown += 1
		return
	if not best.big and not best.get("preview", false) and int(best.prio) < important_priority and randf() > routine_chance:
		stats.cooldown += 1
		return
	var w := _take_word(best.big)
	if w == null:
		stats.limit += 1
		return
	_show(w, best)
	_last_pop = _clock
	stats.shown += 1
	history.append({"event": best.event, "text": w.label.text, "big": best.big})
	Perf.mark("comic_word")

## Свободное слово из пула; при полном экране крупное вытесняет самое старое, обычное — не показывается.
func _take_word(force: bool) -> ComicWord:
	var active := 0
	var free: ComicWord = null
	var oldest: ComicWord = null
	for w in _pool:
		if w.active:
			active += 1
			if oldest == null or w.age_real > oldest.age_real:
				oldest = w
		elif free == null:
			free = w
	if active < max_on_screen:
		if free:
			return free
		var nw := _new_word()
		_pool.append(nw)
		return nw
	if force and oldest:
		_release(oldest)
		return oldest
	return null

func _show(w: ComicWord, r: Dictionary) -> void:
	var ev: String = r.event
	var d: Dictionary = _data[ev]
	var big: bool = r.big
	w.active = true
	w.visible = true
	w.event = ev
	w.big = big
	w.screen = r.screen or big
	w.preview = bool(r.get("preview", false))
	w.world_pos = r.pos
	w.cam = get_viewport().get_camera_3d()
	w.age_real = 0.0
	w.age_game = 0.0
	w.warm_frames = -1
	w.time_mult = big_time_mult if big else 1.0
	var base := big_scale if big else (screen_scale if r.screen else world_scale)
	w.base_scale = base * float(r.scale) * randf_range(1.0 - scale_jitter, 1.0 + scale_jitter)
	w.tilt = deg_to_rad(randf_range(-tilt_deg, tilt_deg) * (0.6 if big else 1.0))
	w.jitter = Vector2(randf_range(-world_jitter_px, world_jitter_px), randf_range(-world_jitter_px, world_jitter_px) * 0.5)
	if w.screen and not big:
		w.jitter = Vector2(randf_range(-160.0, 160.0), randf_range(40.0, 90.0))
	var fill := Color.from_string(String(d.get("fill", "#ffe03a")), Color(1, 0.88, 0.23))
	var burst_c := Color.from_string(String(d.get("burst", "#e8361e")), Color(0.9, 0.2, 0.1))
	# Слово и буквы
	w.label.label_settings = _ls_big if big else _ls
	w.label.material = _text_mat_big if big else _text_mat
	w.label.text = _pick_word(ev, d)
	w.label.modulate = fill
	w.label.reset_size()
	var sz := w.label.size
	w.label.position = -sz * 0.5 + Vector2(0, sz.y * 0.04)
	# «Взрыв» за словом
	var ink := sz - Vector2(1, 1) * float(w.label.label_settings.outline_size) * 0.6
	var rx := ink.x * 0.5 * 1.25 + burst_pad.x
	var ry := ink.y * 0.5 * 1.05 + burst_pad.y
	w.half = Vector2(rx, ry) * burst_spike.y + Vector2.ONE * burst_outline_px
	var tex: Texture2D = _textures.get(ev, _generic_texture)
	w.sprite.material = null
	w.sprite.rotation = 0.0
	w.sprite.flip_h = false
	w.sprite_shadow.visible = false
	if tex == null and not _kit_bursts.is_empty():
		# Рисованный «взрыв» комплекта: случайный (не тот же подряд), перекрашен в цвет события
		var idx := randi() % _kit_bursts.size()
		if idx == _last_kit and _kit_bursts.size() > 1:
			idx = (idx + 1 + randi() % (_kit_bursts.size() - 1)) % _kit_bursts.size()
		_last_kit = idx
		var kt := _kit_bursts[idx]
		var wpx := (ink.x + burst_pad.x * 2.0) * kit_burst_scale
		var hpx := maxf((ink.y + burst_pad.y * 2.0) * kit_burst_scale, wpx / maxf(kit_burst_max_aspect, 1.0))
		w.burst.visible = false
		w.outline.visible = false
		w.shadow.visible = false
		w.sprite.visible = true
		w.sprite.texture = kt
		w.sprite.material = _kit_mat
		w.sprite.scale = Vector2(wpx / kt.get_width(), hpx / kt.get_height())
		w.sprite.rotation = deg_to_rad(randf_range(-kit_burst_tilt_deg, kit_burst_tilt_deg))
		w.sprite.flip_h = randf() < 0.5
		w.sprite.modulate = burst_c
		w.half = Vector2(wpx, hpx) * 0.46
		if kit_shadow_alpha > 0.0:
			w.sprite_shadow.visible = true
			w.sprite_shadow.texture = kt
			w.sprite_shadow.scale = w.sprite.scale
			w.sprite_shadow.rotation = w.sprite.rotation
			w.sprite_shadow.flip_h = w.sprite.flip_h
			w.sprite_shadow.position = shadow_offset * (1.6 if big else 1.0)
			w.sprite_shadow.modulate = Color(0, 0, 0, kit_shadow_alpha)
	elif tex:
		w.burst.visible = false
		w.outline.visible = false
		w.shadow.visible = false
		w.sprite.visible = true
		w.sprite.texture = tex
		w.sprite.scale = Vector2(rx * 2.0 * burst_spike.y / tex.get_width(), ry * 2.0 * burst_spike.y / tex.get_height())
		w.sprite.modulate = Color.WHITE if _textures.has(ev) else burst_c
	else:
		w.sprite.visible = false
		w.burst.visible = true
		w.outline.visible = true
		w.shadow.visible = true
		var pts := _burst_polygon(rx, ry, burst_points + randi() % 5)
		var uv := PackedVector2Array()
		var out := PackedVector2Array()
		for p in pts:
			uv.append(Vector2(p.x / (rx * burst_spike.y), p.y / (ry * burst_spike.y)))
			out.append(p + p.normalized() * burst_outline_px)
		w.burst.polygon = pts
		w.burst.uv = uv
		w.burst.color = burst_c
		w.outline.polygon = out
		w.shadow.polygon = out
		w.shadow.position = shadow_offset * (1.6 if big else 1.0)
	w.modulate = Color.WHITE
	_place(w, 0.0, Vector2.ZERO, 0.0)

func _burst_polygon(rx: float, ry: float, spikes: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := spikes * 2
	var phase := randf() * TAU
	for i in n:
		var a := phase + TAU * (float(i) + randf_range(-0.22, 0.22)) / n
		var r := randf_range(burst_spike.x, burst_spike.y) if i % 2 == 0 else randf_range(0.86, 0.97)
		pts.append(Vector2(cos(a) * rx * r, sin(a) * ry * r))
	return pts

## Слова — на английском для всех языков (так задумано, шрифт Bangers — только латиница); для своего языка
## можно добавить событию "words_<язык>" (например "words_ru") — возьмётся при этом языке (нужен шрифт с кириллицей).
func _pick_word(ev: String, d: Dictionary) -> String:
	var words: Array = d.get("words_" + I18n.locale(), d.get("words", ["POW!"]))
	if words.is_empty():
		return "POW!"
	var s: String = words[randi() % words.size()]
	if words.size() > 1 and s == _last_words.get(ev, ""):
		s = words[(words.find(s) + 1 + randi() % (words.size() - 1)) % words.size()]
	_last_words[ev] = s
	return s

func _release(w: ComicWord) -> void:
	w.active = false
	w.visible = false
	w.warm_frames = -1

# --- Кадр ---

func _process(delta: float) -> void:
	var real := FX.real_delta(delta)
	var game := real if get_tree().paused else delta
	_clock += real
	_flush()
	var vig := 0.0
	var preview := false
	var combo_word := false
	for w in _pool:
		if w.active:
			_animate(w, real, game)
			if w.active and w.preview:
				preview = true
			if w.active and w.event == "combo" and not w.preview:
				combo_word = true
			if w.active and w.big:
				vig = maxf(vig, w.modulate.a * clampf(w.anim_scale, 0.0, 1.0))
	# Образец — поверх меню. Слово связки и его виньетка — под HUD: одновременно
	# звучит Один, и большое FUSION! иначе закрывает его реплику. После слова
	# возвращаем обычный слой для всех других боевых эффектов.
	_layer.layer = 25 if preview else (4 if combo_word else 6)
	_vignette.visible = vig > 0.01 and vignette_alpha > 0.0
	_vignette.color = Color(0, 0, 0, vig * vignette_alpha)
	if _glyph_warm_frames > 0:
		_glyph_warm_frames -= 1
		if _glyph_warm_frames == 0:
			for l in _glyph_warm:
				l.visible = false

func _animate(w: ComicWord, real: float, game: float) -> void:
	if w.warm_frames > 0:
		w.warm_frames -= 1
		w.modulate.a = 0.03
		if w.warm_frames == 0:
			_release(w)
		return
	w.age_real += real
	var tm := w.time_mult
	var pin := pop_in_time * (1.4 if w.big else 1.0)
	var s := 1.0
	if w.age_real < pin:
		var k := w.age_real / pin
		if k < 0.6:
			s = pop_overshoot * ease(k / 0.6, 0.4)
		else:
			s = lerpf(pop_overshoot, 1.0, ease((k - 0.6) / 0.4, 0.6))
	else:
		w.age_game += game
	w.anim_scale = s
	var g := w.age_game
	var off := Vector2.ZERO
	var rot := 0.0
	var shake_end := shake_time * tm
	if w.age_real >= pin and g < shake_end:
		var amp := 1.0 - g / shake_end
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_px * amp * (1.6 if w.big else 1.0)
		rot = deg_to_rad(randf_range(-shake_deg, shake_deg)) * amp
	var fade_start := (shake_time + hold_time) * tm
	var rise := 0.0
	w.modulate.a = 1.0
	if g > fade_start:
		var f := (g - fade_start) / (fade_time * tm)
		if f >= 1.0:
			_release(w)
			return
		w.modulate.a = 1.0 - f
		rise = rise_px * ease(f, 0.5) * (1.5 if w.big else 1.0)
	_place(w, rise, off, rot)

func _place(w: ComicWord, rise: float, off: Vector2, rot: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var sc := w.base_scale * w.anim_scale * GameSettings.comic_scale
	w.scale = Vector2.ONE * maxf(sc, 0.001)
	w.rotation = w.tilt + rot
	var combo_lane := w.event == "combo" and w.big and not w.preview
	var combo_lane_start := vp.x * lerpf(0.4, 0.5, clampf((GameSettings.text_scale() - 1.0) / 0.6, 0.0, 1.0))
	if combo_lane:
		# Левую часть занимает реплика Одина. Ограничиваем только слово связки,
		# учитывая наклон и overshoot, чтобы буквы и всплеск помещались справа.
		var lane_half := maxf((vp.x - screen_margin_px - combo_lane_start) * 0.5 - shake_px * 1.6, 1.0)
		var half_width := (absf(cos(w.rotation)) * w.half.x + absf(sin(w.rotation)) * w.half.y) * 1.15 * w.scale.x
		if half_width > lane_half:
			w.scale *= lane_half / half_width
	var pos: Vector2
	if w.preview:
		pos = vp * Vector2(0.5, 0.16)
	elif combo_lane:
		pos = Vector2((combo_lane_start + vp.x - screen_margin_px) * 0.5, vp.y * 0.42)
	elif w.big:
		pos = vp * Vector2(0.5, 0.42)
	elif w.screen:
		pos = vp * Vector2(0.5, 0.5) + w.jitter
	else:
		var cam := get_viewport().get_camera_3d()
		if w.cam == null or not is_instance_valid(w.cam) or cam != w.cam:
			_release(w)
			return
		if cam.is_position_behind(w.world_pos):
			w.visible = false
			return
		w.visible = true
		var dist := cam.global_position.distance_to(w.world_pos)
		var dk := clampf(distance_ref / maxf(dist, 0.1), min_distance_scale, 1.0)
		w.scale *= dk
		pos = cam.unproject_position(w.world_pos) + (w.jitter + Vector2(0, -world_lift_px)) * dk
	pos += off + Vector2(0, -rise)
	# Не даём слову уехать за край экрана
	var h := w.half * w.base_scale * GameSettings.comic_scale
	if combo_lane:
		h = w.half * w.scale.x
	var m := screen_margin_px
	pos.x = vp.x * 0.5 if h.x * 2.0 + m * 2.0 > vp.x else clampf(pos.x, m + h.x, vp.x - m - h.x)
	pos.y = vp.y * 0.5 if h.y * 2.0 + m * 2.0 > vp.y else clampf(pos.y, m + h.y, vp.y - m - h.y)
	w.position = pos

# --- Вспомогательное ---

func _is_finisher(source: String) -> bool:
	return source == "axe_finisher" or source == "melee_finisher"

## Стиль мили игрока: "blade" (топор, клинки), "blunt" (дубина, молот), "pierce" (копьё).
func _melee_style(enemy: Node) -> String:
	var p: Node = enemy.get("player") as Node
	if p == null:
		p = get_tree().get_first_node_in_group("player")
	var style := "blade"
	if p and is_instance_valid(p) and p.has_method("current_melee_style"):
		style = String(p.call("current_melee_style"))
	return style if _data.has(style) else "blade"

func _head(enemy: Node3D) -> Vector3:
	var s := float(enemy.get("model_scale")) if enemy.get("model_scale") != null else 1.0
	return enemy.global_position + Vector3(0, 1.6 * s, 0)

## Точка перед камерой на уровне удара (удар-приземление — под ногами, оттуда слово не видно).
func _ahead_of_camera(center: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return center
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return center + fwd * 3.5 + Vector3(0, 0.9, 0)

func _load_data() -> void:
	var f := FileAccess.open(WORDS_PATH, FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				if parsed[k] is Dictionary:
					_data[k] = parsed[k]
	if _data.is_empty():
		push_warning("ComicFX: не прочитан %s" % WORDS_PATH)
		_data = {"slam": {"words": ["KA-BOOM!"], "priority": 60}}
	for ev in _data.keys():
		var path: String = SPRITE_DIR + ev + ".png"
		if ResourceLoader.exists(path):
			_textures[ev] = load(path)
	if ResourceLoader.exists(SPRITE_DIR + "burst.png"):
		_generic_texture = load(SPRITE_DIR + "burst.png")
	for i in KIT_BURST_COUNT:
		var kp := KIT_BURST_PATH % (i + 1)
		if ResourceLoader.exists(kp):
			_kit_bursts.append(load(kp))

func _build_resources() -> void:
	var font: Font = load(FONT_PATH)
	_ls = _label_settings(font, font_size)
	_ls_big = _label_settings(font, big_font_size)
	_text_mat = _halftone(false, font_size * 1.2, 9.0)
	_text_mat_big = _halftone(false, big_font_size * 1.2, 14.0)
	_burst_mat = _halftone(true, 1.0, 11.0)
	_kit_mat = ShaderMaterial.new()
	_kit_mat.shader = KIT_BURST
	_kit_mat.set_shader_parameter("tint_strength", kit_tint_strength)

func _label_settings(font: Font, size: int) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = Color.WHITE
	var k := float(size) / float(font_size)
	ls.outline_size = int(round(outline_px * k))
	ls.outline_color = Color.BLACK
	ls.shadow_size = int(round(outline_px * k))
	ls.shadow_color = Color(0, 0, 0, 0.9)
	ls.shadow_offset = shadow_offset * k
	return ls

func _halftone(radial: bool, text_height: float, spacing: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HALFTONE
	m.set_shader_parameter("radial", radial)
	m.set_shader_parameter("text_height", text_height)
	m.set_shader_parameter("dot_spacing", spacing)
	if radial:
		m.set_shader_parameter("dot_strength", 0.4)
		m.set_shader_parameter("highlight", 0.22)
	else:
		m.set_shader_parameter("dot_strength", 0.22)
		m.set_shader_parameter("highlight", 0.5)
		m.set_shader_parameter("dot_max", 0.34)
	return m

func _new_word() -> ComicWord:
	var w := ComicWord.new()
	w.visible = false
	w.shadow = Polygon2D.new()
	w.shadow.color = Color(0, 0, 0, 0.85)
	w.shadow.antialiased = true
	w.add_child(w.shadow)
	w.outline = Polygon2D.new()
	w.outline.color = Color.BLACK
	w.outline.antialiased = true
	w.add_child(w.outline)
	w.burst = Polygon2D.new()
	w.burst.material = _burst_mat
	w.burst.antialiased = true
	w.add_child(w.burst)
	w.sprite_shadow = Sprite2D.new()
	w.sprite_shadow.visible = false
	w.add_child(w.sprite_shadow)
	w.sprite = Sprite2D.new()
	w.sprite.visible = false
	w.add_child(w.sprite)
	w.label = Label.new()
	w.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	w.label.label_settings = _ls
	w.label.material = _text_mat
	w.add_child(w.label)
	_layer.add_child(w)
	return w

## Растеризация всех букв словаря в обоих размерах заранее: первый глиф шрифта на 160 px с обводкой —
## заметная работа CPU в кадре появления слова.
func _warm_glyphs() -> void:
	var chars := {}
	for ev in _data:
		for word in (_data[ev] as Dictionary).get("words", []):
			for ch in String(word):
				chars[ch] = true
	var text := "".join(PackedStringArray(chars.keys()))
	if _glyph_warm.is_empty():
		for big in [false, true]:
			var l := Label.new()
			l.label_settings = _ls_big if big else _ls
			l.material = _text_mat_big if big else _text_mat
			l.modulate = Color(1, 1, 1, 0.02)
			l.position = Vector2(0, 0)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_layer.add_child(l)
			_glyph_warm.append(l)
	for l in _glyph_warm:
		l.text = text
		l.visible = true
	_glyph_warm_frames = 4

class ComicWord extends Node2D:
	var active := false
	var event := ""
	var big := false
	var screen := false
	var world_pos := Vector3.ZERO
	var cam: Camera3D
	var age_real := 0.0
	var age_game := 0.0
	var time_mult := 1.0
	var base_scale := 1.0
	var anim_scale := 0.0
	var tilt := 0.0
	var jitter := Vector2.ZERO
	var half := Vector2.ONE
	var warm_frames := -1
	var preview := false
	var shadow: Polygon2D
	var outline: Polygon2D
	var burst: Polygon2D
	var sprite: Sprite2D
	var sprite_shadow: Sprite2D
	var label: Label
