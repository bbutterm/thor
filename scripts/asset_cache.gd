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
	"res://assets/painted/rpg_items/",
	"res://assets/mjolnir/",
	"res://assets/quaternius/guns/",
	"res://assets/quaternius/props/",
	"res://weapons/defs/",
	"res://sounds/sfx/",
	"res://sounds/",
	# Звук владельца (блок Б6): эффекты и голос (музыку держит сам Music)
	"res://sounds/owner/sfx/",
	"res://sounds/voice/",
	"res://sprites/vfx/",
	# UI-скин: карточки рун/трейтов, панели, кнопки, иконки — первое открытие выбора руны читало их с диска
	# посреди забега (~30 мс CPU, с рендером — ещё загрузка в видеопамять)
	"res://sprites/ui/panels/",
	"res://sprites/ui/buttons/",
	"res://sprites/ui/hud/",
	"res://sprites/ui/icons/",
	# Экраны в забеге (ui/screen_art.gd): загрузки между залами и «страница комикса» при смерти
	"res://sprites/loading/",
	"res://sprites/death/",
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
	"res://enemies/sven.tscn",
	"res://enemies/jarl.tscn",
	# Заставки боссов забега (ui/boss_card.gd); остальные карточки — на будущее, не держим
	"res://sprites/boss_cards/fat_sven.webp",
	"res://sprites/boss_cards/jarl_bjorn.webp",
	# Разрушаемые пропсы (props/destructible.gd)
	"res://props/barrel.tscn",
	"res://props/crate.tscn",
	"res://props/barrel_explosive.tscn",
	"res://props/destruct_tuning.tres",
]
const EXTS := ["gltf", "glb", "fbx", "wav", "ogg", "tscn", "tres", "webp"]

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
	# Графика мира: декор, декали, частицы и небо текущего мира (scripts/world_art.gd) — только используемые
	# (листы-заготовки и другие миры в памяти не держим)
	for p in WorldArt.preload_paths(Run.map):
		if not p in out:
			out.append(p)
	return out

## Запускает фоновую загрузку. Можно вызывать много раз — повторно не грузит.
static func start() -> void:
	if _started:
		return
	_started = true
	# «-- … sync_load»: грузить сразу в главном потоке. Для замеров Forward+ на программном Vulkan (lavapipe):
	# там фоновая загрузка с компиляцией шейдеров в потоках намертво зависает в драйвере на старте.
	var sync := "sync_load" in OS.get_cmdline_user_args()
	for p in paths():
		if _held.has(p):
			continue
		if sync or ResourceLoader.has_cached(p):
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

## Выход из игры: дождаться фоновых загрузок (иначе поток читает сцену, пока движок уже выгружает
## скрипты, — «Parse Error … sven.tscn» при быстром выходе) и отпустить удержанное.
static func shutdown() -> void:
	for p in _pending:
		ResourceLoader.load_threaded_get(p)
	_pending.clear()
	_held.clear()

static func is_finished() -> bool:
	return _finished
