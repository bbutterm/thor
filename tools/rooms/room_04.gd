extends RefCounted
## Описание зала room_04 «Коридор Хель» для генератора (tools/build_scenes.gd → room_defs, 4-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 4. Коридор Хель — длинный зал, метатели в конце, укрытия
	return {
		"file": "room_04", "title": "Коридор Хель", "w": 16.0, "d": 34.0, "max_alive": 60,
		"blocks": [
			[Vector3(-4, 0.6, 6), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(4, 0.6, 0), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(-4, 0.6, -6), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(0, 1.0, -13), Vector3(10, 2, 3), "stone_dark"],
			# Открытые ворота внутри западной границы: боковые стены и перемычка,
			# пол и невидимая внешняя граница остаются непрерывными.
			[Vector3(-6.75, 1.8, 9.1), Vector3(2.5, 3.6, 0.6), "wood"],
			[Vector3(-6.75, 1.8, 13.9), Vector3(2.5, 3.6, 0.6), "wood"],
			[Vector3(-5.5, 3.45, 11.5), Vector3(0.7, 0.7, 5.4), "wood"],
		],
		"pillars": [],
		"enemies": [["thrower", Vector3(-3, 2.1, -13), 0], ["thrower", Vector3(3, 2.1, -13), 0], ["grunt", Vector3(-4, 0, -3), 0], ["grunt", Vector3(4.5, 0, -9), 0], ["grunt", Vector3(0, 0, 2), 0], ["grunt", Vector3(-5, 0, -10), 0], ["fodder", Vector3(-7.2, 0, 11.5), 0, 13, 2.625, {"entry_mode": "gate", "entry_target": Vector3(-3.5, 0.05, 11.5), "spread_axes": Vector2(0.1, 1.5), "entry_batch": 1}],
			["grunt", Vector3(-5, 0, -10), 1], ["bloated", Vector3(5, 0, -10), 1], ["grunt", Vector3(4, 0, -9), 1], ["squad", Vector3(0, 0, -8), 1, 1, 0.0, {"squad_options": ["loki_ambush", "loki_flank"]}], ["fodder", Vector3(-2, 0, -0.5), 1, 14, 2.75],
			["shieldbearer", Vector3(0, 0, -8), 2], ["bloated", Vector3(-5, 0, -10), 2], ["grunt", Vector3(5, 0, -10), 2], ["grunt", Vector3(0, 0, 2), 2], ["grunt", Vector3(-4, 0, -3), 2], ["fodder", Vector3(-1.5, 0, -1), 2, 10, 2.25]],
		"props": [["barrel", Vector3(-6.8, 0, 6.8)], ["barrel", Vector3(6, 0, 4)], ["crate", Vector3(-6, 0, -2)], ["crate", Vector3(6, 0, -6)], ["barrel", Vector3(0, 0, -4)]],
	}
