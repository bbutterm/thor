extends RefCounted
## Описание зала room_07 «Причал с драккаром» для генератора (tools/build_scenes.gd → room_defs, 7-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 7. Причал с драккаром (GDD 16) — корабль (модель Quaternius Pirate Kit поверх невидимой коллизии: палуба 2.2 м,
	# нос 3.2 м), склад на берегу 3 м. Наверх: сходни-ящики 1.1 м → палуба (залезание), прыжковая руна у склада.
	return {
		"file": "room_07", "title": "Причал с драккаром", "w": 26.0, "d": 30.0, "max_alive": 60,
		"blocks": [
			[Vector3(6, 1.1, 0), Vector3(5, 2.2, 15), "none"],
			[Vector3(6, 1.6, -9.0), Vector3(3, 3.2, 2), "none"],
			[Vector3(2.0, 0.55, 2), Vector3(3, 1.1, 2), "wood"],
			[Vector3(2.0, 0.55, -5), Vector3(3, 1.1, 2), "wood"],
			[Vector3(-8, 1.5, 4), Vector3(8, 3, 6), "stone_dark"],
		],
		"pillars": [],
		"models": [["res://assets/quaternius/pirate/Ship_Large.gltf", Vector3(6, K.SHIP_Y, 0), 90.0, 1.0]],
		"jump_pads": [[Vector3(-3, 0, 9), 8.0]],
		"enemies": [["grunt", Vector3(-4, 0, -6), 0], ["grunt", Vector3(-8, 0, -6), 0], ["thrower", Vector3(6, 2.3, 5), 0], ["bloated", Vector3(-9, 0, -9), 0], ["grunt", Vector3(6, 2.3, -4), 0], ["fodder", Vector3(-4, 0, -2), 0, 11, 2.375],
			["shaman", Vector3(-8, 3.1, 4), 1], ["merc", Vector3(6, 3.3, -9.5), 1], ["grunt", Vector3(6, 2.3, -4), 1], ["grunt", Vector3(6, 2.3, 5.5), 1], ["grunt", Vector3(-9, 0, -9), 1], ["grunt", Vector3(-8, 0, -6), 1], ["fodder", Vector3(-4, 0, -4), 1, 12, 2.5],
			["shieldbearer", Vector3(-2, 0, -8), 2], ["thrower", Vector3(6, 2.3, -6), 2], ["grunt", Vector3(6, 2.3, 5.5), 2], ["grunt", Vector3(-9, 0, -9), 2], ["grunt", Vector3(-8, 0, -6), 2], ["grunt", Vector3(-4, 0, -6), 2], ["fodder", Vector3(-5, 0, -10), 2, 13, 2.625]],
		"props": [["barrel", Vector3(-11, 0, -2)], ["barrel", Vector3(-10, 0, -1)], ["barrel", Vector3(-11, 0, 0)], ["crate", Vector3(-4, 0, 6)], ["crate", Vector3(-4, 0.92, 6)],
			["barrel", Vector3(5, 2.2, 6)], ["barrel", Vector3(7, 2.2, -3)], ["crate", Vector3(-11, 3.0, 6)], ["barrel", Vector3(-1, 0, -11)]],
	}
