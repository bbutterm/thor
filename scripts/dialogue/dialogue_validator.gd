extends RefCounted
class_name DialogueValidator
## Проверка данных диалогов для тестов (dialogue_test): ссылки, условия, выборы.
## Компонент DialogueManager (этап 5 рефакторинга): числа и состояние — поля DialogueManager (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — Dialogue.validator; нужные снаружи функции есть и на DialogueManager.

var dm: DialogueManager

func _init(owner_node: DialogueManager) -> void:
	dm = owner_node

## Ошибки данных: у каждой реплики id, speaker (известный), emotion (из списка), text; условия разбираются.
func validate() -> Array[String]:
	var errs: Array[String] = dm.load_errors.duplicate()
	var ids := {}
	for sc in dm.scenes:
		var sid := str(sc.get("id", ""))
		if sid == "":
			errs.append("%s: сцена без id" % sc._file)
		elif ids.has(sid):
			errs.append("повтор id сцены %s" % sid)
		ids[sid] = true
		if not str(sc.get("trigger", "")) in DialogueManager.TRIGGERS:
			errs.append("%s: неизвестное событие «%s»" % [sid, sc.get("trigger", "")])
		if (sc.get("lines", []) as Array).is_empty():
			errs.append("%s: пустая сцена" % sid)
		if sc.has("image") and ScreenArt.story_path(str(sc.image)) == "" and str(sc.image) != "none":
			errs.append("%s: нет сюжетного кадра «%s» (sprites/story/)" % [sid, sc.image])
		if sc.has("backdrop") and ScreenArt.backdrop_path(str(sc.backdrop)) == "" and str(sc.backdrop) != "none":
			errs.append("%s: нет фона «%s» (sprites/backgrounds/)" % [sid, sc.backdrop])
		_validate_lines(sc.get("lines", []), sid, errs, ids)
	for p in dm.pools:
		for it in dm.pools[p]:
			_validate_lines(it.lines, p, errs, ids)
	return errs

func _validate_lines(lines: Array, where: String, errs: Array[String], ids: Dictionary) -> void:
	for l in lines:
		if not l is Dictionary:
			errs.append("%s: реплика не объект" % where)
			continue
		if l.has("pool"):
			var pn := str(l.pool)
			if pn != "$reaction" and not dm.pools.has(pn):
				errs.append("%s: нет пула %s" % [where, pn])
			continue
		var lid := str(l.get("id", ""))
		if lid == "":
			errs.append("%s: реплика без id («%s»)" % [where, l.get("text", "")])
		elif ids.has(lid):
			errs.append("%s: повтор id %s" % [where, lid])
		ids[lid] = true
		var sp := str(l.get("speaker", ""))
		if sp == "" or not dm.speakers.has(sp):
			errs.append("%s: неизвестный говорящий «%s»" % [lid, sp])
		if not str(l.get("emotion", "")) in DialogueManager.EMOTIONS:
			errs.append("%s: эмоция «%s»" % [lid, l.get("emotion", "")])
		if str(l.get("text", "")).strip_edges() == "":
			errs.append("%s: пустой текст" % lid)
		if l.has("image") and str(l.image) != "none" and ScreenArt.story_path(str(l.image)) == "":
			errs.append("%s: нет сюжетного кадра «%s» (sprites/story/)" % [lid, l.image])
		var chs: Array = l.get("choices", [])
		if not chs.is_empty():
			if chs.size() != 2:
				errs.append("%s: выборов должно быть 2" % lid)
			for ch in chs:
				if str(ch.get("id", "")) == "" or str(ch.get("text", "")) == "" or str(ch.get("label", "")) == "":
					errs.append("%s: у выбора нет id/label/text" % lid)
				_validate_lines(ch.get("lines", []), lid, errs, ids)
