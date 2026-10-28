extends Node
class_name DialogueManager
## Автозагрузка «Dialogue» — диалоги-новелла (как в Hades) и короткие реплики-пузыри.
## Данные: data/dialogues/*.json, по файлу на персонажа (формат — в STORY.md, раздел «Формат данных»).
##
## Сцена (scene): id, trigger, priority, conditions[], lines[]; сюжетные сцены не повторяются (Save.seen),
##   "repeat": true — может повторяться.
## Пул (pools): короткие реплики, повторяются. Ключ пула — "<id файла>.<имя>", например "odin.death_fall".
## Реплика: id, speaker, emotion, text, необязательно choices[2] (ответ Тора: огрызнуться / согласиться),
##   "voice": клип озвучки sounds/voice/<id>.ogg (или массив дублей — случайный; что в клипе — data/owner_audio.json),
##   "sfx": звук владельца при показе (например "coach_whistle"). Голос — русский на любом языке.
##   {"pool": "odin.run_start"} внутри сцены — подставить случайную реплику из пула; "$reaction" — реакцию на смерть.
## Выбор диалога: самая приоритетная непросмотренная сцена события с выполненными условиями,
## иначе — случайная реплика из пула.
## Перевод (scripts/i18n.gd): data/dialogues/<язык>/<файл>.json — {"speakers": {id: {"en": имя}},
##   "lines": {id реплики: {"ru": оригинал, "en": перевод}}}; ответ Тора — ключ «<id реплики>/<id выбора>».
##   Нет перевода — русский. Подставляется при показе (pool_lines / expand / bark); шаблоны —
##   tools/i18n_dialogues.py. Подписи выборов («Огрызнуться») — через tr (data/i18n/en.po).

signal scene_started(scene_id: String)
signal scene_finished(scene_id: String)

const DIR := "res://data/dialogues/"
## Куда смотреть за переводом: DIR + <язык> + "/" + <файл>.json
const EMOTIONS := ["neutral", "happy", "angry", "shocked", "smug", "embarrassed"]
const OPS := ["==", "!=", ">=", "<=", ">", "<"]
## Флаги без значения
const FLAGS := ["first_time", "won", "lost"]
## События, у которых бывает сцена
const TRIGGERS := ["run_start", "death", "victory", "boss_intro", "boss_defeat", "plan_open", "plan_buy",
	"shop_enter", "shop_buy", "shop_broke", "shop_low_hp", "shop_rich", "shop_cursed", "challenge", "meet"]

## Вероятность, что после реакции Одина на смерть Тор ответит (с выбором «огрызнуться / согласиться»)
@export var thor_reply_chance: float = 0.4
## Вероятность, что к дивану заглянет знакомый персонаж (пулы *.visit, после его сцены знакомства)
@export var visitor_chance: float = 0.3
## Вероятность реплики Хеймдалля на старте забега (после знакомства с ним)
@export var heimdall_chance: float = 0.35
## Шанс, что Один отреагирует на смерть тела (пул odin.death_body_<тело>), а не на причину смерти
@export var body_death_chance: float = 0.35

var speakers: Dictionary = {}
var scenes: Array[Dictionary] = []
var pools: Dictionary = {}
var load_errors: Array[String] = []
## Журнал прочитанного за сессию: [{speaker, text}]
var history: Array[Dictionary] = []
@export var history_limit: int = 300
## Можно ли показывать паузящие сцены прямо в забеге (старт, босс). Тесты выключают.
var in_run_scenes: bool = true

var _box: DialogueBox
var _bubble: BarkBubble
var _last_pick: Dictionary = {}
var _playing: bool = false
var _extra_ctx: Dictionary = {}
## Перевод текущего языка: id реплики → текст; id говорящего → имя. Русские имена — _ru_names.
var _loc_lines: Dictionary = {}
var _loc_names: Dictionary = {}
var _ru_names: Dictionary = {}
var _loc_locale: String = ""

