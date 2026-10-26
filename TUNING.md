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
| Отскок (GDD 7.2) | `slam_bounce_ratio` / `slam_bounce_min_height` | 0.6 / 1.2 м | Удар-приземление задел врага → подбрасывает на долю высоты падения (не ниже минимума), двойной прыжок восстанавливается |
| Отскок | `slam_bounce_window` / `slam_bounce_boost` | 0.2 с / ×1.6 | Пробел в окне после отскока — выше (по высоте) |
| По головам | `stomp_damage` / `stomp_stun` / `stomp_bounce_velocity` | 11 (0.5 У) / 0.8 с / 9.5 | Приземлился на врага без Ctrl — урон, стан, отскок; с ренжем не работает |
| Уступ | `ledge_min_height` / `ledge_max_height` | 0.75 / 2.2 м | Край над ступнями, на который Тор залезает сам (жми вперёд в стену) |
| Уступ | `ledge_climb_time` / `ledge_climb_ranged_mult` | 0.3 с / ×1.5 | Время залезания; с ренжем дольше |
| От стены | `wall_jumps` / `wall_jump_push` / `wall_jump_up` | 2 / 7 / 8.5 | Пробел в воздухе у стены — отскок; 2 раза до касания земли, двойной прыжок не тратит |
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

`rooms_per_run` 4. **Слава по GDD 15.2** (блок Г): база — Слава врага из `enemies/defs/*.tres` (корм 1, боец 3, особый 5), элита `glory_elite_kill` 15, босс `glory_boss_kill` 150, мини-босс — 50 (в `MinibossDef`); враг без описания — `glory_per_kill` 3. Множители: добивание мили ×1.5 (`glory_melee_kill_mult`), ренжем ×0.5 (`glory_ranged_kill_mult`), тело (`BodyDef.glory_mult`: Трэлл ×2, Солдат ×0.7). Бонусы: серия 10 убийств `glory_streak_bonus` +10, мультикилл `glory_multikill_bonus` +1 за каждого, шмяк об стену `glory_wall_splat_bonus` +1, зал зачищен `glory_room_clear` +5, финишер `glory_combo_finisher_bonus` 0. Вердикт — `verdict()` (80 «Сойдёт», 200 «Вальхалла»).

## Тела и руны — ресурсы `run/bodies/*.tres`, `run/runes/*.tres`

Дублируй файл → поменяй поля в инспекторе → новое тело/руна появится в игре само. Эффекты рун по `id` — в `player.gd → recalc_from_runes()` и `scenes/game.gd → _on_rune_picked()`.

## Реплики Одина — `data/dialogues/odin.json`, раздел `pools`

Событие → список реплик (`speaker`, `emotion`, `text`, `id`). Добавляй сколько хочешь; формат — в `STORY.md`.

## Диалоги — `ui/dialogue_box.gd`, `ui/bark_bubble.gd`, `scripts/dialogue_manager.gd`, `run/odin.gd`

| Где | Параметр | По умолчанию | Что делает |
|---|---|---|---|
| DialogueBox | `chars_per_second` | 48 | Скорость печати текста |
| DialogueBox | `punctuation_pause` | 0.12 | Пауза после . ! ? … |
| DialogueBox | `portrait_bounce` | 0.06 | «Подпрыгивание» портрета при смене эмоции |
| DialogueBox | `inactive_dim` | 0.45 | Затемнение неговорящего портрета |
| DialogueBox | `open_guard` | 0.25 | Защита от двойного клика после открытия |
| BarkBubble | `hold_time` / `max_hold_time` | 2.2 / 4.0 | Сколько держится пузырь в бою |
| Dialogue | `thor_reply_chance` | 0.4 | Шанс ответа Тора (с выбором) после реакции Одина на смерть |
| Dialogue | `visitor_chance` | 0.3 | Шанс, что к дивану заглянет знакомый персонаж (пулы `*.visit`) |
| Dialogue | `heimdall_chance` | 0.35 | Шанс реплики Хеймдалля на старте забега (после знакомства) |
| Odin | `combat_cooldown` | 12 | Реплика Одина в бою не чаще (GDD 17) |

## Бой-реплики и причина смерти — `run/run_tracker.gd`

`idle_time` 4 с / `idle_speed` 0.6 («ДВИГАЙСЯ!»), `multikill_count` 3 за `multikill_window` 0.8 с («Хоть что-то»), `big_damage_fraction` 0.35 HP за `big_damage_window` 3 с («Скуф…»), `quick_death_time` 45 с («быстро сдох»), `long_life_time` 420 с («долго жил»), `fall_death_y` −15 (ниже — смерть от падения).

