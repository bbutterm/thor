extends Node3D
class_name ShaderWarmup
## Прогрев шейдеров при входе в забег: пока экран затемнён, перед камерой на несколько кадров рисуется
## по образцу всего, что появляется в бою (враги со вспышкой и свечением, оружие, снаряды, огонь, молнии,
## искры, цифры урона, телеграф босса). Иначе шейдер/пайплайн компилируется в момент первого появления
## эффекта — классический фриз на Windows (особенно D3D12/Vulkan).

## Сколько кадров держать образцы перед камерой (экран в это время затемнён — HUD.fade_in)
const FRAMES := 10

var _frames_left: int = FRAMES
var _enemies: Array[Enemy] = []

static func run(game: Node3D) -> void:
	var cam := game.get_viewport().get_camera_3d()
	if cam == null:
		return
	# Поворот игрока к точке появления применяется в его _process — применим сразу, иначе образцы
	# окажутся вне кадра, отсекутся и ничего не прогреют
	var player := game.get("player") as Player
	if player:
		player.rotation.y = player.rotation_target.y
		player.head.rotation.x = player.rotation_target.x
	var w := ShaderWarmup.new()
	w.name = "ShaderWarmup"
	# Дочерний узел камеры — образцы остаются в кадре, даже если камера сдвинется
	cam.add_child(w)
	w.position = Vector3(0, -1.0, -3.2)
	w.game_node = game
	w._build()

var game_node: Node

