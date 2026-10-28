# scripts/ — автозагрузки и общие системы: эффекты, звук, графика мира, настройки, сохранения, диалоги

Перед правкой эффектов и материалов перечитай «Фризы» в корневом `CLAUDE.md`.

## Что здесь (автозагрузки помечены)
| Файл | Класс / автозагрузка | Роль |
|---|---|---|
| `fx.gd` + `fx/*.gd` | `FX` (фасад) + модули | hit-stop, цифры урона, молнии, кольца, искры, текстурные эффекты, декали |
| `vfx_screen.gd`, `vfx_tuning.gd` | `VfxScreen`, `VfxTuning` | экранные эффекты; числа `data/vfx_tuning.tres` |
| `comic_fx.gd` + `comic/*.gd` | `ComicFX` (авто; класс `ComicWords`) | комиксовые слова-удары |
| `music.gd` | `Music` (авто) | адаптивная музыка |
| `audio.gd` | `Audio` | звуки, голос, подмена синтеза записями владельца |
| `perf.gd` | `Perf` (авто) | F3-оверлей, отчёт о лаге, лог фризов |
| `asset_cache.gd` | `AssetCache` | загрузка и удержание моделей/анимаций/звуков |
| `shader_warmup.gd` | `ShaderWarmup` | прогрев шейдеров при входе в зал |
| `outline.gd`, `outline_tuning.gd` | `Outline` | комиксовая обводка |
| `world_art.gd`, `world_art_tuning.gd` | `WorldArt` | небо, свет, атмосфера, кеш материалов декора |
| `weapon_meshes.gd` | `WeaponMeshes` | модели оружия (см. `weapons/CLAUDE.md`) |
| `settings.gd` | `GameSettings` | все настройки GDD 22 |
| `dialogue_manager.gd` + `dialogue/*.gd` | `Dialogue` (авто; класс `DialogueManager`) | сцены-новеллы и пулы реплик |
| `save_game.gd` | `Save` (авто) | сохранение |
| `i18n.gd` | `I18n` | язык, `I18n.t()` в статических функциях |

## Эффекты (`fx.gd`)
**Устройство** (этап 5 рефакторинга): `FX` — фасад, все вызовы в игре — `FX.xxx`; в `fx.gd` — всё состояние (`static var`), константы, `tree()` и однострочные обёртки. Реализация — статические модули `fx/` (их зовут только `FX` и друг друга):

| Модуль | Что внутри |
|---|---|
| `fx/fx_time.gd` — `FXTime` | hit-stop, `slowmo`, `tick`, `real_delta`, `_set_time_scale`, `reset_time` |
| `fx/fx_basic.gd` — `FXBasic` | `damage_number`, `lightning`, `burst`, `ring`, `sparks`, `make_material` |
| `fx/fx_shared.gd` — `FXShared` | общие материалы `fx_material`/`fx_apply`, учёт instance uniform, затухание в GL (`sync_fades`), `shared_mesh` |
| `fx/fx_sprite_kit.gd` — `FXSpriteKit` | VFX-комплект: `cfg`, `sprite_material`, прогрев, пулы `FXSprites`, параметры экземпляра, спрайты на полу |
| `fx/fx_impacts.gd` — `FXImpacts` | `hit_flash`, `spark_star`, ихор, `smoke`, `explosion`, `shockwave`, `crack`, `scorch`, `slam_impact`… |
| `fx/fx_elements.gd` — `FXElements` | `fire_sprites`, ленты молнии, `ice_hit` |
| `fx/fx_enemy_hooks.gd` — `FXEnemyHooks` | `enemy_hit`, `enemy_died`, `is_undead`, `perfect_catch` |

