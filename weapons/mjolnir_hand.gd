extends Node
class_name MjolnirHand
## Мьёльнир в левой руке: ПКМ — метнуть, повторное ПКМ (или таймер) — вернуть.
## Сам полёт — в mjolnir_projectile.gd.

signal state_changed(in_hand: bool)

@export_group("Бросок")
@export var throw_speed: float = 32.0
@export var base_damage: float = 30.0
## Через сколько секунд молот сам летит обратно
@export var auto_return_after: float = 1.5
@export var return_speed: float = 36.0
## Насколько резко молот поворачивает к руке на возврате (дуга)
@export var return_turn_accel: float = 140.0
@export var max_wall_bounces: int = 2

@export_group("Цепная молния")
@export var chain_damage_ratio: float = 0.5
@export var chain_radius: float = 7.0

@export_group("Отдача")
@export var hit_hitstop: float = 0.04
@export var catch_shake: float = 0.15

var damage_mult: float = 1.0
var return_speed_mult: float = 1.0
var in_hand: bool = true
var projectile: Node3D = null

@export var player_path: NodePath = ^".."
@export var pivot_path: NodePath
@export var hand_mesh_path: NodePath

@onready var player: Player = get_node(player_path)
@onready var pivot: Node3D = get_node_or_null(pivot_path)
@onready var hand_mesh: Node = get_node_or_null(hand_mesh_path)

const REST_POS := Vector3(-0.5, -0.37, -1.0)
const REST_ROT := Vector3(-10, -15, 12)

func _ready() -> void:
	if pivot:
		pivot.position = REST_POS
		pivot.rotation_degrees = REST_ROT

## Цвет кожи и рукава (из тела BodyDef). Рука — ViewmodelArm или (старое) простой меш.
func set_hand_color(c: Color, sleeve: Color = Color(0, 0, 0, 0)) -> void:
	if hand_mesh is ViewmodelArm:
		(hand_mesh as ViewmodelArm).recolor(c, sleeve)
	elif hand_mesh is MeshInstance3D:
		(hand_mesh as MeshInstance3D).material_override = FX.make_material(c, 0.9)

func _physics_process(_delta: float) -> void:
	if player == null or player.is_dead or not player.input_enabled:
		return
	if Input.is_action_just_pressed("throw"):
		request_throw_or_recall()

func request_throw_or_recall() -> void:
	if in_hand:
		throw_hammer()
	elif projectile and is_instance_valid(projectile):
		projectile.call("start_return")

func throw_hammer() -> void:
	if not in_hand:
		return
	in_hand = false
	var proj: Node3D = preload("res://weapons/mjolnir_projectile.gd").new()
	player.get_parent().add_child(proj)
	var origin := player.get_aim_origin() + player.get_aim_forward() * 0.8 + player.global_transform.basis.x * -0.35
	proj.call("launch", self, origin, player.get_aim_forward() * throw_speed)
	projectile = proj
	if pivot:
		var tw := pivot.create_tween()
		tw.tween_property(pivot, "position", REST_POS + Vector3(0.3, 0.2, -0.4), 0.06)
		tw.tween_property(pivot, "position", REST_POS + Vector3(0, -0.8, 0), 0.1)
		tw.tween_callback(func() -> void: pivot.visible = false)
	player.camera_fx.add_trauma(0.12)
	Audio.play("sounds/sfx/hammer_throw.wav")
	state_changed.emit(false)

## Вызывается снарядом, когда молот вернулся в руку.
func on_caught() -> void:
	in_hand = true
	projectile = null
	if pivot:
		pivot.visible = true
		pivot.position = REST_POS + Vector3(0.15, 0.1, -0.35)
		pivot.rotation_degrees = REST_ROT + Vector3(30, 0, 0)
		var tw := pivot.create_tween().set_parallel(true)
		tw.tween_property(pivot, "position", REST_POS, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pivot, "rotation_degrees", REST_ROT, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	player.camera_fx.add_trauma(catch_shake)
	Audio.play("sounds/sfx/hammer_catch.wav")
	state_changed.emit(true)

func current_damage() -> float:
	return base_damage * damage_mult

func hand_point() -> Vector3:
	return player.get_aim_origin() + player.global_transform.basis.x * -0.4 + Vector3(0, -0.3, 0)

## Сбросить при смене зала (на всякий случай).
func force_return_instant() -> void:
	if projectile and is_instance_valid(projectile):
		projectile.queue_free()
	if not in_hand:
		on_caught()
