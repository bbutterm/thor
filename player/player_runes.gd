extends RefCounted
class_name PlayerRunes
## Руны забега (GDD 11): пересчёт от рун, множители урона, крит, «Зов грома», «Огненный шаг»,
## проклятые руны Локи.
## Компонент игрока (этап 2 рефакторинга): числа и состояние — поля Player (их ставят сцена, тела
## и тесты), здесь только логика. Доступ — player.runes; публичные функции есть и на Player.

var p: Player

func _init(player: Player) -> void:
	p = player

func recalc_from_runes(run: Node, full_heal: bool = false) -> void:
	var body: BodyDef = run.body if run else null
	var base_hp := body.max_health if body else p.max_health
	var old_max := p.max_health
	# Руны по уровням (GDD 11, Run.rune_value: уровень 1–3, у жреца ×2)
	p.max_health = base_hp + run.rune_value("max_health")
	p.dash_charges_max = (body.dash_charges if body else p.dash_charges_base) + int(run.rune_value("dash_charge")) + int(run.rune_value("loki_spin"))
	p._rune_dash_recharge_mult = run.rune_value("dash_charge", true) if run.rune_level("dash_charge") > 0 else 1.0
	p.axe.damage_mult = (body.axe_damage_mult if body else 1.0) * (1.0 + run.rune_value("axe_damage"))
	p.mjolnir.damage_mult = (body.hammer_damage_mult if body else 1.0) * (1.0 + run.rune_value("hammer_power"))
	p.mjolnir.return_speed_mult = 1.0 + run.rune_value("hammer_power", true)
	p.extra_jumps = (p.movement_profile.extra_jumps if p.movement_profile else 1) + int(run.rune_value("valkyrie_wings"))
	p.shield_max = run.rune_value("sif_shield")
	p.shield = maxf(p.shield, p.shield_max) if full_heal else minf(p.shield, p.shield_max)
	if full_heal:
		p.health = p.max_health
		p.dash_charges = p.dash_charges_max
	else:
		p.health = minf(p.max_health, p.health + maxf(0.0, p.max_health - old_max))
		p.dash_charges = mini(p.dash_charges + 1, p.dash_charges_max)
	p._emit_all()

## Множитель урона от рун: «Нож в спину Локи» (удар мили в спину), проклятые руны Локи.
func _rune_damage_mult(target: Object, source: String) -> float:
	var m := 1.0
	if Run.rune_level("loki_hiccup") > 0:
		m *= Run.rune_value("loki_hiccup")
	if Run.rune_level("loki_glass") > 0:
		m *= Run.rune_value("loki_glass")
	var e := target as Enemy
	if e and source.begins_with("melee") and Run.rune_level("loki_backstab") > 0:
		var to_p := p.global_position - e.global_position
		to_p.y = 0
		if to_p.length() > 0.01 and e.global_transform.basis.z.dot(to_p.normalized()) < -0.35:
			m *= Run.rune_value("loki_backstab")
	return m

## Крит (GDD 8): базовые 5 % + «Глаз ворона». Молнии, огонь и стены не критуют.
func _roll_crit(source: String) -> bool:
	if not (source.begins_with("melee") or source == "ranged" or source == "hammer"):
		return false
	return randf() < p.crit_chance_base + Run.rune_value("raven_eye")

func _on_crit(target: Object) -> void:
	Perf.mark("crit")
	FX.hitstop(p.crit_hitstop)
	Audio.sfx("critical_hit")
	var t3 := target as Node3D
	if t3:
		FX.sparks(p.get_parent(), t3.global_position + Vector3(0, 1.4, 0), Color(1, 0.9, 0.2), 12, 6.0)

## «Зов грома»: каждый N-й удар мили — молния с неба по цели (1 У).
func _rune_on_hit(target: Object, source: String) -> void:
	if not source.begins_with("melee") or Run.rune_level("thunder_call") == 0:
		return
	p._thunder_hits += 1
	if p._thunder_hits < int(Run.rune_value("thunder_call")):
		return
	p._thunder_hits = 0
	var t3 := target as Node3D
	if t3 == null or not is_instance_valid(t3):
		return
	var top := t3.global_position + Vector3(randf_range(-0.5, 0.5), 9.0, randf_range(-0.5, 0.5))
	FX.lightning(p.get_parent(), top, t3.global_position + Vector3(0, 1.0, 0), 0.3)
	Audio.play("sounds/sfx/lightning.wav")
	Perf.mark("thunder_call")
	if t3.has_method("take_hit") and not t3.get("is_dead"):
		t3.call("take_hit", p.thunder_call_damage, Vector3.UP * 2.0, "lightning")

## «Огненный шаг»: рывок оставляет огонь.
func _rune_on_dash() -> void:
	if Run.rune_level("fire_step") == 0:
		return
	var fire := preload("res://weapons/fire_zone.gd").new()
	p.get_parent().add_child(fire)
	fire.setup(p.global_position, 1.6, Run.rune_value("fire_step"), 18.0)

## Проклятые руны Локи: икота (подпрыгивает сам) и «вертушка» (камера крутится на 180°).
func _rune_tick(delta: float) -> void:
	if Run.rune_level("loki_hiccup") > 0:
		p._hiccup_t += delta
		if p._hiccup_t >= p.hiccup_period:
			p._hiccup_t = 0.0
			if p.is_on_floor():
				p.velocity.y = p.jump_velocity * 0.6
			p.camera_fx.add_trauma(0.1)
			Perf.mark("loki_hiccup")
	if Run.rune_level("loki_spin") > 0:
		p._spin_t -= delta
		if p._spin_t <= 0.0 and randf() < p.spin_chance_per_sec * delta:
			p._spin_t = 6.0
			p.rotation_target.y += PI
			p.camera_fx.add_trauma(0.2)
			Perf.mark("loki_spin")
