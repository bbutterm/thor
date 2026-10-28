# Рефакторинг: заметки по этапам

Промт и правила — `docs/REFACTOR_PROMPT.md`.

## Этап 1. Документация по папкам и тесты по изменениям (28.10)

### Было → стало
| Было | Стало |
|---|---|
| Корневой `CLAUDE.md`, 142 строки, все подробности в одном файле | Корневой `CLAUDE.md` — карта папок, общие правила (фризы, генератор и ручные сцены, слои физики, урон через `deal_damage`, `@export` + `TUNING.md`), локализация, команды проверки |
| Руны Мьёльнира, удар-приземление, тела (стиль движения), шкала стиля, руки | `player/CLAUDE.md` |
| Мьёльнир, перезарядка броска, трейты Б4, оружие правой руки, модели оружия | `weapons/CLAUDE.md` |
| `enemy.gd`, элита, мини-босс, Свен, Ярл, модели персонажей Quaternius | `enemies/CLAUDE.md` |
| Залы и волны, ручные/генерируемые сцены, новый боевой зал, одевание (Б0), открытые залы, декор, модели окружения | `rooms/CLAUDE.md` |
| Разрушаемое (бочки, ящики, мосты) | `props/CLAUDE.md` |
| `Run`, Один, обучение, `RunTracker`, тела (пассивки), данные по GDD, структура забега (И), серебро и ларёк (К), испытания (Ф), открытия, боевые часы | `run/CLAUDE.md` |
| HUD, подсказка хвата, скин UI (С), графика экранов, окна диалогов, портреты | `ui/CLAUDE.md` |
| `FX` и VFX-комплект, комикс-слова, музыка и звук владельца, `Perf`, `AssetCache`, прогрев, обводка (Б1), графика и свет мира, настройки, диалоги, сохранение | `scripts/CLAUDE.md` |
| Список команд тестов, полный набор, фризы с рендерингом, кадры, бот-плейтест (Н5) | `tests/CLAUDE.md` |
| Генератор, разовые правки сцен, импорт звука, локализационные скрипты, сборка Windows и проверки экспорта | `tools/CLAUDE.md` |
| — | `tests/test_map.json` — какой файл → какие тесты |
| — | `tools/run_tests.py` — `--changed` / `--test` / `--all`, `--jobs N`, `--dry-run`; сам прогон — существующий `tools/run_test_suite.py` |

Проверка «ничего не потеряно»: все 883 фрагмента в обратных кавычках из старого `CLAUDE.md` найдены в новых файлах (кроме строк блока кода с командами — они переписаны списком в `tests/CLAUDE.md`).

### Что уже было сделано раньше (не дублировал)
- Отдельные сохранения и настройки на тест: `tools/run_test_suite.py` даёт каждому тесту свой `XDG_DATA_HOME`, поэтому общие `user://test_save.json` / `user://test_settings.cfg` не пересекаются между процессами.
- Параллельный прогон: `THOR_TEST_JOBS=1..8` в `run_test_suite.py`. `run_tests.py --jobs` передаёт его же.

### Как выбираются тесты по изменениям
1. Правила `tests/test_map.json` (префикс пути или шаблон `*`), объединение всех сработавших.
2. Изменён сам тест (`tests/<имя>_test.*`) — он.
3. Тесты, чей `.gd` упоминает `res://`-путь файла или его `class_name`. Если класс упоминают больше 8 тестов (`Player`, `Enemy`…), он считается общим и берутся только тесты из карты.
4. Файл без правила (и не из `ignore`) — `default`: `smoke_test`, `generator_test`, `ai_test`.
5. `project.godot`, `export_presets.cfg` — все тесты.

Примеры: `weapons/mjolnir_hand.gd` → 10 тестов, `player/player.gd` → 11, `scripts/fx.gd` → 5, `enemies/bosses/jarl.gd` → 15, документация → 0.

### Обёртки совместимости
Нет (кода игры этап не трогал).

### Найдено и не тронуто
- **`comic_test` плавал** (в `main` до этапа): в разных прогонах падали разные проверки — «удар босса по игроку → OOF/UGH», «крит: ровно одно слово на 3-м ударе» (лишнее `rank_1`), «удар-приземление → слово в мире» (лишнее `multikill`) и др. Причина — `randf()` без зерна (криты, шанс обычного слова, ИИ). Исправлено отдельным коммитом вне рефакторинга: `seed(4242)` в начале `_run()` (`tests/comic_test.gd`), проверки не менялись. До: 7 из 8 прогонов зелёные (4 параллельно); после: 12 из 12.
- Незалитые ветки других исполнителей с изменениями, которых нет в `main`: `codex/hitch-n11` (анализатор лога фризов), `codex/sven-art` (другая версия портретов Свена), `codex/skirt-work` (описание опыта), `codex/future-finale-art` (черновые картинки финала). Файлы, которые трогает этап 1, они не меняют.

### Время полного прогона (59 тестов, 4 ядра)
- До: 3 мин 38 с (`THOR_TEST_JOBS=4`), 58 PASS, 1 FAIL — `comic_test` (плавающий, см. выше).
- После: 2 мин 57 с (`run_tests.py --all --jobs 4`); единственный FAIL — тот же плавающий `comic_test`, исправлен отдельным коммитом.
- Цель промта «быстрее 25 минут» уже выполнена.

