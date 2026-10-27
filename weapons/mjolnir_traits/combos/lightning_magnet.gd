extends MjolnirTraitHandler
## Связка «Грозовой магнит» (Молния + Магнит, блок Б4): пока воткнутый молот стягивает толпу, по ней
## раз в interval бьёт цепной разряд; при возврате (раскидывание Магнита) молния прыгает от каждого.

@export var interval: float = 0.6
@export var damage: float = 8.0
## Возврат: от каждого раскиданного молния прыгает ещё на столько врагов
@export var recall_chain: int = 2
@export var recall_chain_damage: float = 11.0

## Сколько разрядов было (для тестов)
var discharges: int = 0

func _magnet_radius() -> float:
	var m := hand.trait_handler(&"magnet")
	if m == null:
		return 6.0
	return float(m.get("radius_lvl2") if m.level >= 2 else m.get("radius"))

func on_stuck_tick(proj: MjolnirProjectile, delta: float) -> void:
	if not proj.data.get("magnet_armed", false):
		return
	var t: float = float(proj.data.get("thunder_magnet_t", 0.3)) - delta
	if t > 0.0:
		proj.data["thunder_magnet_t"] = t
		return
	proj.data["thunder_magnet_t"] = interval
	var el := hand.element_handler()
	var hp := proj.global_position
	var any := false
	for e in enemies_near(proj.get_tree(), hp, _magnet_radius()):
		FX.lightning(proj.fx_parent(), hp, e.global_position + Vector3(0, 1.0, 0), 0.15)
		hurt(e, damage * proj.damage_mult, Vector3.UP * 1.0, "lightning")
		var s := ElementStatus.of(e, true)
		if s:
			s.shock(float(el.get("shock_time")) if el and el.get("shock_time") != null else 5.0)
		any = true
	if any:
		discharges += 1
		Audio.play("sounds/sfx/lightning.wav")
		mark()

func on_recall_start(proj: MjolnirProjectile, _by_player: bool) -> void:
	# Магнит раскидал толпу (его хук раньше и снимает magnet_armed) — цепь от каждого
	if proj.data.get("thunder_magnet_t", null) == null:
		return
	proj.data.erase("thunder_magnet_t")
	var el := hand.element_handler()
	if el == null or not el.has_method("chain"):
		return
	for e in enemies_near(proj.get_tree(), proj.global_position, _magnet_radius()):
		el.call("chain", e, recall_chain_damage, recall_chain, 6.0)
