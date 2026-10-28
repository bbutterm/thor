extends RefCounted
class_name DialogueConditions
## Условия сцен и реплик: разбор строки условия, контекст (сохранение, забег), проверка.
## Компонент DialogueManager (этап 5 рефакторинга): числа и состояние — поля DialogueManager (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — Dialogue.conditions; нужные снаружи функции есть и на DialogueManager.

var dm: DialogueManager

func _init(owner_node: DialogueManager) -> void:
	dm = owner_node

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
	for op in DialogueManager.OPS:
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
	if src in DialogueManager.FLAGS:
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
	for k in dm._extra_ctx:
		ctx[k] = dm._extra_ctx[k]
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