Новый эффект: функция в модуле своей темы + обёртка в `fx.gd`; новое состояние — `static var` в `fx.gd`.
- hit-stop (тикает из `Run._process`), цифры урона, молнии, кольца, искры. Материалы эффектов — общие (`FX.fx_apply`, шейдеры `shaders/fx_*.gdshader`, цвет per-instance), меши — общие (`FX.shared_mesh`).
- Hit-stop: `FX.real_delta(delta)` — реальная длительность кадра при `Engine.time_scale` ≠ 1 (delta кадра масштабирован значением на НАЧАЛО кадра).
- **VFX-комплект владельца** (`sprites/vfx/*.webp`, описание `sprites/ui/README_UI_VFX.md`, `data/ui_manifest.json`): текстурные эффекты — `FX.hit_flash/spark_star/ichor_splash/splat/smoke/shockwave/crack/slam_impact/ice_hit/fire_sprites`, ленты в `FX.lightning`, звёзды в `FX.sparks`; хуки врага — `FX.enemy_hit`/`FX.enemy_died` (ихор — у нежити, `FX.is_undead`). Один шейдер `shaders/fx_sprite.gdshader` (полосы-атласы, billboard в шейдере; instance `color` = оттенок+яркость в альфе, `sprite` = кадр/billboard/поворот/fps, в GL ещё `fade`; выделенный блок экземпляра занимает 16 ячеек), материал на текстуру — `FX.sprite_material(key)` (создаёт прогрев, живут вечно). Узлы — пулы с лимитами в узле `FXSprites` (top_level, `transient`). Числа — `data/vfx_tuning.tres` (`VfxTuning`).
- Экранные (линии скорости, виньетка берсерка, кольцо идеального хвата) — `vfx_screen.gd` (`VfxScreen.attach` в `Game._ready`, сам читает игрока; прячет процедурные дубли HUD; создаёт `CatchAssist`). «Взрывы» под словами — `comic_burst_01..06` + `shaders/comic_burst.gdshader` в `ComicFX`.
- Затухающие декали — пулы FX на `fx_sprite`: подпалина `FX.scorch` (огонь, взрыв), лужа браги (`FX.sprite_apply`, `FX.EXTRA_SPRITES`). Взрыв — `FX.explosion` (числа `explosion_*` в `data/vfx_tuning.tres`). Монета серебра — общий меш-диск и материал `FX`.
- Тест `tests/vfx_test.tscn`, кадры `tests/vfx_shots.tscn` (xvfb).

## Комиксовые слова (`comic_fx.gd`, автозагрузка `ComicFX`)
Устройство (этап 5): в `comic_fx.gd` — состояние, очередь и показ (`_request`, `_flush`, `_show`), кадр `_process`, внутренний класс `ComicWord`; компоненты `comic/`: `comic_hooks.gd` (`ComicHooks`, `ComicFX.hooks`: `pop` и хуки `on_*`), `comic_animator.gd` (`ComicAnimator`: анимация и проекция слова), `comic_assets.gd` (`ComicAssets`: данные JSON, материалы растра, шрифт, пул, прогрев глифов). Вызовы `ComicFX.pop/on_*` — обёртки.
`ComicFX.pop(event, pos, big)` и хуки `ComicFX.on_*` (однострочные вызовы в player/enemy/mjolnir/enemy_projectile). Словарь, цвета, приоритеты — `data/comic_words.json`; рисованные «взрывы» — `sprites/comic/<событие>.png` или `burst.png` (иначе процедурные); шейдеры `shaders/comic_halftone.gdshader`, `comic_vignette.gdshader`; шрифт `fonts/Bangers-Regular.ttf`. Рисуется в 2D (CanvasLayer 6) с проекцией точки мира; пул слов, общие материалы. Реже и не всегда на весь экран: кулдаун, `routine_chance`, `important_priority`, `fullscreen_events` (остальные — крупно в мире), масштаб от расстояния. Комикс-слова всегда английские (`words_<язык>` в `data/comic_words.json` — для своего языка). Тест `comic_test`.

## Музыка и звук
- `music.gd` (автозагрузка `Music`) — адаптивная музыка: слои `base/drums/full` трека из `sounds/music/<трек>/`, переходы в такт, фильтр на паузе/в диалоге, стингер на удар-приземление; трек и слой выбираются сами по сцене (`Music.auto`, `Music._auto_state`).
- **Звук владельца (ElevenLabs, блок Б6):** `sounds/owner/music/<трек>/` (важнее синтеза с тем же именем; слои — одна петля через НЧ-фильтр, **сменяют** друг друга, а не складываются), `sounds/owner/sfx/`, `sounds/voice/` — делает `tools/import_owner_audio.py <архив>` (нормализация, обрезка тишины); синтез `tools/make_sfx.py` туда не пишет и остаётся запасным (звуки в `sounds/sfx/` синтезирует он). Карта — `data/owner_audio.json`: `sfx` (имя синтеза или нового события → файл, pitch/db/min_interval; `Audio.play` подменяет сам, новое событие — `Audio.sfx(id, запасной путь)`), `music` (темп), `voice` (клип → кто/текст). Озвучка реплики — поле `"voice"` (id или массив дублей) у реплики в `data/dialogues/*.json`, `"sfx"` — звук при показе; играет `Dialogue.speak_line` (окно новеллы, пузырь, `Odin.say`), один голос за раз (`Audio.voice`, шина Voice); «Хха!»/«Ух!» — `Audio.thor_grunt/thor_pain`. Проверка — `audio_test`, `music_test`.

