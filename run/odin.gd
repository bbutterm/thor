extends Node
## Автозагрузка «Odin» — саркастичные реплики Одина. Тексты в data/odin_lines.json.

signal line_spoken(text: String)

const LINES_PATH := "res://data/odin_lines.json"

var _lines: Dictionary = {}
var _last_by_event: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(LINES_PATH, FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_lines = parsed
	if _lines.is_empty():
		push_warning("Odin: не удалось загрузить реплики из %s" % LINES_PATH)

## Возвращает случайную реплику события (без повтора подряд) и шлёт сигнал для HUD.
func say(event: String) -> String:
	var pool: Array = _lines.get(event, [])
	if pool.is_empty():
		return ""
	var text: String = pool[randi() % pool.size()]
	if pool.size() > 1 and text == _last_by_event.get(event, ""):
		text = pool[(pool.find(text) + 1) % pool.size()]
	_last_by_event[event] = text
	line_spoken.emit(text)
	return text

func pick(event: String) -> String:
	var pool: Array = _lines.get(event, [])
	return "" if pool.is_empty() else pool[randi() % pool.size()]
