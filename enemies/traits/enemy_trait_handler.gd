extends Node
class_name EnemyTraitHandler
## Базовый обработчик черты моба (GDD 12.6): узел-ребёнок врага, как EliteHandler. Наследники переопределяют
## хуки: _apply_stats (до/при добавлении), on_hit (сигнал Enemy.hit_taken), свой ход — _trait_tick.
## Значок над головой прячется дальше EnemyTraits.icon_hide_distance от камеры (проверка раз в несколько кадров).

var def: EnemyTraitDef
var enemy: Enemy
var _icon_t: float = 0.0

func setup(e: Enemy, d: EnemyTraitDef) -> void:
	enemy = e
	def = d
	name = "Trait_" + d.id
	e.add_child(self)
	e.hit_taken.connect(on_hit)
	_apply_stats()

func _apply_stats() -> void:
	pass

func on_hit(_damage: float, _source: String) -> void:
	pass

func _trait_tick(_delta: float) -> void:
	pass

func alive() -> bool:
	return is_instance_valid(enemy) and not enemy.is_dead and enemy.is_inside_tree()

func _physics_process(delta: float) -> void:
	if not alive():
		return
	_trait_tick(delta)
	_icon_t -= delta
	if _icon_t <= 0.0:
		_icon_t = 0.2
		var mark := enemy.get_node_or_null("TraitMark") as Node3D
		var cam := enemy.get_viewport().get_camera_3d() if enemy.get_viewport() else null
		if mark and cam:
			mark.visible = cam.global_position.distance_to(enemy.global_position) < EnemyTraits.icon_hide_distance
