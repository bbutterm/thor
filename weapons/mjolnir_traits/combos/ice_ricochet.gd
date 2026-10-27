extends MjolnirTraitHandler
## Связка «Ледяной рикошет» (Лёд + Рикошет, блок Б4): каждый отскок молота (от стены или врага)
## оставляет на полу ледяную корку и промораживает всех вокруг.

@export var crust_radius: float = 1.6
@export var crust_time: float = 4.0
@export var crust_fall_stun: float = 0.8
@export var chill_radius: float = 2.5
@export var max_crusts: int = 6

var _crusts: Array[Node] = []
## Сколько корок оставил (для тестов)
var crusts: int = 0

func on_hit_world(proj: MjolnirProjectile, pos: Vector3, _normal: Vector3, stuck: bool) -> void:
	if not stuck:
		_crust(proj, pos)

func on_hit_enemy(proj: MjolnirProjectile, enemy: Node3D, _damage: float) -> void:
	# Отскок от врага — Рикошет уже записал его в ric_hit (его хук идёт раньше связок)
	var hit: Dictionary = proj.data.get("ric_hit", {})
	if hit.has(enemy.get_instance_id()):
		_crust(proj, enemy.global_position + Vector3(0, 0.5, 0))

func _crust(proj: MjolnirProjectile, pos: Vector3) -> void:
	var hit := floor_below(proj, pos, 5.0)
	if hit.is_empty():
		return
	_crusts.assign(_crusts.filter(func(z: Variant) -> bool: return is_instance_valid(z) and not (z as Node).is_queued_for_deletion()))
	while _crusts.size() >= maxi(1, max_crusts):
		_crusts.pop_front().queue_free()
	var ice := preload("res://weapons/ice_zone.gd").new()
	proj.fx_parent().add_child(ice)
	ice.setup(hit.position, crust_radius, crust_time, crust_fall_stun)
	_crusts.append(ice)
	crusts += 1
	FX.ice_hit(proj.fx_parent(), hit.position, 0.8)
	var el := hand.element_handler()
	if el:
		for e in enemies_near(proj.get_tree(), (hit.position as Vector3) + Vector3(0, 0.9, 0), chill_radius):
			el.apply_element(e, 1.0, hit.position, null)
	mark()
