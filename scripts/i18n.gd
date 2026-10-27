extends RefCounted
class_name I18n
## Локализация: русский — основной язык (ключи переводов = сами русские строки), английский — второй.
## Переводы интерфейса и данных — data/i18n/en.po (gettext; Godot читает .po сам, без импорта),
## подключены в project.godot (internationalization/locale/translations), запасной язык — ru:
## нет перевода → показывается русский ключ.
## В коде: tr("Русская строка") в узлах; в статических функциях — I18n.t("…") (tr() там недоступен).
## Строки с подстановкой — tr("СЛАВА %d") % n (ключ — шаблон). Данные (.tres) переводятся при показе:
## tr(def.title). Новая строка → `python3 tools/i18n_extract.py` (добавит ключ в en.po) → вписать msgstr.
## Диалоги — data/dialogues/en/<файл>.json (id реплики → перевод), см. DialogueManager.
## Язык — настройка [text] language (GameSettings), применяется сразу и при старте (apply).

const LOCALES := ["ru", "en"]
## Подписи языков в настройках — каждая на своём языке, не переводятся
const NAMES := {"ru": "Русский", "en": "English"}
const DEFAULT := "ru"

## Перевод для статических функций (tr() — метод объекта)
static func t(s: String) -> String:
	return TranslationServer.translate(s)

## Текущий язык: «ru» / «en» (региональный суффикс отбрасываем)
static func locale() -> String:
	return TranslationServer.get_locale().get_slice("_", 0)

static func is_default() -> bool:
	return locale() == DEFAULT

static func sanitize(loc: String) -> String:
	var l := loc.get_slice("_", 0).to_lower()
	return l if l in LOCALES else DEFAULT

## Включить язык. Узлы с автопереводом получат NOTIFICATION_TRANSLATION_CHANGED сами;
## экраны, собранные кодом, перестраиваются по GameSettings.events.changed("text", "language").
static func apply(loc: String) -> void:
	var l := sanitize(loc)
	if TranslationServer.get_locale() != l:
		TranslationServer.set_locale(l)
