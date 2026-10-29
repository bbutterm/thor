extends RefCounted
class_name GenRooms
## Генератор: обычные боевые залы и зал-ларёк из описаний tools/rooms/*.gd — геометрия, блоки по стилям,
## вышки, пандусы, декор и картинки на стенах, одевание (RoomDresser).
## Компонент SceneBuilder (этап 4 рефакторинга): числа и состояние — поля SceneBuilder (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — генератор.rooms; нужные снаружи функции есть и на SceneBuilder.

const K = preload("res://tools/rooms/room_kit.gd")

## Вид Мидгарда в генерируемых залах (срез графики зала 10 → все залы, Н1 29.10): профиль света и тумана
## (холодное небо и дымка против тёплых факелов) — Room.visual_map; ключ зала "visual_map" перекрывает
## ("" — без профиля, карта мира Run.map). Ручные арены (длинный дом, погреб Свена) остаются на карте мира.
const DEFAULT_VISUAL_MAP := "res://run/maps/midgard_slice.tres"
## Поверхности среза вместо штатных surface_* (rooms/materials, RoomDresser.SURFACES): крупнее пятна, меньше
## шума, тёплая палитра. Ключ "dress": {"surface_materials": {...}} зала дополняет и перекрывает.
const SLICE_SURFACES := {
	"surface_plank": "res://rooms/materials/slice_plank.tres",
	"surface_wood": "res://rooms/materials/slice_wood.tres",
	"surface_floor_dirt": "res://rooms/materials/slice_dirt.tres",
	"surface_floor_brick": "res://rooms/materials/slice_floor_brick.tres",
	"surface_rock": "res://rooms/materials/slice_rock.tres",
	"surface_stone": "res://rooms/materials/slice_stone.tres",
	"surface_pillar": "res://rooms/materials/slice_pillar.tres",
}
## Ориентиры (Н1): у подъёмов (низ пандуса, ступени вышки, прыжковая руна) — факел на стойке и знамя.
## Факел не добавляется, а переносится ближайший боковой (свет — проходы в GL Compatibility), не больше
## LANDMARK_MAX на зал; ключ зала "torch_overrides" (ручная расстановка) или "landmarks": false отключает.
const LANDMARK_MAX := 2
const LANDMARK_TORCH_Y := 2.8
const LANDMARK_SIDE := 0.8
const LANDMARK_BANNERS := ["banner_hammer", "banner_raven"]

## Поверхности одевания зала: общий вид среза + свои ключа "dress"/"surface_materials".
func _surface_materials(d: Dictionary) -> Dictionary:
	var out := SLICE_SURFACES.duplicate()
	out.merge((d.get("dress", {}) as Dictionary).get("surface_materials", {}), true)
	return out

var gen: SceneBuilder

func _init(owner_node: SceneBuilder) -> void:
	gen = owner_node

## Блок — деревянный настил над полом: материал "wood", толщина ≤ 0.5 м, низ выше 1 м (мост деревни, Биврёст).
func _is_wood_deck(b: Array) -> bool:
	var c: Vector3 = b[0]
	var sz: Vector3 = b[1]
	return b[2] == "wood" and sz.y <= 0.5 and c.y - sz.y * 0.5 > 1.0

## Блок Б0 «Одеть залы»: общие меши и материалы одевания (rooms/meshes, rooms/materials) и даль за стенами.
func build_dress() -> void:
	print("Одевание залов: меши, материалы, даль…")
	RoomDresser.build_assets()
	gen._save(RoomDresser.build_backdrop(), RoomDresser.BACKDROP_SCENE)

## Стиль одевания блока зала (RoomDresser): дом, мост/настил, только коллизия, дерево, камень;
## ключ "dress": {"styles": {индекс: стиль}} зала перекрывает (например, "tower" — круглая башня).
func _block_style(d: Dictionary, i: int) -> String:
	var over: Dictionary = (d.get("dress", {}) as Dictionary).get("styles", {})
	if over.has(i):
		return over[i]
	for h in d.get("houses", []):
		if h[0] == i:
			return "house"
	var b: Array = d.blocks[i]
	if _is_wood_deck(b):
		return "deck"
	if b[2] == "none":
		return "none"
	return "wood" if b[2] == "wood" else "stone"

