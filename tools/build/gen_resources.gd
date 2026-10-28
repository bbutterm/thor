extends RefCounted
class_name GenResources
## Генератор: ресурсы тел и рун (run/bodies, run/runes).
## Компонент SceneBuilder (этап 4 рефакторинга): числа и состояние — поля SceneBuilder (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — генератор.resources; нужные снаружи функции есть и на SceneBuilder.

var gen: SceneBuilder

func _init(owner_node: SceneBuilder) -> void:
	gen = owner_node

func build_resources() -> void:
	print("Ресурсы…")
	var bodies := [
		{"id": "berserker", "name": "Берсерк", "desc": "Много здоровья, бьёт тяжело, бегает медленно. Орёт.", "hp": 150.0, "speed": 7.5, "dash": 2, "axe": 1.3, "hammer": 1.0, "glory": 1.0, "hand": Color(1.0, 0.86, 0.78), "sleeve": Color(0.55, 0.22, 0.18), "melee": "axe", "ranged": ""},
		{"id": "hunter", "name": "Охотник", "desc": "Быстрый и хрупкий. Три руны Мьёльнира.", "hp": 80.0, "speed": 10.0, "dash": 3, "axe": 0.9, "hammer": 1.2, "glory": 1.0, "hand": Color(0.9, 0.76, 0.64), "sleeve": Color(0.32, 0.42, 0.28), "melee": "knife", "ranged": "crossbow"},
		{"id": "thrall", "name": "Батрак", "desc": "Всё слабое, но Слава ×2. Социальный лифт.", "hp": 60.0, "speed": 8.5, "dash": 2, "axe": 0.7, "hammer": 0.8, "glory": 2.0, "hand": Color(0.95, 0.82, 0.72), "sleeve": Color(0.55, 0.5, 0.42), "melee": "club", "ranged": ""},
	]
	# Тела и руны теперь данные по GDD (блок Г): существующие файлы не перезаписываем — правятся руками
	for b in bodies:
		if ResourceLoader.exists("res://run/bodies/%s.tres" % b.id):
			continue
		var r := BodyDef.new()
		r.id = b.id
		r.display_name = b.name
		r.description = b.desc
		r.max_health = b.hp
		r.move_speed = b.speed
		r.dash_charges = b.dash
		r.axe_damage_mult = b.axe
		r.hammer_damage_mult = b.hammer
		r.glory_mult = b.glory
		r.hand_color = b.hand
		r.sleeve_color = b.sleeve
		# Стартовое оружие — описания из weapons/defs/
		r.start_melee = load("res://weapons/defs/%s.tres" % b.melee) as WeaponDef
		r.start_ranged = load("res://weapons/defs/%s.tres" % b.ranged) as WeaponDef if b.ranged != "" else null
		ResourceSaver.save(r, "res://run/bodies/%s.tres" % b.id)
	var runes := [
		{"id": "axe_damage", "title": "Руна Тюра", "desc": "Урон оружия ближнего боя +25%", "glyph": "ᛏ", "color": Color(1.0, 0.55, 0.35)},
		{"id": "dash_charge", "title": "Копыта Слейпнира", "desc": "+1 руна Мьёльнира", "glyph": "ᛖ", "color": Color(0.5, 0.85, 1.0)},
		{"id": "hammer_power", "title": "Гнев Мьёльнира", "desc": "Молот бьёт на 40% сильнее и возвращается на 30% быстрее", "glyph": "ᛗ", "color": Color(0.55, 0.75, 1.0)},
		{"id": "slam_fire", "title": "Огонь Муспельхейма", "desc": "Удар-приземление поджигает землю на 2 секунды", "glyph": "ᚲ", "color": Color(1.0, 0.5, 0.15)},
		{"id": "max_health", "title": "Яблоко Идунн", "desc": "+30 к максимуму здоровья", "glyph": "ᛁ", "color": Color(0.5, 1.0, 0.5)},
		{"id": "dash_damage", "title": "Таран Хеймдалля", "desc": "Рывок сквозь врагов наносит 15 урона и отбрасывает", "glyph": "ᚱ", "color": Color(1.0, 0.85, 0.35)},
		{"id": "heal", "title": "Мёд поэзии", "desc": "Сразу лечит 50 здоровья. Вкусно.", "glyph": "ᚨ", "color": Color(1.0, 0.75, 0.3)},
	]
	for d in runes:
		if ResourceLoader.exists("res://run/runes/%s.tres" % d.id):
			continue
		var r := RuneDef.new()
		r.id = d.id
		r.title = d.title
		r.description = d.desc
		r.glyph = d.glyph
		r.color = d.color
		ResourceSaver.save(r, "res://run/runes/%s.tres" % d.id)
