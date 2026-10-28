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
	# Комиксовая обводка (scripts/outline.gd): образцы обводятся и при выключенной настройке — включение
	# в паузе потом без компиляции; на всех форматах вершин (у оверлея, как у вспышки, — свои пайплайны)
	Outline.begin_warmup()
	var game: Node = self
	var right := global_transform.basis.x
	var center := global_position
	# Враги: по одному каждого вида, со вспышкой урона и свечением замаха (общий оверлей на скин-мешах)
	# В GL Compatibility вариант шейдера не зависит от формата вершин, а запас instance-переменных ограничен:
	# оверлей вспышки только на паре образцов. Старый счётчик видел 263–270 узлов с текущими материалами при
	# полном прогреве, но он не показывает занятые слоты. В Forward+ оверлей на всех: пайплайн на каждый формат вершин.
	var gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var i := 0
	for path in ["res://enemies/grunt.tscn", "res://enemies/thrower.tscn", "res://enemies/boss.tscn",
			"res://enemies/fodder.tscn", "res://enemies/bloated.tscn", "res://enemies/shieldbearer.tscn", "res://enemies/shaman.tscn", "res://enemies/merc.tscn",
			"res://enemies/sven.tscn", "res://enemies/jarl.tscn"]:
		var e := (load(path) as PackedScene).instantiate() as Enemy
		e.process_mode = Node.PROCESS_MODE_DISABLED
		if i == 0:
			Loot.make_elite(e)
		e.position = right * ((i - 1) * 0.9 if i < 3 else (i - 5.5) * 0.7) + (Vector3.ZERO if i < 3 else Vector3(0, 0, -1.2))
		add_child(e)
		e.remove_from_group("enemies")
		e.collision_layer = 0
		e.collision_mask = 0
		if not gl or i < 2:
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
		var gl_flash: ShaderMaterial
		if gl:
			gl_flash = Enemy.FLASH_MATERIAL_GL.duplicate() as ShaderMaterial
			gl_flash.next_pass = Outline.flash_next_pass()
			gl_flash.set_shader_parameter("flash", 1.0)
			gl_flash.set_shader_parameter("glow", 1.0)
		var with_overlay := 0
		for mi in h.find_children("*", "MeshInstance3D", true, false):
			if gl and with_overlay >= 2:
				continue
			with_overlay += 1
			var gi := mi as GeometryInstance3D
			gi.material_overlay = gl_flash if gl else Enemy.FLASH_MATERIAL
			if not gl:
				gi.set_instance_shader_parameter("flash", 1.0)
				gi.set_instance_shader_parameter("glow", 1.0)
		Outline.add(h)
	# Оружие (на слое мира — как у врагов)
	var wi := 0
	for kind in WeaponMeshes.MODEL_WEAPONS.keys() + WeaponMeshes.PAINTED.keys() + ["axe", "hammer", "club", "staff", "sword", "spear", "pitchfork", "torch", "shield"]:
		var wpn := WeaponMeshes.build(kind)
		add_child(wpn)
		Outline.add(wpn)
		wpn.position = right * (wi * 0.15 - 1.3) + Vector3(0, 1.2, 0)
		wi += 1
	# Оружие этапа 1: ренж, подбор, сундук, трассеры, гильзы, вспышка; и то же во вьюмодели рук
	Loot.warmup_samples(self, right)
	# Разрушаемое: бочка, ящик, взрывная бочка (метка), их обломки и шар лечения из ящика
	Destructible.warmup_samples(self, right)
	# Двери-награды: арка, проём, иконка-глиф и подписи (Label3D), котёл привала
	RewardFlow.warmup_samples(self, right)
	# Глифы подписей в мире (цифры урона, элита, двери) и экранов выбора — заранее во всех размерах
	_warm_label_glyphs()
	_warm_ui_glyphs()
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
	# Портреты тех, кто может заговорить пузырём в этом зале (загрузка картинки в бою — фриз ~20 мс)
	Portrait.prefetch(_room_speakers())
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
	# Текстурные эффекты VFX-комплекта: все материалы (по одному на текстуру) во всех режимах billboard
	FX.warmup_sprites(self, p, right)
	# Свободный узел пула эффектов отдаёт материал (FX._take): квад остаётся с материалом по умолчанию,
	# и его пайплайны компилируются при первом же исчезновении дыма (~0.5 с после первой разбитой бочки,
	# первой смерти) — даже у скрытого узла. Прогреваем здесь: те же общие квады без материала.
	# (и прозрачными — эффект прячется, когда transparency ещё не 0)
	for k in 6:
		var bare := MeshInstance3D.new()
		bare.mesh = FX.shared_mesh(["quad", "quad_bottom", "quad_floor"][k % 3])
		bare.transparency = 0.0 if k < 3 else 0.5
		bare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bare.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(bare)
		bare.position = Vector3(0, -3.0, 0)
		bare.visible = false
	FX.hit_flash(game, p, 0.4)
	FX.smoke(game, p, 0.4)
	FX.scorch(game, center, 0.8)
	# Графика мира: декор на стенах, рунные круги, частицы атмосферы (искры, огонь очага, туман) — все материалы
	WorldArt.warmup(self, p, right)
	# Одевание залов (блок Б0): общий шейдер поверхностей и все меши MultiMesh со своими материалами
	RoomDress.warmup(self, center, right)
	if VfxScreen.instance and is_instance_valid(VfxScreen.instance):
		VfxScreen.instance.warmup(FRAMES)
	ComicFX.warmup()
	var fire := preload("res://weapons/fire_zone.gd").new()
	add_child(fire)
	fire.setup(center, 0.8, 0.2, 0.0)
	var proj: Node3D = preload("res://enemies/enemy_projectile.gd").new()
	add_child(proj)
	proj.call("launch", p, Vector3.ZERO, 0.0, null)
	proj.remove_from_group("reflectable")
	proj.set_physics_process(false)
	# Телеграф взрыва (Раздутый, элита «Взрывной», Свен)
	Blast.warmup_sample(self, Vector3(0, 0.1, 0.5))
	# Толстый Свен: плевок и лужа браги, полоса телеграфа тарана (у всех BossEnemy)
	var puddle := BrewPuddle.new()
	add_child(puddle)
	puddle.position = Vector3(0.6, 0.05, 0.3)
	puddle.set_physics_process(false)
	puddle._disc.scale = Vector3(0.6, 0.02, 0.6)
	var glob := BrewGlob.new()
	add_child(glob)
	glob.position = Vector3(-0.6, 1.0, 0.3)
	glob.set_physics_process(false)
	for e in _enemies:
		if e is BossEnemy:
			(e as BossEnemy).warmup_strip()
	var hammer := WeaponMeshes.hammer()
	add_child(hammer)
	Outline.add(hammer)
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
	Outline.warming = false

