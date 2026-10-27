extends Node
class_name StyleMeter
## Шкала стиля «ДОСТОЙНО!» (блок Б3, GDD 8) — вместо Ярости (блок П). Узел «StyleMeter» игрока (создаёт
## Player._ready; Player.rage — старое имя, тот же узел). Числа — player/style_tuning.tres (StyleTuning).
##
## Очки — за разнообразные убийства и трюки (таблица StyleTuning.points): убийство — из сигнала
## Run.kill_registered (способ — по источнику урона, kill_action), трюки — StyleMeter.event(&"…") одной
## строкой из игрового кода (отскок, прыжок по головам, идеальный хват, шмяк о стену, отражение).
## Повтор того же приёма даёт меньше (память «усталости» тает со временем), урон по Тору сбивает шкалу,
## без новых очков она пустеет, а на высоких рангах ещё и постоянно утекает.
## Ранги: Скуф → Сойдёт → Неплохо → Достойно → ДОСТОЙНЕЙШИЙ! Высший — берсерк (бывшая Ярость): урон и
## скорость ×1.5, неуязвимость к стану, berserk_time секунд; потом шкала падает в середину after_berserk_rank.
## Ранг влияет на Славу (Run.style_glory_mult), музыку (music_level → Music) и голос Одина.

## value 0..1 — заполненность шкалы (в берсерке — сколько осталось), active — идёт берсерк
signal changed(value: float, active: bool)
## Ранг сменился (вверх или вниз)
signal rank_changed(rank: int, previous: int)
## Получены очки: приём, сколько начислено (после повтора и рун)
signal gained(action: StringName, amount: float)
signal berserk_started
signal berserk_ended

const RANKS := 5
const TOP := 4
## Названия рангов (tr при показе); слова комикса — события rank_1..rank_4 в data/comic_words.json
const RANK_NAMES := ["Скуф", "Сойдёт", "Неплохо", "Достойно", "ДОСТОЙНЕЙШИЙ!"]

@export var tuning: StyleTuning = preload("res://player/style_tuning.tres")

## Текущий узел (трюки шлют StyleMeter.event без ссылки на игрока)
static var current: StyleMeter

var player: Player
var points: float = 0.0
var rank: int = 0
var active: bool = false
var berserk_left: float = 0.0
## Усталость приёмов: действие → число недавних применений (тает)
var fatigue: Dictionary = {}
## Сколько секунд без новых очков
var idle_time: float = 0.0
## Часы шкалы (игровое время; кулдауны голоса и слов)
var clock: float = 0.0
var _kill_times: Array[float] = []
var _multi_level: int = 0
var _last_pop: Dictionary = {}
## Слово ранга ждёт rank_pop_delay секунд (чтобы не перебить слово самого приёма): ранг и сколько осталось
var _pop_rank: int = -1
var _pop_left: float = 0.0
var _last_voice: Dictionary = {}
var _worthy_retry: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	current = self
	if player == null:
		player = get_parent() as Player
	if Run.has_signal("kill_registered"):
		Run.kill_registered.connect(_on_kill)
	if player and player.get("mjolnir"):
		var hand: Variant = player.get("mjolnir")
		if hand is Object and (hand as Object).has_signal("perfect_catch"):
			(hand as Object).connect("perfect_catch", func() -> void: event(&"perfect_catch"))
	Run.style_glory_mult = glory_mult()

func _exit_tree() -> void:
	if current == self:
		current = null

# --- Вход: трюки и убийства ---

## Трюк из игрового кода одной строкой: StyleMeter.event(&"wall_splat"). Нет игрока — ничего.
static func event(action: StringName) -> void:
	if current and is_instance_valid(current):
		current.add_action(action)

## Способ убийства по источнику урона (Player.deal_damage / Enemy.take_hit) → ключ очков.
static func kill_action(source: String) -> StringName:
	match source:
		"melee":
			return &"kill_melee"
		"melee_finisher":
			return &"kill_finisher"
		"melee_heavy":
			return &"kill_heavy"
		"ranged":
			return &"kill_ranged"
		"slam":
			return &"kill_slam"
		"stomp":
			return &"kill_stomp"
		"hammer", "lightning":
			return &"kill_hammer"
		"fall":
			return &"kill_fall"
		"wall":
			return &"kill_wall"
		"reflect":
			return &"kill_reflect"
		"dash":
			return &"kill_dash"
		"explosion":
			return &"kill_explosion"
		"fire":
			return &"kill_fire"
	if source.begins_with("melee"):
		return &"kill_melee"
	return &"kill_other"

func _on_kill(source: String) -> void:
	note_kill(source)

