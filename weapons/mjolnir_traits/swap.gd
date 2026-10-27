extends MjolnirTraitHandler
## Приём «Обмен» (блок Б4, группа «к молоту» — с Притяжением не берётся): ПКМ по ЛЕТЯЩЕМУ молоту —
## Тор и молот мгновенно меняются местами (уход из окружения, заход за спину щитоносцу). Молот оказывается
## там, где стоял Тор, и сразу летит к руке — сквозь толпу, которую Тор только что бросил.
## Воткнутый молот ПКМ возвращает как обычно. Ур. 2 — в точке прибытия волна, раскидывающая врагов.

## Неуязвимость Тора сразу после обмена (с)
@export var arrive_invuln: float = 0.35
## Ур. 2: волна в точке прибытия
@export var burst_radius: float = 3.0
@export var burst_damage: float = 11.0
@export var burst_knockback: float = 9.0

## Счётчики для тестов
var swaps: int = 0
var bursts: int = 0

func on_recall_start(proj: MjolnirProjectile, by_player: bool) -> void:
	if not by_player or proj.recalled_from_stuck or proj.is_clone:
		return
	var p := hand.player
	if p == null or p.is_dead:
		return
	var from := p.global_position
	var to := _safe_point(p, proj.global_position - Vector3(0, 0.9, 0), from)
	if to == Vector3.INF:
		return
	mark()
	swaps += 1
	p.global_position = to
	p.velocity.y = maxf(p.velocity.y, 0.0)
	p._air_peak_y = to.y
	p._invuln_left = maxf(p._invuln_left, arrive_invuln)
	# Молот — на место Тора, дальше обычный возврат к руке (бьёт всех на пути)
	proj.global_position = from + Vector3(0, 1.0, 0)
	proj.vel = (p.global_position - from).normalized() * 0.1
	proj.hit_ids.clear()
	var parent := p.get_parent()
	FX.burst(parent, from + Vector3(0, 1.0, 0), 0.8, Color(0.55, 0.85, 1.0, 0.6), 0.2)
	FX.burst(parent, to + Vector3(0, 1.0, 0), 0.8, Color(0.55, 0.85, 1.0, 0.6), 0.2)
	FX.lightning(parent, from + Vector3(0, 1.0, 0), to + Vector3(0, 1.0, 0), 0.2)
	p.camera_fx.kick_fov(10.0)
	p.camera_fx.speed_lines_pulse()
	Audio.play("sounds/sfx/dash.wav")
	StyleMeter.event(&"hammer_swap")
	if level >= 2:
		_burst(p, to)
	hand.trait_call(&"on_swap", [hand, from, to])

## Свободная точка для капсулы игрока: от want к fallback, первая без пересечения с миром
func _safe_point(p: Player, want: Vector3, fallback: Vector3) -> Vector3:
	var col := p.get_node_or_null("Collider") as CollisionShape3D
	if col == null or col.shape == null:
		return want
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = col.shape
	q.collision_mask = 1
	q.exclude = [p.get_rid()]
	for i in 9:
		var t := float(i) / 8.0
		var pt := want.lerp(fallback, t)
		q.transform = Transform3D(Basis.IDENTITY, pt + col.position)
		if space.intersect_shape(q, 1).is_empty():
			return pt
	return Vector3.INF

func _burst(p: Player, center: Vector3) -> void:
	bursts += 1
	for e in enemies_near(p.get_tree(), center + Vector3(0, 0.9, 0), burst_radius):
		var dir := e.global_position - center
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		hurt(e, burst_damage, dir * burst_knockback + Vector3.UP * 4.0, "hammer")
	FX.ring(p.get_parent(), center, burst_radius, Color(0.6, 0.85, 1.0, 0.9), 0.3)
