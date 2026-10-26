extends Node
class_name EliteHandler
## Базовый обработчик модификатора элиты: узел-ребёнок врага. Наследники переопределяют нужные хуки.
## Хуки вызывает враг (enemy.gd): filter_damage — из take_hit (до HP), on_struck_player — по сигналу
## struck_player (удар дошёл до Тора), on_died — по сигналу died. Свой ход — в _physics_process.

var mod: EliteModifier
var enemy: Enemy

## До add_child врага (как make_elite): можно менять характеристики.
func setup(e: Enemy, m: EliteModifier) -> void:
	enemy = e
	mod = m
	name = "Elite_" + m.id
	e.elite_handlers.append(self)
	e.add_child(self)
	e.struck_player.connect(on_struck_player)
	e.died.connect(func(_x: Enemy) -> void: on_died())
	_apply_stats()

func _apply_stats() -> void:
	pass

## Сколько урона дойдёт до HP (0 — поглощён).
func filter_damage(damage: float, _knockback: Vector3, _source: String) -> float:
	return damage

func on_struck_player(_amount: float) -> void:
	pass

func on_died() -> void:
	pass

func label_suffix() -> String:
	return ""

func alive() -> bool:
	return is_instance_valid(enemy) and not enemy.is_dead and enemy.is_inside_tree()
