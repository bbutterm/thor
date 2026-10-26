extends RefCounted
class_name GameSettings
## Настройки игрока с сохранением в user://settings.cfg (ConfigFile).
## Каждая подсистема пишет свою секцию; при сохранении остальные секции файла не трогаем —
## сюда потом вольётся полное меню настроек.
## Секция [comic]: enabled (комиксовые слова вкл/выкл), scale (размер слов).

const PATH := "user://settings.cfg"
const COMIC_SCALE_MIN := 0.5
const COMIC_SCALE_MAX := 1.6

static var comic_enabled: bool = true
static var comic_scale: float = 1.0
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	comic_enabled = bool(cf.get_value("comic", "enabled", comic_enabled))
	comic_scale = clampf(float(cf.get_value("comic", "scale", comic_scale)), COMIC_SCALE_MIN, COMIC_SCALE_MAX)

static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)  # сохраняем чужие секции, если файл уже есть
	cf.set_value("comic", "enabled", comic_enabled)
	cf.set_value("comic", "scale", comic_scale)
	var err := cf.save(PATH)
	if err != OK:
		push_warning("GameSettings: не удалось сохранить %s (%d)" % [PATH, err])

static func set_comic_enabled(v: bool) -> void:
	ensure_loaded()
	comic_enabled = v
	save()

static func set_comic_scale(v: float) -> void:
	ensure_loaded()
	comic_scale = clampf(v, COMIC_SCALE_MIN, COMIC_SCALE_MAX)
	save()
