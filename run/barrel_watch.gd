extends Node
class_name BarrelWatch
## Бочка «разбита» (блок К, GDD 15.2: бочка — 3–8 серебра), если её отбросило быстрее
## Economy.barrel_break_speed: удар-приземление, Мьёльнир, сильный удар, таран, падение с высоты.
## Разбитая бочка разлетается щепками и исчезает, серебро рассыпается монетами.
## Бочки — обычные RigidBody3D из props/barrel.tscn (без своего скрипта), поэтому следим отсюда.

const BARREL_SCENE := "res://props/barrel.tscn"
const WOOD := Color(0.55, 0.36, 0.2)
## Проверять раз в столько физических кадров
const EVERY := 2

var _frame: int = 0

func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame % EVERY != 0:
		return
	var limit := Silver.cfg().barrel_break_speed
	for n in get_tree().get_nodes_in_group("props"):
		var rb := n as RigidBody3D
		if rb == null or rb.scene_file_path != BARREL_SCENE or rb.is_queued_for_deletion():
			continue
		if rb.linear_velocity.length() > limit:
			break_barrel(rb)

static func break_barrel(rb: RigidBody3D) -> void:
	Perf.mark("barrel_break")
	var parent := rb.get_parent()
	var pos := rb.global_position + Vector3(0, 0.5, 0)
	FX.sparks(parent, pos, WOOD, 16, 6.0, 14.0, 0.09, 0.5)
	FX.burst(parent, pos, 0.7, Color(0.8, 0.6, 0.35, 0.5), 0.25)
	Audio.play("sounds/sfx/barrel_break.wav")
	rb.remove_from_group("props")
	rb.queue_free()
	Silver.drop(parent, pos, Silver.barrel_amount())
