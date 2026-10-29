extends RefCounted
class_name FeelSwitch
## Сравнение «старое / новое» для изменений ощущений партии 1 (NOW.md, П0): F6 в «Быстрой проверке».
## По умолчанию — новое. Ключи: hammer_cooldown (П1), hammer_recall (П5), hammer_power (П2), enemy_count (П3), boss_armor (П4),
## painted_textures (партия 10.1: текстуры залов, QuickTextures).

static var old_keys: Dictionary = {}

static func is_old(key: StringName) -> bool:
	return bool(old_keys.get(key, false))

static func set_old(key: StringName, value: bool) -> void:
	old_keys[key] = value

static func set_all_old(value: bool) -> void:
	for k in [&"hammer_cooldown", &"hammer_recall", &"hammer_power", &"enemy_count", &"boss_armor", &"painted_textures"]:
		old_keys[k] = value
	QuickTextures.apply(value)
