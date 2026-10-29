extends RefCounted
## Описание зала room_09 «Деревня у фьорда» для генератора (tools/build_scenes.gd → room_defs, 9-й в списке).
## Формат ключей — комментарий над room_defs() в tools/build_scenes.gd и rooms/CLAUDE.md.
## П7 «зал как путь», схема A docs/mockups/room_09_village_A_chosen.png (старая раскладка — rooms/quick_old/room_09_old.tscn,
## F6 в «Быстрой проверке»).

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	# Улица в гору ~40 м: набережная у воды (0 м) → серпантином рынок (2 м) → площадь (4 м) → двор длинного дома (6 м),
	# двери-награды у крыльца. Дома по бокам: на рынке — крыши 5 м, на площади — 7 м. Короткий путь по крышам:
	# лестница на левый дом рынка → мост-настил (ломается) → крыша дома площади → прыжок во двор; прыжковая руна
	# на площади — на правую крышу. Длинный дом за двором — вид с порога (коллизия только у блока за стеной).
	return {
		"file": "room_09", "title": "Деревня у фьорда", "w": 32.0, "d": 46.0, "max_alive": 20,
		"exit_y": 6.0,
		"doors_early": true,
		"spawn_telegraph": 1.0,
		"spawn_pos": Vector3(-2, 0, 17.3),
		"floor_openings": [[Vector2(0, 20.5), Vector2(31.6, 4.6)]],
		"water": [[Rect2(-16, 18.2, 32, 4.8)], -0.9],
		"enemy_fall_y": -0.5,
		"blocks": [
			# 0 рынок 2 м, 1 площадь 4 м, 2 двор 6 м — террасы улицы
			[Vector3(0, 1, 7.5), Vector3(32, 2, 11), "stone_dark"],
			[Vector3(0, 2, -3), Vector3(32, 4, 10), "stone_dark"],
			[Vector3(0, 3, -15.5), Vector3(32, 6, 15), "stone_dark"],
			# 3–4 дома рынка (крыши 5 м), 5–6 дома площади (крыши 7 м)
			[Vector3(-11, 3.5, 8), Vector3(6, 3, 5), "wood"],
			[Vector3(11, 3.5, 8.5), Vector3(6, 3, 4), "wood"],
			[Vector3(-11, 5.5, -2), Vector3(6, 3, 6), "wood"],
			[Vector3(11, 5.5, -3), Vector3(6, 3, 5), "wood"],
			# 7 мост-настил с крыши рынка к дому площади (ломается ударом-приземлением)
			[Vector3(-11, 4.85, 3.25), Vector3(1.6, 0.3, 4.5), "wood"],
			# 8 длинный дом за двором (за северной стеной, за коридором выхода)
			[Vector3(0, 8, -34), Vector3(20, 4, 6), "wood"],
		],
		"pillars": [],
		"houses": [[3, "e", "Plaster", {"recipe": "thatch"}], [4, "w", "UnevenBrick", {"recipe": "tile"}],
			[5, "e", "UnevenBrick", {"recipe": "planks"}], [6, "w", "Plaster", {"recipe": "terrace"}],
			[8, "s", "UnevenBrick", {"recipe": "tile", "yard": false}]],
		# Серпантин: набережная → рынок (вдоль кромки, вправо), рынок → площадь (влево), площадь → двор (по центру)
		"ramps": [
			[Vector3(7.5, 1.0, 14.2), Vector3(2.4, 0.24, 9.22), 12.53, "wood", -90.0],
			[Vector3(2, 3.0, 3.3), Vector3(2.4, 0.24, 10.2), 11.31, "wood", 90.0],
			[Vector3(0, 5.0, -5.5), Vector3(3, 0.24, 5.39), 21.8, "wood"],
		],
		"ladders": [[Vector3(-7.6, 2.0, 8), 3.0, 90.0]],
		"jump_pads": [[Vector3(6.5, 4, -1.5), 8.0]],
		"floor_tex": "dirt_straw",
		"enemies": [
			# П3-состав каждой волны: 60–70 % корма пачками 5–8, 1–2 особых (generator_test).
			# Волна 1 — набережная: с лодок (11)
			["grunt", Vector3(-8, 0, 16), 0], ["grunt", Vector3(8, 0, 16.5), 0], ["grunt", Vector3(12, 0, 15), 0], ["bloated", Vector3(-13, 0, 15), 0],
			["fodder", Vector3(-11, 0, 16), 0, 7, 1.4],
			# Волна 2 — рынок: из дверей домов (12)
			["grunt", Vector3(-7, 2.05, 10), 1], ["grunt", Vector3(7.5, 2.05, 9), 1], ["shieldbearer", Vector3(0, 2.05, 6), 1],
			["bloated", Vector3(-4, 2.05, 4), 1], ["fodder", Vector3(-7, 2.05, 6), 1, 8, 1.2],
			# Волна 3 — площадь: из-за крыш и из ворот двора (10)
			["thrower", Vector3(11, 7.05, -3), 2], ["shaman", Vector3(0, 6.05, -11), 2], ["grunt", Vector3(-5, 4.05, -4), 2],
			["grunt", Vector3(5, 4.05, -5), 2], ["fodder", Vector3(-3, 6.05, -10), 2, 6, 1.4]],
		"props": [["barrel", Vector3(-13, 0, 14.5)], ["barrel", Vector3(13, 0, 17)], ["crate", Vector3(-3, 2.0, 11)], ["crate", Vector3(4, 2.0, 11.5)],
			["barrel", Vector3(-1, 2.0, 9)], ["barrel", Vector3(-6, 4.0, -6)], ["crate", Vector3(6, 4.0, -6.5)], ["barrel", Vector3(-12, 7.0, -3)],
			["barrel", Vector3(8, 6.0, -18)], ["barrel", Vector3(-8, 6.0, -19)]],
		"models": [["res://assets/quaternius/pirate/Ship_Small.gltf", Vector3(-9, -0.5, 20.5), 80.0, 0.9]],
		# Плакаты на стенах домов рынка
		"decor": [["wanted_poster", Vector3(-11, 3.4, 10.5 + 0.31 + K.WALL_INSET), 0.0, 1.2], ["odin_poster", Vector3(11, 3.4, 10.5 + 0.31 + K.WALL_INSET), 0.0, 1.2]],
	}
