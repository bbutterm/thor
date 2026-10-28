extends RefCounted
## Описание зала room_01 «Зал бочек» для генератора (tools/build_scenes.gd → room_defs, 1-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 1. Зал Бочек — разминка, много физики
	return {
		"file": "room_01", "title": "Зал бочек", "w": 24.0, "d": 24.0, "max_alive": 20,
		"blocks": [
			[Vector3(-6, 0.75, -3), Vector3(4, 1.5, 4), "wood"],
			[Vector3(6, 0.75, 2), Vector3(4, 1.5, 4), "wood"],
		],
		"pillars": [Vector3(-6, 0, 6), Vector3(6, 0, -6), Vector3(0, 0, 0)],
		# Открытая вышка: ступени с севера, площадка для удара-приземления.
		"watchtowers": [Vector3(9, 0, -2.5)],
		"jump_pads": [[Vector3(9.5, 0, 4.8), 8.0]],
		"enemies": [
			# П3: 16 + 16 (было 15 + 16 + 18), корм пачками по 5–7.
			["grunt", Vector3(-4, 0, -6), 0], ["grunt", Vector3(4, 0, -7), 0], ["grunt", Vector3(1, 0, -9), 0], ["bloated", Vector3(7, 0, -9), 0], ["thrower", Vector3(-6, 1.6, -3), 0],
			["fodder", Vector3(-8.5, 0, -10.5), 0, 6, 1.75, {"entry_mode": "edge", "entry_target": Vector3(-8.5, 0.05, -7), "spread_axes": Vector2(1.2, 0.35), "entry_batch": 1}], ["fodder", Vector3(-3, 0, -8.5), 0, 5, 1.625],
			["shieldbearer", Vector3(0, 0, -9), 1], ["thrower", Vector3(-6, 1.6, -3), 1], ["grunt", Vector3(7.5, 0, -8), 1],
			["fodder", Vector3(-8.5, 0, -8.5), 1, 5, 1.625],
			["squad", Vector3(-3.5, 0, -8.5), 1, 1, 0.0, {"squad": "pack", "squad_override": {"fodder": 6, "grunt": 2}}]],
		"props": K.ring_props(Vector3(0, 0, -3), 3.5, 6, "barrel") + [["crate", Vector3(-9, 0, 3)], ["crate", Vector3(-9, 0.95, 3)], ["crate", Vector3(9, 0, 7)], ["barrel", Vector3(8, 0, 8)]],
	}
