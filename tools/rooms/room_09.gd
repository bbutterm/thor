extends RefCounted
## Описание зала room_09 «Деревня у фьорда» для генератора (tools/build_scenes.gd → room_defs, 9-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 9. Деревня (GDD 16) — дома с плоскими крышами 2.5–3 м, мост между домами над улицей, площадь.
	# Наверх: ящики-ступени 1 м → крыши (залезание), прыжковая руна на площади, мост.
	return {
		"file": "room_09", "title": "Деревня у фьорда", "w": 30.0, "d": 28.0, "max_alive": 20,
		"blocks": [
			[Vector3(-9, 1.5, -5), Vector3(6, 3, 5), "wood"],
			[Vector3(9, 1.5, -5), Vector3(6, 3, 5), "wood"],
			[Vector3(-9, 1.5, 6), Vector3(5, 3, 5), "wood"],
			[Vector3(9, 1.25, 6), Vector3(5, 2.5, 5), "wood"],
			[Vector3(0, 2.85, -5), Vector3(12, 0.3, 2), "wood"],
			[Vector3(-5.5, 0.5, 6), Vector3(2, 1, 2), "wood"],
			[Vector3(6, 0.5, 2.5), Vector3(2, 1, 2), "wood"],
			[Vector3(-5, 0.5, -1.5), Vector3(2, 1, 2), "wood"],
		],
		"pillars": [],
		# П11: рецепты домов MegaKit — черепица, солома, доски, терраса (крыши на столбах над плоской крышей)
		"houses": [[0, "s", "Plaster", {"recipe": "tile"}], [1, "s", "UnevenBrick", {"recipe": "thatch"}],
			[2, "e", "UnevenBrick", {"recipe": "planks"}], [3, "w", "Plaster", {"recipe": "terrace"}]],
		# Улица деревни — утоптанная земля с соломой (assets/textures/midgard/dirt_straw)
		"floor_tex": "dirt_straw",
		"jump_pads": [[Vector3(0, 0, 3), 8.0]],
		"enemies": [
			# П3: 16 + 16 (было 19 + 21 + 15).
			["grunt", Vector3(-3, 0, -9), 0], ["grunt", Vector3(3, 0, -9), 0], ["thrower", Vector3(-10, 3.1, -4), 0], ["bloated", Vector3(-12, 0, 0), 0], ["grunt", Vector3(12, 0, 0), 0],
			["fodder", Vector3(0, 0, -1), 0, 6, 1.75], ["fodder", Vector3(3, 0, -1), 0, 5, 1.625],
			["shaman", Vector3(0, 3.1, -5), 1], ["shieldbearer", Vector3(0, 0, -8), 1], ["grunt", Vector3(-12, 0, 0), 1], ["grunt", Vector3(12, 0, 0), 1], ["grunt", Vector3(-3, 0, -9), 1],
			["fodder", Vector3(3, 0, -1), 1, 6, 1.75], ["fodder", Vector3(1, 0, 0), 1, 5, 1.625]],
		"props": [["barrel", Vector3(-12, 0, -10)], ["barrel", Vector3(12, 0, -10)], ["crate", Vector3(-13, 0, 1)], ["crate", Vector3(13, 0, 1)], ["barrel", Vector3(2, 0, 7)],
			["barrel", Vector3(-2, 0, 8)], ["crate", Vector3(-9, 3.0, -5.5)], ["barrel", Vector3(9, 3.0, -4)], ["crate", Vector3(9, 2.5, 7)]],
		# Плакаты на южных стенах домов (лицевая сторона модулей — z = −2.31): «Разыскивается» и Один «Качайся!»
		"decor": [["wanted_poster", Vector3(-11, 1.75, -2.31 + K.WALL_INSET), 0.0, 1.4], ["odin_poster", Vector3(11, 1.75, -2.31 + K.WALL_INSET), 0.0, 1.4]],
	}