## Label3D растеризует букву (FreeType) и перезаливает текстуру кеша шрифта при первом показе этой буквы
## в этом размере с этой обводкой. Цифры урона прогревались двумя числами, подписи дверей — одной дверью:
## первые двери-награды давали на Forward+ (llvmpipe) +460 мс, новые цифры и подписи элиты — мелкие рывки.
## Размеры и обводки — как у FX.damage_number / Loot.make_elite (48/12) и RewardDoor._label (54/9, 34/6, 170/28).
func _warm_label_glyphs() -> void:
	var font := load("res://fonts/RussoOne-Regular.ttf") as Font
	var small := "0123456789()/·+-–—%×:!?., " + I18n.t("Элита")
	for m in Loot.elite_modifiers():
		small += I18n.t(m.title)
	var titles := ""
	var descs := ""
	var glyphs := ""
	for r in Run.all_rewards:
		titles += tr(r.title).to_upper()
		descs += tr(r.description)
		glyphs += r.glyph
	var y := 0.0
	for spec in [[48, 12, small], [54, 9, titles], [34, 6, descs], [170, 28, glyphs]]:
		var chars := {}
		for ch in String(spec[2]):
			chars[ch] = true
		var l := Label3D.new()
		if font:
			l.font = font
		l.font_size = spec[0]
		l.outline_size = spec[1]
		l.text = "".join(PackedStringArray(chars.keys()))
		l.pixel_size = 0.0004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Color(1, 1, 1, 0.05)
		add_child(l)
		l.position = Vector3(0, 0.6 + y, -0.5)
		y += 0.1