## Компоненты (этап 5 рефакторинга): логика по файлам scripts/dialogue/dialogue_*.gd, состояние — поля выше.
var locale: DialogueLocale
var conditions: DialogueConditions
var validator: DialogueValidator

func _init() -> void:
	locale = DialogueLocale.new(self)
	conditions = DialogueConditions.new(self)
	validator = DialogueValidator.new(self)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			in_run_scenes = false
	load_all()
	GameSettings.events.changed.connect(func(section: String, key: String) -> void:
		if section == "text" and key == "language":
			locale.refresh_locale())

# --- Загрузка ---

func load_all() -> void:
	speakers.clear()
	scenes.clear()
	pools.clear()
	load_errors.clear()
	var files: Array = []
	var d := DirAccess.open(DIR)
	if d:
		files = Array(d.get_files())
	if files.is_empty():
		files = Array(ResourceLoader.list_directory(DIR))
	files.sort()
	for f in files:
		if str(f).get_extension() == "json":
			_load_file(DIR + str(f))
	_ru_names.clear()
	for k in speakers:
		_ru_names[k] = {"name": speakers[k].get("name", k), "initial": speakers[k].get("initial", "")}
	_loc_locale = ""
	locale.refresh_locale()

# --- Перевод ---

func _load_file(p: String) -> void:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		load_errors.append("%s: не открыть" % p)
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		load_errors.append("%s:%d: %s" % [p, json.get_error_line(), json.get_error_message()])
		return
	var d: Variant = json.data
	if not d is Dictionary:
		load_errors.append("%s: корень не объект" % p)
		return
	var file_id: String = str(d.get("id", p.get_file().get_basename()))
	var sp: Dictionary = d.get("speakers", {})
	for k in sp:
		speakers[k] = sp[k]
	for s in d.get("scenes", []):
		if s is Dictionary:
			var sc: Dictionary = s
			sc["_file"] = file_id
			sc["_conds"] = _parse_all(sc.get("conditions", []), "%s/%s" % [file_id, sc.get("id", "?")])
			scenes.append(sc)
	var pl: Dictionary = d.get("pools", {})
	for k in pl:
		var items: Array = []
		for it in pl[k]:
			var item: Dictionary = it if it is Dictionary else {"text": str(it)}
			if not item.has("lines"):
				item = {"lines": [item], "conditions": item.get("conditions", [])}
			item["_conds"] = _parse_all(item.get("conditions", []), "%s.%s" % [file_id, k])
			items.append(item)
		pools["%s.%s" % [file_id, k]] = items

func _parse_all(conds: Array, where: String) -> Array:
	var out: Array = []
	for c in conds:
		var parsed := conditions.parse_condition(str(c))
		if not parsed.ok:
			load_errors.append("%s: условие «%s» — %s" % [where, c, parsed.error])
		out.append(parsed)
	return out

# --- Условия ---

# --- Выбор ---

## Самая приоритетная непросмотренная сцена события с выполненными условиями (или {}).
func pick_scene(trigger: String) -> Dictionary:
	var ctx := conditions.context(trigger)
	var best: Array[Dictionary] = []
	var best_pri := -INF
	for sc in scenes:
		if sc.get("trigger", "") != trigger:
			continue
		if not sc.get("repeat", false) and Save.is_seen(str(sc.get("id", ""))):
			continue
		if not conditions.check(sc._conds, ctx):
			continue
		var pri := float(sc.get("priority", 0))
		if pri > best_pri:
			best_pri = pri
			best = [sc]
		elif pri == best_pri:
			best.append(sc)
	if best.is_empty():
		return {}
	return best[randi() % best.size()]

