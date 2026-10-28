extends RefCounted
## Описание зала room_03 «Кольцо колонн» для генератора (tools/build_scenes.gd → room_defs, 3-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 3. Кольцо колонн — вокруг башни 5 м (супер-прыжок + двойной на неё)
	return {
		"file": "room_03", "title": "Кольцо колонн", "w": 28.0, "d": 28.0, "max_alive": 60,
		"blocks": [
			[Vector3(0, 2.5, -2), Vector3(4, 5, 4), "stone_dark"],
			[Vector3(0, 0.6, 4), Vector3(3, 1.2, 3), "wood"],
		],
		"pillars": K.ring_points(Vector3(0, 0, -2), 9.0, 8),
		"jump_pads": [[Vector3(-3.5, 0, 6.5), 9.0], [Vector3(3.5, 0, 6.5), 9.0]],
		# Башня — круглая (каменный барабан и деревянная площадка по коллизии 4 × 4)
		"dress": {"styles": {0: "tower"}},
		"enemies": [["grunt", Vector3(-5.5, 0, -7), 0], ["grunt", Vector3(6, 0, -8), 0], ["grunt", Vector3(-8, 0, -0.5), 0], ["grunt", Vector3(7.5, 0, 0), 0], ["bloated", Vector3(-10, 0, -6), 0], ["grunt", Vector3(10, 0, -10), 0], ["fodder", Vector3(-7.5, 0, -10), 0, 12, 2.5],
			["thrower", Vector3(0, 5.1, -2), 1], ["thrower", Vector3(-10, 0, -10), 1], ["grunt", Vector3(11, 0, -10), 1], ["grunt", Vector3(0, 0, -11), 1], ["grunt", Vector3(-8, 0, -0.5), 1], ["grunt", Vector3(-6, 0, -8), 1], ["fodder", Vector3(7.5, 0, -9.5), 1, 13, 2.625],
			["shaman", Vector3(0.5, 5.1, -1.5), 2], ["shieldbearer", Vector3(0, 0, -8), 2], ["grunt", Vector3(10, 0, -10), 2], ["grunt", Vector3(7.5, 0, 0), 2], ["grunt", Vector3(6, 0, -8), 2], ["grunt", Vector3(-8, 0, -0.5), 2], ["grunt", Vector3(0, 0, -11), 2], ["fodder", Vector3(-8, 0, -10), 2, 14, 2.75]],
		"props": K.ring_props(Vector3(0, 0, -2), 5.5, 8, "crate"),
	}
