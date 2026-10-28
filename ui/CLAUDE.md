# ui/ — HUD, меню, экраны выбора, скин, диалоговые окна

Всё строится кодом, `.tscn` — пустые обёртки со скриптом (генерирует `tools/build_scenes.gd`). Русские строки — только через `tr()` (проверяет `i18n_test`, см. корневой `CLAUDE.md`, «Локализация»).

## Что здесь
- HUD: `hud.gd` (+ `RuneHammer` — `rune_hammer.gd`: руны на бойке, шкала высоты в рукояти, полоска перезарядки броска по низу бойка `set_cooldown`; состояние молота, `HUD._retranslate`), `style_hud.gd` (`StyleHUD.attach`), `weapon_hud.gd`, `silver_hud.gd`, `mjolnir_traits_hud.gd`, `trial_hud.gd`, `skin_bar.gd`, `hud_icon.gd`, `boss_bar.gd`, `offscreen_indicators.gd` (враги за экраном + иконка «где молот», когда Мьёльнир не в руке и вне поля зрения), `catch_assist.gd`.
- Выбор: `rune_pick.gd`, `trait_pick.gd`, `choice_pick.gd`, `body_select.gd`, `training_plan.gd`, `shop.gd` (`ShopScreen`), `combo_announce.gd`.
- Меню и экраны: `main_menu.gd`, `pause_menu.gd`, `end_screen.gd`, `settings_panel.gd`, `loading_screen.gd`, `screen_art.gd`, `comic_insert.gd`, `boss_card.gd`, `comic_page.gd`.
- Диалоги: `dialogue_box.gd`, `portrait.gd`, `bark_bubble.gd`.
- Скин: `ui_skin.gd`, `skin_style_box.gd`, `skin_card.gd`; `color_filter.gdshader` — фильтр цветовой слепоты.

## Подсказка идеального хвата
`catch_assist.gd` (`CatchAssist`, создаёт `VfxScreen._ready`) — сходящееся к прицелу кольцо по `MjolnirProjectile.catch_eta()` (прокрутка того же возврата вперёд; точно до кадра), золотое окно ±`perfect_window` (до и после поимки, `MjolnirHand.perfect_window_left()`), клавиша броска, стрелка «откуда летит», итог «ИДЕАЛЬНО!/РАНО/ПОЗДНО · мс» (сигнал `MjolnirHand.catch_timing`). Выключатель `[access] catch_assist` (по умолчанию вкл). Тест — `tests/catch_test.tscn` (с `-- <папка>` под xvfb — кадры).

## Скин UI (блок С)
`ui_skin.gd` (`UISkin`) читает `data/ui_manifest.json` (картинки владельца `sprites/ui/**`; координаты — в px исходника, импорт уменьшает иконки `size_limit=256` → `src_to_tex(id)`): `texture(id)`, `stylebox(id, scale)` → `SkinStyleBox` (`skin_style_box.gd`: 9-slice С МАСШТАБОМ — StyleBoxTexture рисует поля 1:1; прозрачные поля картинки — за пределами контрола), `theme()` + `apply(control)` (тема и мипмапы на корне экрана — CanvasLayer тему не передаёт), `style_button(b, main|secondary|danger)`, иконки `weapon_icon/trait_icon/rune_category_icon`. Вариации темы: `SecondaryButton`, `DangerButton`, `SmallButton`, `WoodPanel`, `NamePlate`. `UIStyle.button(text, size, kind)` и `UIStyle.panel(bg, border, kind "" | wood | window | plate)` уже на скине. Карточки выбора — `skin_card.gd` (`SkinCard`: card_rune / card_trait + рамка редкости при наведении). HUD: `skin_bar.gd` (рамка + заливка по `fill_rect`), `hud_icon.gd`, `boss_bar.gd`, `offscreen_indicators.gd`. Кадры интерфейса: `xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/ui_shots.tscn -- <папка>` (с `en` в конце — на английском).

## Настройки
UI — `settings_panel.gd` (`SettingsPanel`, 6 вкладок; из главного меню и паузы). Логика и хранение — `scripts/settings.gd` (`GameSettings`, см. `scripts/CLAUDE.md`). A/B — подтверждение/назад в UI; подсказки клавиш — `GameSettings.current_binding`.