## Производительность и загрузка
- `perf.gd` (автозагрузка `Perf`) — F3-оверлей, F5 / кнопка в паузе «Сообщить о лаге» (zip с логом, сохранением и сведениями о системе на рабочий стол — `Perf.report_lag()`), лог фризов `user://hitches.log`, `Perf.mark("событие")` в игровом коде, счётчики компиляций пайплайнов (`pso_draw` = фриз на отрисовке). Тест `report_test`.
- `asset_cache.gd` (`AssetCache`) — загрузка и удержание моделей/анимаций/звуков (старт в `Run._ready`, ожидание в `Game._ready`); новые ассеты персонажей/оружия/звуков — в папки из `AssetCache.DIRS`, отдельные файлы — `AssetCache.FILES`. В GL/Vulkan по умолчанию загрузка фоновая; в `--headless` — синхронная: Dummy-рендерер может повредить RID при одновременной загрузке и создании ресурсов в других автозагрузках. Явный аргумент `sync_load` по-прежнему включает синхронную загрузку для замеров lavapipe. Проверки геометрии — `tests/headless_assets_test.tscn`, воспроизведение и полные логи — `docs/headless_loader_2026-10-27/README.md`.
- `shader_warmup.gd` (`ShaderWarmup`) — прогрев шейдеров при входе в каждый зал (под затемнением). Новый вид эффекта/материала — добавь сюда. Тест `shader_warmup_test`.

## Комиксовая обводка (блок Б1, GDD 20)
`outline.gd` (`Outline`) + `shaders/outline.gdshader` — «вывернутая оболочка» (cull_front, сдвиг по нормали в пикселях экрана, тоньше с расстоянием; `depth_draw_never` → проход прозрачных: без теней и prepass). **Один** `ShaderMaterial` на игру (`Outline.material()`), без instance-переменных (сам не добавляет их, но ранее выделенный блок узла может сохраняться до удаления RID), кладётся в `material_overlay`; у врагов слот делится со вспышкой: горит вспышка — оверлей `Enemy.FLASH_MATERIAL`, обводка — его `next_pass`, погасла — `Outline.overlay()` вместо null. Обводятся: враги/боссы (`EnemyVisual._collect_meshes`, бочка Свена, рука и голова Ярла), `Destructible` (узел `Model`), `WeaponPickup`, `AmmoPickup`, `Chest`, Мьёльнир в полёте; **стены, декор, руки от первого лица — нет** (руки — решение по кадрам). Новый вид — `Outline.add(узел_модели)` (не кольца/метки). Настройка `[video] outline` / `outline_width` (вкладка «Экран», вживую — `Outline.apply_settings`), числа — `data/outline_tuning.tres` (`OutlineTuning`). Прогрев — `ShaderWarmup` (`Outline.begin_warmup/end_warmup`: обводит образцы и при выключенной). **Не читай `Enemy.FLASH_MATERIAL.next_pass` напрямую** — GDScript сворачивает свойство константы при компиляции (всегда null): `Outline.flash_next_pass()`. Тест `tests/outline_test.tscn`, кадры `tests/outline_shots.tscn -- <папка>`, цена — `tests/perf_bench.tscn -- 8 outline`.

## Графика мира (`world_art.gd`)
Комплект владельца `assets/sky|decals|decor|textures/`, `docs/world_art/`; другие миры — в запасе, исключены из экспорта. `WorldArt`, числа — `data/world_art.tres` / `WorldArtTuning`.
- Небо и дымка мира — поля группы «Небо и атмосфера» в `run/maps/<мир>.tres` (`sky` — путь к панораме, `exposure`, `ambient_*`, `fog_*`, флаги `ground_fog`/`dust_motes`/`torch_embers`), применяет `WorldArt.apply_world` (`Game._ready`, копия окружения; без `sky` — процедурное небо сцены).
- Профиль графики зала — `Room.visual_map` (RunMap только для вида: небо с тонировкой `sky_tint*` — шейдер `shaders/panorama_tint.gdshader`, свет, туман, `room_outline_multiplier`/`room_halftone_multiplier`); применяет `Game._finish_room_load` при смене профиля, без профиля — `Run.map`. Генерируемые залы Мидгарда — `run/maps/midgard_slice.tres` (см. `rooms/CLAUDE.md`).
- Атмосфера зала — `WorldArt.dress_room` (`Game._load_room`): искры над `Torches/*` и очагом `Decor/Hearth` (+ языки пламени), пылинки, низкий туман (узел `Atmosphere`, CPUParticles3D).
- Рунные круги: прыжковые руны, двери-награды (`WorldArt.circle_for_color`).
- **Статичный декор/декали/частицы — StandardMaterial3D из кеша `WorldArt.material(key, kind)`, без instance uniform** (не тратят буфер GL Compatibility); новый вид — в `WorldArt.material_specs()` (прогрев).
- **Свет мира** (RunMap «Свет и цвет»): солнце — по диску панорамы (`sky_sun_uv` + `sky_rotation_deg`; середина панорамы = +Z), высота `sun_elevation_deg`; ACES, SSAO/SSIL, glow, объёмный туман, цветокоррекция `grade_*` — `WorldArt.apply_world`; зал под крышей (`Room.indoor`, длинный дом) — `WorldArt.apply_room` (`indoor_*`, солнце гаснет), тени факелов только в Forward+ (`torch_shadows`).
- Тест `world_art_test`, кадры `tests/world_art_shots.tscn -- <папка>`. Декор залов — `rooms/CLAUDE.md`.

