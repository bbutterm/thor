extends Node
## Автозагрузка «Dialogue» — диалоги-новелла (как в Hades) и короткие реплики-пузыри.
## Данные: data/dialogues/*.json, по файлу на персонажа (формат — в STORY.md, раздел «Формат данных»).
##
## Сцена (scene): id, trigger, priority, conditions[], lines[]; сюжетные сцены не повторяются (Save.seen),
##   "repeat": true — может повторяться.
## Пул (pools): короткие реплики, повторяются. Ключ пула — "<id файла>.<имя>", например "odin.death_fall".
## Реплика: id, speaker, emotion, text, необязательно choices[2] (ответ Тора: огрызнуться / согласиться).
##   {"pool": "odin.run_start"} внутри сцены — подставить случайную реплику из пула; "$reaction" — реакцию на смерть.
## Выбор диалога: самая приоритетная непросмотренная сцена события с выполненными условиями,
## иначе — случайная реплика из пула.

signal scene_started(scene_id: String)
signal scene_finished(scene_id: String)

const DIR := "res://data/dialogues/"
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			in_run_scenes = false
	load_all()

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
		var parsed := parse_condition(str(c))
		if not parsed.ok:
			load_errors.append("%s: условие «%s» — %s" % [where, c, parsed.error])
		out.append(parsed)
	return out

# --- Условия ---

## Разбирает условие: "deaths >= 3", "killed_by == boss_jarl", "first_time", "!seen:odin_intro",
## "has_unlock:boomerang", "tag:quick", "choice:odin_intro == snap", "deaths_by.fall >= 2", "random < 0.3".
func parse_condition(s: String) -> Dictionary:
	var src := s.strip_edges()
	if src == "":
		return {"ok": false, "error": "пустое условие"}
	var neg := false
	if src.begins_with("!"):
		neg = true
		src = src.substr(1).strip_edges()
	for op in OPS:
		var i := src.find(op)
		if i > 0:
			var lhs := src.substr(0, i).strip_edges()
			var rhs := src.substr(i + op.length()).strip_edges()
			if lhs == "" or (rhs != "" and rhs[0] in ["=", "<", ">", "!"]):
				if rhs.begins_with("="):
					continue
				return {"ok": false, "error": "лишний оператор"}
			if rhs.begins_with("\"") and rhs.ends_with("\"") and rhs.length() >= 2:
				rhs = rhs.substr(1, rhs.length() - 2)
			if rhs == "":
				return {"ok": false, "error": "нет значения справа"}
			if not _is_var_name(lhs):
				return {"ok": false, "error": "непонятная переменная «%s»" % lhs}
			return {"ok": true, "kind": "cmp", "var": lhs, "op": op, "value": rhs, "neg": neg}
	if src in FLAGS:
		return {"ok": true, "kind": "flag", "var": src, "neg": neg}
	var colon := src.find(":")
	if colon > 0:
		var fn := src.substr(0, colon)
		var arg := src.substr(colon + 1).strip_edges()
		if fn in ["seen", "has_unlock", "tag", "event"] and arg != "":
			return {"ok": true, "kind": fn, "arg": arg, "neg": neg}
	return {"ok": false, "error": "не разобрать"}

func _is_var_name(v: String) -> bool:
	var re := RegEx.create_from_string("^[a-z_][a-z0-9_]*([.:][a-z0-9_]+)?$")
	return re.search(v) != null

func context(trigger: String = "") -> Dictionary:
	var ctx := Save.context()
	ctx["trigger"] = trigger
	ctx["event_count"] = Save.event_count(trigger) if trigger != "" else 0
	for k in _extra_ctx:
		ctx[k] = _extra_ctx[k]
	return ctx

