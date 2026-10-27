extends Node
## Автозагрузка «Odin» — короткие реплики Одина пузырём в HUD (без паузы).
## Тонкая обёртка над Dialogue: тексты — пулы файла data/dialogues/odin.json ("pools").
## say("idle") берёт случайную реплику пула odin.idle. Старые события (run_start, death, room_clear…) — те же имена пулов.
## Лимит GDD 17: в бою не чаще раза в combat_cooldown секунд (события из EXEMPT — без лимита).

signal line_spoken(text: String)

## Реплика Одина в бою не чаще раза в N секунд (GDD 17)
@export var combat_cooldown: float = 12.0
## События, которые не ждут лимита (начало забега, босс, итог)
## «berserk» — Один орёт при берсерке (GDD 8), не ждёт лимита (но и не сбрасывает его)
const EXEMPT := ["run_start", "boss_start", "miniboss_start", "miniboss_death", "victory", "death", "berserk"]

var _last_combat_time: float = -1000.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

static func _pool(event: String) -> String:
	return "odin." + event

func _exempt(event: String) -> bool:
	for e in EXEMPT:
		if event == e or event.begins_with(e + "_"):
			return true
	return false

## Возвращает случайную реплику события (без повтора подряд) и шлёт сигнал для HUD.
## Пусто — если события нет, идёт сцена-новелла или не прошёл лимит боевых реплик.
func say(event: String) -> String:
	if Dialogue.is_playing():
		return ""
	var exempt := _exempt(event)
	if not exempt and _now() - _last_combat_time < combat_cooldown:
		return ""
	var lines := Dialogue.pool_lines(_pool(event))
	if lines.is_empty():
		return ""
	var line: Dictionary = lines[0]
	var text := Dialogue.format_text(str(line.get("text", "")))
	if text == "":
		return ""
	if not exempt:
		_last_combat_time = _now()
	# Озвучка (поле "voice" реплики) — на шине Voice, один голос за раз
	Dialogue.speak_line(line, Audio.VOICE_BARK)
	line_spoken.emit(text)
	return text

## Реплика без показа (для экранов).
func pick(event: String) -> String:
	return Dialogue.pool_text(_pool(event))

## Сбросить лимит (новый забег).
func reset_cooldown() -> void:
	_last_combat_time = -1000.0