## Случайная реплика(и) из пула с учётом условий, без повтора подряд. Пусто, если пула нет.
func pool_lines(pool: String) -> Array:
	var items: Array = pools.get(pool, [])
	if items.is_empty():
		return []
	var ctx := conditions.context()
	var ok: Array = []
	for it in items:
		if conditions.check(it._conds, ctx):
			ok.append(it)
	if ok.is_empty():
		return []
	var idx := randi() % ok.size()
	if ok.size() > 1 and _last_pick.get(pool, -1) == items.find(ok[idx]):
		idx = (idx + 1) % ok.size()
	_last_pick[pool] = items.find(ok[idx])
	var out: Array = (ok[idx].lines as Array).duplicate(true)
	for l in out:
		if l is Dictionary:
			locale.localize_line(l)
	return out

func has_pool(pool: String) -> bool:
	return not pools.get(pool, []).is_empty()

## Первая реплика пула как текст (для пузыря), с подстановкой {deaths} и т. п.
func pool_text(pool: String) -> String:
	var lines := pool_lines(pool)
	return format_text(str(lines[0].get("text", ""))) if not lines.is_empty() else ""

func format_text(t: String) -> String:
	if t.find("{") < 0:
		return t
	var ctx := conditions.context()
	ctx["deaths_next"] = int(ctx.get("deaths", 0)) + 1
	ctx["time"] = _fmt_time(float(ctx.get("last_run_time", 0.0)))
	return t.format(ctx)

static func _fmt_time(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]

## Пул реакции Одина на итог забега: причина и метки из Save.last_run.
func reaction_pool(won: bool) -> String:
	if won:
		return "odin.victory_reaction"
	var lr: Dictionary = Save.data.get("last_run", {})
	var tags: Array = lr.get("tags", [])
	var cause := str(lr.get("cause", ""))
	var order: Array = []
	if "quick" in tags:
		order.append("quick")
	if cause in ["fall", "own_fire", "barrel"]:
		order.append(cause)
	if "ranged" in tags:
		order.append("ranged")
	if cause == "boss":
		order.append("boss")
	if "long" in tags:
		order.append("long")
	if cause != "":
		order.append(cause)
	# Реакция на смерть тела (блок Л) — иногда, если нет «особой» причины (быстро, упал, огонь, бочка)
	var body_id := str(lr.get("body", ""))
	if body_id != "" and has_pool("odin.death_body_" + body_id) and randf() < body_death_chance \
			and not ("quick" in tags or cause in ["fall", "own_fire", "barrel"]):
		return "odin.death_body_" + body_id
	for c in order:
		if has_pool("odin.death_" + c):
			return "odin.death_" + c
	return "odin.death"

# --- Показ ---

func box() -> DialogueBox:
	if _box == null or not is_instance_valid(_box):
		_box = DialogueBox.new()
		_box.name = "DialogueBox"
		get_tree().root.add_child(_box)
		_box.choice_made.connect(_on_choice_made)
		_box.line_shown.connect(_on_line_shown)
	return _box

func bubble() -> BarkBubble:
	if _bubble == null or not is_instance_valid(_bubble):
		_bubble = BarkBubble.new()
		_bubble.name = "BarkBubble"
		get_tree().root.add_child(_bubble)
	return _bubble

func is_playing() -> bool:
	return _playing

