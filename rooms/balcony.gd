extends StaticBody3D
class_name Balcony
## Разрушаемый деревянный балкон (длинный дом Ярла, GDD 14.2 / 16): StaticBody3D (не CSG) — настил и
## столбы. break_apart() — телеграф (тряска, пыль) и обломки: доски-физтела на слое debris (7),
## с тем же мешем/материалом, что у настила (без новых материалов), живут debris_lifetime секунд.
## Ярл ломает балконы в фазе 3 (enemies/bosses/jarl.gd); кто стоял сверху — падает.
## Мосты и настилы обычных залов (генератор: блок "wood" над полом → Balcony со slam_breakable) ломает
## удар-приземление Тора сверху (Player._do_slam_impact → on_slam). Балконы длинного дома Ярла — нет
## (slam_breakable = false по умолчанию: фазе 2 они нужны целыми до фазы 3).

signal broken(balcony: Balcony)

## Сколько досок-обломков (не больше — физика)
@export var debris_count: int = 6
@export var debris_lifetime: float = 4.0
## Тряска перед обрушением (с)
@export var shake_time: float = 0.45
## Ломается ударом-приземлением Тора сверху (мосты деревни, Биврёст); с какой высоты падения (м)
@export var slam_breakable: bool = false
@export var slam_break_height: float = 1.0

var is_broken: bool = false
var _breaking: bool = false

func _ready() -> void:
	add_to_group("balconies")

## Верх настила (точка в центре, мировые координаты) — сюда прыгает Ярл.
func top_point() -> Vector3:
	var deck := get_node_or_null("Deck") as CollisionShape3D
	if deck and deck.shape is BoxShape3D:
		return deck.global_position + Vector3(0, (deck.shape as BoxShape3D).size.y * 0.5, 0)
	return global_position

## Стоит ли точка на этом балконе (сверху, в пределах настила).
func has_point_on_top(p: Vector3, margin: float = 0.3) -> bool:
	var deck := get_node_or_null("Deck") as CollisionShape3D
	if deck == null or not deck.shape is BoxShape3D:
		return false
	var size := (deck.shape as BoxShape3D).size
	var local := deck.global_transform.affine_inverse() * p
	return absf(local.x) <= size.x * 0.5 + margin and absf(local.z) <= size.z * 0.5 + margin and local.y > 0.0 and local.y < size.y * 0.5 + 2.5

## Удар-приземление Тора по настилу сверху (player.gd). true — ломается.
func on_slam(height: float) -> bool:
	if not slam_breakable or is_broken or _breaking or height < slam_break_height:
		return false
	Perf.mark("deck_slam_break")
	break_apart()
	return true

## Сломать (с тряской shake_time). instant — сразу (тесты).
func break_apart(instant: bool = false) -> void:
	if is_broken or _breaking:
		return
	_breaking = true
	Perf.mark("balcony_shake")
	var top := top_point()
	FX.burst(get_parent(), top, 1.5, Color(0.8, 0.7, 0.55, 0.45), shake_time)
	Audio.play("sounds/sfx/wall_splat.wav")
	if instant or shake_time <= 0.0:
		_collapse()
		return
	var tw := create_tween()
	var base := position
	for i in 6:
		tw.tween_property(self, "position", base + Vector3(randf_range(-0.06, 0.06), randf_range(-0.05, 0.0), randf_range(-0.06, 0.06)), shake_time / 6.0)
	tw.tween_callback(_collapse)

func _collapse() -> void:
	if is_broken:
		return
	is_broken = true
	Perf.mark("balcony_break")
	var parent := get_parent()
	var deck_mesh := get_node_or_null("Mesh") as MeshInstance3D
	var top := top_point()
	FX.burst(parent, top, 2.2, Color(0.75, 0.62, 0.45, 0.5), 0.35)
	FX.sparks(parent, top, Color(0.75, 0.55, 0.35), 18, 6.0)
	Audio.play("sounds/sfx/barrel_break.wav" if ResourceLoader.exists("res://sounds/sfx/barrel_break.wav") else "sounds/sfx/boss_slam.wav")
	ComicFX.pop("slam", top)
	if deck_mesh:
		_spawn_debris(parent, deck_mesh)
	broken.emit(self)
	queue_free()

## Доски: тот же меш настила, уменьшенный по длине (масштаб узла), — общий материал, свой пайплайн уже есть.
func _spawn_debris(parent: Node, deck_mesh: MeshInstance3D) -> void:
	var deck := get_node_or_null("Deck") as CollisionShape3D
	var size := (deck.shape as BoxShape3D).size if deck and deck.shape is BoxShape3D else Vector3(3, 0.3, 8)
	var long_x := size.x >= size.z
	var length := maxf(size.x, size.z)
	var piece_len := length / maxf(1.0, debris_count)
	for i in debris_count:
		var rb := RigidBody3D.new()
		rb.add_to_group("debris")
		rb.collision_layer = 1 << 6
		rb.collision_mask = 1 | (1 << 3) | (1 << 6)
		rb.mass = 2.0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var piece := Vector3(piece_len * 0.9, size.y, minf(size.x, size.z) * 0.5) if long_x else Vector3(minf(size.x, size.z) * 0.5, size.y, piece_len * 0.9)
		bs.size = piece
		cs.shape = bs
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = deck_mesh.mesh
		mi.material_override = deck_mesh.material_override
		mi.scale = piece / size
		rb.add_child(mi)
		parent.add_child(rb)
		var t := (i + 0.5) / debris_count - 0.5
		var off := Vector3(t * length, 0, randf_range(-0.4, 0.4)) if long_x else Vector3(randf_range(-0.4, 0.4), 0, t * length)
		rb.global_position = deck_mesh.global_position + off
		rb.rotation = Vector3(randf_range(-0.3, 0.3), randf_range(-0.4, 0.4), randf_range(-0.3, 0.3))
		rb.apply_central_impulse(Vector3(randf_range(-2, 2), randf_range(0.5, 2.5), randf_range(-2, 2)) * rb.mass)
		rb.apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2)) * rb.mass)
		var tw := rb.create_tween()
		tw.tween_interval(debris_lifetime)
		tw.tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
		tw.tween_callback(rb.queue_free)
