# Тор: Достойная смерть — заметки для агента

Прототип рогалик-шутера от первого лица. Godot **4.6.3** (не .NET), физика Jolt, GDScript со статической типизацией. Общение с владельцем — на русском.

## Где что
- `player/player.gd` — движение (рывок, двойной прыжок, удар-приземление, супер-прыжок), урон; `player/camera_fx.gd` — тряска/FOV/наклон.
- `weapons/` — топор (`axe.gd`), Мьёльнир (`mjolnir_hand.gd` + `mjolnir_projectile.gd`), огонь (`fire_zone.gd`).
- `enemies/enemy.gd` — один скрипт на грунта/метателя/босса (поле `kind`); `enemy_projectile.gd`.
- `rooms/room.gd` + `rooms/*.tscn` — залы, волны (маркеры в `Spawns` с метаданными `kind`/`wave`), дверь, выход.
- `run/run_manager.gd` (автозагрузка `Run`) — забег, Слава, руны; `run/odin.gd` (`Odin`) — реплики из `data/odin_lines.json`.
- `ui/` — HUD, выбор рун, пауза, экран конца, меню (всё строится кодом, `.tscn` — пустые обёртки со скриптом).
- `scripts/fx.gd` — hit-stop (тикает из `Run._process`), цифры урона, молнии, кольца, искры. Материалы эффектов — общие (`FX.fx_apply`, шейдеры `shaders/fx_*.gdshader`, цвет per-instance), меши — общие (`FX.shared_mesh`).
- `scripts/perf.gd` (автозагрузка `Perf`) — F3-оверлей, лог фризов `user://hitches.log`, `Perf.mark("событие")` в игровом коде, счётчики компиляций пайплайнов (`pso_draw` = фриз на отрисовке).
- `scripts/asset_cache.gd` (`AssetCache`) — фоновая загрузка и удержание моделей/анимаций/звуков (старт в `Run._ready`, ожидание в `Game._ready`).
- `scripts/shader_warmup.gd` (`ShaderWarmup`) — прогрев шейдеров при входе в каждый зал (под затемнением).

## Модели (Quaternius, CC0)
- `assets/quaternius/characters/` — тела, одежда, волосы, анимации (`gaits.glb` = UAL1, `animations.glb` = UAL2). Скелет у всех один (65 костей, правая кисть `hand_r`).
- `enemies/humanoid_model.gd` собирает персонажа: тело + одежда + волосы на одном скелете, красит, добавляет библиотеки анимаций `ual1/…`, `ual2/…`. Godot при импорте отрезает суффикс `_Loop` — `HumanoidModel.resolve()` ищет оба варианта.
- Вид и анимации врагов — `MODEL_LOOKS` в `tools/build_scenes.gd` (поля групп «Модель»/«Анимации» в `enemy.gd`). Замена на Synty: положить в сцену врага узел `Visual` со своим `AnimationPlayer` или поменять пути/имена анимаций там.
- `assets/quaternius/village/` — стены 2×3.12 м (`_wall_row` в генераторе ставит их в 2 ряда), текстуры для трипланарных материалов (`_tex_mat`). `assets/quaternius/props/` — бочки, факелы, знамёна.
- Оружие — `scripts/weapon_meshes.gd`: модели `q_*` из `assets/quaternius/weapons/` (материалы подменяются на наши) + процедурные (Мьёльнир, дубина, вилы, факел). Слой 2 = вьюмодель.
- Руки от первого лица — `player/viewmodel_arm.gd`: рука Quaternius (одна сторона, обрезана у локтя), застывшая в позе кулака и выровненная по рукояти; оружие строится им же при запуске (в .tscn не сохраняется). У SubViewport рук свой мир и свет (`own_world_3d`).
- Массовка/драугры: `HumanoidModel.random_look()` смешивает части одежды, волосы, цвета; у грунтов `randomize_look` + `weapon_pool` + `shield_chance`.
- Витрина ассетов: `xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tools/preview_assets.tscn -- out.png lineup|characters|village|props`.

