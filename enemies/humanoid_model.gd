extends Node3D
class_name HumanoidModel
## Сборщик персонажа Quaternius: базовое тело (голова, руки) + одежда + волосы на ОДНОМ скелете,
## плюс общая библиотека анимаций (UAL 1 и 2). Все модели используют одинаковый скелет из 65 костей.
##
## Как поменять модели на другие (например, Synty позже): либо поменяй пути ниже,
## либо положи в сцену врага свой узел "Visual" со своим AnimationPlayer — тогда этот сборщик не используется,
## а имена анимаций задаются в enemy.gd → ANIM_*.

const BASE_DIR := "res://assets/quaternius/characters/"
const ANIM_LIBS := {
	"ual1": BASE_DIR + "gaits.glb",
	"ual2": BASE_DIR + "animations.glb",
}

@export var body: String = "base/Superhero_Male_FullBody.gltf"
@export var outfit: String = "outfits/Male_Peasant.gltf"
@export var hair: String = ""
## Дополнительные части одежды/волос (пути от BASE_DIR) — для массовки из случайных комплектов.
@export var parts: PackedStringArray = []
## Цвета для частей из parts (по индексу; если меньше — берётся cloth_tint).
@export var part_tints: Array[Color] = []
## "" — весь персонаж; "right"/"left" — только одна рука (для вида от первого лица), тело/голова скрыты.
@export var arm_only: String = ""
## Покраска кожи (драугр — серо-синий, ледяной великан — голубой). Белый = без изменений.
@export var skin_tint: Color = Color.WHITE
## Покраска одежды (умножение цвета).
@export var cloth_tint: Color = Color.WHITE
## Свечение глаз (для нежити). Альфа 0 = без свечения.
@export var eye_glow: Color = Color(0, 0, 0, 0)

var skeleton: Skeleton3D
var anim: AnimationPlayer
var _libs_loaded := false

static var _lib_cache: Dictionary = {}

func _ready() -> void:
	build()

func build() -> void:
	if skeleton:
		return
	var base_scene := load(BASE_DIR + body) as PackedScene
	var base := base_scene.instantiate() as Node3D
	add_child(base)
	skeleton = base.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var dressed := outfit != "" or not parts.is_empty()
	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		var m := mi as MeshInstance3D
		if arm_only != "":
			m.visible = false
			continue
		# Одетый персонаж: от базового тела оставляем только голову и шею, иначе тело
		# «просвечивает» сквозь одежду (руки, ноги и торс уже есть в частях одежды).
		if dressed and not m.name.begins_with("Eye"):
			m.mesh = _head_only(m.mesh, body)
		_tint(m, skin_tint, m.name.begins_with("Eye") and eye_glow.a > 0.0)
	if outfit != "":
		_attach(BASE_DIR + outfit, cloth_tint)
		# Тело под одеждой прячем по частям нельзя (один меш), поэтому слегка «сжимаем» его через
		# shrink: оставляем как есть — одежда шире тела и закрывает его.
	if hair != "":
		_attach(BASE_DIR + hair, Color.WHITE)
	for i in parts.size():
		var tint: Color = part_tints[i] if i < part_tints.size() else cloth_tint
		_attach(BASE_DIR + parts[i], tint)
	if arm_only != "":
		# Граница — чуть выше локтя (по позе привязки), чтобы в кадре были только предплечье и кисть
		var elbow := skeleton.find_bone("lowerarm_" + ("r" if arm_only == "right" else "l"))
		var cut_x := absf(skeleton.get_bone_global_rest(elbow).origin.x) - 0.06 if elbow >= 0 else 0.12
		for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
			var m := mi as MeshInstance3D
			if m.visible:
				m.mesh = _side_only(m.mesh, parts[0] + m.name, arm_only, cut_x)
				_tint_skin_surfaces(m)
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	base.add_child(anim)
	anim.root_node = NodePath("..")
	for key in ANIM_LIBS:
		anim.add_animation_library(key, _library(ANIM_LIBS[key]))
	_libs_loaded = true

func _attach(path: String, tint: Color) -> void:
	if not ResourceLoader.exists(path):
		push_warning("HumanoidModel: нет файла " + path)
		return
	var part := (load(path) as PackedScene).instantiate() as Node3D
	var part_skel := part.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mi in part_skel.find_children("*", "MeshInstance3D", false, false):
		var m := mi as MeshInstance3D
		m.owner = null
		part_skel.remove_child(m)
		skeleton.add_child(m)
		m.skeleton = NodePath("..")
		_tint(m, tint, false, true)
	part.free()

