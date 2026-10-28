extends RefCounted
## Зал-ларёк (блок К, GDD 13): тихий зал без волн, ларёк посередине, ящики по углам.
## Описание для генератора (tools/build_scenes.gd → shop_room_def).

const K = preload("res://tools/rooms/room_kit.gd")

static func def() -> Dictionary:
	return {
		"file": "shop_room", "title": "Ларёк Брокка и Эйтри", "w": 22.0, "d": 20.0,
		"blocks": [],
		"pillars": [Vector3(-7.5, 0, -5), Vector3(7.5, 0, -5)],
		"enemies": [],
		"props": K.stack_props(Vector3(-9.5, 0, 6.5)) + K.stack_props(Vector3(8.5, 0, 6.5)) + [["crate", Vector3(-9.5, 0, -8.5)], ["crate", Vector3(9.5, 0, -8.5)]],
		"stall": Vector3(0, 0, 0.5),
		# За ларьком, на северной стене: гобелен и плакат Одина «Качайся!» (вместо авто-знамён у выхода)
		"no_auto": ["north"],
		"decor": [["tapestry", Vector3(-6.5, 3.0, -10 + K.WALL_INSET), 0.0, 3.0], ["odin_poster", Vector3(6.5, 2.4, -10 + K.WALL_INSET), 0.0, 1.9]],
	}
