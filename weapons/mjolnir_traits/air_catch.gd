extends MjolnirTraitHandler
## Приём «Перехват в воздухе» (блок Б4): поймал молот в прыжке — восстанавливаются двойной прыжок
## (и отскоки от стены) и заряд рывка; можно долго не касаться земли. Управление — как у базы.
## Ур. 2 — восстанавливаются все заряды рывка и Тора чуть подбрасывает.

## Сколько зарядов рывка вернуть (ур. 1)
@export var restore_dash: int = 1
## Ур. 2: подброс (вертикальная скорость не меньше, м/с)
@export var hop_lvl2: float = 5.0

## Сколько раз сработал (для тестов)
var catches: int = 0

func on_caught(h: MjolnirHand) -> void:
	var p := h.player
	if p == null or p.is_dead or p.is_on_floor() or p.is_climbing:
		return
	catches += 1
	p._jumps_left = p.extra_jumps
	p._wall_jumps_left = p.wall_jumps
	var add := p.dash_charges_max if level >= 2 else restore_dash
	p.dash_charges = mini(p.dash_charges_max, p.dash_charges + add)
	p.dash_charges_changed.emit(p.dash_charges, p.dash_charges_max, 0.0)
	if level >= 2 and not p.is_slamming:
		p.velocity.y = maxf(p.velocity.y, hop_lvl2)
	FX.ring(p.get_parent(), p.global_position, 1.6, Color(0.6, 0.85, 1.0, 0.8), 0.25)
	p.camera_fx.kick_fov(4.0)
	StyleMeter.event(&"air_catch")
	mark()
