extends BodyTraitHandler
## «Пьяный прицел» (Пьяный скальд): прицел покачивается (камера плавает по двум синусоидам).

## Размах покачивания, градусы
@export var wobble_deg: float = 1.6

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"aim_wobble_deg":
		return float(value) + wobble_deg
	return value