func _build() -> void:
	Perf.mark("shader_warmup")
	var game: Node = self
	var right := global_transform.basis.x
	var center := global_position
	# Враги: по одному каждого вида, со вспышкой урона и свечением замаха (общий оверлей на скин-мешах)
	var i := 0
	for path in ["res://enemies/grunt.tscn", "res://enemies/thrower.tscn", "res://enemies/boss.tscn",
			"res://enemies/fodder.tscn", "res://enemies/bloated.tscn", "res://enemies/shieldbearer.tscn", "res://enemies/shaman.tscn", "res://enemies/merc.tscn"]:
		var e := (load(path) as PackedScene).instantiate() as Enemy
		e.process_mode = Node.PROCESS_MODE_DISABLED
		if i == 0:
			Loot.make_elite(e)
		e.position = right * ((i - 1) * 0.9 if i < 3 else (i - 5.5) * 0.7) + (Vector3.ZERO if i < 3 else Vector3(0, 0, -1.2))
		add_child(e)
		e.remove_from_group("enemies")
		e.collision_layer = 0
		e.collision_mask = 0
		e._set_overlay(1.0, 1.0)
		# Лазер наёмника (общие материалы эффектов)
		if e._laser:
			e._laser.visible = true
			e._laser_dot.visible = true
			e._laser.global_position = e.global_position + Vector3(0, 1.3, 0.6)
			e._laser.scale = Vector3(0.018, 0.018, 1.0)
			e._laser_dot.global_position = e.global_position + Vector3(0, 1.3, 1.1)
		_enemies.append(e)
		i += 1
	# Все части одежды и волос на двух скелетах: случайная внешность драугров собирается из них,
	# и у каждой части свой формат вершин — значит, свои пайплайны (в т.ч. тени и оверлей вспышки)
	for g in ["Male", "Female"]:
		var h := HumanoidModel.new()
		h.body = "base/Superhero_%s_FullBody.gltf" % g
		h.outfit = ""
		var parts: PackedStringArray = []
		for d in ["parts/", "hair/", "outfits/"]:
			for f in ResourceLoader.list_directory(HumanoidModel.BASE_DIR + d):
				if f.get_extension() == "gltf" and (f.begins_with(g + "_") or d == "hair/"):
					parts.append(d + f)
		h.parts = parts
		h.eye_glow = Color(0.4, 0.8, 1.0) if g == "Male" else Color(0, 0, 0, 0)
		h.skin_tint = Color(0.8, 0.85, 0.9)
		add_child(h)
		h.position = right * (1.6 if g == "Male" else -1.6)
		for mi in h.find_children("*", "MeshInstance3D", true, false):
			var gi := mi as GeometryInstance3D
			gi.material_overlay = Enemy.FLASH_MATERIAL
			gi.set_instance_shader_parameter("flash", 1.0)
			gi.set_instance_shader_parameter("glow", 1.0)
	# Оружие (на слое мира — как у врагов)
	var wi := 0
	for kind in WeaponMeshes.MODEL_WEAPONS.keys() + ["axe", "hammer", "club", "staff", "sword", "spear", "pitchfork", "torch", "shield"]:
		var wpn := WeaponMeshes.build(kind)
		add_child(wpn)
		wpn.position = right * (wi * 0.15 - 1.3) + Vector3(0, 1.2, 0)
		wi += 1
	# Оружие этапа 1: ренж, подбор, сундук, трассеры, гильзы, вспышка; и то же во вьюмодели рук
	Loot.warmup_samples(self, right)
	# Двери-награды: арка, проём, иконка-глиф и подписи (Label3D), котёл привала
	RewardFlow.warmup_samples(self, right)
	# Серебро (монета) и вывеска ларька (блок К)
	var coin := SilverCoin.new()
	add_child(coin)
	coin.set_physics_process(false)
	coin.remove_from_group("silver_coins")
	coin.position = right * 0.9 + Vector3(0, 0.6, 0)
	# Лава испытания Локи (блок Ф)
	TrialRunner.warmup_samples(self, right)
	var sign := ShopStall.make_sign_label()
	add_child(sign)
	sign.position = Vector3(0, 1.6, 0)
	sign.scale = Vector3.ONE * 0.3
	var pl := game_node.get("player") as Player if game_node else null
	if pl and pl.weapons:
		pl.weapons.warmup_viewmodel(FRAMES)
	# Эффекты
	var p := center + Vector3(0, 1.0, 0)
	FX.damage_number(game, p, 12)
	FX.damage_number(game, p, 40, Color(1, 0.4, 0.2), true)
	FX.lightning(game, p - right, p + right, 0.2)
	FX.burst(game, p, 0.5, Color(1, 1, 1, 0.5), 0.2)
	FX.ring(game, center, 1.0, Color(1, 1, 1, 0.8), 0.2)
	FX.sparks(game, p, Color(1, 0.8, 0.4), 8, 3.0, 10.0, 0.07, 0.2)
	ComicFX.warmup()
	var fire := preload("res://weapons/fire_zone.gd").new()
	add_child(fire)
	fire.setup(center, 0.8, 0.2, 0.0)
	var proj: Node3D = preload("res://enemies/enemy_projectile.gd").new()
	add_child(proj)
	proj.call("launch", p, Vector3.ZERO, 0.0, null)
	proj.remove_from_group("reflectable")
	proj.set_physics_process(false)
	# Телеграф взрыва (Раздутый, элита «Взрывной»)
	Blast.warmup_sample(self, Vector3(0, 0.1, 0.5))
	var hammer := WeaponMeshes.hammer()
	add_child(hammer)
	hammer.position = right * 0.6 + Vector3(0, 1.0, 0)
	# Свет без теней (как у огня, снарядов, молота) на весь зал: в GL Compatibility под каждый материал,
	# которого впервые касается такой свет, компилируется свой вариант шейдера
	var light := OmniLight3D.new()
	light.omni_range = 40.0
	light.light_energy = 0.01
	add_child(light)
	light.position = Vector3(0, 1.0, 0)
	# Красная вспышка экрана при уроне (рисуется, только когда не прозрачна)
	var hud := game_node.get("hud") as CanvasLayer if game_node else null
	if hud and hud.get("_hurt_rect"):
		(hud.get("_hurt_rect") as ColorRect).color.a = 0.02
	# Телеграф босса
	for e in _enemies:
		if e.kind == Enemy.Kind.BOSS:
			e._show_slam_telegraph()

func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left > 0:
		return
	for e in _enemies:
		if is_instance_valid(e) and e._telegraph and is_instance_valid(e._telegraph):
			e._telegraph.queue_free()
	queue_free()
