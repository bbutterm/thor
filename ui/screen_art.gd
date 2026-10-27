extends RefCounted
class_name ScreenArt
## Иллюстрации владельца для экранов (комплект docs/world_art): портреты тел, фоны окна новеллы,
## заставки боссов, «страница комикса», загрузочные экраны, сюжетные кадры. Пути, сопоставления, кеш.
##
## Фризы: боевые картинки (заставки Свена и Ярла, кадры смерти, загрузки) держит AssetCache
## (DIRS/FILES) — они уже в памяти к первому залу. Экраны между забегами (тела, фоны, сюжет) просят
## prefetch() заранее (фоновая загрузка в меню, на «странице комикса» после смерти); tex() отдаёт
## готовое и держит ссылку, чтобы картинка не выгружалась и не читалась с диска снова.

const BODIES := "res://sprites/bodies/"
const BACKGROUNDS := "res://sprites/backgrounds/"
const BOSS_CARDS := "res://sprites/boss_cards/"
const DEATH := "res://sprites/death/"
const LOADING := "res://sprites/loading/"
const STORY := "res://sprites/story/"
const FRAME := "res://sprites/death/frame.webp"
const LOADING_COUNT := 8

## Фон окна новеллы (DialogueBox.open, поле сцены "backdrop"): короткое имя → sprites/backgrounds/<файл>.webp.
## Можно писать и сразу имя файла ("dwarf_shop"). "run" — фон текущего мира (WORLD_BACKDROPS), "none" — без картинки.
const BACKDROPS := {
	"couch": "couch_room", "shop": "dwarf_shop", "midgard": "midgard_village", "bifrost": "bifrost_gate",
	"helheim": "hel_throne", "jotunheim": "jotunheim", "yggdrasil": "yggdrasil_top",
}
## Мир забега (RunMap.world_id) → фон сцен, которые играются прямо в забеге
const WORLD_BACKDROPS := {"midgard": "midgard_village", "jotunheim": "jotunheim", "helheim": "hel_throne", "asgard": "yggdrasil_top"}
## Боссы со своей заставкой: death_source_id врага → id (пулы <id>.*, odin.page_boss_<id>) и картинка
## sprites/boss_cards/<card>.webp. Остальные карточки (garm, hel, hrungnir, ice_troll, odin) — на будущее.
const BOSSES := {
	"miniboss_sven": {"id": "sven", "card": "fat_sven", "miniboss": true},
	"boss_jarl": {"id": "jarl", "card": "jarl_bjorn", "miniboss": false},
}
## Причина смерти Тора (RunTracker.cause_of) → иллюстрация sprites/death/<файл>.webp и пул odin.page_<файл>.
## "ranged" — убил метатель или Тор умер с ренжем в руках (метка ranged); неизвестное — драугр.
const DEATH_ART := {"barrel": "barrel", "boss": "boss", "draugr": "draugr", "fall": "fall", "own_fire": "fire", "ranged": "ranged"}
## Кто стреляет издалека: смерть от них — картинка «ranged»
const RANGED_KILLERS := ["draugr_thrower"]

## Паузящие вставки (заставка босса, стоп-кадр комикса) в тестах выключены — как сцены в забеге
## (Dialogue.in_run_scenes): тесты считают кадры. art_screens_test включает их сам.
static var pauses_in_tests: bool = false

static var _cache: Dictionary = {}
static var _requested: Dictionary = {}

# --- Текстуры ---

## Текстура по пути (null — нет файла). Запрошенная prefetch() — дожидается фоновой загрузки.
static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D
	if _requested.has(path):
		_requested.erase(path)
		t = ResourceLoader.load_threaded_get(path) as Texture2D
	if t == null:
		t = load(path) as Texture2D
	_cache[path] = t
	return t

## Фоновая загрузка заранее (экран откроется позже — не читаем картинку с диска в момент показа).
static func prefetch(paths: Array) -> void:
	for p in paths:
		var path := str(p)
		if path == "" or _cache.has(path) or _requested.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.has_cached(path):
			_cache[path] = load(path)
			continue
		if ResourceLoader.load_threaded_request(path, "", false) == OK:
			_requested[path] = true