## Буквы экранов выбора (руна, трейт, привал/Локи), пузыря реплик — в их размерах и обводках
## (UIStyle.label: шрифт + размер + обводка = свой кеш глифов). Первое открытие выбора руны посреди забега
## растеризовало весь текст карточек. Один раз за запуск игры: кеш шрифта живёт, пока жив шрифт.
static var _ui_glyphs_warmed: bool = false

func _warm_ui_glyphs() -> void:
	if _ui_glyphs_warmed:
		return
	_ui_glyphs_warmed = true
	var text := "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя" \
		+ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?«»\"'—–-+×%()/[]→·…ᛗ "
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var box := VBoxContainer.new()
	box.modulate = Color(1, 1, 1, 0.02)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	# (размер, обводка): заголовки выбора 40/10 и 38/10, подсказки 18/4, имя говорящего 22/6, номер карточки 16/5,
	# название 19/5, описание 15/3, 14/3, 13/3, статус трейта 15/4, имя в пузыре 16/4
	for spec in [[40, 10], [38, 10], [18, 4], [22, 6], [16, 5], [19, 5], [15, 3], [14, 3], [13, 3], [15, 4], [16, 4]]:
		box.add_child(UIStyle.label(text, spec[0], Color.WHITE, spec[1]))

## Кто может заговорить в бою пузырём с портретом: Хугин (обучение), босс/мини-босс, ведущий испытания,
## хозяин двери-награды (Один на привале, Локи, Фрейя, Эйтри на наковальне); Тор — в каждом зале.
## У говорящего до шести эмоций в памяти.
func _room_speakers() -> PackedStringArray:
	# Тор может заговорить о тяжёлом ранении в любом бою; прогреваем все его эмоции заранее.
	var out := PackedStringArray(["thor"])
	var tut := game_node.get("tutorial") as Tutorial if game_node else null
	if tut and tut.active:
		out.append("hugin")
	if Run.is_boss_room():
		out.append("jarl")
	elif Run.is_miniboss_room():
		var mb := Run.miniboss_def() as MinibossDef
		if mb and mb.intro_pool != "":
			out.append(mb.intro_pool.get_slice(".", 0))
	var room := game_node.get("room") as Node if game_node else null
	var trial := room.get_node_or_null("Trial") as TrialRunner if room else null
	if trial and trial.def:
		# Пустые поля означают стандартный пул ведущего (TrialDef.pool), а не отсутствие реплик.
		for which in ["intro", "win", "fail"]:
			var trial_speaker := trial.def.pool(which).get_slice(".", 0)
			if trial_speaker != "" and not trial_speaker in out:
				out.append(trial_speaker)
	# Хозяин двери-награды: привал — Один, сделка — Локи, благословение — Фрейя, наковальня — Эйтри.
	# dwarves.eitri — имя пула, но сам говорящий в его репликах именно eitri.
	var host: String = {"rest": "odin", "loki": "loki", "freya": "freya", "anvil": "eitri"}.get(Run.current_reward(), "")
	if host != "":
		out.append(host)
	return out

func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left > 0:
		return
	for e in _enemies:
		if is_instance_valid(e) and e._telegraph and is_instance_valid(e._telegraph):
			e._telegraph.queue_free()
	queue_free()

## Образцы ушли (и при смене сцены до конца прогрева) — next_pass вспышки снова по настройке
func _exit_tree() -> void:
	Outline.end_warmup()
