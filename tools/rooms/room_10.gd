extends RefCounted
## Описание зала room_10 «Двор частокола» для генератора (tools/build_scenes.gd → room_defs, 10-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	return {
		"file": "room_10", "title": "Двор частокола", "w": 30.0, "d": 30.0, "max_alive": 60,
		"tutorial_vertical": true,
		"floor_tex": "dirt_straw",
		"visual_map": "res://run/maps/midgard_slice.tres",
		# Те же факелы: перемещены к путям, а не добавлены новые источники света.
		"torch_overrides": [[2, Vector3(-12.3, 2.8, 8.5)], [1, Vector3(11.3, 5.6, -6.8)]],
		"decor": [
			["banner_hammer", Vector3(-12.3, 2.0, 8.5), 0.0, 1.5],
			["banner_raven", Vector3(11.3, 4.6, -6.8), 0.0, 1.5],
		],
		"blocks": [
			# Постоянные помосты: верх 3.0 м; толщина > 0.5, поэтому это не ломаемые мосты.
			[Vector3(-9, 2.7, -4), Vector3(6, 0.6, 6), "wood"],
			[Vector3(9, 2.7, -4), Vector3(6, 0.6, 6), "wood"],
			# Верхний западный помост: верх 6.75 м.
			[Vector3(-6.5, 6.45, 11.5), Vector3(6, 0.6, 5), "wood"],
			# Мост y=3: _is_wood_deck создаёт Balcony со slam_breakable=true.
			# Нахлёст на постоянные помосты — 0.1 м.
			[Vector3(0, 2.85, -4), Vector3(12.2, 0.3, 2), "wood"],
		],
		"pillars": [],
		# Без ступеней: восточная вышка соединена с помостом пологим маршем.
		"watchtowers": [[Vector3(9, 3, 1.4), false]],
		"jump_pads": [[Vector3(-2.2, 0, 7), 10.0]],

		# Явные поверхности и соединения для ходовой навигации; координаты локальны залу.
		"enemy_navigation": {
			"clearance": 0.55,
			# Проекция участка нижнего марша, под которым недостаточно места для тела.
			"ground_exclusions": [[Vector2(-10, 5.35), Vector2(3, 7.5)]],
			"regions": [
				["MidWest", [K.nav_quad(Vector3(-11.45, 3, -6.45), Vector3(-6.55, 3, -1.55))]],
				# Обход центрального участка наклонного марша; под высоким концом есть проход.
				["MidEast", [
					K.nav_quad(Vector3(6.55, 3, -6.45), Vector3(7.05, 3, -5.8)),
					K.nav_quad(Vector3(7.05, 3, -6.45), Vector3(10.95, 3, -5.8)),
					K.nav_quad(Vector3(10.95, 3, -6.45), Vector3(11.45, 3, -5.8)),
					K.nav_quad(Vector3(6.55, 3, -5.8), Vector3(7.05, 3, -2.3)),
					K.nav_quad(Vector3(10.95, 3, -5.8), Vector3(11.45, 3, -2.3)),
					K.nav_quad(Vector3(6.55, 3, -2.3), Vector3(7.05, 3, -1.55)),
					K.nav_quad(Vector3(7.05, 3, -2.3), Vector3(10.95, 3, -1.55)),
					K.nav_quad(Vector3(10.95, 3, -2.3), Vector3(11.45, 3, -1.55)),
				]],
				["RampLow", [K.nav_quad(Vector3(-10.95, 2.865, -0.55), Vector3(-9.05, 0.135, 8.55))]],
				["RampHigh", [K.nav_quad(Vector3(-7.75, 3.16875, -0.55), Vector3(-5.85, 6.58125, 8.55))]],
				["Upper", [K.nav_quad(Vector3(-8.95, 6.75, 9.55), Vector3(-4.05, 6.75, 13.45))]],
				["RampTower", [K.nav_quad(Vector3(8.15, 3.290948, -5.35), Vector3(9.85, 6.459052, -0.45))]],
				["TowerTop", [K.nav_quad(Vector3(8.15, 6.75, 0.55), Vector3(9.85, 6.75, 2.25))]],
				["Bridge", [K.nav_quad(Vector3(-5.55, 3, -4.45), Vector3(5.55, 3, -3.55))], NodePath("Geometry/Block3")],
			],
			# Переходы по маршруту StairGuides и в обоих концах моста.
			"links": [
				["StairFoot", Vector3(-10, 0, 9.8), Vector3(-10, 0.135, 8.55)],
				["StairMiddle", Vector3(-10, 2.865, -0.55), Vector3(-10, 3, -1.6)],
				["StairUpper", Vector3(-6.8, 3, -1.6), Vector3(-6.8, 3.16875, -0.55)],
				["StairTop", Vector3(-6.8, 6.58125, 8.55), Vector3(-6.8, 6.75, 9.8)],
				["TowerFoot", Vector3(9, 3, -6.35), Vector3(9, 3.290948, -5.35)],
				["TowerLanding", Vector3(9, 6.459052, -0.45), Vector3(9, 6.75, 0.65)],
				["BridgeWest", Vector3(-6.8, 3, -4), Vector3(-5.3, 3, -4), NodePath("Geometry/Block3")],
				["BridgeEast", Vector3(5.3, 3, -4), Vector3(6.8, 3, -4), NodePath("Geometry/Block3")],
				["JumpWest", Vector3(-11, 3, -6.35), Vector3(-11, 0, -9.05), {"traverse": "jump", "layers": 2, "bidirectional": false}],
				["JumpEast", Vector3(11, 3, -6.35), Vector3(11, 0, -9.05), {"traverse": "jump", "layers": 2, "bidirectional": false}],
			],
		},

		# Коллизия + вид — одна повёрнутая коробка WORLD. Небольшой заход в площадки.
		"ramps": [
			[Vector3(-10, 1.38506, 3.96552), Vector3(3, 0.24, 10.64911), 16.69924, "wood"],
			[Vector3(-6.8, 4.76264, 4.04213), Vector3(3, 0.24, 10.89360), -20.55605, "wood"],
			[Vector3(9, 4.77423, -2.83485), Vector3(2.8, 0.24, 7.14486), -32.88476, "wood"],
		],

		# Проём ниже уровня двора: вид и физический пол используют те же границы.
		"floor_openings": [[Vector2(12.5, 1.5), Vector2(3, 3)]],
		# Высота гибели врага относительно зала; в остальных залах действует обычный предел.
		"enemy_fall_y": -0.5,

		# Существующий механизм `markers` добавляет +0.05 м к каждому значению.
		# Это точки для испытаний, они не меняют поведение существующего ИИ.
		"markers": {
			"StairGuides": [
				Vector3(-10, 0, 9), Vector3(-10, 3, -1.6),
				Vector3(-8, 3, -1.6), Vector3(-6.8, 3, -1.6),
				Vector3(-6.8, 6.75, 9.8),
			],
			"TowerStart": Vector3(9, 3, -5.8),
			"UpperLanding": Vector3(-6.5, 6.75, 11.5),
			"BridgeCenter": Vector3(0, 3, -4),
			"FallEdge": Vector3(11.4, 3, -1.7),
		},

		"enemies": [
			# 10/15 корма, 2 особых; стрелки на средних помостах.
			["fodder", Vector3(0, 0, -11.5), 0, 10, 2.25, {"entry_mode": "edge", "entry_target": Vector3(0, 0.05, -8), "spread_axes": Vector2(2, 0.2), "entry_batch": 1}],
			["grunt", Vector3(-4, 0, -6), 0], ["grunt", Vector3(4, 0, -6), 0],
			["grunt", Vector3(0, 0, 0), 0],
			["merc", Vector3(11, 3, -5.8), 0], ["thrower", Vector3(-10, 3, -3.5), 0],

			# 11/17 корма, 2 особых; один стрелок на верхнем ярусе.
			["fodder", Vector3(0, 0, -11.5), 1, 11, 2.375, {"entry_mode": "edge", "entry_target": Vector3(0, 0.05, -8), "spread_axes": Vector2(2, 0.2), "entry_batch": 1}],
			["grunt", Vector3(-4, 0, -6), 1], ["grunt", Vector3(4, 0, -6), 1],
			["grunt", Vector3(-4, 0, 0), 1], ["grunt", Vector3(4, 0, 0), 1],
			["shaman", Vector3(11, 3, -5.8), 1], ["thrower", Vector3(-6.5, 6.75, 11.5), 1],

			# 12/18 корма, 2 особых.
			["fodder", Vector3(0, 0, -11.5), 2, 12, 2.5, {"entry_mode": "edge", "entry_target": Vector3(0, 0.05, -8), "spread_axes": Vector2(2, 0.2), "entry_batch": 1}],
			["grunt", Vector3(-4, 0, -6), 2], ["grunt", Vector3(4, 0, -6), 2],
			["grunt", Vector3(-4, 0, 0), 2], ["grunt", Vector3(4, 0, 0), 2],
			["shieldbearer", Vector3(4, 0, -8), 2], ["merc", Vector3(11, 3, -5.8), 2],
		],
		"models": [
			["res://assets/quaternius/props/Cauldron.gltf", Vector3(-12.2, 0, -8.5), 0.0, 1.0],
			["res://assets/quaternius/props/Table_Large.gltf", Vector3(12.2, 0, 6.8), 90.0, 1.0],
			["res://assets/quaternius/props/Book_Stack_1.gltf", Vector3(12.2, 0.82, 6.8), 20.0, 1.0],
			["res://assets/quaternius/props/Cage_Small.gltf", Vector3(13.2, 0, 9), 15.0, 1.0],
		],
		"props": [["barrel", Vector3(-12, 0, -11)], ["crate", Vector3(12, 0, -11)]],
		# Не ставить случайные угловые пропсы и декали поверх проектного проёма.
		"dress": {"corner_props": false, "decals": 0, "surface_materials": {
			"surface_plank": "res://rooms/materials/slice_plank.tres",
			"surface_wood": "res://rooms/materials/slice_wood.tres",
			"surface_floor_dirt": "res://rooms/materials/slice_dirt.tres",
			"surface_rock": "res://rooms/materials/slice_rock.tres",
		}, "palisade_rows": [
			[Vector3(-13, 0, -12), Vector3(-13, 0, -7)],
			[Vector3(13, 0, -11), Vector3(13, 0, -6)],
			[Vector3(-13, 0, 8), Vector3(-13, 0, 12)],
		]},
	}
