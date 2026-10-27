extends MjolnirTraitHandler
## Связка «Ураганный рывок» (Ветер + Притяжение к молоту, блок Б4): пока Тор летит к молоту, врагов
## на пути сдувает в стороны, а на прилёте — вихрь сносит толпу вокруг (в стены, с краёв и балконов).

@export var path_radius: float = 2.6
@export var path_push: float = 14.0
@export var arrive_radius: float = 5.5
@export var arrive_push: float = 18.0
@export var arrive_lift: float = 6.0
@export var arrive_damage: float = 5.0

var _pushed: Dictionary = {}
## Сколько раз сработал вихрь прилёта (для тестов)
var gusts: int = 0

func on_recall_start(_proj: MjolnirProjectile, _by_player: bool) -> void:
	_pushed.clear()

func on_recall_tick(_proj: MjolnirProjectile, _delta: float) -> void:
	var pull := hand.trait_handler(&"pull_to_hammer")
	if pull == null or not pull.call("is_pulling"):
		return
	var p := hand.player
	var fwd := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	for e in enemies_near(p.get_tree(), p.global_position + Vector3(0, 0.9, 0), path_radius):
		if _pushed.has(e.get_instance_id()):
			continue
		_pushed[e.get_instance_id()] = true
		var side := fwd.cross(Vector3.UP)
		if side.dot(e.global_position - p.global_position) < 0.0:
			side = -side
		MjolnirElementHandler.push_enemy(e, (side + fwd * 0.4).normalized() * path_push + Vector3.UP * 3.0)
		FX.smoke(p.get_parent(), e.global_position + Vector3(0, 0.6, 0), 0.9, Color(0.85, 0.95, 0.9, 0.7))

func on_pull_arrive(h: MjolnirHand, pos: Vector3) -> void:
	var p := h.player
	var parent := p.get_parent()
	for e in enemies_near(p.get_tree(), pos + Vector3(0, 0.9, 0), arrive_radius):
		var dir := e.global_position - pos
		dir.y = 0
		var d := dir.length()
		dir = dir / d if d > 0.01 else Vector3.FORWARD
		var falloff := clampf(1.0 - d / arrive_radius, 0.5, 1.0)
		hurt(e, arrive_damage, Vector3.ZERO, "hammer")
		if is_instance_valid(e) and not e.is_dead:
			MjolnirElementHandler.push_enemy(e, dir * arrive_push * falloff + Vector3.UP * arrive_lift * falloff)
	FX.ring(parent, pos, arrive_radius, Color(0.85, 0.95, 0.9, 0.85), 0.4)
	for i in 6:
		var a := TAU * i / 6.0
		FX.smoke(parent, pos + Vector3(cos(a) * arrive_radius * 0.5, 0.4, sin(a) * arrive_radius * 0.5), 1.2, Color(0.85, 0.95, 0.9, 0.75))
	ComicFX.pop("gust", pos + Vector3(0, 1.2, 0), true)
	Audio.sfx("wind_gust", "sounds/sfx/dash.wav")
	gusts += 1
	mark()
