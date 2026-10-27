extends Node
## Разовое убранство длинного дома Ярла (ручная сцена rooms/boss_arena.tscn): стропила и конёк из брёвен MegaKit,
## люстры, очаг посередине, столы у южной стены. Только декор без коллизии — геймплей арены не меняется.
## Повторный запуск заменяет узел Decor целиком (кроме Decor/WallArt — графики на стенах, tools/dress_longhouse_art.tscn). Запуск: godot --headless --path . res://tools/dress_longhouse.tscn

const SCENE := "res://rooms/boss_arena.tscn"
const QV := "res://assets/quaternius/village/"
const QP := "res://assets/quaternius/props/"

func _add(parent: Node, name: String, path: String, pos: Vector3, rot_y: float = 0.0, scl: Vector3 = Vector3.ONE) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.name = name
	n.position = pos
	n.rotation_degrees.y = rot_y
	n.scale = scl
	parent.add_child(n)
	return n

func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)

func _ready() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	var old := root.get_node_or_null("Decor")
	# Графика на стенах (tools/dress_longhouse_art.tscn) — сохраняем при пересборке убранства
	var wall_art := old.get_node_or_null("WallArt") if old else null
	if wall_art:
		old.remove_child(wall_art)
	if old:
		root.remove_child(old)
		old.free()
	var decor := Node3D.new()
	decor.name = "Decor"
	root.add_child(decor)
	if wall_art:
		decor.add_child(wall_art)
	# Стропила поперёк зала (бревно Roof_Log 10.7 м вдоль Z, свой сдвиг по Y ≈ 3.85) — каждые 4 м, верх ~6.6 м
	for i in 11:
		var z := -20.0 + i * 4.0
		_add(decor, "Rafter%d" % i, QV + "Roof_Log.gltf", Vector3(0, 1.9, z), 90.0, Vector3(1, 1, 2.15))
	# Конёк вдоль зала
	_add(decor, "Ridge", QV + "Roof_Log.gltf", Vector3(0, 2.8, 0), 0.0, Vector3(1, 1, 4.15))
	# Люстры между стропилами
	for z in [-14.0, -6.0, 6.0, 14.0]:
		_add(decor, "Chandelier_%d" % int(z), QP + "Chandelier.gltf", Vector3(0, 5.4, z))
	# Очаг посередине: каменная оградка и тёплый свет
	var hearth := Node3D.new()
	hearth.name = "Hearth"
	decor.add_child(hearth)
	var k := 0
	for x in [-1.0, 1.0]:
		for j in 9:
			_add(hearth, "Stone%d" % k, QV + "Prop_Brick%d.gltf" % (1 + k % 4), Vector3(x * 1.1, 0.08, -2.4 + j * 0.6), randf() * 360.0, Vector3.ONE * 1.6)
			k += 1
	for z in [-2.7, 2.7]:
		for j in 4:
			_add(hearth, "Stone%d" % k, QV + "Prop_Brick%d.gltf" % (1 + k % 4), Vector3(-0.9 + j * 0.6, 0.08, z), randf() * 360.0, Vector3.ONE * 1.6)
			k += 1
	var light := OmniLight3D.new()
	light.name = "HearthLight"
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.position = Vector3(0, 1.0, 0)
	hearth.add_child(light)
	# Столы пира у южной стены (у точки появления — по бокам, проход свободен)
	for x in [-6.0, 6.0]:
		_add(decor, "Table_%d" % int(x), QP + "Table_Large.gltf", Vector3(x, 0, 19.6), 0.0)
	decor.owner = root
	_own(decor, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, SCENE)
	print("dress_longhouse: ", "готово" if err == OK else "ошибка %d" % err)
	root.free()
	get_tree().quit(0 if err == OK else 1)
