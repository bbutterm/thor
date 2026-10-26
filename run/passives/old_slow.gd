extends BodyTraitHandler
## «Кряхтит» (Старый жрец): медленный (скорость тела 6.5) и кряхтит при прыжке — слово «КХЕ!» и звук.

@export_range(0.0, 1.0) var groan_chance: float = 0.6

func on_jump(p: Player) -> void:
	if randf() >= groan_chance:
		return
	Audio.play("sounds/land.ogg")
	ComicFX.pop("groan", p.global_position + Vector3(0, 1.9, 0) - p.global_transform.basis.z * 1.2)
	mark("groan")
