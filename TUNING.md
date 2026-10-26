# TUNING — где крутить «ощущения»

Все числа — `@export`-поля: открой сцену в Godot, выдели узел, меняй в инспекторе. Код трогать не нужно.

## Игрок — `player/player.tscn`, узел **Player** (`player/player.gd`)

| Группа | Параметр | По умолчанию | Что делает |
|---|---|---|---|
| Бег | `move_speed` | 8 | Базовая скорость (тело её переопределяет: Берсерк 7.5, Охотник 10, Трэлл 8.5) |
| Бег | `ground_accel` / `ground_decel` | 70 / 55 | Разгон и торможение на земле. Больше — «отзывчивее» |
| Бег | `air_accel` | 28 | Управление в воздухе |
| Бег | `air_overspeed_drag` / `ground_overspeed_drag` | 6 / 18 | Как быстро гасится скорость после рывка |
| Прыжок | `jump_velocity` | 9.0 | Высота прыжка (~1.7 м) |
| Прыжок | `extra_jumps` | 1 | Сколько прыжков в воздухе |
| Прыжок | `gravity` / `fall_gravity_mult` | 24 / 1.35 | Вес персонажа; падение тяжелее подъёма |
| Прыжок | `coyote_time` / `jump_buffer` | 0.1 / 0.1 | Прощение поздних/ранних нажатий |
| Рывок | `dash_speed` / `dash_duration` | 24 / 0.16 | Сила и длина рывка |
| Рывок | `dash_recharge` | 1.2 | Перезарядка одного заряда |
| Рывок | `dash_invuln` | 0.15 | Неуязвимость в начале рывка |
| Рывок | `dash_exit_keep` | 0.55 | Сколько скорости остаётся после рывка |
| Приземление | `slam_speed` | 34 | Скорость падения при Ctrl |
| Приземление | `slam_base_radius` + `slam_radius_per_meter` | 3.5 + 0.25/м | Радиус волны растёт с высотой |
| Приземление | `slam_base_damage` + `slam_damage_per_meter` | 20 + 3/м | Урон волны |
| Приземление | `slam_base_knockback` + `slam_knockback_per_meter` | 10 + 0.8/м | Отбрасывание |
| Супер-прыжок | `super_jump_window` | 0.25 | Окно после приземления |
| Супер-прыжок | `super_jump_height_mult` | 2.5 | Во сколько раз выше обычного |
| Здоровье | `heal_per_kill` | 3 | Лечение за убийство |
| Толчки | `push_force` | 1.6 | Как сильно игрок толкает бочки |

## Камера — `player/player.tscn`, узел **Head/Camera** (`player/camera_fx.gd`)

`base_fov` 85, `fov_per_overspeed` 0.9 (FOV растёт от скорости), `shake_max_offset` 0.22, `shake_max_roll_deg` 4, `shake_decay` 1.8, `head_bob_enabled`, `head_bob_amount` 0.05, `strafe_tilt_enabled`, `strafe_tilt_deg` 2.5.

## Топор — узел **Axe** (`weapons/axe.gd`)

Массивы по ступеням комбо [1-й, 2-й, 3-й удар]:
`stage_damage_mult` [1, 1, 2.2], `stage_knockback` [7, 7, 16], `stage_knock_up` [2, 2, 5.5],
`stage_windup` [0.06, 0.06, 0.12], `stage_active` [0.11, 0.11, 0.13], `stage_recovery` [0.14, 0.14, 0.32],
`stage_hitstop` [0.045, 0.045, 0.085], `stage_shake` [0.18, 0.18, 0.42].
Плюс `base_damage` 22, `combo_window` 0.38, `reflect_speed_mult` 1.8.
Позы замаха — константа `POSES` в начале скрипта (позиция/поворот вьюмодели).
Хитбокс — узел **Head/Camera/AxeHitbox** (ShapeCast3D, коробка 2.6×2×1.6).

## Мьёльнир — узел **Mjolnir** (`weapons/mjolnir_hand.gd`)

База по GDD 10: `throw_speed` 32, `base_damage` 33 (1.5 У), `max_range` 25 м (дальше — возврат), `auto_return_after` 1.5 с (полёт без попадания в стену), `sticks_to_world` вкл. (втыкается в стену/пол), `stuck_auto_return` 0.8 с (сколько воткнутый молот ждёт ПКМ; трейты «на воткнутый» продлевают до 3–5 с; 0 — ждёт всегда), `return_speed` 36, `return_turn_accel` 140 (дуга возврата), `max_wall_bounces` 0 (было 2: теперь отскоки даёт Рикошет), `chain_targets` 0 (базовой молнии нет — это трейт), `chain_damage_ratio` 0.5, `chain_radius` 7, `hit_hitstop` 0.04.
Без молота: `dash_recharge_bonus` 0.2 (рывок перезаряжается на 20 % быстрее). Идеальный хват: `perfect_window` 0.15 с (ПКМ до или после поимки), `perfect_damage_mult` 2.