## Графика экранов (комплект владельца, `docs/world_art/`)
Пути и сопоставления — `screen_art.gd` (`ScreenArt`: `tex()` с кешем, `prefetch()` в фоне, `prefetch_between_runs()` из меню и после смерти; в headless предзагрузка экранов пропущена, `tex()` загружает по запросу, чтобы не тормозить кадр победы; боевые картинки — заставки, загрузки, кадры смерти — в `AssetCache`). Тела — `sprites/bodies/<id>.webp` (+`locked.webp`) в `BodySelect` (портрет во весь рост, головы на карточках); открытия — поле `icon` в `run/unlocks/*.tres` (`sprites/unlocks/`); фоны новеллы — `DialogueBox.open(…, backdrop)`: `couch`/`shop`/`run` (мир забега → `midgard_village`)/имя файла `sprites/backgrounds/`, у сцены JSON — поле `"backdrop"`; сюжетные кадры — `"image"` у реплики или сцены (`sprites/story/<id>.webp`, `"none"` — убрать; портреты прячутся). Вставки на паузе (`comic_insert.gd`, своё время, клик пропускает, ждут конца новеллы): заставка босса `boss_card.gd` (`ScreenArt.BOSSES` по `death_source_id`) и «страница комикса» `comic_page.gd` (стоп-кадр + рамка `sprites/death/frame.webp` + растр `shaders/comic_page.gdshader`, причина смерти → `sprites/death/<ключ>.webp`, подписи — пулы `odin.page_<ключ>`/`odin.page_boss_<id>`); выключатели `[comic] page`/`boss_card`; **в тестах выключены** (`ScreenArt.pauses_in_tests`, как `Dialogue.in_run_scenes`). Загрузочный экран `loading_screen.gd` (на корне: `show_now()` перед сменой сцены, `transition()` между залами, `finish()` из `Game._load_room`; советы — пул `odin.loading`). Тест `tests/art_screens_test.tscn` (с `-- <папка>` под xvfb — кадры).

## Диалоговые окна и портреты
- `dialogue_box.gd` — окно новеллы (портреты, имя, печать, выбор ответа Тора, «Пропустить», журнал); `bark_bubble.gd` — пузырь в углу для не-Одина. Логика сцен — `scripts/dialogue_manager.gd`.
- `portrait.gd` — портрет `sprites/portraits/<speaker>_<emotion>.webp` (или `.png`): нет эмоции → neutral, нет файла → процедурная заглушка.
- **Портреты** (комплект владельца: thor, odin, loki, sif, freya, hild, hel, skadi, heimdall, jarl, hugin — он же munin, draugr; созданные отдельно — brokk, eitri, sven и дополнительные эмоции, источник каждого файла в `CREDITS.md`). Точки лиц для крупного плана — `data/portrait_faces.json`; Хугин и Мунин используют один файл, но разные точки. Новые портреты: положить файл, в `.import` поставить `compress/mode=1`, `process/size_limit=1024` (как у соседей). Для brokk/eitri/sven и дополнительных эмоций `process/size_limit=768`: проверять кадрами и размером экспорта. Прогрев портретов включает все доступные эмоции Тора в каждом зале, потому что он может заговорить в бою. Кадры: `tests/portrait_shots.tscn`.

## Типовые задачи
- Смена языка на лету: экраны, собранные кодом, ловят `GameSettings.events.changed("text", "language")` и пересобираются (меню, пауза, настройки) или обновляют подписи (`HUD._retranslate`).
- Новая кнопка/панель — `UIStyle.button`/`UIStyle.panel` или `UISkin.style_button`, не свои StyleBox.

## Тесты
`ui_test` (скин UI, HUD — полосы, щит, рывок, молот, индикаторы; настройки, переназначение клавиш), `art_screens_test`, `i18n_test`, `gamepad_test`, `catch_test`, `portrait_test`, `portrait_review_test`, `dialogue_test`. Кадры — `tests/ui_shots.tscn`, `tests/deck_shots.tscn`.
