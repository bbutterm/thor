extends RefCounted
## Описание зала room_11 «Башня над фьордом» для генератора (tools/build_scenes.gd → room_defs, 11-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# 11. Башня: бой на четырёх уровнях, соединённых пологими маршами.
	return {
		"file": "room_11", "title": "Башня над фьордом", "w": 36.0, "d": 40.0, "max_alive": 60,
		"tutorial_vertical": true,
		"floor_tex": "dirt_straw",
		# Требуют описанных в патче общих расширений генератора/Room.
		"exit_y": 19.5,
		"wave_gates": {3: {"area": Rect2(-6.4, -19.5, 17.0, 9.0), "min_y": 19.0, "grounded": true}},
		"blocks": [
			# Неразрушаемые опорные помосты: y = 6.5, 13.0, 19.5.
			[Vector3(-8, 6.2, -12), Vector3(8, 0.6, 4), "wood"],
			[Vector3(-2, 12.7, 12), Vector3(8, 0.6, 4), "wood"],
			[Vector3(2, 19.2, -15), Vector3(18, 0.6, 10), "wood"],
			# Два необязательных моста: _is_wood_deck -> Balcony, ломаются ударом.
			[Vector3(0, 6.35, -12), Vector3(8.2, 0.3, 2.4), "wood"],
			[Vector3(6, 12.85, 12), Vector3(8.2, 0.3, 2.4), "wood"],
			# Узкая постоянная сцепка верхней площадки с полом коридора выхода.
			[Vector3(0, 19.2, -20.25), Vector3(3, 0.6, 1), "wood"],
		],
		"pillars": [],
		# Верх достигает уровня площадки за 0.45 м до кромки; концы маршей немного заходят на неё.
		"ramps": [
			[Vector3(-11, 3.136129, 0.187140), Vector3(3, 0.24, 21.802245), 18.390977, "wood"],
			[Vector3(-5, 9.636129, -0.187140), Vector3(3, 0.24, 21.802245), -18.390977, "wood"],
			[Vector3(1, 16.136129, 0.187140), Vector3(3, 0.24, 21.802245), 18.390977, "wood"],
		],
		# Первую руну обойти и запрыгнуть на площадку после набора высоты; следующие — сокращают марши.
		"jump_pads": [[Vector3(-8.5, 0, -8.5), 8.0], [Vector3(-8.5, 6.5, -12.8), 8.0], [Vector3(-2.5, 13, 12.8), 8.0]],
		"enemy_navigation": {
			"clearance": 0.55,
			# Под низкой частью первого марша высоты недостаточно для капсулы.
			"ground_exclusions": [[Vector2(-11, 6.9), Vector2(3, 6.2)]],
			"regions": [
				["Level1", [K.nav_quad(Vector3(-11.45, 6.5, -13.45), Vector3(-4.55, 6.5, -10.55))]],
				["Level2", [K.nav_quad(Vector3(-5.45, 13, 10.55), Vector3(1.45, 13, 13.45))]],
				["Summit", [K.nav_quad(Vector3(-6.45, 19.5, -19.45), Vector3(10.45, 19.5, -10.55))]],
				["Ramp1", [K.nav_quad(Vector3(-11.95, 6.383632, -9.2), Vector3(-10.05, 0.265985, 9.2))]],
				["Ramp2", [K.nav_quad(Vector3(-5.95, 6.765985, -9.2), Vector3(-4.05, 12.883632, 9.2))]],
				["Ramp3", [K.nav_quad(Vector3(0.05, 19.383632, -9.2), Vector3(1.95, 13.265985, 9.2))]],
				["Bridge1", [K.nav_quad(Vector3(-3.55, 6.5, -12.65), Vector3(3.55, 6.5, -11.35))], NodePath("Geometry/Block3")],
				["Bridge2", [K.nav_quad(Vector3(2.45, 13, 11.35), Vector3(9.55, 13, 12.65))], NodePath("Geometry/Block4")],
			],
			"links": [
				["Foot1", Vector3(-11, 0, 10.8), Vector3(-11, 0.265985, 9.2)],
				["Landing1", Vector3(-11, 6.383632, -9.2), Vector3(-11, 6.5, -10.7)],
				["Foot2", Vector3(-5, 6.5, -10.7), Vector3(-5, 6.765985, -9.2)],
				["Landing2", Vector3(-5, 12.883632, 9.2), Vector3(-5, 13, 10.7)],
				["Foot3", Vector3(1, 13, 10.7), Vector3(1, 13.265985, 9.2)],
				["Landing3", Vector3(1, 19.383632, -9.2), Vector3(1, 19.5, -10.7)],
				["Bridge1Access", Vector3(-4.7, 6.5, -12), Vector3(-3.5, 6.5, -12), NodePath("Geometry/Block3")],
				["Bridge2Access", Vector3(1.3, 13, 12), Vector3(2.5, 13, 12), NodePath("Geometry/Block4")],
			],
		},
		"markers": {
			"TowerGuides": [Vector3(-11, 0, 10.8), Vector3(-11, 6.5, -10.7), Vector3(-5, 6.5, -10.7),
				Vector3(-5, 13, 10.7), Vector3(1, 13, 10.7), Vector3(1, 19.5, -10.7)],
			"SlamStart": Vector3(10.5, 19.5, -14),
			"SlamLanding": Vector3(12.5, 0, -14),
			"Summit": Vector3(4, 19.5, -14),
		},
		"enemies": [
			# 10 / 15, 66.7 %: вход со двора, стрелок на первом ярусе.
			["fodder", Vector3(12, 0, 10), 0, 10, 2.0, {"entry_mode": "edge", "entry_target": Vector3(12, 0.05, 6), "spread_axes": Vector2(1.6, 0.2), "entry_batch": 1}],
			["grunt", Vector3(-4, 0, 5), 0], ["grunt", Vector3(3, 0, 2), 0], ["grunt", Vector3(12, 0, -4), 0],
			["merc", Vector3(10, 0, -8), 0], ["thrower", Vector3(-6, 6.5, -12), 0],

			# 11 / 17, 64.7 %: снизу лезут новые кормовые, шаман на помосте, стрелок на мосту.
			["fodder", Vector3(10, 0, -14), 1, 11, 2.0, {"entry_batch": 1}],
			["grunt", Vector3(-2, 0, 1), 1], ["grunt", Vector3(5, 0, -4), 1],
			["grunt", Vector3(-10, 6.5, -12), 1], ["grunt", Vector3(-5.8, 6.5, -12), 1],
			["shaman", Vector3(-8.5, 6.5, -12), 1], ["thrower", Vector3(3, 6.5, -12), 1],

			# 12 / 18, 66.7 %: корм выходит с первого яруса; второй мост занял стрелок.
			["fodder", Vector3(-8, 6.5, -12), 2, 12, 1.2, {"entry_batch": 1}],
			["grunt", Vector3(9, 0, -11), 2], ["grunt", Vector3(12, 0, -9), 2],
			["grunt", Vector3(-4, 13, 12), 2], ["grunt", Vector3(0, 13, 12), 2],
			["shaman", Vector3(-10, 6.5, -13), 2], ["thrower", Vector3(8, 13, 12), 2],

			# 22 / 33, 66.7 %: ядро финала на вершине и живая цель для прыжка на дворе.
			["fodder", Vector3(3, 19.5, -14.5), 3, 12, 2.0, {"entry_batch": 1}],
			["grunt", Vector3(-3, 19.5, -17), 3], ["grunt", Vector3(8, 19.5, -17), 3],
			["grunt", Vector3(8, 19.5, -12), 3], ["grunt", Vector3(-3, 19.5, -12), 3],
			["shaman", Vector3(-1, 19.5, -15), 3], ["thrower", Vector3(9, 19.5, -15), 3],
			["fodder", Vector3(12.5, 0, -14), 3, 10, 1.5, {"entry_batch": 1}],
			["grunt", Vector3(9.5, 0, -10), 3], ["grunt", Vector3(11, 0, -10), 3],
			["grunt", Vector3(12.5, 0, -10), 3], ["grunt", Vector3(14, 0, -10), 3], ["grunt", Vector3(15, 0, -12), 3],
		],
		"props": [["barrel", Vector3(-15, 0, 15)], ["crate", Vector3(15, 0, 15)]],
		"no_auto": ["north"],
		"dress": {"corner_props": false, "palisade_rows": [
			[Vector3(-11.5, 6.5, -13.8), Vector3(-9, 6.5, -13.8)],
			[Vector3(-5.5, 13, 13.8), Vector3(-3, 13, 13.8)],
			[Vector3(8, 19.5, -19.7), Vector3(10.5, 19.5, -19.7)],
		], "timber_posts": [
			[Vector3(-12.1, 0, -14.1), 6.5, 0.35], [Vector3(-3.9, 0, -14.1), 6.5, 0.35],
			[Vector3(-6.1, 0, 14.1), 13.0, 0.35], [Vector3(2.1, 0, 14.1), 13.0, 0.35],
			[Vector3(-7.1, 0, -19.8), 19.5, 0.35], [Vector3(11.1, 0, -19.8), 19.5, 0.35],
			[Vector3(11.1, 0, -10.1), 19.5, 0.35],
		]},
	}
