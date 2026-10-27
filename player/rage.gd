extends Node
class_name Rage
## Ярость (GDD 8): шкала копится за убийства в серии — между убийствами не больше kill_window секунд,
## иначе серия и шкала сбрасываются. Полная (kills_to_full убийств) — берсерк на berserk_time секунд:
## урон и скорость бега ×1.5, неуязвимость к стану (отбрасыванию), Один орёт. Музыка — блок Р.
## Узел «Rage» игрока (создаёт Player._ready). Убийства — из сигнала Run.kill_registered.

## value 0..1 — заполненность шкалы (в берсерке — сколько осталось), active — идёт берсерк
signal changed(value: float, active: bool)
signal berserk_started
signal berserk_ended

## Окно между убийствами серии, с
@export var kill_window: float = 3.0
## Сколько убийств в серии — полная шкала
@export var kills_to_full: int = 25
## Длительность берсерка, с
@export var berserk_time: float = 8.0
## Множители в берсерке
@export var damage_mult: float = 1.5
@export var speed_mult: float = 1.5
## Хит-стоп в момент включения берсерка, с
@export var hitstop_on_start: float = 0.12

var player: Player
var kills: int = 0
var active: bool = false
var _song_acc: float = 0.0
var berserk_left: float = 0.0
var _since_kill: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if player == null:
		player = get_parent() as Player
	if Run.has_signal("kill_registered"):
		Run.kill_registered.connect(_on_kill)

## Заполненность шкалы 0..1
func value() -> float:
	if active:
		return clampf(berserk_left / maxf(berserk_time, 0.01), 0.0, 1.0)
	return clampf(float(kills) / float(maxi(kills_to_full, 1)), 0.0, 1.0)

## Сколько секунд осталось до сброса серии (для HUD); 0 — серии нет
func window_left() -> float:
	return maxf(0.0, kill_window - _since_kill) if kills > 0 and not active else 0.0

func current_damage_mult() -> float:
	return damage_mult if active else 1.0

func current_speed_mult() -> float:
	return speed_mult if active else 1.0

## В берсерке Тора не сбивают: удары не отбрасывают (у Тора нет стана — это его «стан»)
func is_stun_immune() -> bool:
	return active

func _on_kill(_source: String) -> void:
	if player == null or player.is_dead:
		return
	add_kill()

## Убийство в серию (вызывает сигнал Run.kill_registered; тесты — напрямую)
func add_kill() -> void:
	if active:
		return
	kills += 1
	# Руна «Песнь берсерка»: Ярость копится быстрее (+30 % → +80 %) — дробная часть копится отдельно
	_song_acc += Run.rune_value("berserk_song")
	while _song_acc >= 1.0:
		_song_acc -= 1.0
		kills += 1
	_since_kill = 0.0
	if kills >= kills_to_full:
		start_berserk()
	else:
		changed.emit(value(), active)

func start_berserk() -> void:
	active = true
	berserk_left = berserk_time
	kills = 0
	_since_kill = 0.0
	Perf.mark("berserk_start")
	Odin.say("berserk")
	Dialogue.thor_bark("berserk", 1.0)
	if player:
		player.camera_fx.add_trauma(0.45)
		player.camera_fx.kick_fov(12.0)
		ComicFX.pop("berserk", player.global_position + Vector3(0, 1.8, 0) - player.global_transform.basis.z * 2.0, true)
	FX.hitstop(hitstop_on_start)
	Audio.play("sounds/sfx/enemy_growl.wav")
	berserk_started.emit()
	changed.emit(value(), active)

func end_berserk() -> void:
	if not active:
		return
	active = false
	berserk_left = 0.0
	kills = 0
	Perf.mark("berserk_end")
	Odin.say("rage_over")
	berserk_ended.emit()
	changed.emit(value(), active)

## Сброс без реплик (новый забег, смерть)
func reset() -> void:
	active = false
	berserk_left = 0.0
	kills = 0
	_since_kill = 0.0
	changed.emit(value(), active)

func _physics_process(delta: float) -> void:
	if player and player.is_dead:
		if active or kills > 0:
			reset()
		return
	if active:
		berserk_left -= delta
		changed.emit(value(), active)
		if berserk_left <= 0.0:
			end_berserk()
	elif kills > 0:
		_since_kill += delta
		if _since_kill > kill_window:
			# Серия прервалась — шкала пустеет
			kills = 0
			changed.emit(value(), active)