Тексты — `data/dialogues/*.json`: правь прямо в JSON (формат в `STORY.md`).

## «План тренировок» — `run/unlocks/*.tres` (`run/unlock_def.gd`), `ui/training_plan.gd`

Цены и эффекты — в файлах открытий (инспектор): `price`, `amount` (для перков: `move_speed_pct` 0.05, `max_health` 20, `dash_charges` 1, `catch_window` 0.2, `start_silver` 30, `shop_discount` 0.15, `first_rune_level` 2), `requires`, `available` (перк уже работает). На экране: `card_height` 92, `glory_pulse_time` 0.25.
Слава за забег целиком уходит в копилку (`Save.data.glory.bank`).
Обычный JSON: событие → список фраз. Добавляй сколько хочешь.

## Оружие правой руки (этап 1) — `weapons/defs/*.tres` (`weapons/weapon_def.gd`)

Каждое оружие — отдельный ресурс: дублируй `.tres`, поменяй поля — оружие появится само (в пуле выпадения, если `in_drop_pool`). 1 У (GDD) = 22 урона.

| Оружие | Урон | Скорость | Бег | Особое | В пуле |
|---|---|---|---|---|---|
| Топор `axe` | 22 (1 У), комбо 3: ×1 ×1 ×2.2 | 1.0 | ×1.1 | — | да |
| Меч `sword` | 15.4 (0.7 У), комбо 4: ×1 ×1 ×1 ×1.8 | 1.3 | ×1.1 | `special = parry` (пока не сделано) | да |
| Дубина `club` | 28.6 (1.3 У) | 0.75 | ×1.0 | `stun_on_hit` 1.5 с, `knockback_mult` 1.6 | да |
| Копьё `spear` | 19.8 (0.9 У), тычки | 1.0 | ×1.05 | `reach` 1.8 (≈3.5 м), `max_targets` 3 | нет |
| Коса `scythe` | 17.6 (0.8 У) | 0.8 | ×1.0 | `arc` 1.8 (широкая дуга) | нет |
| Кирка `pickaxe` | 26.4 (1.2 У) | 0.75 | ×1.0 | `stunned_mult` 2 (×2 по оглушённым) | нет |
| Нож `knife` | 11 (0.5 У), тычки | 1.7 | ×1.2 | `backstab_mult` 3 | нет (старт Охотника) |
| Арбалет `crossbow` | 17.6 (0.8 У) | 1 / 12, ~0.95 с на выстрел | ×0.8 | `pierce` 1 | да |
| Пистолет `pistol` | 6.6 (0.3 У) | 8 / 40, 0.17 с | ×0.8 | точный | да |
| Пистолет-пулемёт `smg` | 3.3 (0.15 У) | 30 / 90, 0.07 с | ×0.8 | разброс растёт `spread_per_shot_deg` | нет |
| Автомат `rifle` | 5.5 (0.25 У) | 30 / 60, 0.1 с | ×0.8 | `recoil_climb_deg` 0.35 — прицел уходит вверх | нет |
| Обрез `shotgun` | 6 × 2.64 (0.12 У) | 2 / 16, перезарядка 1.6 с | ×0.8 | дробь, `spread_deg` 6 | нет |

Поля мили: `attack_speed` (делитель базовых таймингов топора), `reach` (ход хитбокса вперёд), `arc` (ширина хитбокса), `combo_count`, `stage_damage_mult`, `swing_set` (slash/thrust), `knockback_mult`, `max_targets`, `stun_on_hit`, `backstab_mult` (в спину, по умолчанию 1.5), `stunned_mult`, `heavy_damage_mult` 2 / `heavy_windup` 0.4 (сильный удар — зажать ЛКМ), `hitstop_mult`.
Поля ренжа: `fire_interval`, `automatic`, `pellets`, `spread_deg` / `spread_per_shot_deg` / `spread_max_deg` / `spread_recover`, `recoil_kick_deg` (отдача камеры), `recoil_climb_deg`, `mag_size`, `reserve_start` / `reserve_max`, `reload_time`, `pierce`, `max_range`, `fire_move_mult` 0.65 (бег во время стрельбы), `tracer` / `tracer_speed`, `shell_casing`, `muzzle_offset`.
Общие: `move_speed_mult` (мили ≥ 1, ренж 0.8), `dash_recharge_mult` (ренж 1.3 — рывок на 30 % дольше), вид в руке `view_*`, на полу `pickup_scale`.
**Уровень оружия 1–3:** +20 % урона за уровень (`WeaponDef.level_mult`).

