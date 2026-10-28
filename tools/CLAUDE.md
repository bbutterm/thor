# tools/ — генератор сцен, одевание залов, сборка, импорт ассетов, проверки

## Генератор сцен (`build_scenes.gd`)
- Генерирует сцены игрока, врагов, бочек, **обычных боевых залов** (`room_defs()`: `rooms/room_01…09.tscn`), зала-ларька (`shop_room_def()`), UI и `scenes/game.tscn`. Меняешь их структуру — правь генератор и перезапускай: `godot --headless --path . res://tools/build_scenes.tscn`. Коммить только намеренно изменённые .tscn: генератор переписывает `unique_id` в негенерируемых по смыслу сценах — такой шум откатывай **по одному файлу**, никогда не всю папку.
- **Ручные сцены** — `MANUAL_SCENES` (`rooms/boss_arena.tscn`, `rooms/sven_arena.tscn`; новые арены — туда же): генератор их не создаёт и не перезаписывает (`_save` отказывается, проверка — `tests/generator_test.tscn`).
- Вид и анимации врагов — `MODEL_LOOKS`; пропсы — `build_props` (новый разрушаемый пропс — см. `props/CLAUDE.md`); даль — `build_dress`; стены — `_wall_row`, дома — `_house`, вышки — `_watchtower`, авто-щиты/знамёна — `_build_wall_art`, материалы — `_tex_mat`, стиль блока — `_block_style`. Ключи `room_defs()` — `rooms/CLAUDE.md`.
- `room_dresser.gd` (`RoomDresser`) — одевание залов (вызывается в конце `_build_room`), подробно — `rooms/CLAUDE.md`.
- Разовые правки ручных сцен (запускать сценой, не `-s`): `dress_arenas.tscn` (арена Свена), `dress_longhouse.tscn` (убранство длинного дома, узел `Decor`), `dress_longhouse_art.tscn` (картинки длинного дома).
- `setup_project.gd` — одноразовая настройка проекта (`godot --headless --path . -s tools/setup_project.gd`): Jolt, имена слоёв физики, управление, автозагрузки, главная сцена.

## Ассеты и звук
- `make_sfx.py` — синтез звуков `sounds/sfx/` и запасной музыки (например, `music_jarl`).
- `import_owner_audio.py <архив>` — звук владельца в `sounds/owner/…`, `sounds/voice/` (нормализация, обрезка тишины); см. `scripts/CLAUDE.md`, «Музыка и звук».
- `mdx2glb.py` — WC3 .mdx → .glb (рисованное оружие). `make_arm_texture.py` — кожа рук с татуировками. `build_fodder_model.py` — модель корма.
- `preview_assets.tscn` — витрина ассетов (команда — `tests/CLAUDE.md`).

## Локализация
`i18n_extract.py` (ключи `tr()` → `data/i18n/en.po`; `--check` — отчёт), `i18n_dialogues.py [--check]` (шаблоны и покрытие `data/dialogues/en/`). Правила — корневой `CLAUDE.md`.

## Тесты и CI
- `run_tests.py` — запуск по изменениям/одного/всех (`--changed`, `--test`, `--all`, `--jobs`), карта — `tests/test_map.json`; под капотом — `run_test_suite.py`.
- `run_test_suite.sh` / `run_test_suite.py` (+ `run_test_process.py`, `godot_log_check.py`) — полный изолированный прогон; самотест — `test_run_test_suite.py`.
- `run_ci_fast.py` — быстрые проверки перед push (полный набор всё равно обязателен), `run_hitch_render.sh`, `run_render_prefetch_probe.sh`, `ci_windows_selftest.py`.

## Сборка Windows для плейтеста
`python3 tools/package_playtest.py` (Godot 4.6.3 и export templates 4.6.3). Скрипт проверяет исключения ресурсов, импортирует проект, экспортирует один `.exe`, создаёт ZIP из одного файла, проверяет CRC и предел 95 000 000 байт. Если доступна системная libdeflate — использует стандартный DEFLATE с более плотным сжатием; иначе zlib. Логи ограничены 50 МБ, лежат в `export/windows/`.

При добавлении залов/диалогов перед экспортом: `python3 tools/check_export_assets.py` (сцены, прямые вызовы UI, текущие реплики и алиасы портретов); `check_export_decor.py` — защита заготовок, исключённых из демо-экспорта; `export_dialogue_assets.py` (+ `deferred_dialogue_assets.json`) — картинки, на которые ссылаются диалоги; самотесты упаковки: `python3 tools/test_export_assets.py`, `test_export_decor.py` и `python3 tools/test_package_playtest.py`. Исключения из `export_presets.cfg` предназначены для демо Мидгарда: если ресурс станет нужен, убери соответствующий фильтр. Проверка готовой сборки: `<exe> --headless -- --selftest`; успех — `SELFTEST OK` и хотя бы один враг.
