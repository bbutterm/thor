extends RefCounted
## Описание зала room_02 «Ярусы Ётунов» для генератора (tools/build_scenes.gd → room_defs, 2-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 2. Ярусы — центральная платформа 2.6 м: нужен двойной или супер-прыжок
	return {
		"file": "room_02", "title": "Ярусы Ётунов", "w": 26.0, "d": 24.0, "max_alive": 60,
		"blocks": [
			[Vector3(0, 1.3, -3), Vector3(7, 2.6, 7), "stone_dark"],
			[Vector3(-10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(-4.5, 0.5, 2.5), Vector3(2, 1, 2), "wood"],
		],
		"pillars": [Vector3(-7, 0, 6), Vector3(7, 0, 6)],
		"jump_pads": [[Vector3(0, 0, 5), 8.0]],
		"enemies": [["grunt", Vector3(-5, 0, -8), 0], ["grunt", Vector3(5, 0, -8), 0], ["thrower", Vector3(0, 2.7, -4), 0], ["thrower", Vector3(-10, 2.1, -7), 0], ["grunt", Vector3(-8, 0, 0), 0], ["fodder", Vector3(3, 0, 5.5), 0, 11, 2.375],
			["thrower", Vector3(10, 2.1, -7), 1], ["grunt", Vector3(-3, 0, 4), 1], ["grunt", Vector3(0.5, 0, 2), 1], ["shaman", Vector3(0, 2.7, -2), 1], ["grunt", Vector3(-5, 0, -8), 1], ["grunt", Vector3(-8, 0, 0), 1], ["fodder", Vector3(3.5, 0, 4), 1, 12, 2.5],
			["merc", Vector3(-8, 0, 0), 2], ["bloated", Vector3(6, 0, -10), 2], ["grunt", Vector3(3, 0, 4), 2], ["grunt", Vector3(-3, 0, 4), 2], ["grunt", Vector3(-5.5, 0, -6), 2], ["grunt", Vector3(5, 0, -8), 2], ["fodder", Vector3(-4.5, 0, -9), 2, 13, 2.25]],
		"props": [["barrel", Vector3(-1, 2.6, -1)], ["barrel", Vector3(1, 2.6, -5)], ["crate", Vector3(-8, 0, 3)], ["crate", Vector3(8, 0, 3)], ["barrel", Vector3(0, 0, 3)]],
	}
