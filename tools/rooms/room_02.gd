extends RefCounted
## Описание зала room_02 «Ярусы Ётунов» для генератора (tools/build_scenes.gd → room_defs, 2-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 2. Ярусы — центральная платформа 2.6 м: нужен двойной или супер-прыжок
	return {
		"file": "room_02", "title": "Ярусы Ётунов", "w": 26.0, "d": 24.0, "max_alive": 20,
		"blocks": [
			[Vector3(0, 1.3, -3), Vector3(7, 2.6, 7), "stone_dark"],
			[Vector3(-10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(-4.5, 0.5, 2.5), Vector3(2, 1, 2), "wood"],
		],
		"pillars": [Vector3(-7, 0, 6), Vector3(7, 0, 6)],
		"jump_pads": [[Vector3(0, 0, 5), 8.0]],
		"enemies": [
			# П3: 16 + 18 (было 16 + 18 + 19); волна 2 — прежний состав с шаманом и свитой.
			["grunt", Vector3(-5, 0, -8), 0], ["grunt", Vector3(5, 0, -8), 0], ["thrower", Vector3(0, 2.7, -4), 0], ["thrower", Vector3(-10, 2.1, -7), 0], ["grunt", Vector3(-8, 0, 0), 0],
			["fodder", Vector3(3, 0, 5.5), 0, 6, 1.75], ["fodder", Vector3(-4.5, 0, -9), 0, 5, 1.625],
			["thrower", Vector3(10, 2.1, -7), 1], ["grunt", Vector3(-3, 0, 4), 1], ["grunt", Vector3(0.5, 0, 2), 1], ["grunt", Vector3(-5, 0, -8), 1], ["grunt", Vector3(-8, 0, 0), 1],
			["squad", Vector3(3.5, 0, 4), 1, 1, 0.0, {"squad": "shaman_escort", "squad_override": {"fodder": 7}, "squad_anchor_pos": Vector3(0, 2.7, -2)}],
			["fodder", Vector3(-4.5, 0, -9), 1, 5, 1.625]],
		"props": [["barrel", Vector3(-1, 2.6, -1)], ["barrel", Vector3(1, 2.6, -5)], ["crate", Vector3(-8, 0, 3)], ["crate", Vector3(8, 0, 3)], ["barrel", Vector3(0, 0, 3)]],
	}