## Убийство (сигнал Run.kill_registered; тесты — напрямую): очки за способ и мульти-килл.
func note_kill(source: String) -> void:
	if player == null or player.is_dead:
		return
	add_action(kill_action(source))
	_kill_times = _kill_times.filter(func(t: float) -> bool: return clock - t <= tuning.multikill_window)
	if _kill_times.is_empty():
		_multi_level = 0
	_kill_times.append(clock)
	if _kill_times.size() >= tuning.multikill_big_count and _multi_level < 2:
		_multi_level = 2
		add_action(&"multikill_big")
	elif _kill_times.size() >= tuning.multikill_count and _multi_level < 1:
		_multi_level = 1
		add_action(&"multikill")

## Множитель повтора для приёма сейчас (1 — свежий, меньше — заезженный).
func repeat_mult(action: StringName) -> float:
	var f := float(fatigue.get(action, 0.0))
	return maxf(tuning.repeat_min_mult, pow(tuning.repeat_falloff, f))

## Очки за приём: база × повтор × руна «Песнь берсерка» × тело (modify_stat "style_gain_mult").
## Возвращает начисленное. В берсерке шкала не копится.
func add_action(action: StringName) -> float:
	if active or (player and player.is_dead):
		return 0.0
	var base := float(tuning.points.get(String(action), 0.0))
	if base <= 0.0:
		return 0.0
	var amount := base * repeat_mult(action) * gain_mult()
	fatigue[action] = minf(float(fatigue.get(action, 0.0)) + 1.0, tuning.repeat_memory_max)
	idle_time = 0.0
	gained.emit(action, amount)
	add_points(amount)
	return amount

## Общий множитель набора: руна «Песнь берсерка» (+30 % → +80 %) и тело.
func gain_mult() -> float:
	var m := 1.0 + Run.rune_value("berserk_song")
	if player and player.has_method("modify_stat"):
		m *= float(player.modify_stat(&"style_gain_mult", 1.0))
	return m

## Прибавить/отнять очки напрямую (тесты, руны, урон). Полная шкала — берсерк.
func add_points(amount: float) -> void:
	if active:
		return
	set_points(points + amount)

func set_points(p: float) -> void:
	if active:
		return
	var top := top_points()
	points = clampf(p, 0.0, top)
	if points >= top:
		start_berserk()
		return
	_update_rank()
	changed.emit(value(), active)

## Урон по Тору (Player.take_damage) сбивает шкалу. В берсерке — нет.
func on_damaged(amount: float) -> void:
	if active or amount <= 0.0:
		return
	idle_time = tuning.idle_delay  # пустеет сразу, без передышки
	add_points(-maxf(tuning.damage_knock_min, amount * tuning.damage_knock_per_hp))

# --- Ранги и их последствия ---

func top_points() -> float:
	return tuning.rank_points[TOP] if tuning.rank_points.size() > TOP else 100.0

## Ранг по очкам (без берсерка).
func rank_for(p: float) -> int:
	var r := 0
	for i in mini(tuning.rank_points.size(), RANKS):
		if p >= tuning.rank_points[i]:
			r = i
	return r

static func rank_name(r: int) -> String:
	return RANK_NAMES[clampi(r, 0, RANKS - 1)]

## Заполненность 0..1: очки до полной шкалы; в берсерке — сколько его осталось.
func value() -> float:
	if active:
		return clampf(berserk_left / maxf(tuning.berserk_time, 0.01), 0.0, 1.0)
	return clampf(points / maxf(top_points(), 0.01), 0.0, 1.0)

## Доля шкалы, с которой начинается ранг r (для засечек HUD).
func rank_fraction(r: int) -> float:
	return clampf(tuning.rank_points[clampi(r, 0, tuning.rank_points.size() - 1)] / maxf(top_points(), 0.01), 0.0, 1.0)

func glory_mult() -> float:
	return tuning.rank_glory_mult[clampi(rank, 0, tuning.rank_glory_mult.size() - 1)] if not tuning.rank_glory_mult.is_empty() else 1.0

## Слой музыки (Music._auto_state): 0 — фон, 1 — бой, 2 — полный трек (с music_full_rank и в берсерке).
func music_level(fighting: bool) -> int:
	if active:
		return 2
	if not fighting:
		return 0
	return 2 if rank >= tuning.music_full_rank else 1

func current_damage_mult() -> float:
	return tuning.damage_mult if active else 1.0

func current_speed_mult() -> float:
	return tuning.speed_mult if active else 1.0

## В берсерке Тора не сбивают: удары не отбрасывают (у Тора нет стана — это его «стан»)
func is_stun_immune() -> bool:
	return active

func _update_rank() -> void:
	var r := TOP if active else rank_for(points)
	if r == rank:
		return
	var prev := rank
	rank = r
	Run.style_glory_mult = glory_mult()
	rank_changed.emit(rank, prev)
	if rank > prev:
		_on_rank_up(rank)