## Трейты Мьёльнира — `weapons/mjolnir_traits/*.tres`

Открой `.tres` → поле **handler** → там числа трейта (ур. 1 / ур. 2). Название, описание, руна, цвет, группа — в самом `.tres`. Новый трейт: скопируй `.tres` и скрипт-обработчик (наследник `MjolnirTraitHandler`), поменяй — в игре появится сам.

| Трейт | Группа | Главные числа |
|---|---|---|
| Огненный след | след | `spacing` 1.8 м, `radius` 1.1 / 1.6, `duration` 3 / 5 с, `dps` 6.6 (0.3 У/с), `max_zones` 10, свет у каждого `light_every` 3-го |
| Притяжение к молоту | возврат | `speed` 30, `max_time` 1.2 с, `damage` 22 (1 У), `hit_radius` 1.6, `knockback` 11, `exit_up` 10, `mantle_height` 2.2 м (залезть на уступ над молотом), `stuck_hold` 3 с; ур. 2 — `arrive_slam_*` |
| Магнит | возврат | `radius` 6 / 9 м, `pull_speed` 7, `hold_distance` 1.6, `boss_factor` 0.25, `blast_damage` 11, `blast_knockback` 15, `stuck_hold` 3 с |
| Бумеранг | возврат | `speed_mult` 1.25, `loop_time` 0.5 с, `turn_rate` 3.6 рад/с; ур. 2 — две петли |
| Цепная молния | попадание | `targets` 3 / 5, `damage` 11 (0.5 У), `radius` 7 м |
| Рикошет | воткнулся | `ricochets` 3 / 5, `seek_radius` 14 м |
| Громоотвод | воткнулся | `interval` 1 / 0.6 с, `radius` 4 м, `damage` 15, `stuck_hold` 5 с |
| Буря | бросок | `hold_delay` 0.18 с, `duration` 3 / 5 с, `radius` 3, `tick` 0.3 с, `tick_damage` 11; ур. 2 — `pull_speed_lvl2` 5, `pull_radius_lvl2` 7 |
| Землетрясение | — | `trigger_distance` 5 м, `wave_delay` 0.12 с, `radius_mult`/`damage_mult` 1 (от удара-приземления игрока); ур. 2 — третья волна `third_wave_*` |
| Гром небесный | — | `max_distance` 40, `radius` 3, `damage` 33; ур. 2 — `stun_time_lvl2` 1 с |

Правила (GDD 10): трейт той же группы заменяет старый (на экране выбора — второе нажатие), повтор — уровень 2, на уровне 2 больше не выпадает, в одном предложении нет двух трейтов одной группы.

## Мини-босс — `enemies/minibosses/fat_sven.tres` (`MinibossDef`)

Толстый Свен (заглушка): `max_health` 550 (25 У), `move_speed` 4.2, `knock_resist` 0.6, `attack_damage` 18, `windup_time` 0.75, удар по площади `slam_radius` 4.5 / `slam_damage` 20 / `slam_windup` 0.9, `far_slam_chance` 0.004 (за кадр, издалека; у финального босса `boss_far_slam_chance` 0.02), `glory` 50, вид `model_scale` 1.5 × `fatness` 1.35, свита `escort_count` 2.

## Враги — `enemies/grunt.tscn`, `thrower.tscn`, `boss.tscn` (`enemies/enemy.gd`)

| | Грунт | Метатель | Босс |
|---|---|---|---|
| `max_health` | 60 | 40 | 480 |
| `move_speed` | 4.4 | 3.8 | 3.6 |
| `attack_damage` | 12 | 10 (снаряд) | 20 / удар по площади 25 |
| `windup_time` (телеграф) | 0.6 | 0.55 | 0.8 / 1.0 |
| `knock_resist` | 0 | 0 | 0.75 |

Ещё: `wall_splat_speed` 8.5 (с какой скорости отбрасывания враг «шмякается» об стену), `wall_splat_damage` 12, `wall_splat_stun` 1.0, `keep_min_dist`/`keep_max_dist` 8/12 (метатель), `boss_slam_radius` 6.5. **Удар босса по площади попадает, только если ты на земле — прыгай!**

Трупы: `max_debris` 10 (сколько «рэгдоллов» лежит одновременно, лишние исчезают), `debris_lifetime` 4 с.

