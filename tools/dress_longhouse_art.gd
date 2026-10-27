extends Node
## Разовое: графика владельца на стенах длинного дома Ярла (ручная сцена rooms/boss_arena.tscn, assets/decor/):
## щиты рядами по боковым стенам, знамёна у выхода и по бокам, гобелен на южной стене. Узлы WallDecor
## (rooms/wall_decor.gd: квад собирается при запуске из общего материала WorldArt, без коллизии и тени).
## Знамёна-модели Quaternius (узел Banners) заменяются рисованными на тех же местах.
## Повторный запуск заменяет узлы Decor/WallArt и Banners целиком. Запуск (сценой, не -s):
##   godot --headless --path . res://tools/dress_longhouse_art.tscn

const SCENE := "res://rooms/boss_arena.tscn"
const DECOR := preload("res://rooms/wall_decor.gd")
## Внутренние грани стен: x = ±11 (боковые), z = −22 (выход), z = +22 (вход); лицевая сторона модулей — +0.09 м
const SIDE_X := 11.0 - 0.03
const NORTH_Z := -22.0 + 0.03
const SOUTH_Z := 22.0 - 0.03

func _art(parent: Node, name: String, art: String, pos: Vector3, yaw: float, height: float) -> void:
	var n := Node3D.new()
	n.name = name
	n.set_script(DECOR)
	n.set("art", art)
	n.set("height", height)
	n.position = pos
	n.rotation_degrees.y = yaw
	parent.add_child(n)

func _replace(root: Node, parent: Node, name: String) -> Node3D:
	var old := parent.get_node_or_null(name)
	if old:
		parent.remove_child(old)
		old.free()
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	n.owner = root
	return n

func _ready() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	var decor := root.get_node_or_null("Decor")
	if decor == null:
		push_error("dress_longhouse_art: нет узла Decor (сначала tools/dress_longhouse.tscn)")
		get_tree().quit(1)
		return
	var shields: Array = WorldArt.SHIELDS
	var banners: Array = WorldArt.BANNERS
	# Знамёна по бокам — там, где висели модели (z = −5.5 и 7.5), выше балконов
	var bn := _replace(root, root, "Banners")
	var k := 0
	for z in [-5.5, 7.5]:
		_art(bn, "BannerW%d" % int(z), banners[k % 8], Vector3(-SIDE_X, 4.45, z), 90.0, 2.4)
		_art(bn, "BannerE%d" % int(z), banners[(k + 3) % 8], Vector3(SIDE_X, 4.45, z), -90.0, 2.4)
		k += 1
	var wa := _replace(root, decor, "WallArt")
	# Щиты рядом по боковым стенам (над балконами; факелы — z = ±11, знамёна — −5.5 и 7.5)
	var s := 0
	for z in [-19.0, -15.0, -8.3, -1.5, 2.0, 4.8, 14.5, 18.5]:
		_art(wa, "ShieldW%d" % int(z), shields[s % 8], Vector3(-SIDE_X, 4.85, z), 90.0, 1.1)
		_art(wa, "ShieldE%d" % int(z), shields[(s + 3) % 8], Vector3(SIDE_X, 4.85, z), -90.0, 1.1)
		s += 1
	# Выход (северная стена, проём 4 м, факелы — x = ±3.2): большие знамёна и щиты по краям
	_art(wa, "BannerN_L", "banner_wolf", Vector3(-6.2, 4.0, NORTH_Z), 0.0, 2.7)
	_art(wa, "BannerN_R", "banner_raven", Vector3(6.2, 4.0, NORTH_Z), 0.0, 2.7)
	_art(wa, "ShieldN_L", "shield_raven", Vector3(-9.2, 4.6, NORTH_Z), 0.0, 1.2)
	_art(wa, "ShieldN_R", "shield_sun", Vector3(9.2, 4.6, NORTH_Z), 0.0, 1.2)
	# Вход (южная стена, за спиной у точки появления): гобелен посередине, щиты по бокам
	_art(wa, "Tapestry", "tapestry", Vector3(0, 3.4, SOUTH_Z), 180.0, 3.6)
	for i in 4:
		var x: float = [-8.8, -3.6, 3.6, 8.8][i]
		_art(wa, "ShieldS%d" % i, shields[(i + 5) % 8], Vector3(x, 4.5, SOUTH_Z), 180.0, 1.15)
	for n in [bn, wa]:
		for c in n.get_children():
			c.owner = root
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, SCENE)
	print("dress_longhouse_art: ", "готово" if err == OK else "ошибка %d" % err)
	root.free()
	get_tree().quit(0 if err == OK else 1)
