extends RefCounted
## Описание зала room_06 «Склад медовухи» для генератора (tools/build_scenes.gd → room_defs, 6-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 6. Склад медовухи — штабеля ящиков, крушить всё
	return {
		"file": "room_06", "title": "Склад медовухи", "w": 26.0, "d": 26.0, "max_alive": 20,
		"blocks": [
			[Vector3(-7, 1.0, -5), Vector3(5, 2, 3), "wood"],
			[Vector3(7, 1.0, 1), Vector3(5, 2, 3), "wood"],
		],
		"pillars": [Vector3(0, 0, -4)],
		"watchtowers": [Vector3(10, 0, -4)],
		"enemies": [
			# П3: 16 + 16 (было 15 + 16 + 18).
			["grunt", Vector3(4, 0, -9.5), 0], ["grunt", Vector3(0.5, 0, -11), 0], ["bloated", Vector3(-4, 0, -9), 0], ["merc", Vector3(8, 0, -9), 0], ["grunt", Vector3(-6, 0, 4), 0],
			["fodder", Vector3(-0.5, 0, -8), 0, 6, 1.75], ["fodder", Vector3(6.5, 0, -10), 0, 5, 1.625],
			["shaman", Vector3(-7.5, 2.1, -5.5), 1], ["shieldbearer", Vector3(0, 0, -9), 1], ["grunt", Vector3(8, 0, -9), 1], ["grunt", Vector3(-4, 0, -9), 1], ["grunt", Vector3(6, 0, -6), 1],
			["fodder", Vector3(-5.5, 0, 7.5), 1, 6, 1.75], ["fodder", Vector3(6.5, 0, -10), 1, 5, 1.625]],
		"props": K.stack_props(Vector3(-3, 0, 3)) + K.stack_props(Vector3(3, 0, -8)) + K.stack_props(Vector3(-9, 0, 5)) + [["barrel", Vector3(9, 0, 8)], ["barrel", Vector3(10, 0, 7)], ["barrel", Vector3(-10, 0, -10)]],
		# Плакат «Разыскивается» (Локи) на западной стене склада, у входа
		"decor": [["wanted_poster", Vector3(-13 + K.WALL_INSET, 1.9, 1.0), 90.0, 1.5]],
		# Разлитая медовуха у штабелей и бочек
		"decals": [["puddle_mead", Vector3(9.5, 0, 6.5), 40.0, 2.6], ["puddle_mead", Vector3(-1.5, 0, 5.0), 200.0, 1.8]],
	}