## Залы — `rooms/*.tscn`, корневой узел (`rooms/room.gd`)

`wave_delay` 0.9 (пауза между волнами), `spawn_interval` 0.12 (враги волны появляются по одному с этим шагом — сборка персонажа дорогая, все сразу давали фриз).

## Комиксовые слова — автозагрузка `scripts/comic_fx.gd` (`ComicFX`)

Поля `@export` в начале скрипта (автозагрузка — правятся в коде). Словарь, цвета букв/«взрыва» и приоритеты событий — `data/comic_words.json`. Рисованный «взрыв» — положи `sprites/comic/<событие>.png` (как есть) или общий `sprites/comic/burst.png` (красится цветом события).

| Группа | Параметр | По умолчанию | Что делает |
|---|---|---|---|
| Когда | `cooldown` | 0.4 с | Минимум между словами (крупные — без кулдауна) |
| Когда | `max_on_screen` | 3 | Слов на экране одновременно; крупное вытесняет самое старое |
| Когда | `multikill_window` / `multikill_count` / `multikill_big_count` | 0.5 с / 3 / 5 | Мульти-килл: слово / крупное на весь экран |
| Когда | `slam_min_height` | 0 м | Ниже — удар-приземление без слова |
| Когда | `big_slam_height` | 10 м | С этой высоты — крупное слово на весь экран |
| Когда | `big_slam_hitstop` | 0.15 с | Hit-stop удара с 10+ м (GDD 7.4; работает и при выключенных словах) |
| Когда | `lightning_kill_only` | true | Цепная молния даёт слово, только если убила |
| Вид | `font_size` / `big_font_size` | 96 / 160 | Размер шрифта Bangers (обычные / крупные) |
| Вид | `outline_px` | 22 | Чёрная обводка букв |
| Вид | `world_scale` / `screen_scale` / `big_scale` | 0.7 / 0.62 / 1.0 | Масштаб: над точкой в мире / по игроку (OOF!) / на весь экран |
| Вид | `finisher_kill_scale` | 1.2 | Добивание крупнее крита |
| Вид | `scale_jitter` / `tilt_deg` | ±0.12 / ±15° | Разброс размера и наклона |
| Вид | `burst_points`, `burst_pad`, `burst_spike`, `burst_outline_px` | 13, (22, 26), (1.12, 1.42), 8 | Форма процедурного «взрыва» |
| Вид | `world_lift_px` / `world_jitter_px` | 30 / 45 | Слово выше точки удара и случайный сдвиг |
| Вид | `vignette_alpha` | 0.85 | Виньетка под крупным словом |
| Анимация | `pop_in_time` / `pop_overshoot` | 0.1 с / 1.3 | Появление 0 → 1.3 → 1.0 (реальное время — видно во время hit-stop) |
| Анимация | `shake_time` / `shake_px` / `shake_deg` | 0.15 с / 7 / 3° | Дрожь |
| Анимация | `hold_time` / `fade_time` / `rise_px` | 0.05 / 0.15 с / 40 | Пауза и исчезновение с подъёмом (игровое время — во время стопа слово «стоит») |
| Анимация | `big_time_mult` | 2.2 | Крупные слова живут дольше |

Игрок может выключить слова и поменять их размер (50–160 %) в паузе и в «Настройках» главного меню; сохраняется в `user://settings.cfg`, секция `[comic]`.

## Отладка — автозагрузка `scripts/perf.gd` (`Perf`)

F3 — оверлей кадров. `hitch_ms` 33: кадр дольше этого пишется в `user://hitches.log`.

## Забег — автозагрузка `run/run_manager.gd`

`rooms_per_run` 4, `miniboss_rooms` [1, 3] (в каких залах, считая с 0, последней волной выходит мини-босс → выбор трейта), `miniboss_def_path`. Слава: `glory_per_kill` 10, `glory_combo_finisher_bonus` 5, `glory_multikill_bonus` 15, `glory_wall_splat_bonus` 5, `glory_room_clear` 25, `glory_boss_kill` 150. Пороги вердикта — функция `verdict()` (150 «Сойдёт», 400 «Вальхалла»).

## Тела и руны — ресурсы `run/bodies/*.tres`, `run/runes/*.tres`

Дублируй файл → поменяй поля в инспекторе → новое тело/руна появится в игре само. Эффекты рун по `id` — в `player.gd → recalc_from_runes()` и `scenes/game.gd → _on_rune_picked()`.

## Реплики Одина — `data/odin_lines.json`

Обычный JSON: событие → список фраз. Добавляй сколько хочешь.