## Бочка и ящик в свободных углах зала (не больше двух): углы не пустые, а пропсы — разрушаемые.
func _corner_props(d: Dictionary, openings: Array[Rect2] = []) -> Array:
	var out: Array = []
	var hw: float = d.w * 0.5 - 1.1
	var hd: float = d.d * 0.5 - 1.1
	var kinds := ["barrel", "crate"]
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, hd), Vector3(hw, 0, -hd), Vector3(-hw, 0, hd)]:
		if out.size() >= 2:
			break
		var ok := true
		for opening in openings:
			if opening.grow(1.2).has_point(Vector2(c.x, c.z)):
				ok = false
		for b in d.blocks:
			var bc: Vector3 = b[0]
			var bs: Vector3 = b[1]
			if absf(c.x - bc.x) < bs.x * 0.5 + 1.2 and absf(c.z - bc.z) < bs.z * 0.5 + 1.2:
				ok = false
		for pr in d.props:
			if (pr[1] as Vector3).distance_to(c) < 2.0:
				ok = false
		for jp in d.get("jump_pads", []):
			if (jp[0] as Vector3).distance_to(c) < 2.5:
				ok = false
		if ok:
			out.append([kinds[out.size() % 2], c])
	return out

func build_rooms() -> void:
	print("Залы…")
	for d in gen.room_defs():
		_build_room(d, false)
	# Зал-ларёк Брокка и Эйтри (блок К): без врагов, сам ларёк собирает rooms/shop_stall.gd
	_build_room(gen.shop_room_def(), false)
	# Арены боссов (Длинный дом Ярла, погреб Свена) — ручные сцены, см. MANUAL_SCENES