### Узел **Weapons** игрока (`weapons/weapon_holder.gd`)
`switch_time` 0.25 (свитч), `auto_switch_on_empty` (пустой ренж без запаса → мили), `auto_reload`, `interact_radius` 2.4 (подбор по E), `ammo_pickup_radius` 1.4, `ammo_box_fraction` 0.4 (ящик = 40 % запаса), `ammo_drop_chance` 0.15 (метатели ×2), `drop_all_weapons` false (true — в пуле всё оружие, а не только стартовое GDD), `drop_level2_chance` 0.2 / `drop_level3_chance` 0.05, `fire_slow_time` 0.3 (сколько длится замедление «при стрельбе»), `prop_bullet_impulse` 1.2, `max_casings` 24, `casing_lifetime` 2, `max_tracers` 40, `bolt_stick_time` 1.5.

### Мили-удары — узел **Axe** (`weapons/axe.gd`)
Базовые тайминги и отдача (массивы ступеней выше) — общие для всего мили; оружие масштабирует их своим `attack_speed`. Урон теперь берётся из `WeaponDef.damage` (поле `base_damage` — только запасной вариант без оружия).
Сильный удар: `heavy_hold_time` 0.28 (сколько держать ЛКМ), `heavy_active` 0.14, `heavy_recovery` 0.36, `heavy_knockback` 15, `heavy_knock_up` 6, `heavy_hitstop` 0.09, `heavy_shake` 0.45.

### Прочее
- Камера: `recoil_return_speed` 14 (как быстро гаснет отдача).
- Игрок: `melee_kill_heal` 2 (добивание мили лечит 3 + 2 HP).
- Забег: `glory_melee_kill_mult` 1.5, `glory_ranged_kill_mult` 0.5 (Слава за убийство мили/ренжем).
- Залы: `elite_chance` 0.1, `max_elites` 1 (элита: ×2.5 HP, урон ×1.5, золотая метка, роняет оружие 60 % мили / 40 % ренж), `chest_chance` 0.5 (сундук после зачистки; в первом зале всегда, у босса нет).

## Данные по GDD (блок Г)

- **Враги** — `enemies/defs/*.tres` (`EnemyDef`): HP в «У» (`hp_u`, 1 У = 22), скорость, урон, слой, мир, Слава, серебро. Применяются к врагам, которые уже есть (`game_kind` grunt → драугр-воин 2.5 У / 4.4 / 12; thrower → метатель 1.5 У / 3.8 / 15). Остальные — `implemented = false`, ждут блока З.
- **Руны** — `run/runes/*.tres` (`RuneDef`): `category`, `level_descriptions` (ур. 1–3), `implemented`. Руны без механики не выпадают.
- **Тела** — `run/bodies/*.tres` (`BodyDef`): + `movement_style`, `passive`, `flaw` (`run/passives/*.tres`, `PassiveDef`), `price`, `odin_comment`. 9 тел по GDD 6, закрытые открываются в «Плане тренировок».
- Генератор сцен больше не перезаписывает существующие `run/bodies` и `run/runes` — это данные, правь их в инспекторе.

## Музыка — автозагрузка `scripts/music.gd` (`Music`), треки `sounds/music/<трек>/<слой>.ogg`

`bpm` 120, `beats_per_bar` 4 (переходы слоёв — на доле, треков — на такте), `volume_db` −6, `layer_fade` 0.6 с, `track_fade` 1.2 с, `muffle_cutoff_hz` 650 (пауза, диалог, смерть), `stinger_min_power` 0.6 (удар-приземление с такой силой — стингер), `stinger_duck_db` −18 / `stinger_duck_time` 0.18 с (провал музыки под стингер; во время hit-stop длится дольше).
Слои: `base` (фон: бас и пэды) → `drums` (бой: есть живые враги) → `full` (Ярость: у игрока `is_berserk()`). Треки: `menu`, `plan` («План тренировок»), `midgard`, `miniboss`, `boss`, `shop` (включается `Music.play_track("shop")`).
Заглушки синтезирует `python3 tools/make_sfx.py music` (нужен ffmpeg). Настоящие треки — положить файлы с теми же именами (.ogg или .wav), все слои трека одной длины.

## Портреты — `sprites/portraits/<speaker>_<emotion>.webp|png`, `ui/portrait.gd`, `ui/dialogue_box.gd`

Окно диалога: `portrait_size` 440×660 (пропорции спрайтов 2:3), `portrait_bottom` 40 (низ портрета уходит под плашку текста). Пузырь реплики: крупный план лица, `face_crop` 0.34 (сторона квадрата в долях ширины холста), центр — глаза из `data/portrait_faces.json`. Импорт портретов: WebP с потерями 0.85, не больше 1024 по высоте (иначе сборка выросла бы на ~70 МБ).

