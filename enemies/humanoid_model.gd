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
	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		_tint(mi as MeshInstance3D, skin_tint, mi.name.begins_with("Eye") and eye_glow.a > 0.0)
	if outfit != "":
		_attach(BASE_DIR + outfit, cloth_tint)
		# Тело под одеждой прячем по частям нельзя (один меш), поэтому слегка «сжимаем» его через
		# shrink: оставляем как есть — одежда шире тела и закрывает его.
	if hair != "":
		_attach(BASE_DIR + hair, Color.WHITE)
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
		_tint(m, tint, false)
	part.free()

func _tint(mi: MeshInstance3D, tint: Color, glow: bool) -> void:
	if tint == Color.WHITE and not glow:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		if src is BaseMaterial3D:
			var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			m.albedo_color = m.albedo_color * tint
			if glow:
				m.emission_enabled = true
				m.emission = eye_glow
				m.emission_energy_multiplier = 4.0
			mi.set_surface_override_material(s, m)

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
