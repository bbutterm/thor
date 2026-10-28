extends RefCounted
## Описание зала room_08 «Яма-колизей» для генератора (tools/build_scenes.gd → room_defs, 8-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 8. Яма-колизей (GDD 16) — яма с кормом посередине, трибуны-террасы 2 м по бокам, ложи 4 м в углах.
	# Наверх: ступени 1 м → террасы → ложи (залезание), прыжковая руна в центре ямы — 10 м над ареной.
	return {
		"file": "room_08", "title": "Яма-колизей", "w": 28.0, "d": 28.0, "max_alive": 60,
		"blocks": [
			[Vector3(-11, 1.0, 0), Vector3(6, 2, 20), "stone_dark"],
			[Vector3(11, 1.0, 0), Vector3(6, 2, 20), "stone_dark"],
			[Vector3(-11, 2.0, -9), Vector3(6, 4, 4), "stone_dark"],
			[Vector3(11, 2.0, 9), Vector3(6, 4, 4), "stone_dark"],
			[Vector3(-6.5, 0.5, 6), Vector3(3, 1, 3), "wood"],
			[Vector3(6.5, 0.5, -6), Vector3(3, 1, 3), "wood"],
		],
		"pillars": [Vector3(-4, 0, -8), Vector3(4, 0, 8)],
		"jump_pads": [[Vector3(0, 0, 0), 10.0]],
		# Следы прошлых боёв в яме: подпалины и засохший ихор
		"decals": [["scorch", Vector3(-4.5, 0, 3.5), 15.0, 3.2], ["scorch", Vector3(4, 0, -9), 120.0, 2.6], ["ichor_splat_02", Vector3(3, 0, 4.5), 70.0, 1.8]],
		"enemies": [["grunt", Vector3(-4, 0, -2), 0], ["grunt", Vector3(4, 0, -4), 0], ["thrower", Vector3(-11, 2.1, -3), 0], ["thrower", Vector3(11, 2.1, 3), 0], ["grunt", Vector3(-11, 2.1, 6), 0], ["grunt", Vector3(0, 0, -8), 0], ["fodder", Vector3(0, 0, -3), 0, 12, 2.5],
			["shaman", Vector3(-11, 4.1, -9), 1], ["merc", Vector3(11, 2.1, -6), 1], ["grunt", Vector3(0, 0, -8), 1], ["grunt", Vector3(-11, 2.1, 6), 1], ["grunt", Vector3(4, 0, -4), 1], ["grunt", Vector3(-4, 0, -2), 1], ["fodder", Vector3(-2, 0, 2), 1, 13, 2.625],
			["shieldbearer", Vector3(0, 0, -6), 2], ["grunt", Vector3(-11, 2.1, 6), 2], ["fodder", Vector3(2, 0, -2), 2, 14, 2.75], ["squad", Vector3(0, 0, -8), 2, 1, 0.0, {"squad": "powder_keg", "squad_override": {"grunt": 4, "bloated": 1}}]],
		"props": K.ring_props(Vector3(0, 0, 0), 6.5, 8, "barrel") + [["crate", Vector3(-13, 2.0, 8)], ["crate", Vector3(13, 2.0, -8)], ["crate", Vector3(-12, 4.0, -10)]],
	}