## Открытая вышка 3.75 м. Четыре ступени с северной стороны дают пройти наверх
## обычными прыжками; видимые опоры/перила не меняют физику и не закрывают обзора.
func _watchtower(parent: Node, name: String, center: Vector3, mat: Material, with_steps: bool = true) -> void:
	var tower := Node3D.new()
	tower.name = name
	tower.position = center
	parent.add_child(tower)
	gen._box(tower, "Deck", Vector3(0, 3.61, 0), Vector3(2.8, 0.28, 2.8), mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			gen._box(tower, "Post_%d_%d" % [int(sx), int(sz)], Vector3(sx * 1.18, 1.7, sz * 1.18), Vector3(0.22, 3.4, 0.22), mat, false)
	if with_steps:
		for i in 4:
			var top := 0.75 * (i + 1)
			var z := -4.8 + i
			gen._box(tower, "Step%d" % i, Vector3(0, top - 0.09, z), Vector3(1.5, 0.18, 0.95), mat)
			for sx in [-1.0, 1.0]:
				gen._box(tower, "StepPost%d_%d" % [i, int(sx)], Vector3(sx * 0.62, top * 0.5, z), Vector3(0.14, top, 0.14), mat, false)
	# Перила — только вид; северная сторона открыта для выхода со ступеней.
	for sx in [-1.0, 1.0]:
		gen._box(tower, "Rail_%d" % int(sx), Vector3(sx * 1.32, 4.35, 0), Vector3(0.12, 0.12, 2.5), mat, false)
	gen._box(tower, "RailSouth", Vector3(0, 4.35, 1.32), Vector3(2.5, 0.12, 0.12), mat, false)

## Пологие проходы: [центр, размер, наклон X, материал, необязательный поворот Y], углы в градусах.
func _build_ramps(parent: Node, ramps: Array, mats: Dictionary, plank_path: String = "") -> void:
	if ramps.is_empty():
		return
	var plank: Material
	for i in ramps.size():
		var spec: Array = ramps[i]
		var kind := str(spec[3])
		var material: Material = null
		if kind != "none":
			material = mats.get(kind, mats.stone_dark) as Material
		if kind == "wood":
			# Общий материал настилов; при отсутствии — штатное дерево генератора.
			if plank == null:
				var path := plank_path if plank_path != "" else "res://rooms/materials/surface_plank.tres"
				plank = load(path) as Material
			if plank != null:
				material = plank
		var ramp := gen._box(parent, "Ramp%d" % i, spec[0], spec[1], material)
		var yaw := float(spec[4]) if spec.size() > 4 else 0.0
		ramp.rotation_degrees = Vector3(float(spec[2]), yaw, 0.0)

func _build_room(d: Dictionary, boss: bool) -> void:
	# Случайные повороты пропсов — одни и те же при каждом запуске генератора (меньше шума в .tscn)
	seed(hash(d.file))
	var root := Node3D.new()
	root.name = d.file.capitalize().replace(" ", "")
	root.set_script(load("res://rooms/room.gd"))
	root.set("room_title", d.title)
	var visual_map_path := str(d.get("visual_map", DEFAULT_VISUAL_MAP))
	if visual_map_path != "":
		root.set("visual_map", load(visual_map_path) as RunMap)
	root.set("max_alive", int(d.get("max_alive", 0)))
	if d.get("tutorial_vertical", false):
		root.set_meta("tutorial_vertical", true)
	if d.has("wave_gates"):
		root.set_meta("wave_gates", d.wave_gates)
	var exit_y := float(d.get("exit_y", 0.0))
	if d.has("exit_y"):
		root.set_meta("exit_y", exit_y)
	if d.has("enemy_fall_y"):
		root.set_meta("enemy_fall_y", float(d.enemy_fall_y))
	var w: float = d.w
	var dep: float = d.d
	var h := 6.0
	var floor_mat := gen._tex_mat("q_floor", "Brick", Color(0.72, 0.68, 0.64), 0.35)
	var wall_mat: Material = null  # стены — модели Quaternius, у коробок только коллизия
	var mats := {
		"wood": gen._tex_mat("q_wood", "WoodTrim", Color(0.85, 0.75, 0.65), 0.5),
		"stone_dark": gen._tex_mat("q_rock", "RockTrim", Color(0.7, 0.7, 0.74), 0.4),
	}
	var pillar_mat := gen._tex_mat("q_pillar", "UnevenBrick", Color(0.8, 0.78, 0.75), 0.45)
	for kind in SceneBuilder.MIDGARD_BLOCKS:
		mats[kind] = gen._world_tex_mat("m_" + kind, SceneBuilder.MIDGARD_BLOCKS[kind], Color(0.9, 0.9, 0.92), 0.3)
	if d.has("floor_tex"):
		floor_mat = gen._world_tex_mat("m_floor_" + d.floor_tex, d.floor_tex, Color(0.92, 0.9, 0.88), 0.3)

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	var openings := gen.room_floor._floor_opening_rects(d.get("floor_openings", []), w, dep)
	var floor := gen._box(geo, "Floor", Vector3(0, -0.5, 0), Vector3(w + 2, 1, dep + 2), floor_mat)
	if not openings.is_empty():
		gen.room_floor._cut_floor(floor, openings, w, dep)
	# Стены (дверной проём 4 м по центру северной стены, z = -d/2)
	var gap := 4.0
	var side_w := (w - gap) / 2.0
	gen._box(geo, "WallN_L", Vector3(-(gap / 2 + side_w / 2), h / 2, -dep / 2 - 0.5), Vector3(side_w, h, 1), wall_mat)
	gen._box(geo, "WallN_R", Vector3(gap / 2 + side_w / 2, h / 2, -dep / 2 - 0.5), Vector3(side_w, h, 1), wall_mat)
	gen._box(geo, "WallS", Vector3(0, h / 2, dep / 2 + 0.5), Vector3(w + 2, h, 1), wall_mat)
	gen._box(geo, "WallW", Vector3(-w / 2 - 0.5, h / 2, 0), Vector3(1, h, dep + 2), wall_mat)
	gen._box(geo, "WallE", Vector3(w / 2 + 0.5, h / 2, 0), Vector3(1, h, dep + 2), wall_mat)
	# Стены — секции Quaternius (UnevenBrick), в 2 ряда
	var walls := Node3D.new()
	walls.name = "WallModels"
	geo.add_child(walls)
	gen._wall_row(walls, "N_L", Vector3(-w / 2, 0, -dep / 2 - 0.1), side_w, 0)
	gen._wall_row(walls, "N_R", Vector3(gap / 2, 0, -dep / 2 - 0.1), side_w, 0)
	gen._wall_row(walls, "S", Vector3(w / 2, 0, dep / 2 + 0.1), w, 180)
	gen._wall_row(walls, "W", Vector3(-w / 2 - 0.1, 0, dep / 2), dep, 90)
	gen._wall_row(walls, "E", Vector3(w / 2 + 0.1, 0, -dep / 2), dep, -90)
	gen._wall_row(walls, "CL", Vector3(-gap / 2 - 0.1, 0, -dep / 2 - 0.5) + Vector3(0, exit_y, 0), 5.0, 90)
	gen._wall_row(walls, "CR", Vector3(gap / 2 + 0.1, 0, -dep / 2 - 5.5) + Vector3(0, exit_y, 0), 5.0, -90)
	gen._wall_row(walls, "CE", Vector3(-gap / 2 - 1, 0, -dep / 2 - 5.6) + Vector3(0, exit_y, 0), gap + 2, 0)
	# Коридор за дверью
	gen._box(geo, "CorridorFloor", Vector3(0, -0.5, -dep / 2 - 3) + Vector3(0, exit_y, 0), Vector3(gap + 2, 1, 5), floor_mat)
	gen._box(geo, "CorridorL", Vector3(-gap / 2 - 0.5, h / 2, -dep / 2 - 3) + Vector3(0, exit_y, 0), Vector3(1, h, 5), wall_mat)
	gen._box(geo, "CorridorR", Vector3(gap / 2 + 0.5, h / 2, -dep / 2 - 3) + Vector3(0, exit_y, 0), Vector3(1, h, 5), wall_mat)
	gen._box(geo, "CorridorEnd", Vector3(0, h / 2, -dep / 2 - 6) + Vector3(0, exit_y, 0), Vector3(gap + 2, h, 1), wall_mat)
	var portal := gen._mat("portal", Color(0.45, 0.8, 1.0), 0.3, false, 2.5)
	gen._box(geo, "Portal", Vector3(0, 2.2, -dep / 2 - 5.45) + Vector3(0, exit_y, 0), Vector3(2.6, 3.6, 0.1), portal, false)

	for i in d.blocks.size():
		var b: Array = d.blocks[i]
		if _is_wood_deck(b):
			# Деревянный мост/настил над полом (GDD 16): ломается ударом-приземлением сверху (rooms/balcony.gd),
			# при новом заходе в зал — снова целый (зал собирается из сцены заново)
			gen._balcony(geo, "Block%d" % i, b[0], b[1], mats.wood, false, true)
			continue
		# "none" — только коллизия (вид даёт декоративная модель из "models", например корпус корабля)
		gen._box(geo, "Block%d" % i, b[0], b[1], null if b[2] == "none" else mats.get(b[2], mats.stone_dark))
	var ramps: Array = d.get("ramps", [])
	var surface_materials := _surface_materials(d)
	var plank_override := str(surface_materials.get("surface_plank", ""))
	_build_ramps(geo, ramps, mats, plank_override)
	# Небольшие наблюдательные вышки: реальные ступени и настил, декоративные опоры.
	var towers: Array = d.get("watchtowers", [])
	var tower_material: Material = mats.wood
	if plank_override != "":
		tower_material = load(plank_override) as Material
	for i in towers.size():
		var spec: Variant = towers[i]
		if spec is Array:
			_watchtower(geo, "Watchtower%d" % i, spec[0], tower_material, bool(spec[1]))
		else:
			_watchtower(geo, "Watchtower%d" % i, spec, tower_material)
	for i in d.pillars.size():
		var pp: Vector3 = d.pillars[i]
		gen._cyl(geo, "Pillar%d" % i, pp + Vector3(0, h / 2, 0), 0.8, h, pillar_mat)
		gen._cyl(geo, "PillarBase%d" % i, pp + Vector3(0, 0.25, 0), 1.05, 0.5, pillar_mat)
		gen._cyl(geo, "PillarCap%d" % i, pp + Vector3(0, h - 0.2, 0), 1.0, 0.4, pillar_mat)

	# Разрушаемые балконы: [центр настила, размер настила] — rooms/balcony.gd
	var bals: Array = d.get("balconies", [])
	if not bals.is_empty():
		var bnode := Node3D.new()
		bnode.name = "Balconies"
		root.add_child(bnode)
		for i in bals.size():
			gen._balcony(bnode, "Balcony%d" % i, bals[i][0], bals[i][1], mats.wood)

	# Дверь
	var door := gen._box(root, "Door", Vector3(0, h / 2 + exit_y, -dep / 2 - 0.5), Vector3(gap, h, 0.6), gen._tex_mat("q_door", "WoodTrim", Color(0.55, 0.32, 0.25), 0.6))
	var door_rune := gen._mat("door_rune", Color(1.0, 0.45, 0.2), 0.5, false, 3.0)
	gen._box(door, "Rune", Vector3(0, 0.3, 0.33), Vector3(0.5, 2.2, 0.05), door_rune, false)
	gen._box(door, "RuneBar", Vector3(0, 0.9, 0.33), Vector3(1.4, 0.3, 0.05), door_rune, false)

	# Выход
	var exit := Area3D.new()
	exit.name = "Exit"
	exit.collision_layer = SceneBuilder.TRIGGER_L
	exit.collision_mask = SceneBuilder.PLAYER_L
	exit.position = Vector3(0, 1.5 + exit_y, -dep / 2 - 4)
	var es := CollisionShape3D.new()
	es.name = "Shape"
	var ebox := BoxShape3D.new()
	ebox.size = Vector3(gap, 3, 2.5)
	es.shape = ebox
	exit.add_child(es)
	root.add_child(exit)

	# Точка появления игрока — у южной стены, лицом к двери
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0, float(d.get("spawn_y", 0.0)) + 0.1, dep / 2 - 2.5)
	if d.get("spawn_y", 0.0) > 0.0:
		spawn.position = Vector3(-w / 2 + 4, float(d.spawn_y) + 0.1, dep / 2 - 2.5)
	root.add_child(spawn)

	# Маркеры врагов
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	root.add_child(spawns)
	for i in d.enemies.size():
		var e: Array = d.enemies[i]
		var m := Marker3D.new()
		m.name = "%s_%d" % [e[0], i]
		m.position = e[1] + Vector3(0, 0.05, 0)
		m.set_meta("kind", e[0])
		m.set_meta("wave", e[2])
		if e.size() > 3:
			m.set_meta("count", e[3])
			m.set_meta("spread", e[4] if e.size() > 4 else 1.5)
		if e.size() > 5:
			var entry: Dictionary = e[5]
			# Отряд (SquadDef, GDD 12.6): kind = "squad" + squad / squad_options / squad_override / squad_anchor_pos
			for key in ["entry_mode", "entry_target", "spread_axes", "entry_batch", "squad", "squad_options", "squad_override", "squad_anchor_pos"]:
				if entry.has(key):
					m.set_meta(key, entry[key])
		spawns.add_child(m)

	# Особые точки (не волны): {"Имя": Vector3} — один маркер, {"Имя": [Vector3...]} — группа маркеров
	var marks: Dictionary = d.get("markers", {})
	for mname in marks:
		var v: Variant = marks[mname]
		if v is Vector3:
			var mk := Marker3D.new()
			mk.name = mname
			mk.position = v + Vector3(0, 0.05, 0)
			root.add_child(mk)
		else:
			var grp := Node3D.new()
			grp.name = mname
			root.add_child(grp)
			for k in (v as Array).size():
				var mk2 := Marker3D.new()
				mk2.name = "%s%d" % [mname.trim_suffix("s"), k]
				mk2.position = (v as Array)[k] + Vector3(0, 0.05, 0)
				grp.add_child(mk2)

	# Дома из модулей MegaKit вокруг блоков: [индекс блока в "blocks", сторона двери, стиль, {recipe, yard}] (П11)
	var houses: Array = d.get("houses", [])
	if not houses.is_empty():
		var hnode := Node3D.new()
		hnode.name = "Houses"
		root.add_child(hnode)
		for i in houses.size():
			var hb: Array = d.blocks[houses[i][0]]
			var h: Array = houses[i]
			gen._house(hnode, "House%d" % i, hb[0], hb[1], h[1], h[2] if h.size() > 2 else "Plaster", h[3] if h.size() > 3 else {})

	# Декоративные модели (без коллизии): [путь к сцене, позиция, поворот по Y (град), масштаб]
	var models: Array = d.get("models", [])
	if not models.is_empty():
		var dnode := Node3D.new()
		dnode.name = "Decor"
		root.add_child(dnode)
		for i in models.size():
			var md: Array = models[i]
			var inst := (load(md[0]) as PackedScene).instantiate() as Node3D
			inst.name = "%s_%d" % [(md[0] as String).get_file().get_basename(), i]
			inst.position = md[1]
			inst.rotation_degrees.y = md[2]
			inst.scale = Vector3.ONE * float(md[3])
			dnode.add_child(inst)

	# Прыжковые руны (GDD 7.2): [позиция на полу, высота подброса]
	var pads: Array = d.get("jump_pads", [])
	if not pads.is_empty():
		var pnode := Node3D.new()
		pnode.name = "JumpPads"
		root.add_child(pnode)
		for i in pads.size():
			var jp := Area3D.new()
			jp.name = "JumpPad%d" % i
			jp.set_script(load("res://rooms/jump_pad.gd"))
			jp.position = (pads[i] as Array)[0]
			jp.set("height", (pads[i] as Array)[1])
			pnode.add_child(jp)

	# Бочки и ящики
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var prop_scenes := {}
	var all_props: Array = d.props + (_corner_props(d, openings) if (d.get("dress", {}) as Dictionary).get("corner_props", true) else [])
	for i in all_props.size():
		var pr: Array = all_props[i]
		# "barrel", "crate", "barrel_explosive" → props/<вид>.tscn
		if not prop_scenes.has(pr[0]):
			prop_scenes[pr[0]] = load("res://props/%s.tscn" % pr[0]) as PackedScene
		var inst := (prop_scenes[pr[0]] as PackedScene).instantiate() as Node3D
		inst.name = "%s_%d" % [pr[0], i]
		inst.position = pr[1] + Vector3(0, 0.02, 0)
		inst.rotation.y = randf() * TAU
		props.add_child(inst)

	# Факелы
	var lights := Node3D.new()
	lights.name = "Torches"
	root.add_child(lights)
	var ty := float(d.get("torch_y", 3.2))
	var torch_pos := [Vector3(-w / 2 + 0.2, ty, -dep / 4), Vector3(w / 2 - 0.2, ty, -dep / 4), Vector3(-w / 2 + 0.2, ty, dep / 4), Vector3(w / 2 - 0.2, ty, dep / 4),
		Vector3(-gap / 2 - 1.2, 3.6 + exit_y, -dep / 2 + 0.1), Vector3(gap / 2 + 1.2, 3.6 + exit_y, -dep / 2 + 0.1)]
	for entry in d.get("torch_overrides", []):
		if entry is Array and entry.size() == 2 and int(entry[0]) >= 0 and int(entry[0]) < torch_pos.size() and entry[1] is Vector3:
			torch_pos[int(entry[0])] = entry[1]
		else:
			push_error("torch_overrides: нужен индекс факела и позиция Vector3")
	# Ориентиры у подъёмов: ближайший боковой факел (0–3) переезжает на стойку у подъёма, под ним — знамя
	var landmark_decor: Array = []
	if not d.has("torch_overrides") and d.get("landmarks", true):
		var moved := {}
		var spots := _landmarks(d, w, dep, openings)
		for li in spots.size():
			var spot: Vector3 = spots[li]
			var best := -1
			for ti in 4:
				if moved.has(ti):
					continue
				if best < 0 or Vector2(torch_pos[ti].x - spot.x, torch_pos[ti].z - spot.z).length() < Vector2(torch_pos[best].x - spot.x, torch_pos[best].z - spot.z).length():
					best = ti
			if best < 0:
				break
			moved[best] = true
			torch_pos[best] = spot
			landmark_decor.append([LANDMARK_BANNERS[li % LANDMARK_BANNERS.size()], spot - Vector3(0, 0.8, 0), 0.0, 1.5])
	var flame := gen._mat("flame", Color(1.0, 0.6, 0.2), 0.5, false, 5.0)
	var holder := gen._mat("holder", Color(0.25, 0.22, 0.2), 0.6, false)
	for i in torch_pos.size():
		var t := Node3D.new()
		t.name = "Torch%d" % i
		t.position = torch_pos[i]
		lights.add_child(t)
		# Модель Quaternius Torch_Metal смотрит в +Z — разворачиваем от стены внутрь зала
		var p3: Vector3 = torch_pos[i]
		var yaw := 0.0
		if absf(p3.x) > w / 2 - 1.0:
			yaw = 90.0 if p3.x < 0 else -90.0
		t.rotation_degrees.y = yaw
		gen._model(t, "Model", SceneBuilder.QP + "Torch_Metal.gltf", Vector3(0, -0.3, -0.25), Vector3.ZERO, Vector3.ONE * 1.4)
		gen._mesh(t, "Flame", gen._cylmesh(0.0, 0.11, 0.3), Vector3(0, 0.38, 0.08), flame)
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 2.2
		l.omni_range = 9.0
		l.position = Vector3(0, 0.3, 0)
		t.add_child(l)

	# Знамёна, щиты и плакаты на стенах (комплект владельца assets/decor/, rooms/wall_decor.gd): авто-расстановка
	# по стенам + ключ "decor" зала. Квады собираются при запуске из общего материала WorldArt.
	_build_wall_art(root, d, w, dep, gap, landmark_decor)
	# Статичные декали на полу (assets/decals/, rooms/floor_decal.gd): [декаль, позиция, поворот Y, размер м, (glow)]
	var decals: Array = d.get("decals", [])
	if not decals.is_empty():
		var dn := Node3D.new()
		dn.name = "Decals"
		root.add_child(dn)
		for i in decals.size():
			var dc: Array = decals[i]
			var fd := Node3D.new()
			fd.name = "%s_%d" % [(dc[0] as String).to_pascal_case(), i]
			fd.set_script(load("res://rooms/floor_decal.gd"))
			fd.set("art", dc[0])
			fd.set("size", dc[3])
			fd.set("glow", dc.size() > 4 and bool(dc[4]))
			fd.position = dc[1]
			fd.rotation_degrees.y = dc[2]
			dn.add_child(fd)

	# Портал-свет у выхода
	var pl := OmniLight3D.new()
	pl.name = "PortalLight"
	pl.light_color = Color(0.45, 0.8, 1.0)
	pl.light_energy = 2.5
	pl.omni_range = 7.0
	pl.position = Vector3(0, 2.0 + exit_y, -dep / 2 - 4.5)
	root.add_child(pl)

	# Ларёк (зал-ларёк): узел со скриптом, модели собираются при запуске
	if d.has("stall"):
		var stall := Node3D.new()
		stall.name = "ShopStall"
		stall.set_script(load("res://rooms/shop_stall.gd"))
		stall.position = d.stall
		root.add_child(stall)

	# Одевание (блок Б0): коллизия та же, вид — модели, MultiMesh и общий шейдер поверхностей
	var opts: Dictionary = (d.get("dress", {}) as Dictionary).duplicate()
	opts["surface_materials"] = surface_materials
	var styles := {}
	for i in d.blocks.size():
		styles["Block%d" % i] = _block_style(d, i)
	opts["styles"] = styles
	if d.get("floor_tex", "") == "dirt_straw":
		opts["floor"] = "dirt"
	RoomDresser.new(hash(d.file)).dress_room(root, opts)
	gen.room_floor._build_enemy_navigation(root, d, openings, w, dep)
	gen._save(root, "res://rooms/%s.tscn" % d.file)