## Всё для экранов между забегами: фоны дивана и меню, портреты тел. Из главного меню и после смерти.
static func prefetch_between_runs() -> void:
	var paths: Array = [backdrop_path("couch"), backdrop_path("midgard"), BODIES + "locked.webp"]
	for b in Run.all_bodies:
		paths.append(body_path(b.id))
	prefetch(paths)

## Выход из игры: дождаться фоновых загрузок (иначе поток читает файл, пока движок выгружается).
static func shutdown() -> void:
	for p in _requested:
		ResourceLoader.load_threaded_get(p)
	_requested.clear()
	_cache.clear()

# --- Тела ---

static func body_path(id: String) -> String:
	return BODIES + id + ".webp"

## Портрет тела во весь рост (2:3). Закрытое — силуэт с замком (locked.webp). Нет картинки — null.
static func body_portrait(id: String, locked: bool = false) -> Texture2D:
	if locked:
		return tex(BODIES + "locked.webp")
	return tex(body_path(id))

## Голова и плечи из портрета (квадрат сверху) — значок на карточке тела.
static func body_thumb(id: String, locked: bool = false) -> Texture2D:
	var full := body_portrait(id, locked)
	if full == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = full
	var s := full.get_size()
	var side := s.x * 0.62
	at.region = Rect2((s.x - side) * 0.5, s.y * 0.015, side, side)
	return at

# --- Фоны новеллы ---

## Путь фона по backdrop ("" — без картинки).
static func backdrop_path(backdrop: String) -> String:
	var key := backdrop
	if key == "run":
		var world := Run.map.world_id if Run.map else "midgard"
		key = str(WORLD_BACKDROPS.get(world, "midgard_village"))
	if key == "" or key == "none":
		return ""
	var file := str(BACKDROPS.get(key, key))
	var path := BACKGROUNDS + file + ".webp"
	return path if ResourceLoader.exists(path) else ""

static func backdrop(backdrop_id: String) -> Texture2D:
	return tex(backdrop_path(backdrop_id))

# --- Сюжетные кадры ---

## Кадр sprites/story/<id>.webp ("" — нет такого)
static func story_path(id: String) -> String:
	if id == "" or id == "none":
		return ""
	var path := STORY + id + ".webp"
	return path if ResourceLoader.exists(path) else ""

static func story(id: String) -> Texture2D:
	return tex(story_path(id))

# --- Боссы ---

## {id, card, miniboss} для врага со своей заставкой, иначе {}.
static func boss_info(enemy: Node) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy):
		return {}
	var src := str(enemy.get_meta("death_source_id", ""))
	return BOSSES.get(src, {})

static func boss_card_path(card: String) -> String:
	return BOSS_CARDS + card + ".webp"

# --- Смерть Тора ---

## Ключ иллюстрации и пула подписи (barrel, boss, draugr, fall, fire, ranged) по итогу забега (RunTracker.result).
static func death_key(result: Dictionary) -> String:
	var cause := str(result.get("cause", ""))
	var by := str(result.get("killed_by", ""))
	if by in RANGED_KILLERS or (cause == "draugr" and "ranged" in (result.get("tags", []) as Array)):
		return "ranged"
	return str(DEATH_ART.get(cause, "draugr"))

static func death_art(key: String) -> Texture2D:
	return tex(DEATH + key + ".webp")

# --- Загрузка ---

static func loading_path(i: int) -> String:
	return LOADING + "%d.webp" % (posmod(i, LOADING_COUNT) + 1)

# --- Выключатели ---

static func pauses_allowed() -> bool:
	return pauses_in_tests or not GameSettings._is_test()

## Стоп-кадр «страница комикса» при смерти Тора и босса (настройка [comic] page)
static func page_enabled() -> bool:
	return pauses_allowed() and bool(GameSettings.get_value("comic", "page"))

## Заставка босса при появлении (настройка [comic] boss_card)
static func boss_card_enabled() -> bool:
	return pauses_allowed() and bool(GameSettings.get_value("comic", "boss_card"))
