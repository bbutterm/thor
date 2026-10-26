extends Node3D
class_name JarlArm
## Рука-дубина Ярла Бьорна, брошенная бумерангом (GDD 14.2, фаза 1): летит к точке у Тора по дуге,
## крутится, возвращается к Ярлу. Бьёт Тора туда и обратно (по разу за проход). Всё время полёта —
## окно урона: Ярл без руки (jarl.gd). Меш — дубина WeaponMeshes (общий материал оружия).

signal caught

var damage: float = 20.0
var total_time: float = 3.0
## Доля полёта «туда», «зависание», остальное — «обратно»
var out_frac: float = 0.42
var hover_frac: float = 0.16
## Боковой изгиб дуги (м), знак — в какую сторону
var curve: float = 2.5
var owner_boss: Node3D = null

var _from: Vector3
var _target: Vector3
var _t: float = 0.0
var _hit_out: bool = false
var _hit_back: bool = false
var _model: Node3D
var _hover_pos: Vector3

static func launch(parent: Node, boss: Node3D, from: Vector3, target: Vector3, time: float, damage_: float) -> JarlArm:
	Perf.mark("jarl_arm")
	var a := JarlArm.new()
	a.owner_boss = boss
	a._from = from
	a._target = target
	a.total_time = maxf(0.5, time)
	a.damage = damage_
	a.curve = 2.5 if randf() < 0.5 else -2.5
	parent.add_child(a)
	a.global_position = from
	return a

func _ready() -> void:
	set_meta("transient", true)
	_model = WeaponMeshes.build("club")
	_model.scale = Vector3.ONE * 2.2
	add_child(_model)
	_hover_pos = _target

func _hand_pos() -> Vector3:
	if is_instance_valid(owner_boss):
		return owner_boss.global_position + Vector3(0, 2.4, 0)
	return _from

func _physics_process(delta: float) -> void:
	_t += delta
	var k := _t / total_time
	var pos: Vector3
	var back := false
	if k < out_frac:
		var u := k / out_frac
		var side := (_target - _from).cross(Vector3.UP).normalized()
		# Туда — почти прямо (увернуться вбок), обратно — дугой
		pos = _from.lerp(_target, ease(u, 0.6)) + side * sin(PI * u) * curve * 0.25
	elif k < out_frac + hover_frac:
		pos = _target + Vector3(0, sin(_t * 6.0) * 0.2, 0)
	else:
		back = true
		var u := clampf((k - out_frac - hover_frac) / (1.0 - out_frac - hover_frac), 0.0, 1.0)
		var to := _hand_pos()
		var side2 := (to - _target).cross(Vector3.UP).normalized()
		pos = _target.lerp(to, ease(u, 1.6)) + side2 * sin(PI * u) * curve
	global_position = pos
	_model.rotation.y += delta * 16.0
	_model.rotation.z = 1.2
	var p := get_tree().get_first_node_in_group("player") as Player
	if p and not p.is_dead and (p.global_position + Vector3(0, 0.9, 0)).distance_to(pos) < 1.3:
		if (not back and not _hit_out) or (back and not _hit_back):
			if back:
				_hit_back = true
			else:
				_hit_out = true
			if is_instance_valid(owner_boss):
				RunTracker.note_hit(owner_boss)
			var dir := (p.global_position - pos)
			dir.y = 0
			p.take_damage(damage, dir.normalized() * 8.0 + Vector3.UP * 3.0)
			ComicFX.pop("slam", pos)
	if k >= 1.0:
		caught.emit()
		queue_free()