func _on_rank_up(r: int) -> void:
	Perf.mark("style_rank_up")
	# Слово комикса (на английском, Bangers): высший ранг — сразу крупно (start_berserk); прочие — через
	# rank_pop_delay после приёма (его слово — первым), не чаще rank_pop_cooldown на ранг
	if r < TOP and clock - float(_last_pop.get(r, -1000.0)) >= tuning.rank_pop_cooldown:
		_last_pop[r] = clock
		_pop_rank = r
		_pop_left = tuning.rank_pop_delay
	if r == tuning.voice_rank and r < TOP:
		_worthy_retry = tuning.voice_retry_time
		_try_worthy_voice()

## «Достойно!» — обычная боевая реплика (лимит Одина 12 с): если занят, пробуем ещё voice_retry_time секунд.
func _try_worthy_voice() -> void:
	if rank < tuning.voice_rank or clock - float(_last_voice.get("rank_worthy", -1000.0)) < tuning.voice_cooldown:
		_worthy_retry = 0.0
		return
	if Odin.say("rank_worthy") != "":
		_last_voice["rank_worthy"] = clock
		_worthy_retry = 0.0

func _pop_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	return player.global_position + Vector3(0, 1.8, 0) - player.global_transform.basis.z * 2.0

# --- Берсерк (высший ранг) ---

func start_berserk() -> void:
	active = true
	points = top_points()
	berserk_left = tuning.berserk_time
	_worthy_retry = 0.0
	Perf.mark("berserk_start")
	# «ДОСТОЙНЕЙШИЙ!» (голос владельца) — без лимита Одина, не чаще voice_cooldown; чаще — пул berserk
	if clock - float(_last_voice.get("rank_top", -1000.0)) >= tuning.voice_cooldown:
		if Odin.say("rank_top") != "":
			_last_voice["rank_top"] = clock
	else:
		Odin.say("berserk")
	Dialogue.thor_bark("berserk", 1.0)
	if player:
		player.camera_fx.add_trauma(0.45)
		player.camera_fx.kick_fov(12.0)
	_pop_rank = -1
	ComicFX.pop("rank_%d" % TOP, _pop_pos(), true)
	FX.hitstop(tuning.hitstop_on_start)
	Audio.play("sounds/sfx/enemy_growl.wav")
	_update_rank()
	berserk_started.emit()
	changed.emit(value(), active)

func end_berserk() -> void:
	if not active:
		return
	active = false
	berserk_left = 0.0
	# Середина ранга after_berserk_rank — чтобы утечка не уронила ранг в первый же кадр
	var a := clampi(tuning.after_berserk_rank, 0, TOP - 1)
	points = (tuning.rank_points[a] + tuning.rank_points[a + 1]) * 0.5
	idle_time = 0.0
	Perf.mark("berserk_end")
	Odin.say("rage_over")
	_update_rank()
	berserk_ended.emit()
	changed.emit(value(), active)

## Сброс без реплик (новый забег, смерть, тесты)
func reset() -> void:
	active = false
	berserk_left = 0.0
	points = 0.0
	idle_time = 0.0
	fatigue.clear()
	_kill_times.clear()
	_multi_level = 0
	_worthy_retry = 0.0
	_pop_rank = -1
	var prev := rank
	rank = 0
	Run.style_glory_mult = glory_mult()
	if prev != 0:
		rank_changed.emit(0, prev)
	changed.emit(value(), active)

## Сбросить кулдауны голоса и слов (тесты)
func reset_cooldowns() -> void:
	_last_pop.clear()
	_last_voice.clear()

func _physics_process(delta: float) -> void:
	clock += delta
	if player and player.is_dead:
		if active or points > 0.0:
			reset()
		return
	# Память о приёмах тает
	if not fatigue.is_empty():
		for k in fatigue.keys():
			var f := float(fatigue[k]) - tuning.repeat_memory_decay * delta
			if f <= 0.0:
				fatigue.erase(k)
			else:
				fatigue[k] = f
	if _worthy_retry > 0.0:
		_worthy_retry -= delta
		_try_worthy_voice()
	if _pop_rank > 0:
		_pop_left -= delta
		if _pop_left <= 0.0:
			# Пока ждали, ранг мог упасть — тогда слова нет
			if rank >= _pop_rank and not active:
				ComicFX.pop("rank_%d" % _pop_rank, _pop_pos(), false)
			_pop_rank = -1
	if active:
		berserk_left -= delta
		changed.emit(value(), active)
		if berserk_left <= 0.0:
			end_berserk()
		return
	if points <= 0.0:
		return
	idle_time += delta
	var drain := tuning.rank_drain[rank] if rank < tuning.rank_drain.size() else 0.0
	if idle_time >= tuning.idle_delay:
		drain += tuning.idle_drain
	if drain > 0.0:
		points = maxf(0.0, points - drain * delta)
		_update_rank()
		changed.emit(value(), active)
