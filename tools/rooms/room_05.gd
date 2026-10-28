extends RefCounted
## Описание зала room_05 «Мост Биврёст (сломан)» для генератора (tools/build_scenes.gd → room_defs, 5-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 5. Мост — пониженная середина, два «берега»
	return {
		"file": "room_05", "title": "Мост Биврёст (сломан)", "w": 30.0, "d": 22.0, "max_alive": 20,
		"blocks": [
			[Vector3(-10.5, 1.0, 0), Vector3(9, 2, 22), "stone_dark"],
			[Vector3(10.5, 1.0, 0), Vector3(9, 2, 22), "stone_dark"],
			[Vector3(0, 1.75, -2), Vector3(12, 0.5, 2.5), "wood"],
		],
		"pillars": [Vector3(-3, 0, 6), Vector3(3, 0, -7)],
		"enemies": [
			# П3: 16 + 16 (было 21 + 15 + 16).
			["grunt", Vector3(-10, 2, -6), 0], ["grunt", Vector3(10, 2, -6), 0], ["grunt", Vector3(0, 0, -6), 0], ["thrower", Vector3(10, 2, 6), 0], ["merc", Vector3(12, 2, -8), 0],
			["fodder", Vector3(7.25, 2, 4), 0, 6, 1.75, {"entry_mode": "balcony", "entry_target": Vector3(4.4, 0.05, 4), "spread_axes": Vector2(0.35, 3.5), "entry_batch": 1}], ["fodder", Vector3(0, 0, 3), 0, 5, 1.625],
			["shaman", Vector3(12, 2, -5), 1], ["shieldbearer", Vector3(2, 2.1, -2), 1], ["grunt", Vector3(-10, 2, 4), 1], ["grunt", Vector3(10, 2, 2), 1], ["grunt", Vector3(-3, 0, 2), 1],
			["fodder", Vector3(0, 0, 2.5), 1, 6, 1.75], ["fodder", Vector3(0, 0, -6), 1, 5, 1.625]],
		"props": [["barrel", Vector3(-12, 2, 3)], ["barrel", Vector3(12, 2, -3)], ["crate", Vector3(0, 2.0, -2)], ["crate", Vector3(2, 0, 6)], ["barrel", Vector3(-2, 0, -8)]],
		"spawn_y": 2.0,
	}