## Материал кожи (кисти/лицо в частях одежды) — красим цветом кожи, а не одежды.
static func is_skin_material(m: Material) -> bool:
	if m == null:
		return false
	var n := m.resource_name.to_lower()
	return n.contains("regular") or n.contains("skin") or n.contains("superhero") or n.contains("body_mat")

func _tint(mi: MeshInstance3D, tint: Color, glow: bool, is_cloth: bool = false) -> void:
	if tint == Color.WHITE and not glow and not (is_cloth and skin_tint != Color.WHITE):
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		if src is BaseMaterial3D:
			var t := skin_tint if is_cloth and is_skin_material(src) else tint
			mi.set_surface_override_material(s, _tinted(src as BaseMaterial3D, t, eye_glow if glow else Color(0, 0, 0, 0)))

static var _tint_cache: Dictionary = {}

## Покрашенная копия материала — общая для всех персонажей с тем же цветом (палитры дискретные),
## чтобы у толпы драугров было несколько материалов, а не по копии на каждую поверхность каждого врага.
static func _tinted(src: BaseMaterial3D, tint: Color, glow: Color) -> BaseMaterial3D:
	var key := "%d|%s|%s" % [src.get_instance_id(), tint.to_html(), glow.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var m := src.duplicate() as BaseMaterial3D
	m.albedo_color = m.albedo_color * tint
	if glow.a > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 4.0
	_tint_cache[key] = m
	return m

## Случайный комплект «массовки»: смешиваем части одежды крестьянина и рейнджера, причёски, цвета.
## Возвращает словарь полей для HumanoidModel (или для enemy.gd: model_body, model_outfit="", model_parts...).
static func random_look(rng: RandomNumberGenerator, female: bool = false) -> Dictionary:
	var g := "Female" if female else "Male"
	var pick := func(arr: Array) -> Variant: return arr[rng.randi() % arr.size()]
	var cloth_palette := [Color(0.62, 0.42, 0.28), Color(0.5, 0.25, 0.2), Color(0.32, 0.4, 0.55), Color(0.4, 0.48, 0.3),
		Color(0.55, 0.55, 0.5), Color(0.75, 0.68, 0.55), Color(0.35, 0.3, 0.28), Color(0.6, 0.3, 0.15), Color(0.45, 0.35, 0.5)]
	var skin_palette := [Color(1, 1, 1), Color(0.95, 0.85, 0.78), Color(0.85, 0.7, 0.6), Color(0.7, 0.55, 0.45), Color(1.0, 0.92, 0.88)]
	var outfit_kind := func() -> String: return "Peasant" if rng.randf() < 0.55 else "Ranger"
	var p: PackedStringArray = []
	var t: Array[Color] = []
	p.append("parts/%s_%s_Body.gltf" % [g, outfit_kind.call()]); t.append(pick.call(cloth_palette))
	p.append("parts/%s_%s_Arms.gltf" % [g, outfit_kind.call()]); t.append(pick.call(cloth_palette))
	p.append("parts/%s_%s_Legs.gltf" % [g, outfit_kind.call()]); t.append(pick.call(cloth_palette))
	var feet := "parts/%s_Ranger_Feet%s.gltf" % [g, "_Boots" if not female else ""] if rng.randf() < 0.5 else "parts/%s_Peasant_Feet.gltf" % g
	p.append(feet); t.append(Color(0.6, 0.5, 0.42))
	if rng.randf() < 0.25:
		p.append("parts/%s_Ranger_Acc_Pauldron%s.gltf" % [g, "s" if female else ""]); t.append(Color(0.8, 0.8, 0.85))
	var hood := rng.randf() < 0.2
	if hood:
		p.append("parts/%s_Ranger_Head_Hood.gltf" % g); t.append(pick.call(cloth_palette))
	var hair_opts := ["hair/Hair_Buns.gltf", "hair/Hair_BuzzedFemale.gltf", "hair/Hair_Long.gltf"] if female else \
		["hair/Hair_Buzzed.gltf", "hair/Hair_SimpleParted.gltf", "hair/Hair_Long.gltf", ""]
	var hair_tint: Color = pick.call([Color(0.25, 0.17, 0.1), Color(0.55, 0.38, 0.2), Color(0.85, 0.7, 0.45), Color(0.7, 0.3, 0.12), Color(0.15, 0.13, 0.12)])
	var h: String = "" if hood else pick.call(hair_opts)
	if h != "":
		p.append(h); t.append(hair_tint)
	if not female and rng.randf() < 0.6:
		p.append("hair/Hair_Beard.gltf"); t.append(hair_tint)
	p.append("hair/Eyebrows_%s.gltf" % ("Female" if female else "Regular")); t.append(hair_tint)
	return {
		"body": "base/Superhero_%s_FullBody.gltf" % g,
		"outfit": "",
		"parts": p,
		"part_tints": t,
		"skin_tint": pick.call(skin_palette),
	}

static var _side_cache: Dictionary = {}

## Оставляет одну руку: в позе привязки (T-поза) правая рука лежит при x < 0 (персонаж смотрит в +Z).
static func _side_only(src: Mesh, key: String, which: String, cut_x: float = 0.12) -> Mesh:
	var k := key + "|" + which + "|%.2f" % cut_x
	if _side_cache.has(k):
		return _side_cache[k]
	var out := ArrayMesh.new()
	var sign := -1.0 if which == "right" else 1.0
	for sidx in src.get_surface_count():
		var arrays := src.surface_get_arrays(sidx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if verts[idx[t]].x * sign > cut_x and verts[idx[t + 1]].x * sign > cut_x and verts[idx[t + 2]].x * sign > cut_x:
				keep.append(idx[t])
				keep.append(idx[t + 1])
				keep.append(idx[t + 2])
		if keep.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(sidx))
	_side_cache[k] = out
	return out

## У частей одежды кожа (кисти) — отдельная поверхность с материалом кожи: красим её как кожу.
func _tint_skin_surfaces(m: MeshInstance3D) -> void:
	for sidx in m.mesh.get_surface_count():
		var mat := m.mesh.surface_get_material(sidx)
		if mat and is_skin_material(mat):
			var c := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			c.albedo_color = skin_tint
			m.set_surface_override_material(sidx, c)

static var _head_cache: Dictionary = {}

## Заранее режет меш головы для тела (AssetCache.finish) — иначе это делает первый враг волны.
static func warm_head_mesh(body_path: String) -> void:
	if _head_cache.has(body_path) or not ResourceLoader.exists(BASE_DIR + body_path):
		return
	var base := (load(BASE_DIR + body_path) as PackedScene).instantiate()
	var skel := base.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mi in skel.find_children("*", "MeshInstance3D", false, false):
		if not mi.name.begins_with("Eye"):
			_head_only((mi as MeshInstance3D).mesh, body_path)
			break
	base.free()

## Отрезает от меша тела всё ниже шеи (по позе привязки, 83% роста). Кешируется по пути тела.
static func _head_only(src: Mesh, key: String) -> Mesh:
	if _head_cache.has(key):
		return _head_cache[key]
	if DisplayServer.get_name() == "headless":
		# Без рендеринга данных вершин нет — меш оставляем как есть (тесты, --selftest)
		return src
	var out := ArrayMesh.new()
	for sidx in src.get_surface_count():
		var arrays := src.surface_get_arrays(sidx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ymax := -INF
		for v in verts:
			ymax = maxf(ymax, v.y)
		var cut := ymax * 0.83
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if verts[idx[t]].y >= cut and verts[idx[t + 1]].y >= cut and verts[idx[t + 2]].y >= cut:
				keep.append(idx[t])
				keep.append(idx[t + 1])
				keep.append(idx[t + 2])
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(sidx))
	_head_cache[key] = out
	return out

static func _library(path: String) -> AnimationLibrary:
	if _lib_cache.has(path):
		return _lib_cache[path]
	var lib := AnimationLibrary.new()
	var scene := (load(path) as PackedScene).instantiate()
	var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for lib_name in ap.get_animation_library_list():
		var src := ap.get_animation_library(lib_name)
		for anim_name in src.get_animation_list():
			var a := src.get_animation(anim_name)
			if anim_name.ends_with("_Loop") or anim_name in ["Sword_Idle"]:
				a.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(anim_name, a)
	scene.free()
	_lib_cache[path] = lib
	return lib

## Проиграть анимацию по короткому имени (ищет в обеих библиотеках).
func play(anim_name: String, blend: float = 0.15, speed: float = 1.0) -> bool:
	if anim == null:
		return false
	var full := resolve(anim_name)
	if full == "":
		return false
	if anim.current_animation != full:
		anim.play(full, blend, speed)
	else:
		anim.speed_scale = speed
	return true

## Полное имя анимации ("ual2/Zombie_Idle"). Godot при импорте отрезает суффикс _Loop — ищем оба варианта.
func resolve(anim_name: String) -> String:
	if anim == null:
		return ""
	for key in ANIM_LIBS:
		for n in [anim_name, anim_name.trim_suffix("_Loop")]:
			if anim.has_animation(key + "/" + n):
				return key + "/" + n
	return ""

func has_anim(anim_name: String) -> bool:
	return resolve(anim_name) != ""

func list_anims() -> PackedStringArray:
	return anim.get_animation_list() if anim else PackedStringArray()