## Точки ориентиров (позиции факела): низ пандусов, низ ступеней вышек, прыжковые руны — сбоку от подъёма,
## к ближней стене; не в блоке, не у пропсов и не над вырезом в полу. Не больше LANDMARK_MAX, не ближе 5 м друг к другу.
func _landmarks(d: Dictionary, w: float, dep: float, openings: Array[Rect2]) -> Array:
	# Кандидаты: [основание подъёма, ось подъёма (xz), полуширина]
	var cands: Array = []
	for r in d.get("ramps", []):
		var spec: Array = r
		var size: Vector3 = spec[1]
		var axis := Basis.from_euler(Vector3(deg_to_rad(float(spec[2])), deg_to_rad(float(spec[4]) if spec.size() > 4 else 0.0), 0.0)) * Vector3(0, 0, size.z * 0.5)
		var c: Vector3 = spec[0]
		var foot := c + axis if (c + axis).y < (c - axis).y else c - axis
		# Верх нижнего конца; пандус с пола уходит концом чуть под пол — тогда основание на полу
		foot.y = foot.y + size.y * 0.5 if foot.y > 0.5 else 0.0
		cands.append([foot, Vector3(axis.x, 0, axis.z), size.x * 0.5])
	for t in d.get("watchtowers", []):
		# Без ступеней (Array с false) вышку соединяет пандус — его низ уже в списке
		if t is Array and not bool(t[1]):
			continue
		var tc: Vector3 = t[0] if t is Array else t
		cands.append([tc + Vector3(0, 0, -4.8), Vector3(0, 0, 1), 0.75])
	for jp in d.get("jump_pads", []):
		cands.append([(jp as Array)[0], Vector3(0, 0, 1), 1.0])
	var out: Array = []
	for cand in cands:
		if out.size() >= LANDMARK_MAX:
			break
		var base: Vector3 = cand[0]
		var axis2: Vector3 = cand[1]
		var side := Vector3(axis2.z, 0, -axis2.x).normalized() if axis2.length() > 0.01 else Vector3.RIGHT
		# Сначала — сторона дальше от центра зала (к стене)
		var dirs: Array = [side, -side]
		if (base + side).length() < (base - side).length():
			dirs = [-side, side]
		for dir in dirs:
			var p: Vector3 = base + dir * (float(cand[2]) + LANDMARK_SIDE)
			p.y = base.y + LANDMARK_TORCH_Y
			if _landmark_free(d, p, w, dep, openings, out):
				out.append(p)
				break
	return out

