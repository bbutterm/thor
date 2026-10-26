extends BodyTraitHandler
## «Пьяному море по колено» (Пьяный скальд): первый полученный удар в каждом зале не ранит.

var _armed: bool = true

func on_equip(_p: Player) -> void:
	_armed = true

func on_room_start(_p: Player) -> void:
	_armed = true

func on_damaged(p: Player, amount: float) -> float:
	# Падение в пропасть (урон 9999) не прощаем
	if not _armed or amount >= 9000.0:
		return amount
	_armed = false
	FX.ring(p.get_parent(), p.global_position + Vector3(0, 1.0, 0), 1.4, Color(1.0, 0.85, 0.45, 0.85), 0.3)
	ComicFX.pop("shrug", p.global_position + Vector3(0, 1.9, 0) - p.global_transform.basis.z * 1.2)
	mark("free_hit")
	return 0.0

## Удар в этом зале ещё не потрачен (для тестов)
func is_armed() -> bool:
	return _armed