## Важно
- **Фризы.** Не создавай материал на каждый эффект/удар: новый материал = компиляция пайплайна (Forward+), а когда последний материал вида умирает, его пайплайны выкидываются. Бери общий (`FX.fx_apply`, `WeaponMeshes.mat`, `HumanoidModel._tinted`), меняй вид через per-instance (`set_instance_shader_parameter`, `GeometryInstance3D.transparency`, оверлей `shaders/hit_flash.tres` у врагов). Новый вид эффекта — добавь его в `ShaderWarmup`. Новые ассеты персонажей/оружия/звуков — в папки из `AssetCache.DIRS`.
- Сцены игрока, врагов, бочек, залов, UI и `scenes/game.tscn` **генерирует** `tools/build_scenes.gd`. Меняешь структуру сцены — правь генератор и перезапускай его. ⚠️ Если владелец правил залы руками в редакторе, генератор их перезапишет — спроси сначала.
- Блоки уровней — StaticBody3D, не CSG (CSG давал провалы сквозь пол в первые кадры).
- Слои физики: 1 world, 2 player, 3 enemies, 4 props, 5 projectiles, 6 triggers, 7 debris.
- Вьюмодель рук — слой отображения 2, отдельный SubViewport (`Head/Camera/ViewmodelContainer`).
- Все «ощущенческие» числа — `@export`; при изменении обнови `TUNING.md`.
- Звуки в `sounds/sfx/` синтезирует `tools/make_sfx.py`.
- `_kit_original/` — исходная демо-сцена кита, игнорируется Godot (`.gdignore`).

## Проверки (запускать после изменений)
```
godot --headless --path . --import
godot --headless --path . res://tools/build_scenes.tscn              # если менялись генерируемые сцены
godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn # полный забег, ожидается 0 FAIL
godot --headless --path . --fixed-fps 60 res://tests/reach_test.tscn # достижимость платформ
godot --headless --path . --fixed-fps 60 res://tests/ai_test.tscn    # враги доходят и бьют во всех залах
godot --headless --path . --fixed-fps 60 res://tests/hitch_test.tscn -- 50  # фризы (CPU-часть)
```
Фризы с рендерингом (Forward+ на программном Vulkan: `apt-get install mesa-vulkan-drivers`):
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --fixed-fps 60 --rendering-method forward_plus --resolution 320x180 res://tests/hitch_test.tscn -- 50` (и то же с `gl_compatibility`). Прогон ~10 мин; кадры без событий — шум программного рендера, не считаются.
Скриншоты (нужен xvfb): `xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/screenshots.tscn -- <папка>`.

Экспорт: `godot --headless --path . --export-release "Windows Desktop" export/windows/ThorDostoynayaSmert.exe` (нужны export templates 4.6.3). Проверка сборки: `<exe> --headless -- --selftest`.

## Диалоги и сохранения (ночь 26.10, блоки А–В)
- `scripts/dialogue_manager.gd` (автозагрузка `Dialogue`) — сцены-новеллы и пулы коротких реплик из `data/dialogues/*.json` (по файлу на персонажа, формат — `STORY.md` → «Формат данных»). Выбор: самая приоритетная непросмотренная сцена события с выполненными условиями, иначе пул. Точки входа: `on_run_start`, `on_boss_intro`, `on_boss_defeat`, `after_run`, `run_trigger(событие, пул)`, `bark(реплика)`.
- `ui/dialogue_box.gd` — окно новеллы (портреты, имя, печать, выбор ответа Тора, «Пропустить», журнал); `ui/portrait.gd` — портрет `sprites/portraits/<speaker>_<emotion>.png` или процедурная заглушка; `ui/bark_bubble.gd` — пузырь в углу для не-Одина.
- `run/odin.gd` (`Odin`) — тонкая обёртка: `Odin.say(событие)` = пузырь HUD из пула `odin.<событие>`, лимит 12 с в бою.
- `run/run_tracker.gd` (`RunTracker`, узел в сцене игры) — время забега, причина смерти, «ДВИГАЙСЯ!»/мульти-килл/«Скуф…». **Источник урона по Тору:** перед `player.take_damage()` вызывай `RunTracker.note_damage("barrel")` или `RunTracker.note_hit(enemy)` (id из `enemy_id`/`death_source_id`/`kind`). Падение определяется само.
- `scripts/save_game.gd` (автозагрузка `Save`) — `user://save.json` с версией и миграцией. Тесты (`res://tests/*`) и `--selftest` пишут в `user://test_save.json`.