## Настройки (`settings.gd`, `GameSettings`)
Все настройки GDD 22 в `user://settings.cfg` (секции `[audio] [controls] [video] [hud] [text] [access] [comic] [input] [pad_input]`; чужие секции сохраняются; тесты пишут в `user://test_settings.cfg`). `get_value/set_value(секция, ключ)` (set — сохраняет, применяет, шлёт `GameSettings.events.changed`), `apply_startup()` (из `Run._ready`: шины Master/Music/SFX/Voice, окно, клавиши, фильтр цветовой слепоты), `apply_to_player(p)` (из `Player._ready`: чувствительность, инверсия, FOV, тряска `CameraFX.shake_scale`, покачивание). Клавиши: `rebind` / `reset_input` — клавиатура/мышь, `rebind_pad` / `reset_pad_input` — геймпад и направления стиков независимо; Start зарезервирован, конфликтующие действия остаются доступными для переназначения. `note_input` из `Run._input` отслеживает последнее устройство, `current_binding` обновляет подсказки; A/B — подтверждение/назад в UI. Проверки — `tests/gamepad_test.tscn`, снимки 1280×800 — `tests/deck_shots.tscn`, ограничения — `docs/deck_2026-10-27/README.md`. Помощь: `aim_assist()` (`RangedWeapon.assisted_aim`), `slam_slowmo()` (`PlayerSlam._slam_assist_tick`), `catch_assist()`. UI — `ui/settings_panel.gd`.

## Диалоги (`dialogue_manager.gd`, автозагрузка `Dialogue`)
Устройство (этап 5): выбор, показ и точки входа — в `dialogue_manager.gd`; компоненты `dialogue/`: `dialogue_locale.gd` (`DialogueLocale`: перевод, `localize_line`), `dialogue_conditions.gd` (`DialogueConditions`: разбор и проверка условий), `dialogue_validator.gd` (`DialogueValidator`: проверка данных для `dialogue_test`).
Сцены-новеллы и пулы коротких реплик из `data/dialogues/*.json` (по файлу на персонажа, формат — `STORY.md` → «Формат данных»; `STORY.md` — сюжетная библия, черновик). Выбор: самая приоритетная непросмотренная сцена события с выполненными условиями, иначе пул. Точки входа: `on_run_start`, `on_boss_intro`, `on_boss_defeat`, `after_run`, `run_trigger(событие, пул)`, `bark(реплика)`, `speak_line`. Окна — `ui/dialogue_box.gd`, `ui/bark_bubble.gd`, Один — `run/odin.gd`. Перевод реплик — `Dialogue.localize_line` (`DialogueLocale`) (см. корневой `CLAUDE.md`, «Локализация»). Тест `dialogue_test`.

## Сохранение (`save_game.gd`, автозагрузка `Save`)
`user://save.json` с версией и миграцией. Тесты (`res://tests/*`) и `--selftest` пишут в `user://test_save.json`. `Save.is_in_pool(kind, id)`, `Save.target_exists`, `Save.perk(id)`, `Save.apply_permanent_to_body()` (см. `run/CLAUDE.md`, «Открытия»). Тест `save_test`.

## Тесты
`vfx_test`, `comic_test`, `audio_test`, `music_test`, `outline_test`, `world_art_test`, `shader_warmup_test`, `hitch_test`, `headless_assets_test`, `headless_prefetch_test`, `report_test`, `dialogue_test`, `save_test`, `i18n_test`, `gamepad_test`, `ui_test`.
