extends MjolnirTraitHandler
## Связка «Кратер» (Земля + Пике молотом, блок Б4): удар пике оставляет кратер — весь корм в радиусе
## падает замертво, остальных прибивает к полу.

## Радиус кратера — радиус удара-приземления × столько
@export var radius_mult: float = 1.5
@export var pin_time: float = 1.5
## Урон не-корму (корм погибает в любом случае)
@export var damage: float = 11.0

## Сколько корма уронил кратер (для тестов)
var fodder_dropped: int = 0
var craters: int = 0

func on_dive_slam(h: MjolnirHand, center: Vector3, power: float) -> void:
	var p := h.player
	var el := h.element_handler()
	var r := (el.slam_radius(power) if el else p.slam_base_radius) * radius_mult
	var parent := p.get_parent()
	for e in enemies_near(p.get_tree(), center + Vector3(0, 0.9, 0), r):
		if e.kind == Enemy.Kind.FODDER:
			hurt(e, e.health + 1.0, Vector3.DOWN * 4.0, "slam")
			fodder_dropped += 1
		else:
			hurt(e, damage, Vector3.ZERO, "slam")
			var s := ElementStatus.of(e, true)
			if s:
				s.pin(pin_time)
	craters += 1
	FX.shockwave(parent, center, r * 1.1, Color(0.8, 0.65, 0.45))
	FX.crack(parent, center, 99.0)
	FX.ring(parent, center, r, Color(0.75, 0.6, 0.4, 0.95), 0.45)
	FX.sparks(parent, center + Vector3(0, 0.3, 0), Color(0.55, 0.47, 0.4), 40, 11.0, 18.0, 0.16, 0.8)
	ComicFX.pop("quake", center + Vector3(0, 1.2, 0), true)
	p.camera_fx.add_trauma(0.5)
	FX.hitstop(0.08)
	Audio.play("sounds/sfx/slam.wav")
	mark()
