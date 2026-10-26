extends RefCounted
class_name AssetCache
## Предзагрузка тяжёлых ресурсов (персонажи Quaternius, анимации, оружие, звуки, сцены врагов) в фоне
## и удержание ссылок на них. Без удержания Godot выгружает PackedScene, как только враг собран,
## и следующий load() снова читает файл с диска — это давало фризы при спавне волн.
## start() — из главного меню (фоновые потоки), finish() — перед первым залом (дожидается и прогревает кеши).

const DIRS := [
	"res://assets/quaternius/characters/base/",
	"res://assets/quaternius/characters/hair/",
	"res://assets/quaternius/characters/outfits/",
	"res://assets/quaternius/characters/parts/",
	"res://assets/quaternius/weapons/",
	"res://assets/quaternius/guns/",
	"res://assets/quaternius/props/",
	"res://weapons/defs/",
	"res://sounds/sfx/",
	"res://sounds/",
]
const FILES := [
	"res://assets/quaternius/characters/gaits.glb",
	"res://assets/quaternius/characters/animations.glb",
	"res://enemies/grunt.tscn",
	"res://enemies/thrower.tscn",
	"res://enemies/boss.tscn",
	"res://enemies/fodder.tscn",
	"res://enemies/bloated.tscn",
	"res://enemies/shieldbearer.tscn",
	"res://enemies/shaman.tscn",
	"res://enemies/merc.tscn",
]
const EXTS := ["gltf", "glb", "fbx", "wav", "ogg", "tscn", "tres"]

static var _held: Dictionary = {}
static var _pending: PackedStringArray = []
static var _started: bool = false
static var _finished: bool = false

## Все пути, которые держим в памяти.
static func paths() -> PackedStringArray:
	var out := PackedStringArray(FILES)
	for d in DIRS:
		for f in ResourceLoader.list_directory(d):
			if f.get_extension() in EXTS:
				out.append(d + f)
	return out

## Запускает фоновую загрузку. Можно вызывать много раз — повторно не грузит.
static func start() -> void:
	if _started:
		return
	_started = true
	for p in paths():
		if _held.has(p):
			continue
		if ResourceLoader.has_cached(p):
			_held[p] = load(p)
			continue
		if ResourceLoader.load_threaded_request(p, "", true) == OK:
			_pending.append(p)

## Доля загруженного (0..1) — для экрана загрузки.
static func progress() -> float:
	if not _started:
		return 0.0
	var total := _pending.size() + _held.size()
	if total == 0:
		return 1.0
	var done := _held.size()
	for p in _pending:
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_LOADED:
			done += 1
	return float(done) / total

## Дожидается загрузки всего и прогревает кеши HumanoidModel (анимации, обрезанные меши).
static func finish() -> void:
	start()
	if _finished:
		return
	var t0 := Time.get_ticks_msec()
	for p in _pending:
		var res := ResourceLoader.load_threaded_get(p)
		if res:
			_held[p] = res
	_pending.clear()
	for key in HumanoidModel.ANIM_LIBS:
		HumanoidModel._library(HumanoidModel.ANIM_LIBS[key])
	for body in ["base/Superhero_Male_FullBody.gltf", "base/Superhero_Female_FullBody.gltf"]:
		HumanoidModel.warm_head_mesh(body)
	_finished = true
	print("AssetCache: %d ресурсов, %d мс" % [_held.size(), Time.get_ticks_msec() - t0])

static func is_finished() -> bool:
	return _finished