func _landmark_free(d: Dictionary, p: Vector3, w: float, dep: float, openings: Array[Rect2], taken: Array) -> bool:
	if absf(p.x) > w * 0.5 - 0.5 or absf(p.z) > dep * 0.5 - 0.5:
		return false
	for o in taken:
		if Vector2(p.x - o.x, p.z - o.z).length() < 5.0:
			return false
	for opening in openings:
		if opening.grow(0.6).has_point(Vector2(p.x, p.z)):
			return false
	for b in d.blocks:
		var bc: Vector3 = b[0]
		var bs: Vector3 = b[1]
		if absf(p.x - bc.x) < bs.x * 0.5 + 0.4 and absf(p.z - bc.z) < bs.z * 0.5 + 0.4 and bc.y - bs.y * 0.5 < p.y:
			return false
	for r in d.get("ramps", []):
		var rc: Vector3 = r[0]
		var rs: Vector3 = r[1]
		if Vector2(p.x - rc.x, p.z - rc.z).length() < maxf(rs.x, rs.z) * 0.5 and absf(p.x - rc.x) < rs.x * 0.5 + 0.3:
			return false
	for pr in d.props:
		if Vector2(p.x - pr[1].x, p.z - pr[1].z).length() < 1.2:
			return false
	for jp in d.get("jump_pads", []):
		if Vector2(p.x - jp[0].x, p.z - jp[0].z).length() < 1.6:
			return false
	for pp in d.pillars:
		if Vector2(p.x - pp.x, p.z - pp.z).length() < 1.2:
			return false
	return true