func check(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if not _check_one(c, ctx):
			return false
	return true

func _check_one(c: Dictionary, ctx: Dictionary) -> bool:
	if not c.get("ok", false):
		return false
	var res := false
	match c.kind:
		"flag":
			match c.var:
				"first_time":
					res = int(ctx.get("event_count", 0)) <= 1
				"won":
					res = bool(ctx.get("last_won", false))
				"lost":
					res = not bool(ctx.get("last_won", false))
		"seen":
			res = Save.is_seen(c.arg)
		"has_unlock":
			res = Save.has_method("is_unlocked") and Save.call("is_unlocked", c.arg)
		"tag":
			res = c.arg in Save.data.get("last_run", {}).get("tags", [])
		"event":
			res = Save.event_count(c.arg) > 0
		"cmp":
			res = _compare(_resolve(c.var, ctx), c.op, c.value)
	return res != c.neg

func _resolve(v: String, ctx: Dictionary) -> Variant:
	if v == "random":
		return randf()
	if v.begins_with("deaths_by."):
		return Save.deaths_by(v.substr(10))
	if v.begins_with("killed_by_count."):
		return Save.killed_by_count(v.substr(16))
	if v.begins_with("event."):
		return Save.event_count(v.substr(6))
	if v.begins_with("choice:") or v.begins_with("choice."):
		return Save.get_choice(v.substr(7))
	return ctx.get(v, null)

func _compare(a: Variant, op: String, raw: String) -> bool:
	if a == null:
		a = 0 if raw.is_valid_float() else ""
	if (a is int or a is float or a is bool) and raw.is_valid_float():
		var x := float(a)
		var y := raw.to_float()
		match op:
			"==": return is_equal_approx(x, y)
			"!=": return not is_equal_approx(x, y)
			">=": return x >= y
			"<=": return x <= y
			">": return x > y
			"<": return x < y
	var sa := str(a)
	match op:
		"==": return sa == raw
		"!=": return sa != raw
	return false

# --- Выбор ---

## Самая приоритетная непросмотренная сцена события с выполненными условиями (или {}).
func pick_scene(trigger: String) -> Dictionary:
	var ctx := context(trigger)
	var best: Array[Dictionary] = []
	var best_pri := -INF
	for sc in scenes:
		if sc.get("trigger", "") != trigger:
			continue
		if not sc.get("repeat", false) and Save.is_seen(str(sc.get("id", ""))):
			continue
		if not check(sc._conds, ctx):
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
	var ctx := context()
	var ok: Array = []
	for it in items:
		if check(it._conds, ctx):
			ok.append(it)
	if ok.is_empty():
		return []
	var idx := randi() % ok.size()
	if ok.size() > 1 and _last_pick.get(pool, -1) == items.find(ok[idx]):
		idx = (idx + 1) % ok.size()
	_last_pick[pool] = items.find(ok[idx])
	return (ok[idx].lines as Array).duplicate(true)

func has_pool(pool: String) -> bool:
	return not pools.get(pool, []).is_empty()

## Первая реплика пула как текст (для пузыря), с подстановкой {deaths} и т. п.
func pool_text(pool: String) -> String:
	var lines := pool_lines(pool)
	return format_text(str(lines[0].get("text", ""))) if not lines.is_empty() else ""

func format_text(t: String) -> String:
	if t.find("{") < 0:
		return t
	var ctx := context()
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
		var line: Dictionary = l.duplicate(true)
		line["text"] = format_text(str(line.get("text", "")))
		for ch in line.get("choices", []):
			ch["text"] = format_text(str(ch.get("text", "")))
			ch["lines"] = expand(ch.get("lines", []))
		out.append(line)
	return out

## Показывает реплики новеллой и ждёт конца. backdrop: "run" (полупрозрачно поверх боя) или "couch" (между забегами).
func play_lines(lines: Array, scene_id: String = "", backdrop: String = "run") -> void:
	var expanded := expand(lines)
	if expanded.is_empty():
		return
	var was_paused := get_tree().paused
	var mouse := Input.mouse_mode
	_playing = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene_started.emit(scene_id)
	var b := box()
	b.open(expanded, scene_id, backdrop)
	await b.finished
	_playing = false
	get_tree().paused = was_paused
	Input.mouse_mode = mouse
	scene_finished.emit(scene_id)

func play_scene(sc: Dictionary, backdrop: String = "run") -> void:
	var id := str(sc.get("id", ""))
	Save.mark_seen(id)
	await play_lines(sc.get("lines", []), id, backdrop)
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
func bark(line: Dictionary) -> void:
	var text := format_text(str(line.get("text", "")))
	if text == "":
		return
	var sp := str(line.get("speaker", "odin"))
	_on_line_shown(line)
	if sp == "odin":
		Odin.line_spoken.emit(text)
	else:
		bubble().show_line(sp, str(line.get("emotion", "neutral")), text)

func bark_pool(pool: String) -> void:
	var lines := pool_lines(pool)
	if not lines.is_empty():
		bark(lines[0])

func _on_choice_made(scene_id: String, choice_id: String) -> void:
	if scene_id != "":
		Save.set_choice(scene_id, choice_id)
	var key := "choice_" + choice_id
	Save.data.events[key] = int(Save.data.events.get(key, 0)) + 1

func _on_line_shown(line: Dictionary) -> void:
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
	var ctx := context()
	for k in pools:
		if str(k).ends_with(".visit"):
			for it in pools[k]:
				if check(it._conds, ctx):
					keys.append(k)
					break
	if keys.is_empty():
		return []
	return pool_lines(keys[randi() % keys.size()])

# --- Проверка данных (тест) ---

## Ошибки данных: у каждой реплики id, speaker (известный), emotion (из списка), text; условия разбираются.
func validate() -> Array[String]:
	var errs: Array[String] = load_errors.duplicate()
	var ids := {}
	for sc in scenes:
		var sid := str(sc.get("id", ""))
		if sid == "":
			errs.append("%s: сцена без id" % sc._file)
		elif ids.has(sid):
			errs.append("повтор id сцены %s" % sid)
		ids[sid] = true
		if not str(sc.get("trigger", "")) in TRIGGERS:
			errs.append("%s: неизвестное событие «%s»" % [sid, sc.get("trigger", "")])
		if (sc.get("lines", []) as Array).is_empty():
			errs.append("%s: пустая сцена" % sid)
		_validate_lines(sc.get("lines", []), sid, errs, ids)
	for p in pools:
		for it in pools[p]:
			_validate_lines(it.lines, p, errs, ids)
	return errs

func _validate_lines(lines: Array, where: String, errs: Array[String], ids: Dictionary) -> void:
	for l in lines:
		if not l is Dictionary:
			errs.append("%s: реплика не объект" % where)
			continue
		if l.has("pool"):
			var pn := str(l.pool)
			if pn != "$reaction" and not pools.has(pn):
				errs.append("%s: нет пула %s" % [where, pn])
			continue
		var lid := str(l.get("id", ""))
		if lid == "":
			errs.append("%s: реплика без id («%s»)" % [where, l.get("text", "")])
		elif ids.has(lid):
			errs.append("%s: повтор id %s" % [where, lid])
		ids[lid] = true
		var sp := str(l.get("speaker", ""))
		if sp == "" or not speakers.has(sp):
			errs.append("%s: неизвестный говорящий «%s»" % [lid, sp])
		if not str(l.get("emotion", "")) in EMOTIONS:
			errs.append("%s: эмоция «%s»" % [lid, l.get("emotion", "")])
		if str(l.get("text", "")).strip_edges() == "":
			errs.append("%s: пустой текст" % lid)
		var chs: Array = l.get("choices", [])
		if not chs.is_empty():
			if chs.size() != 2:
				errs.append("%s: выборов должно быть 2" % lid)
			for ch in chs:
				if str(ch.get("id", "")) == "" or str(ch.get("text", "")) == "" or str(ch.get("label", "")) == "":
					errs.append("%s: у выбора нет id/label/text" % lid)
				_validate_lines(ch.get("lines", []), lid, errs, ids)
