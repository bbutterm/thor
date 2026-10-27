extends Node
## Разовое (блок Б0 «Одеть залы»): одевание ручных арен (MANUAL_SCENES генератора) тем же RoomDresser, что и
## обычные залы — пол с затемнением, скошенные блоки, рамы, обломки, колонны в углах, декали, кости.
## Длинный дом Ярла (rooms/boss_arena.tscn) — ещё и закрытая двускатная крыша (доски MegaKit изнутри, стропила,
## прогоны, фронтоны), конёк на вершину, зал под крышей (Room.indoor — свой свет, WorldArt.apply_room),
## свет люстр и очага. Коллизия, балконы и маркеры не меняются.
## Повторный запуск заменяет узлы Dress (и всё, что в нём). Запуск (сценой, не -s — нужны автозагрузки):
##   godot --headless --path . res://tools/dress_arenas.tscn

const ARENAS := {
	"res://rooms/boss_arena.tscn": {"floor": "dirt", "palisade": false, "backdrop": false, "vines": false, "decals": 16,
		"styles": {"Block0": "wood", "Block1": "wood", "Block2": "wood", "Block3": "wood"}},
	"res://rooms/sven_arena.tscn": {"floor": "brick", "decals": 14, "styles": {"Block0": "wood", "Block1": "wood"}},
}
## Крыша длинного дома: уклон ската, град; свес за стены, м
const ROOF_PITCH := 28.0
const ROOF_OVERHANG := 0.4

func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)

func _ready() -> void:
	var failed := false
	for path in ARENAS:
		var root := (load(path) as PackedScene).instantiate() as Node3D
		var d := RoomDresser.new(hash(path.get_file().get_basename()))
		d.dress_room(root, ARENAS[path])
		if path.ends_with("boss_arena.tscn"):
			_longhouse_roof(root, d)
			root.set("indoor", true)
			_longhouse_lights(root)
		_own(root, root)
		var ps := PackedScene.new()
		var err := ps.pack(root)
		if err == OK:
			err = ResourceSaver.save(ps, path)
		print("dress_arenas: %s — %s" % [path, "готово" if err == OK else "ошибка %d" % err])
		failed = failed or err != OK
		root.free()
	get_tree().quit(1 if failed else 0)

## Двускатная крыша над стенами (x = ±w/2, верх стен WALL_TOP): изнутри — доски (Floor_WoodDark лицом вниз),
## стропила по скатам над каждой затяжкой (Decor/Rafter*), прогоны вдоль зала, фронтоны досками.
func _longhouse_roof(root: Node3D, d: RoomDresser) -> void:
	var hx := d.w * 0.5 + ROOF_OVERHANG
	var hz := d.dep * 0.5
	var pitch := deg_to_rad(ROOF_PITCH)
	var rise := hx * tan(pitch)
	var top := RoomDresser.WALL_TOP + rise
	var slope_len := hx / cos(pitch)
	var roof := Node3D.new()
	roof.name = "Roof"
	d.dress.add_child(roof)
	# Доски кровли: плитки 2 × 2 м лицом вниз (видны из зала), рядами вдоль ската
	var nz := int(ceil((d.dep + 1.6) / 1.95))
	var ns := int(ceil(slope_len / 1.95))
	for side: float in [-1.0, 1.0]:
		# Поворот вокруг −Z на side·pitch: локальная X плитки/бревна — вдоль ската (от карниза к коньку)
		var tilt := Basis(Vector3.FORWARD, side * pitch)
		for i in ns:
			var t := (i + 0.5) * slope_len / ns
			var px := side * (hx - t * cos(pitch))
			var py := RoomDresser.WALL_TOP + t * sin(pitch)
			for k in nz:
				var pz := -hz - 0.8 + (k + 0.5) * (d.dep + 1.6) / nz
				var b := tilt * Basis(Vector3.RIGHT, PI)
				d._add("tile", d._fit("tile", Vector3(px, py, pz), Vector3(slope_len / ns + 0.06, 0.03, (d.dep + 1.6) / nz + 0.04), 0.0, b))
		# Стропила по скату над затяжками и прогоны вдоль зала (бревна под досками)
		var decor := root.get_node_or_null("Decor")
		var zs: Array = []
		if decor:
			for c in decor.get_children():
				if String(c.name).begins_with("Rafter"):
					zs.append((c as Node3D).position.z)
		if zs.is_empty():
			for i in 11:
				zs.append(-20.0 + i * 4.0)
		for z: float in zs:
			var mid := Vector3(side * hx * 0.5, RoomDresser.WALL_TOP + rise * 0.5 - 0.22, z)
			d._add("log", Transform3D(tilt * Basis.from_scale(Vector3(slope_len, 0.17, 0.17)), mid))
		for f: float in [0.3, 0.62]:
			var px2 := side * hx * (1.0 - f)
			var py2 := RoomDresser.WALL_TOP + rise * f - 0.3
			d._add("log", Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(d.dep + 1.2, 0.15, 0.15)), Vector3(px2, py2, 0)))
	# Фронтоны: треугольники досок над северной и южной стенами (с обеих сторон — изнутри и снаружи)
	var gable := _gable_mesh(hx, rise)
	for sz: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "Gable%s" % ("N" if sz < 0 else "S")
		mi.mesh = gable
		mi.material_override = RoomDress.material("surface_plank")
		mi.position = Vector3(0, RoomDresser.WALL_TOP - 0.05, sz * (hz + 0.15))
		roof.add_child(mi)
		# Стойки фронтона
		for x: float in [-4.0, 0.0, 4.0]:
			var h := rise * (1.0 - absf(x) / hx)
			d._add("log", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(h, 0.14, 0.14)), Vector3(x, RoomDresser.WALL_TOP + h * 0.5 - 0.05, sz * (hz - 0.05))))
	d._flush()
	# Конёк — на вершину (бревно Roof_Log: его меш смещён вверх на ~4.54 м)
	var ridge := root.get_node_or_null("Decor/Ridge") as Node3D
	if ridge:
		ridge.position.y = top - 0.35 - 4.54

## Треугольник фронтона (основание 2·hx, высота rise), двусторонний, цвет вершин — темнее книзу.
func _gable_mesh(hx: float, rise: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-hx, 0, 0)
	var b := Vector3(hx, 0, 0)
	var c := Vector3(0, rise, 0)
	for n in [Vector3.BACK, Vector3.FORWARD]:
		RoomDresser._tri(st, a, b, c, n, Color(0.7, 0.7, 0.7), Color(0.7, 0.7, 0.7), Color.WHITE)
	return st.commit()

## Свет под крышей: очаг ярче и шире, тёплые огни у двух люстр (без теней — тени только у факелов).
func _longhouse_lights(root: Node3D) -> void:
	var hl := root.get_node_or_null("Decor/Hearth/HearthLight") as OmniLight3D
	if hl:
		hl.light_energy = 2.4
		hl.omni_range = 13.0
	for z in [-14.0, 14.0]:
		var ch := root.get_node_or_null("Decor/Chandelier_%d" % int(z)) as Node3D
		if ch == null or ch.has_node("Glow"):
			continue
		var l := OmniLight3D.new()
		l.name = "Glow"
		l.light_color = Color(1.0, 0.66, 0.36)
		l.light_energy = 1.3
		l.omni_range = 11.0
		l.position = Vector3(0, -0.6, 0)
		ch.add_child(l)