## Раскрывает {"pool": ...} и подставляет переменные.
func expand(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		if not l is Dictionary:
			continue
		if l.has("pool"):
			var pool := str(l.pool)
			if pool == "$reaction":
				pool = reaction_pool(bool(Save.data.get("last_run", {}).get("won", false)))
			out.append_array(expand(pool_lines(pool)))
			continue
		var line: Dictionary = locale.localize_line(l.duplicate(true))
		line["text"] = format_text(str(line.get("text", "")))
		for ch in line.get("choices", []):
			ch["text"] = format_text(str(ch.get("text", "")))
			ch["lines"] = expand(ch.get("lines", []))
		out.append(line)
	return out

## Показывает реплики новеллой и ждёт конца. backdrop: "run" (фон мира забега), "couch" (между забегами),
## "shop" или картинка из sprites/backgrounds/ (ScreenArt). image — сюжетный кадр с первой реплики.
func play_lines(lines: Array, scene_id: String = "", backdrop: String = "run", image: String = "") -> void:
	var expanded := expand(lines)
	if expanded.is_empty():
		return
	# Сюжетные кадры сцены — в фоне заранее: первый дождёмся, остальные догрузятся, пока печатается текст
	var pics: Array = [ScreenArt.story_path(image)]
	for l in expanded:
		if l is Dictionary and l.has("image"):
			pics.append(ScreenArt.story_path(str(l.image)))
	ScreenArt.prefetch(pics)
	var was_paused := get_tree().paused
	var mouse := Input.mouse_mode
	_playing = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene_started.emit(scene_id)
	var b := box()
	b.open(expanded, scene_id, backdrop, image)
	await b.finished
	_playing = false
	get_tree().paused = was_paused
	Input.mouse_mode = mouse
	scene_finished.emit(scene_id)

## Поля сцены: "backdrop" — свой фон (важнее переданного), "image" — сюжетный кадр с первой реплики.
func play_scene(sc: Dictionary, backdrop: String = "run") -> void:
	var id := str(sc.get("id", ""))
	Save.mark_seen(id)
	await play_lines(sc.get("lines", []), id, str(sc.get("backdrop", backdrop)), str(sc.get("image", "")))
	Save.save_game()

## Событие: сцена (если есть) или реплика пула. bubble_fallback — реплику пула показать пузырём без паузы.
## Возвращает true, если была показана сцена-новелла.
func run_trigger(trigger: String, fallback_pool: String = "", bubble_fallback: bool = true, backdrop: String = "run") -> bool:
	Save.bump_event(trigger)
	var sc := pick_scene(trigger)
	if not sc.is_empty():
		await play_scene(sc, backdrop)
		return true
	if fallback_pool != "":
		if bubble_fallback:
			bark_pool(fallback_pool)
		else:
			await play_lines(pool_lines(fallback_pool), "", backdrop)
	return false

## Реплика-пузырь без паузы. Один — через HUD (Odin.line_spoken), остальные — в углу экрана.
## Реплику из pool_lines уже перевели — повторно не трогаем (обучение подставило в неё клавиши).
func bark(line: Dictionary) -> void:
	var text := format_text(str(line.get("text", "")))
	if text == "":
		return
	var sp := str(line.get("speaker", "odin"))
	_on_line_shown(line, Audio.VOICE_BARK)
	if sp == "odin":
		Odin.line_spoken.emit(text)
	else:
		bubble().show_line(sp, str(line.get("emotion", "neutral")), text)

## Тор хвастается пузырём (пулы thor.<событие>): с шансом и своим кулдауном, чтобы не болтал без умолку.
@export var thor_bark_cooldown: float = 18.0
var _thor_next_bark: float = 0.0

func thor_bark(event: String, chance: float = 0.45) -> void:
	var pool := "thor." + event
	if not has_pool(pool):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _thor_next_bark or randf() > chance:
		return
	_thor_next_bark = now + thor_bark_cooldown
	bark_pool(pool)

func bark_pool(pool: String) -> void:
	var lines := pool_lines(pool)
	if not lines.is_empty():
		bark(lines[0])

func _on_choice_made(scene_id: String, choice_id: String) -> void:
	if scene_id != "":
		Save.set_choice(scene_id, choice_id)
	var key := "choice_" + choice_id
	Save.data.events[key] = int(Save.data.events.get(key, 0)) + 1

## Озвучка реплики при показе: голос на шине Voice и звук реплики. priority: Audio.VOICE_SCENE — окно новеллы
## (следующая реплика перебивает голос), Audio.VOICE_BARK — пузырь/Odin.say (пока звучит другой голос — без озвучки).
func speak_line(line: Dictionary, priority: int = Audio.VOICE_SCENE) -> void:
	if line.has("sfx"):
		Audio.sfx(str(line.sfx))
	if line.has("voice"):
		Audio.voice(line.voice, priority)

func _on_line_shown(line: Dictionary, voice_priority: int = Audio.VOICE_SCENE) -> void:
	speak_line(line, voice_priority)
	history.append({"speaker": str(line.get("speaker", "")), "text": str(line.get("text", ""))})
	if history.size() > history_limit:
		history = history.slice(history.size() - history_limit)

# --- Точки входа из игры ---

## Старт забега. Сцена (на паузе) — если есть и разрешены сцены в забеге; иначе пузырь Одина.
func on_run_start(body_id: String) -> void:
	Save.bump_event("run_start")
	if in_run_scenes:
		var sc := pick_scene("run_start")
		if not sc.is_empty():
			play_scene(sc, "couch")
			return
	if randf() < heimdall_chance:
		bark_pool("heimdall.run_start")
	if body_id != "" and randf() < 0.5 and has_pool("odin.run_start_" + body_id):
		Odin.say("run_start_" + body_id)
	else:
		Odin.say("run_start")

## Вход в зал босса: сцена знакомства в первый раз, потом — интро-пузырь босса.
func on_boss_intro(boss_id: String = "jarl") -> bool:
	_extra_ctx["boss"] = boss_id
	Save.bump_event("boss_intro")
	if in_run_scenes:
		var sc := pick_scene("boss_intro")
		if not sc.is_empty():
			play_scene(sc)
			return true
	bark_pool(boss_id + ".intro")
	return false

## Босс побеждён — фраза поражения пузырём.
func on_boss_defeat(boss_id: String = "jarl") -> void:
	Save.bump_event("boss_defeat")
	bark_pool(boss_id + ".defeat")

## Между забегами: реакция на смерть/победу (сцена или пул + ответ Тора). Ждёт конца.
func after_run(won: bool) -> void:
	var trigger := "victory" if won else "death"
	Save.bump_event(trigger)
	var sc := pick_scene(trigger)
	if not sc.is_empty():
		await play_scene(sc, "couch")
		return
	var lines := pool_lines(reaction_pool(won))
	if not won and randf() < thor_reply_chance:
		lines.append_array(pool_lines("thor.reply_death"))
	if randf() < visitor_chance:
		lines.append_array(visitor_lines())
	await play_lines(lines, "", "couch")
	Save.save_game()

## Короткий визит знакомого персонажа: случайный пул *.visit, у которого выполнены условия.
func visitor_lines() -> Array:
	var keys: Array = []
	var ctx := conditions.context()
	for k in pools:
		if str(k).ends_with(".visit"):
			for it in pools[k]:
				if conditions.check(it._conds, ctx):
					keys.append(k)
					break
	if keys.is_empty():
		return []
	return pool_lines(keys[randi() % keys.size()])

# --- Проверка данных (тест) ---

# --- Функции компонентов, доступные на DialogueManager ---
# API (## API →) и приватные функции, которые зовут другие файлы (## совместимость →).
# Реализация и описание — в компоненте.

# DialogueLocale (dialogue_locale.gd)

## API → locale.refresh_locale
func refresh_locale() -> void:
	locale.refresh_locale()

## API → locale.has_translation
func has_translation(line_id: String) -> bool:
	return locale.has_translation(line_id)

## API → locale.localize_line
func localize_line(line: Dictionary) -> Dictionary:
	return locale.localize_line(line)

# DialogueConditions (dialogue_conditions.gd)

## API → conditions.parse_condition
func parse_condition(s: String) -> Dictionary:
	return conditions.parse_condition(s)

## API → conditions.context
func context(trigger: String = "") -> Dictionary:
	return conditions.context(trigger)

## API → conditions.check
func check(conds: Array, ctx: Dictionary) -> bool:
	return conditions.check(conds, ctx)

# DialogueValidator (dialogue_validator.gd)

## API → validator.validate
func validate() -> Array[String]:
	return validator.validate()