## Этап 2. Игрок: `player/player.gd` → компоненты (28.10)

### Было → стало
`player.gd` — 1590 строк → 773 (из них ~280 — `@export`-числа и поля состояния, ~190 — обёртки). Логика (~1000 строк) — в семи компонентах:

| Было (`player.gd`) | Стало |
|---|---|
| `_process_walk`, `momentum_limit`, `_start_slide`, `_process_slide`, `_push_rigid_bodies`, `_update_footsteps`, `apply_movement_profile`, `movement_style` | `player_movement.gd` — `PlayerMovement`, `player.movement` (122 строки) |
| `_process_jump`, `_process_gravity`, `_check_stomp`, `can_stomp`, `_check_ledge`, `_try_wall_jump`, `_start_climb`, `_process_climb`, `launch_up` | `player_jumps.gd` — `PlayerJumps`, `player.jumps` (219) |
| `can_start_slam`, `slam_surface_hit`, `_start_slam`, `_cancel_slam`, `_on_landed`, `_do_slam_impact`, `_slam_break_floor`, `_slam_bounce`, `_slam_assist_tick` | `player_slam.gd` — `PlayerSlam`, `player.slam` (187) |
| `can_dash`, `_try_dash`, `_dir_or_forward`, `restore_mjolnir_runes`, `_rune_recharge_progress`, `_spend_dash_charge`, `_start_dash`, `_process_dash`, `_start_ram`, `_end_ram`, `_ram_tick`, `_dash_damage_tick` | `player_dash.gd` — `PlayerDash`, `player.dash` (157) |
| `is_invulnerable`, `take_damage`, `pay_health`, `heal`, `_die`, `refill_shield`, `_rune_on_damaged`, `_rune_second_wind`, `kill_heal`, `_on_kill_registered` | `player_health.gd` — `PlayerHealth`, `player.vitals` (121; имя `health` занято полем HP) |
| `weapon_skill_*`, `_weapon_skill_*`, `_process_weapon_skill_lunge`, `_finish_weapon_skill_lunge_step`, `_end_weapon_skill_lunge`, `_on_weapon_skill_slot_changed` | `player_weapon_skills.gd` — `PlayerWeaponSkills`, `player.skills` (139) |
| `recalc_from_runes`, `_rune_damage_mult`, `_roll_crit`, `_on_crit`, `_rune_on_hit`, `_rune_on_dash`, `_rune_tick` | `player_runes.gd` — `PlayerRunes`, `player.runes` (106) |

На `Player` остались: все `@export` и поля состояния, сигналы, `_ready`, `apply_body_and_runes`, ввод, `_physics_process` (порядок шагов кадра не менялся), `_update_timers`, прицел и скорость, оружие правой руки, пассивки тела, `deal_damage`, шкала стиля и руки.

### Решения
- **Компоненты — `RefCounted`, а не узлы.** Создаются в `Player._init` (раньше `_ready`, поэтому доступны и до входа в дерево), не меняют дерево сцены и порядок `_process`; `player.tscn` не перегенерировался.
- **Состояние осталось на `Player`.** Тесты, HUD, трейты и тела читают и пишут поля напрямую (`p._slam_ready`, `p.set("_invuln_left", …)`, `p.dash_charges`), а сцена и `apply_movement_profile` ставят `@export`. Перенос полей в компоненты потребовал бы менять тесты — по правилам этапа нельзя.
- Перенос сделан скриптом (по токенам, без строк и комментариев): к полям и методам игрока дописано `p.`, к функциям другого компонента — `p.<компонент>.`, `self` → `p`. Тела функций не менялись. Поэтому этап — один коммит, а не семь: все функции перенесены одним механическим проходом и проверены одним полным прогоном.

### Обёртки совместимости (в конце `player.gd`)
- `## API игрока →` (публичные, их зовёт игровой код): `momentum_limit`, `apply_movement_profile`, `movement_style`, `can_stomp`, `launch_up`, `can_start_slam`, `slam_surface_hit`, `can_dash`, `restore_mjolnir_runes`, `is_invulnerable`, `take_damage`, `pay_health`, `heal`, `kill_heal`, `refill_shield`, все `weapon_skill_*`, `recalc_from_runes`.
- `## совместимость →` (приватные, их зовут тесты и трейты): `_process_jump` (runes_test), `_start_slam` (hammer_dive, тесты), `_cancel_slam` (trait_test), `_do_slam_impact` (mjolnir_element, balcony, тесты), `_slam_bounce` (slam_gate_test), `_spend_dash_charge` (runes_test), `_start_dash`, `_end_ram` (destructible_test, hands_test), `_die` (enemy_test), `_weapon_skill_enemy_only_floor` (smoke_test), `_rune_on_dash` (rune_test).
- Тесты не менялись.

### Найдено и не тронуто
- Ничего нового.

### Проверка
- `godot --headless --path . --import` — без ошибок.
- `python3 tools/run_tests.py --all --jobs 4` — 59 из 59 PASS за 3 мин 13 с, без SCRIPT ERROR; предупреждений в логах не больше, чем до этапа (22 против 27).
- Карта тестов: для `player/player_slam|jumps|dash|weapon_skills|runes|health` добавлены свои тесты сверх общего правила `player/`.
