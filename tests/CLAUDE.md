# tests/ — проверки, кадры, бот-плейтест

## Как запускать
- **По изменениям** (обычная работа): `python3 tools/run_tests.py --changed` — тесты по `git diff` от `origin/main` (плюс незакоммиченное) по карте `tests/test_map.json`.
- Один тест: `python3 tools/run_tests.py --test catch_test` (можно несколько `--test`). Все: `python3 tools/run_tests.py --all`. Потоки — `--jobs N` (1–8, по умолчанию 4). Список без запуска — `--dry-run`.
- Полный набор вручную: `tools/run_test_suite.sh . /tmp/thor-test-results` (папка результатов должна быть новой; `THOR_TEST_JOBS=4` — параллельно). Отдельная папка данных на тест (`XDG_DATA_HOME`), лимит 50 МБ на лог. Он также отмечает неожиданные `ERROR`, а намеренные ошибки тестов и сообщения о ресурсах при выходе сохраняет в `*.expected-errors` и перечисляет в сводке; их нужно просматривать отдельно. `run_tests.py` вызывает его же.
- Один тест руками: `godot --headless --path . --fixed-fps 60 res://tests/<имя>.tscn 2>&1 | head -c 50000000 > log` (код выхода — `${PIPESTATUS[0]}`). Перед этим после слияний/переключений — `godot --headless --path . --import` (иначе устаревший кеш классов даёт SCRIPT ERROR каждый кадр и гигантский лог).

**Правило: перед заливкой в `main` — все `tests/*_test.tscn`, у каждого в конце строка «ИТОГ … 0 FAIL»** и нет SCRIPT ERROR. Новый тест — `tests/<имя>_test.tscn` + строка в `test_map.json`.

## Что проверяет каждый тест (основные)
```
smoke_test        # полный забег, ожидается 0 FAIL
reach_test        # достижимость платформ (в т. ч. ярусы залов 7–9)
generator_test    # генератор не трогает ручные арены, все залы забега собраны
ai_test           # враги доходят и бьют во всех залах
enemy_test        # враги Мидгарда, щит, взрыв, шаман, волны
squad_test        # отряды-комбинации: состав, строй, вход сзади, задержка, роли, варианты, залы с отрядами
hazard_test       # снаряды и опасные зоны (телеграф, прыжок/рывок, лужи, лимиты), отражение, роли поведения
elite_test        # элита: все виды × 7 модификаторов
trait_test        # база молота, правила выбора, наковальня, каждая стихия ур. 1–4, приём ур. 1–2, связки (-- elements|techniques|combos — часть)
hitch_test -- 50  # фризы (CPU-часть)
comic_test        # комиксовые слова: события, кулдаун, лимит, выключатель
jump_test         # отскок от удара-приземления, по головам, уступ, от стены
weapon_test       # оружие: слоты, свитч, подбор, патроны, штрафы
body_test         # тела: старт каждым, стили движения, пассивки, подкат, экран выбора
style_test        # шкала стиля: очки приёмов, повтор, урон, спад, ранги, берсерк 8 с, Слава, музыка, голос и слова; бой-реплики Одина
boss_test         # боссы: Толстый Свен (арена, таран, лужи, взрыв), Ярл Бьорн (3 фазы)
vfx_test          # VFX-комплект: общие материалы, пулы и лимиты, анимации до конца, экранные эффекты
world_art_test    # небо мира, декали, декор, атмосфера, общие материалы, текущие instance-материалы
ui_test           # скин UI, HUD (полосы, щит, рывок, молот, индикаторы), настройки, переназначение клавиш
audio_test        # звук владельца: файлы, слои музыки, подмена синтеза, озвучка реплик, один голос
art_screens_test  # графика экранов: тела, открытия, фоны и кадры новеллы, загрузки, заставка босса, страница комикса
destructible_test # бочки/ящики: все источники урона, обломки, содержимое, взрывные, мосты, балконы Ярла
outline_test      # комиксовая обводка: кому есть/нет, один материал, вспышка, настройка вживую, текущие instance-материалы
run_map_test      # двери-награды, порядок залов
shop_test         # серебро и ларёк
trial_test        # испытания
catch_test        # хват Мьёльнира, перезарядка, подсказка (с -- <папка> под xvfb — кадры)
runes_test, slam_gate_test, dive_gate_test   # руны Мьёльнира, допуск удара-приземления и пике
i18n_test         # локализация, в т. ч. русские литералы без tr() в ui/*.gd
combat_clock_test # боевые часы Run.combat_clock
tower_test        # подъём на вышки
bot_test, bot_control_test, bot_*_test       # бот-плейтест
```
Остальные (`dialogue_test`, `save_test`, `tutorial_test`, `gamepad_test`, `portrait_*`, `horde_*`, `fodder_*`, `headless_*`, `report_test`, …) — по имени.

## Соглашения в тестах
- Тесты (`res://tests/*`) и `--selftest` пишут сохранение в `user://test_save.json`, настройки — в `user://test_settings.cfg`; язык в тестах всегда ru.
- Порядок залов — `Run.room_order` (после `Run.start_run`), наборы дверей — `Run.forced_offers`, испытание — `Run.forced_trial = "<id>"`, `Run.doors_enabled = false` — старая одна дверь после руны. Общие шаги — `door_helper.gd` (`resolve_reward`, `take_door`).
- Где важны броски подряд — `hand.throw_cooldown = 0`.
- Вставки на паузе (заставка босса, страница комикса) в тестах выключены (`ScreenArt.pauses_in_tests`, как `Dialogue.in_run_scenes`).
- Окна мультикилла/попадания/шмяка — по `Run.combat_clock`; не заменяй системными часами.

## Фризы с рендерингом
Forward+ на программном Vulkan (`apt-get install mesa-vulkan-drivers`):
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --fixed-fps 60 --rendering-method forward_plus --resolution 320x180 res://tests/hitch_test.tscn -- 50` (и то же с `gl_compatibility`). Прогон ~10 мин; кадры без событий — шум программного рендера, не считаются. Цена отдельных систем — `tests/perf_bench.tscn -- 8 <система>`.

## Кадры (нужен xvfb)
- Общие: `xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/screenshots.tscn -- <папка>`.
- По системам: `ui_shots` (`-- <папка> en` — английский), `deck_shots` (1280×800), `room_shots -- <папка> room_07 …`, `weapon_shots` (640x360), `mjolnir_shots`, `hands_shots -- <папка> [quick]`, `vfx_shots`, `world_art_shots`, `outline_shots`, `portrait_shots`, `enemy_shots`, `boss_shots`, `hazard_shots`, `destruct_shots`.
- Витрина ассетов: `xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tools/preview_assets.tscn -- out.png lineup|characters|village|props`.

## Бот-плейтест и баланс (Н5)
- `bot/bot_player.gd` — бот через ввод и реальные ограничения игрока: руны, второй прыжок перед ударом, перезарядка и хват Мьёльнира. `bot_test.tscn` проверяет забег; `bot_control_test.tscn` — ввод, руны, удар, кулдаун и край платформы.
- Полный прогон: `tests/bot/run_balance.sh /tmp/thor-balance-new 5 skilled 11 3`. Он создаёт отдельное `user://` на процесс, обрезает логи и отказывается перезаписать прежние результаты. Таблицы — `tests/bot/balance_report.py`; методы и ограничения, 45 исходных строк — `docs/balance_2026-10-27.md` и `.jsonl`.
