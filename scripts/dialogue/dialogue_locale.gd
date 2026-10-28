extends RefCounted
class_name DialogueLocale
## Перевод реплик: data/dialogues/en/<файл>.json (id реплики → перевод), смена языка, localize_line.
## Компонент DialogueManager (этап 5 рефакторинга): числа и состояние — поля DialogueManager (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — Dialogue.locale; нужные снаружи функции есть и на DialogueManager.

var dm: DialogueManager

func _init(owner_node: DialogueManager) -> void:
	dm = owner_node

## Перечитать перевод под текущий язык (смена языка в настройках, load_all). Имена говорящих
## меняются прямо в speakers — портреты, пузыри и журнал берут def.name.
func refresh_locale() -> void:
	var loc := I18n.locale()
	if loc == dm._loc_locale:
		return
	dm._loc_locale = loc
	dm._loc_lines.clear()
	dm._loc_names.clear()
	if loc != I18n.DEFAULT:
		var dir := DialogueManager.DIR + loc + "/"
		var files: Array = []
		var d := DirAccess.open(dir)
		if d:
			files = Array(d.get_files())
		if files.is_empty() and DirAccess.dir_exists_absolute(dir):
			files = Array(ResourceLoader.list_directory(dir))
		files.sort()
		for f in files:
			if str(f).get_extension() == "json":
				_load_locale_file(dir + str(f), loc)
	for k in dm.speakers:
		var ru: Dictionary = dm._ru_names.get(k, {})
		var nm := str(dm._loc_names.get(k, ""))
		dm.speakers[k]["name"] = nm if nm != "" else str(ru.get("name", k))
		var ini := str(ru.get("initial", ""))
		if nm != "":
			ini = nm.left(1)
		if ini != "":
			dm.speakers[k]["initial"] = ini

func _load_locale_file(p: String, loc: String) -> void:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not json.data is Dictionary:
		dm.load_errors.append("%s:%d: %s" % [p, json.get_error_line(), json.get_error_message()])
		return
	var d: Dictionary = json.data
	var sp: Dictionary = d.get("speakers", {})
	for k in sp:
		var v: Variant = sp[k]
		var nm := str((v as Dictionary).get(loc, "")) if v is Dictionary else str(v)
		if nm != "":
			dm._loc_names[k] = nm
	var ls: Dictionary = d.get("lines", {})
	for k in ls:
		var v: Variant = ls[k]
		var t := str((v as Dictionary).get(loc, "")) if v is Dictionary else str(v)
		if t.strip_edges() != "":
			dm._loc_lines[k] = t

## Есть ли перевод реплики (id) на текущий язык
func has_translation(line_id: String) -> bool:
	refresh_locale()
	return dm._loc_lines.has(line_id)

## Реплика на текущем языке (копия не нужна — меняет переданный словарь): текст по id,
## ответы Тора по «id/выбор», подписи выборов — tr. Нет перевода — как есть (русский).
func localize_line(line: Dictionary) -> Dictionary:
	refresh_locale()
	if dm._loc_locale == I18n.DEFAULT:
		return line
	var lid := str(line.get("id", ""))
	if lid != "" and dm._loc_lines.has(lid):
		line["text"] = dm._loc_lines[lid]
	for ch in line.get("choices", []):
		if not ch is Dictionary:
			continue
		var key := lid + "/" + str(ch.get("id", ""))
		if dm._loc_lines.has(key):
			ch["text"] = dm._loc_lines[key]
		ch["label"] = dm.tr(str(ch.get("label", "")))
		for sub in ch.get("lines", []):
			if sub is Dictionary:
				localize_line(sub)
	return line
