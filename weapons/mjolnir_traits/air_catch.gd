extends MjolnirTraitHandler
## Приём «Перехват в воздухе»: сверх базовой поимки возвращает ещё руны.
## Ур. 2 — две дополнительные руны и небольшой подброс.

## Дополнительные руны сверх базовой поимки.
@export var restore_dash: int = 1
@export var restore_dash_lvl2: int = 2
## Ур. 2: подброс (вертикальная скорость не меньше, м/с)
@export var hop_lvl2: float = 5.0

## Сколько раз сработал (для тестов)
var catches: int = 0

func on_caught(h: MjolnirHand) -> void:
	var p := h.player
	if p == null or p.is_dead or p.is_on_floor() or p.is_climbing:
		return
	catches += 1
	var add := restore_dash_lvl2 if level >= 2 else restore_dash
	p.restore_mjolnir_runes(add)
	if level >= 2 and not p.is_slamming:
		p.velocity.y = maxf(p.velocity.y, hop_lvl2)
	FX.ring(p.get_parent(), p.global_position, 1.6, Color(0.6, 0.85, 1.0, 0.8), 0.25)
	p.camera_fx.kick_fov(4.0)
	StyleMeter.event(&"air_catch")
	mark()