func _build_wall_art(root: Node, d: Dictionary, w: float, dep: float, gap: float, landmark_decor: Array = []) -> void:
	var art := Node3D.new()
	art.name = "Banners"
	root.add_child(art)
	var ri := absi(hash(d.file)) % 97
	var no_auto: Array = d.get("no_auto", [])
	var k := 0
	var bz: Array = [0.0] if dep < 26 else [-dep / 8, dep / 8 + 2]
	if not "side" in no_auto:
		for z in bz:
			_wall_decor(art, "BannerW%d" % int(z), WorldArt.BANNERS[(ri + k) % 8], Vector3(-w / 2 + K.WALL_INSET, 4.35, z), 90.0, 2.3)
			_wall_decor(art, "BannerE%d" % int(z), WorldArt.BANNERS[(ri + k + 3) % 8], Vector3(w / 2 - K.WALL_INSET, 4.35, z), -90.0, 2.3)
			k += 1
		# Щиты: у углов и между факелами и знамёнами
		var sz: Array = [-dep * 3 / 8, dep * 3 / 8]
		if dep < 26:
			sz += [-dep / 8, dep / 8]
		else:
			sz.append((float(bz[0]) + float(bz[1])) / 2.0)
		for z in sz:
			_wall_decor(art, "ShieldW%d" % int(z), WorldArt.SHIELDS[(ri + k) % 8], Vector3(-w / 2 + K.WALL_INSET, 4.55, z), 90.0, 1.05)
			_wall_decor(art, "ShieldE%d" % int(z), WorldArt.SHIELDS[(ri + k + 4) % 8], Vector3(w / 2 - K.WALL_INSET, 4.55, z), -90.0, 1.05)
			k += 1
	if not "north" in no_auto:
		# Знамёна по бокам выхода (дальше факелов у проёма)
		var nx := gap / 2 + minf(3.6, (w - gap) / 4)
		for sx in [-1.0, 1.0]:
			_wall_decor(art, "BannerN%d" % int(sx), WorldArt.BANNERS[(ri + k) % 8], Vector3(sx * nx, 4.2, -dep / 2 + K.WALL_INSET), 0.0, 2.1)
			k += 1
	if not "south" in no_auto:
		for sx in [-1.0, 1.0]:
			_wall_decor(art, "ShieldS%d" % int(sx), WorldArt.SHIELDS[(ri + k) % 8], Vector3(sx * w / 4, 4.3, dep / 2 - K.WALL_INSET), 180.0, 1.15)
			k += 1
	var extra: Array = d.get("decor", []) + landmark_decor
	for i in extra.size():
		var e: Array = extra[i]
		_wall_decor(art, "%s_%d" % [(e[0] as String).to_pascal_case(), i], e[0], e[1], e[2], e[3])

func _wall_decor(parent: Node, name: String, art: String, pos: Vector3, yaw: float, height: float) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.set_script(load("res://rooms/wall_decor.gd"))
	n.set("art", art)
	n.set("height", height)
	n.position = pos
	n.rotation_degrees.y = yaw
	parent.add_child(n)
	return n
