extends Node
class_name PlayerSlow
## Замедление Тора (элита «Ледяной»): компонент, который добавляется игроку извне и временно уменьшает
## player.move_speed. Если скорость за это время поменял кто-то другой (руны, тело) — новое значение
## считается базой. По окончании (и при удалении узла) база возвращается.

var mult: float = 1.0
var left: float = 0.0
var _base: float = 0.0
var _applied: float = -1.0

## Замедлить на time секунд (множитель скорости mult_). Повторный удар продлевает и берёт сильнейшее.
static func apply(p: Player, mult_: float, time: float) -> PlayerSlow:
	if p == null or time <= 0.0:
		return null
	Perf.mark("player_slow")
	var s := p.get_node_or_null("EliteSlow") as PlayerSlow
	if s == null:
		s = PlayerSlow.new()
		s.name = "EliteSlow"
		p.add_child(s)
	s.mult = minf(s.mult, mult_) if s.left > 0.0 else mult_
	s.left = maxf(s.left, time)
	s.set_physics_process(true)
	s._refresh()
	return s

## Текущий множитель скорости игрока от замедления (1 — нет).
static func factor(p: Player) -> float:
	var s := p.get_node_or_null("EliteSlow") as PlayerSlow if p else null
	return s.mult if s and s.left > 0.0 else 1.0

func _player() -> Player:
	return get_parent() as Player

func _refresh() -> void:
	var p := _player()
	if p == null:
		return
	if _applied < 0.0 or not is_equal_approx(p.move_speed, _applied):
		_base = p.move_speed
	_applied = _base * mult
	p.move_speed = _applied

func _physics_process(delta: float) -> void:
	left -= delta
	if left <= 0.0:
		_restore()
		mult = 1.0
		set_physics_process(false)
		return
	_refresh()

func _restore() -> void:
	var p := _player()
	if p and _applied >= 0.0 and is_equal_approx(p.move_speed, _applied):
		p.move_speed = _base
	_applied = -1.0

func _exit_tree() -> void:
	_restore()
