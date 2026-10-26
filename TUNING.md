# TUNING — где крутить «ощущения»

Все числа — `@export`-поля: открой сцену в Godot, выдели узел, меняй в инспекторе. Код трогать не нужно.

## Игрок — `player/player.tscn`, узел **Player** (`player/player.gd`)

| Группа | Параметр | По умолчанию | Что делает |
|---|---|---|---|
| Бег | `move_speed` | 8 | Базовая скорость (тело её переопределяет: Берсерк 7.5, Охотник 10, Трэлл 8.5) |
| Бег | `ground_accel` / `ground_decel` | 70 / 55 | Разгон и торможение на земле. Больше — «отзывчивее» |
| Бег | `air_control` | 0.7 | Управление в воздухе — доля от наземного разгона (GDD 7.4: 70 %; было `air_accel` 28 ≈ 40 %) |
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
| Пике | `dive_window` / `dive_horizontal_speed` / `dive_down_speed` | 0.35 с / 20 / 24 | Ctrl во время рывка в воздухе или ≤0.35 с после — удар-приземление наклонно по взгляду |
| Отмена удара-приземления | `slam_cancel_by_dash` | вкл | Shift во время падения — обычный рывок, удара нет |
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
| Ледяной след | след | `spacing` 1.8 м, `radius` 1.3, `duration` 4 с, падение — стан `fall_stun` 0.5 / 1 с, толчок `slide_push` 6, `max_zones` 12 (`weapons/ice_zone.gd`) |
| Тяжесть | попадание | стан `pin_time` 1.5 с; ур. 2 — всем в `splash_radius` 2 м |
| Два молота | бросок | копии веером через `spread_deg` 12°, каждый молот ×`damage_mult` 0.6; копии без трейтов, не втыкаются |
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

Толстый Свен: `max_health` 550 (25 У), `move_speed` 4.2, `knock_resist` 0.6, `attack_damage` 18, `windup_time` 0.75, удар по площади `slam_radius` 4.5 / `slam_damage` 20 / `slam_windup` 0.9, `far_slam_chance` 0.004 (за кадр, издалека; у финального босса `boss_far_slam_chance` 0.02), `glory` 50, вид `model_scale` 1.5 × `fatness` 1.35, свита `escort_count` 2. Реплики: `intro_pool` «sven.intro», `death_pool` «sven.death» (`data/dialogues/sven.json`).

Своя механика Свена (блок Н) — `enemies/sven.tscn`, скрипт `enemies/bosses/sven.gd` (`FatSven`, поверх `BossEnemy`):
- **Таран на бочке:** телеграф `charge_aim_time` 0.9 с (красная полоса на полу; направление замирает после `charge_lock_at` 0.7), `charge_speed` 15, `charge_max_dist` 20, `charge_damage` 22, `charge_knock` 13, `charge_cooldown` 6, не ближе `charge_min_dist` 4.5 м; врезался в стену — оглушён `charge_wall_stun` 1.8 с (урон по нему ×1.5). Перепрыгнуть: ноги выше `charge_jump_clear` 1.0 м (`BossEnemy`).
- **Брага:** `spit_cooldown` 5, замах `spit_windup` 0.65, `spit_count` 3 плевка, разброс `spit_spread` 2.4 м, полёт `spit_flight_time` 0.85 / дуга `spit_arc` 3, прямое попадание `spit_damage` 6; лужа `puddle_radius` 1.8 м, `puddle_time` 7 с, скорость Тора в луже ×`puddle_slow` 0.55 (`PlayerSlow`, как у элиты «Ледяной»), не больше `BrewPuddle.max_puddles` 8.
- **Раздувание:** с `swell_hp_fraction` 0.25 HP бежит ×`swell_speed_mult` 1.4 к Тору (не дольше `swell_max_time` 6 с), раздувается на `swell_amount` 0.5; ближе `fuse_range` 3 м — фитиль `fuse_time` 1.1 с (красный круг), взрыв `blast_radius` 5 / `blast_damage` 30 — его конец. Убит раздутым — взрыв ×`death_blast_mult` 0.6 через 0.45 с.
- Арена — `rooms/sven_arena.tscn` (генератор, «Пивной погреб Свена»): `Run.miniboss_arena` подменяет ею зал мини-босса (`Run.miniboss_rooms`); пусто — Свен выходит последней волной обычного зала.

## Ярл Бьорн — `enemies/jarl.tscn` (`enemies/bosses/jarl.gd`), числа GDD — `enemies/defs/jarl.tres`

60 У = 1320 HP, `move_speed` 3.6, удар 25 (`attack_range` 3.6 — широкий замах), удар по площади `boss_slam_radius` 6 / 30, `knock_resist` 0.85. Фазы: `phase2_at` 0.66, `phase3_at` 0.33, рёв `roar_time` 1.2 с.
- **Рука-бумеранг:** `throw_cooldown` 6, бросает дальше `throw_min_dist` 6 м, замах `throw_windup` 0.75, `arm_damage` 20 (туда и обратно), окно `arm_window` 3 с, дальность `arm_range` 16. Урон по Ярлу: с рукой ×`armed_damage_mult` 0.7, в окнах (без руки, сбит, оглушён) ×`window_damage_mult` 1.5.
- **Балкон:** прыжок `leap_time` 1.0 / `leap_height` 4; наверху урон ×`perch_damage_mult` 0.2, сбивают `slam`/`stomp`/`hammer`/`lightning` → оглушён `knocked_stun` 3 с; корм `summon_count` 4 раз в `summon_interval` 5 с (не больше `summon_cap` 16 врагов); снова наверх через `perch_return_time` 12 с; подошёл наверху ближе `perch_swat_range` 2.6 — отмахивается `perch_swat_damage` 15 (раз в 1.8 с).
- **Ярость:** балконы по одному раз в `break_interval` 0.7 с (тряска `Balcony.shake_time` 0.45, `debris_count` 6 досок на `debris_lifetime` 4 с); бодание — телеграф `butt_aim_time` 0.8, `butt_speed` 14, `butt_max_dist` 22, `butt_damage` 30, о стену — оглушён `butt_wall_stun` 2 с, `butt_cooldown` 2.5; прыжок с волной `slam_leap_cooldown` 7, `slam_leap_time` 1.1, `slam_leap_radius` 5, `slam_leap_damage` 25 (только по стоящему на земле); бег ×`phase3_move_mult` 1.25.

## Враги — `enemies/grunt.tscn`, `thrower.tscn`, `boss.tscn` (`enemies/enemy.gd`)

| | Грунт | Метатель | Босс |
|---|---|---|---|
| `max_health` | 60 | 40 | 480 |
| `move_speed` | 4.4 | 3.8 | 3.6 |
| `attack_damage` | 12 | 10 (снаряд) | 20 / удар по площади 25 |
| `windup_time` (телеграф) | 0.6 | 0.55 | 0.8 / 1.0 |
| `knock_resist` | 0 | 0 | 0.75 |

Ещё: `wall_splat_speed` 8.5 (с какой скорости отбрасывания враг «шмякается» об стену), `wall_splat_damage` 12, `wall_splat_stun` 1.0, `keep_min_dist`/`keep_max_dist` 8/12 (метатель), `boss_slam_radius` 6.5, `fall_kill_height` 6 / `fall_damage` 44 / `fall_hit_window` 1.5 с (сброшенный после удара с 6+ м: корм насмерть, остальным 2 У; сам спрыгнувший — без урона), отражённый снаряд — ×1.8 (`REFLECT_DAMAGE_MULT` в `enemy_projectile.gd`). **Удар босса по площади попадает, только если ты на земле — прыгай!**

Трупы: `max_debris` 10 (сколько «рэгдоллов» лежит одновременно, лишние исчезают), `debris_lifetime` 4 с.

## Враги Мидгарда (блок З, GDD 12.1) — `enemies/fodder.tscn`, `bloated.tscn`, `shieldbearer.tscn`, `shaman.tscn`, `merc.tscn`

HP / скорость / урон / Слава — из `enemies/defs/*.tres` (`EnemyDef`, 1 У = 22), остальное — `@export` в сцене (`enemies/enemy.gd`).

| | Корм | Раздутый | Щитоносец | Шаман | Наёмник Локи |
|---|---|---|---|---|---|
| HP (`hp_u`) | 0.8 У = 17.6 | 1 У = 22 | 4 У = 88 | 2 У = 44 | 2 У = 44 |
| `move_speed` | 3.5 | 5 | 3 | 3 | 4 |
| урон (`damage`) | 5 | 44 (2 У) взрыв | 15 + толчок | — (лечит) | 15 × `merc_bullet_mult` 0.5 = 7.5 за пулю |
| `windup_time` (телеграф) | 0.55 | `boss_slam_windup` 0.7 (фитиль, диск радиусом взрыва) | 0.75 | 1.0 (обряд: зелёное кольцо) | 0.8 (лазер) |
| `knock_resist` | 0 | 0.2 | 0.6 | 0.1 | 0 |

- **Корм:** одна модель (тело + один комплект одежды, без оружия/волос/случайной сборки), мычит реже (15 % замахов).
- **Раздутый:** `bloat_trigger_range` 2.4 (с какой дистанции поджигает фитиль), `boss_slam_radius` 3 (радиус взрыва), `bloat_fatness` 1.55, `bloat_swell` 0.3 (раздувание к взрыву). Взрывается и от смерти — бьёт своих в радиусе. Подорвался сам — Славы нет.
- **Щитоносец:** `shield_front_dot` 0.3 (щит закрывает ±72° спереди), `shove_force` 13 / `shove_up` 2.5 (толчок удара щитом), `turn_speed` 2.6 (медленно разворачивается — обходи). Проходят: удар-приземление, по головам, Тор выше на 1.6 м, сзади/сбоку, кирка (`WeaponDef.special = "armor_break"`), огонь, молнии, взрывы; оглушённый щит не держит.
- **Шаман:** `ritual_interval` 6 с, `ritual_heal_radius` 12 м, `ritual_heal_fraction` 0.35 (доля max HP), `ritual_raise_count` 2 (корма за обряд), `ritual_raise_cap` 30 (не поднимает, если врагов уже столько), `shaman_flee_dist` 5 (отходит, но с края не прыгает).
- **Наёмник:** `merc_aim_track` 7 (как быстро лазер догоняет Тора), `merc_burst_count` 6, `merc_burst_interval` 0.1, `merc_spread_deg` 2, `merc_range` 40, `keep_min_dist`/`keep_max_dist` 7/13. Очередь идёт по точке, где лазер был в конце телеграфа, — рывок вбок спасает. Роняет патроны всегда.
- Особых (Раздутый, Щитоносец, Шаман, Наёмник) по GDD 8 сбивают с замаха только сильный удар, Мьёльнир, удар-приземление и прыжок по головам; оглушение оружием — только сильным ударом.
- Урон ≥ 9999 (`Enemy.DEBUG_KILL_DAMAGE`) — отладочное «убить» для тестов, проходит сквозь щит.

## Элита (блок У, GDD 12.4) — `enemies/elite/mods/*.tres` (`EliteModifier`), обработчики `enemies/elite/*.gd`

Любой боец или особый враг (не корм, не босс) с шансом `elite_chance` зала становится элитой: ×2.5 HP, урон ×1.5, свечение цветом модификатора (общий оверлей `shaders/hit_flash.gdshader`, параметр `elite`), подпись модификатора над головой, кольцо под ногами, гарантированный дроп — оружие (60 % мили / 40 % ренж); если в игре уже есть серебро (`Run.add_silver` или автозагрузка `Silver.add`) — с шансом `Loot.elite_silver_chance` 0.4 вместо оружия `Loot.elite_silver` 10 серебра.

| Модификатор | Поля | По умолчанию |
|---|---|---|
| Огненный (`fire`) | `trail_interval` / `trail_radius` / `trail_duration` / `trail_dps` / `trail_max` | раз в 0.45 с на ходу лужа 1.2 м на 3 с, 12 урона/с Тору на земле, не больше 6 луж |
| Ледяной (`ice`) | `slow_mult` / `slow_time` | удар замедляет Тора до ×0.6 на 2 с (компонент `PlayerSlow` на игроке) |
| Бронированный (`armored`) | `armor_u` | первые 3 У (66) урона съедает броня; кирка ломает сразу; остаток — в подписи |
| Быстрый (`fast`) | `speed_mult` | ×1.5 скорость |
| Взрывной (`explosive`) | `blast_radius` / `blast_damage_u` / `blast_delay` | после смерти телеграф 0.8 с и взрыв 1.5 У в радиусе 3.5 м (бьёт и своих) |
| Вампир (`vampire`) | `heal_ratio` | лечится на 2 × нанесённого Тору урона |
| Призыватель (`summoner`) | `summon_interval` / `summon_count` / `summon_kind` / `summon_windup` / `summon_cap` | раз в 8 с телеграф 1 с и 3 корма рядом; не зовёт, если врагов в зале ≥ 30 |

Общее: `weight` (вес в случайном выборе), `enabled`. Новый модификатор — новый `.tres` (и свой обработчик, наследник `EliteHandler`, если нужно новое поведение).

## Залы — `rooms/*.tscn`, корневой узел (`rooms/room.gd`)

`wave_delay` 0.9 (пауза перед следующей волной), `spawn_interval` 0.12 + `spawn_batch` 3 (поток: по 3 врага каждые 0.12 с — GDD 12.5 «2–3 за кадр»; вся волна сразу давала фриз), `next_wave_fraction` 0.3 и `next_wave_timeout` 25 с (следующая волна, когда живых меньше 30 % текущей или прошло 25 с — GDD 12.5).

Маркеры врагов (узел `Spawns`): метаданные `kind` (grunt / thrower / boss / fodder / bloated / shieldbearer / shaman / merc), `wave`, необязательные `count` (толпа из одного маркера) и `spread` (радиус толпы, м). В генераторе — `room_defs()`: `[kind, позиция, волна, сколько, разброс]`.

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

`rooms_per_run` 7 (запасной вариант без карты мира; с картой — `RunMap.rooms`), `miniboss_rooms` [3] (берётся из карты). **Слава по GDD 15.2** (блок Г): база — Слава врага из `enemies/defs/*.tres` (корм 1, боец 3, особый 5), элита `glory_elite_kill` 15, босс `glory_boss_kill` 150, мини-босс — 50 (в `MinibossDef`); враг без описания — `glory_per_kill` 3. Множители: добивание мили ×1.5 (`glory_melee_kill_mult`), ренжем ×0.5 (`glory_ranged_kill_mult`), тело (`BodyDef.glory_mult`: Трэлл ×2, Солдат ×0.7). Бонусы: серия 10 убийств `glory_streak_bonus` +10, мультикилл `glory_multikill_bonus` +1 за каждого, шмяк об стену `glory_wall_splat_bonus` +1, зал зачищен `glory_room_clear` +5, финишер `glory_combo_finisher_bonus` 0. Вердикт — `verdict()` (80 «Сойдёт», 200 «Вальхалла»).

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
`switch_time` 0.25 (свитч), `auto_switch_on_empty` (пустой ренж без запаса → мили), `auto_reload`, `interact_radius` 2.4 (подбор по E), `ammo_pickup_radius` 1.4, `ammo_box_fraction` 0.4 (ящик = 40 % запаса), `ammo_drop_chance` 0.15 (метатели ×2), `drop_all_weapons` false (true — в пуле всё оружие, а не только стартовое GDD), `drop_level2_chance` 0.2 / `drop_level3_chance` 0.05, `fire_slow_time` 0.3 (сколько длится замедление «при стрельбе»), `prop_bullet_impulse` 1.2, `max_casings` 24, `casing_lifetime` 2, `max_tracers` 40, `bolt_stick_time` 1.5, `nail_pin_time` 1 (гвоздомёт прибивает корм), `rocket_radius` 3.5 / `rocket_jump_up` 13 / `rocket_jump_side` 7 (ракетница, рокет-джамп).

### Мили-удары — узел **Axe** (`weapons/axe.gd`)
Базовые тайминги и отдача (массивы ступеней выше) — общие для всего мили; оружие масштабирует их своим `attack_speed`. Урон теперь берётся из `WeaponDef.damage` (поле `base_damage` — только запасной вариант без оружия).
Сильный удар: `heavy_hold_time` 0.28 (сколько держать ЛКМ), `heavy_active` 0.14, `heavy_recovery` 0.36, `heavy_knockback` 15, `heavy_knock_up` 6, `heavy_hitstop` 0.09, `heavy_shake` 0.45.

### Прочее
- Камера: `recoil_return_speed` 14 (как быстро гаснет отдача).
- Игрок: `melee_kill_heal` 2 (добивание мили лечит 3 + 2 HP).
- Забег: `glory_melee_kill_mult` 1.5, `glory_ranged_kill_mult` 0.5 (Слава за убийство мили/ренжем).
- Залы: `elite_chance` 0.1, `max_elites` 1 (элита: ×2.5 HP, урон ×1.5, золотая метка, модификатор, роняет оружие 60 % мили / 40 % ренж — см. раздел «Элита»), `chest_chance` 0.5 (сундук после зачистки; в первом зале всегда, у босса нет) — **только при выключенных дверях** (`Run.doors_enabled = false`); с дверями сундук — награда двери «Сундук».

## Данные по GDD (блок Г)

- **Враги** — `enemies/defs/*.tres` (`EnemyDef`): HP в «У» (`hp_u`, 1 У = 22), скорость, урон, слой, мир, Слава, серебро. Применяются к врагам, которые уже есть (`game_kind` grunt → драугр-воин 2.5 У / 4.4 / 12; thrower → метатель 1.5 У / 3.8 / 15). Блок З добавил корм, Раздутого, Щитоносца, Шамана и Наёмника (`game_kind` fodder / bloated / shieldbearer / shaman / merc). Остальные — `implemented = false`.
- **Руны** — `run/runes/*.tres` (`RuneDef`): `category`, `level_descriptions` (ур. 1–3), `implemented`. Руны без механики не выпадают.
- **Тела** — `run/bodies/*.tres` (`BodyDef`): + `movement_style`, `passive`, `flaw` (`run/passives/*.tres`, `PassiveDef`), `price`, `odin_comment`. 9 тел по GDD 6, закрытые открываются в «Плане тренировок».
- Генератор сцен больше не перезаписывает существующие `run/bodies` и `run/runes` — это данные, правь их в инспекторе.

## Музыка — автозагрузка `scripts/music.gd` (`Music`), треки `sounds/music/<трек>/<слой>.ogg`

`bpm` 120, `beats_per_bar` 4 (переходы слоёв — на доле, треков — на такте), `volume_db` −6, `layer_fade` 0.6 с, `track_fade` 1.2 с, `muffle_cutoff_hz` 650 (пауза, диалог, смерть), `stinger_min_power` 0.6 (удар-приземление с такой силой — стингер), `stinger_duck_db` −18 / `stinger_duck_time` 0.18 с (провал музыки под стингер; во время hit-stop длится дольше).
Слои: `base` (фон: бас и пэды) → `drums` (бой: есть живые враги) → `full` (Ярость: у игрока `is_berserk()`). Треки: `menu`, `plan` («План тренировок»), `midgard`, `miniboss`, `boss`, `shop` (включается `Music.play_track("shop")`).
Заглушки синтезирует `python3 tools/make_sfx.py music` (нужен ffmpeg). Настоящие треки — положить файлы с теми же именами (.ogg или .wav), все слои трека одной длины.

## Портреты — `sprites/portraits/<speaker>_<emotion>.webp|png`, `ui/portrait.gd`, `ui/dialogue_box.gd`

Окно диалога: `portrait_size` 440×660 (пропорции спрайтов 2:3), `portrait_bottom` 40 (низ портрета уходит под плашку текста). Пузырь реплики: крупный план лица, `face_crop` 0.34 (сторона квадрата в долях ширины холста), центр — глаза из `data/portrait_faces.json`. Импорт портретов: WebP с потерями 0.85, не больше 1024 по высоте (иначе сборка выросла бы на ~70 МБ).
## Тела смертных (блок Л) — `run/movement/*.tres`, `run/passives/*.tres`, `run/bodies/*.tres`

**Стиль движения** — `run/movement/<стиль>.tres` (`MovementProfile`), имя файла = `BodyDef.movement_style`. Игрок копирует числа в свои поля (`Player.apply_movement_profile`), без тела — значения из группы «Стиль движения» узла Player (= Базовый). Заряды рывка — у тела (`BodyDef.dash_charges`: Берсерк 1, Охотник и Гонец 3, остальные 2), чтобы перк «+1 рывок» работал у всех.

| Стиль (тела) | Что меняет | Числа |
|---|---|---|
| Базовый (Трэлл) | — | рывок 24 / 0.16 с, перезарядка 1.2 с, двойной прыжок, 2 отскока от стены |
| Шустрый (Охотник) | короткие рывки | `dash_duration` 0.11, `dash_recharge` 0.8 |
| Шустрый+ (Гонец) | ещё быстрее перезарядка (своё решение: GDD не уточняет, чем «+» отличается) | `dash_duration` 0.13, `dash_recharge` 0.6 |
| Таран (Берсерк) | 1 длинный рывок сквозь врагов | `dash_speed` 26, `dash_duration` 0.34, `dash_recharge` 1.6, `dash_ram`; `ram_damage` 15.4 (0.7 У), `ram_knockback` 13 (в стороны), `ram_knock_up` 4, `ram_radius` 1.4, `ram_prop_impulse` 9 (бочки) |
| Прыгун (Скальд, Дева щита) | тройной прыжок, рывка на земле нет | `extra_jumps` 2, `wall_jumps` 3, `wall_jump_mult` 1.25, `dash_on_ground` false |
| Тяжёлый (Жрец, Кузнец) | нет двойного прыжка, мощный удар-приземление | `extra_jumps` 0, `slam_radius_mult` / `slam_damage_mult` 1.5, `slam_stun` 1 с, `slam_bounce_mult` 1.35 |
| Скользящий (Солдат) | рывок на земле → подкат на скорости рывка | `dash_to_slide`, `slide_friction` 0, `momentum_cap` 2.2, `keep_air_momentum` (в воздухе скорость не гасится — bunny-hop) |

**Правила ощущений (GDD 7.4)**, узел Player: `air_control` 0.7; `momentum_cap` 1.8 (предел горизонтальной скорости от рывка, подката и отскоков, × скорость бега); `dash_momentum_bonus` 3 (рывок прибавляет к текущей скорости: выход из рывка = max(24 × 0.55, скорость до рывка + 3), но не выше предела).

**Подкат (GDD 5, 7.2)** — Ctrl + Shift на земле (тратит заряд рывка): `slide_speed` 13 (не ниже текущей), `slide_duration` 0.55 с, `slide_friction` 9 м/с² (у Скользящего 0), `slide_steer` 2.5 рад/с, `slide_camera_drop` 0.55 м, `slide_min_speed_ratio` 0.8 (медленнее — подкат кончается). Прыжок из подката сохраняет скорость. Камера: `crouch_speed` 12 (`camera_fx.gd`).

**Пассивки и изъяны** — `run/passives/<id>.tres` (`PassiveDef`: `implemented`, `todo`, `handler`) + скрипт `run/passives/<id>.gd` (`BodyTraitHandler`). Числа — в инспекторе вложенного ресурса `handler`:

| Черта (тело) | Поля |
|---|---|
| Кровавая ярость (Берсерк) | `damage_per_lost_pct` 1.0, `max_bonus` 0.5 |
| Орёт и плохо лечится (Берсерк) | `heal_mult` 0.5, `shout_chance` 0.3 |
| Привычка к луку (Охотник) | — (ренж не замедляет) |
| Слабак (Трэлл) | `damage_factor` 0.7 — весь урон (раньше было `axe_damage_mult` 0.7 / `hammer_damage_mult` 0.8 в теле — убрано) |
| Мудрость предков (Жрец) | `rune_power` 2 → `Run.rune_count` ×2, руна «Лечение» лечит 100 |
| Кряхтит (Жрец) | `groan_chance` 0.6 (слово «KHEH!» при прыжке) |
| Тактическая перезарядка (Солдат) | — (рывок → магазин из запаса) |
| Пьяному море по колено (Скальд) | — (первый удар в зале — 0 урона; падение в пропасть не прощает) |
| Пьяный прицел (Скальд) | `wobble_deg` 1.6 (частота — `aim_wobble_freq` 0.45 в `camera_fx.gd`) |
| Удар в спину (Гонец) | `backstab_mult` 2.0 (поверх множителя оружия) |
| Трус (Гонец) | `front_mult` 0.7 (враг смотрит на Тора) |
| Своя наковальня (Кузнец) | `level_bonus` 1, `sharpen_cost_mult` 0.5 (заточки ещё нет) |
| Тяжёлые сапоги (Кузнец) | — (нет рывка в воздухе) |
| Мастер щита (Дева щита) | `window_mult` 2, `heal_on_parry` 5 (парирования ещё нет) |
| Не её оружие (Дева щита) | `ranged_mult` 0.75 |

Экран выбора тела (`ui/body_select.gd`): `columns` 3, `card_size` 230×100. Реакция Одина на смерть тела — `body_death_chance` 0.35 (`scripts/dialogue_manager.gd`).

## Ярость (блок П, GDD 8) — узел **Player/Rage** (`player/rage.gd`, создаётся кодом)

| Параметр | По умолчанию | Что делает |
|---|---|---|
| `kill_window` | 3 с | Окно между убийствами серии; дольше — шкала сбрасывается |
| `kills_to_full` | 25 | Убийств в серии до полной шкалы |
| `berserk_time` | 8 с | Длительность берсерка |
| `damage_mult` / `speed_mult` | 1.5 / 1.5 | Урон Тора (всё, что идёт через `deal_damage`) и скорость бега в берсерке |
| `hitstop_on_start` | 0.12 с | Хит-стоп при включении |

В берсерке удары по Тору не отбрасывают («неуязвимость к стану» — стана у Тора нет), шкала заново не копится. HUD (`ui/rage_hud.gd`): `bar_width` 380, `vignette_alpha` 0.75; картинки `sprites/ui/hud/hud_rage_frame.png` + `hud_rage_fill.png`, `sprites/vfx/vfx_rage_vignette.png` — подхватятся сами.

Бой-реплики Одина (GDD 17), лимит — `combat_cooldown` 12 с (`run/odin.gd`, «berserk» — без лимита): «ДВИГАЙСЯ!» `idle_time` 4 с, мульти-килл `multikill_count` 3 за `multikill_window` 0.8 с, «Скуф…» `big_damage_fraction` 0.35 HP за `big_damage_window` 3 с, «Позорище» — добил ренжем (`run/run_tracker.gd`; мульти-килл важнее), «Вот! ВОТ!» — удар-приземление с `big_slam_height` 9 м (узел Player). Тексты — пулы `idle`, `multikill`, `big_damage`, `ranged_kill`, `big_slam`, `berserk`, `rage_over` в `data/dialogues/odin.json`.

## Руны по уровням (блок Т) — `run/runes/*.tres`

У каждой руны `level_values` (ур. 1–3) и иногда `level_values_b` (второе число), `value_kind`: add / mult / interval (как руна усиливается у Старого жреца: значение ×2, множитель (v−1)×2+1, «каждый N-й» → N/2). Повтор руны повышает уровень, максимум 3 (`Run.RUNE_MAX_LEVEL`); руны ур. 3, проклятые и без механики в обычный выбор не попадают. Числа — по таблице GDD 11 (например, Яблоко Идунн 30/55/80, Руна Тюра +25/40/60 %, Зов грома — каждый 5/4/3-й удар).
Игрок (`Player`, группа «Криты и руны»): `crit_chance_base` 0.05, `crit_mult` ×2, `crit_hitstop` 0.09 с (GDD 8, 19), `thunder_call_damage` 22 (1 У), `hiccup_period` 10 с, `spin_chance_per_sec` 0.03.
Проклятые руны Локи (`cursed = true`, выдаются `Run.random_cursed_rune()` — для сделки Локи): Икота Локи (урон ×1.5, сам подпрыгивает раз в 10 с), Вертушка Локи (+2 рывка, камера иногда крутится на 180°), Стеклянная пушка (урон ×1.8, входящий ×1.5).


## Структура забега и двери-награды (блок И, GDD 15.1)

**Мир** — `run/maps/midgard.tres` (`run/run_map.gd`, `RunMap`):
- `rooms` 7 (залов до босса), `miniboss_room` 4 (мини-босс — последней волной 4-го зала, за него трейт), `first_room_reward` combat.
- Двери: `doors_min` 2 / `doors_max` 3, `shop_per_world` 1 (ларёк гарантирован: дверь ларька в каждом наборе, пока не зайдёшь), `shop_earliest_room` 3, `no_peaceful_twice` (отдых и ларёк не подряд), `shop_scene`.
- Награды: элитный бой `elite_room_chance` 0.45 / `elite_room_max` 3 (обычный зал 0.1 / 1), `elite_reward_silver` 30, `elite_reward_glory` 20; отдых `rest_heal_fraction` 0.4; `rune_max_level` 3; Фрейя `freya_rune_level` 2; Локи `loki_hp_cost` 0.5, «кости» `loki_dice_win_chance` 0.5 / `loki_dice_hp_loss` 0.3.

**Награды** — `run/rewards/*.tres` (`run/reward_def.gd`, `RewardDef`): `weight` — частота в % (GDD 15.1: бой 45, элита 15, сундук 10, испытание 10, отдых 8, Фрейя 7, Локи 5; ларёк, мини-босс и босс — 0, по особым правилам), `combat` (false — тихий зал без врагов), `enabled` (false — механики ещё нет, не предлагается), `glyph`/`color` (заглушка иконки), `icon_name` → `sprites/ui/icons/door_<icon_name>.png`.

**Дверь** — `rooms/reward_door.gd`: `FRAME_SCALE` 1.55 (арка Quaternius), `ICON_HEIGHT` 4.95.

## Серебро и ларёк (блок К, GDD 13, 15.2)

**Серебро** — `run/economy.tres` (`run/economy.gd`, `Economy`): сундук `chest_silver` 20, бочка `barrel_silver_min` 3 / `barrel_silver_max` 8, бочка «разбита», если её отбросило быстрее `barrel_break_speed` 8 м/с (удар-приземление, молот, сильный удар, таран, падение с высоты), элита `elite_silver` 10, мини-босс `miniboss_silver` 0 (в GDD нет). С врагов — `enemies/defs/*.tres` (`silver_min/max`: корм 0–1, боец 2, особый 3). Элитный бой — ещё `RunMap.elite_reward_silver` 30.
Монеты: `max_coins_per_drop` 5, разлёт `coin_spread_speed` 3 / `coin_up_speed` 5 / `coin_gravity` 18, магнит через `magnet_delay` 0.45 с в радиусе `magnet_radius` 8 м (после `magnet_any_after` 2 с — с любого расстояния), скорость `magnet_speed_start` 5 → `magnet_speed_max` 26 (разгон `magnet_accel` 40), `collect_radius` 0.8.
Перки «Плана тренировок»: «Жадность» — старт с 30 серебра (`start_silver`), «Скидка у Брокка» — −15 % в ларьке (`shop_discount`).

**Товары** — `run/shop/*.tres` (`run/shop_item_def.gd`): `price` (шаурма 40, руна 60, заточка 80 / `price2` 120 для 2→3, патроны 30, обслуживание Мьёльнира 100, «Кот в мешке» 50, сдать руну +20), `amount` (шаурма — доля лечения 0.3), `by_eitri` (отвечает Эйтри: «Угу»), `odin_pool` (шаурма → «Ты опять за своё?»), `order`. Кузнец (пассивка `smith_level`) — заточка −50 %.
«Кот в мешке» и реакции Брокка — константы в `run/shop.gd`: `BAG_OUTCOMES` (руна 25, оружие ур. 2–3 20, лечение 15, серебро 10, проклятие 15, пусто 15), `BAG_HEAL` 0.5, `BAG_SILVER` 80, `BAG_CURSE` 0.25 (доля текущего HP), `RICH_SILVER` 150 («много серебра»); «мало HP» — меньше 35 %.
Ларёк в зале — `rooms/shop_stall.gd`: `DWARF_SCALE` 0.62, цвета навеса `CLOTH_A/B`.

## Испытания (блок Ф, GDD 15.1)

`run/trials/*.tres` (`run/trial_def.gd`, `TrialDef`): `host` (odin / hild / loki), `kind` (вид условия), `time_limit`, `target`, `allowed_sources` / `forbidden_sources`, `extra_waves`, награда `reward_glory` (GDD 15.2: 40–80) или `reward_rune` (руна 1 из 3 сразу на уровень выше), `weight`, пулы реплик (`<host>.trial_intro / trial_win / trial_fail`).
| Испытание | Условие | Награда |
|---|---|---|
| `odin_no_ranged` | зачистить зал без единого выстрела ренжем | 50 Славы |
| `odin_time` | зачистить зал за `time_limit` 40 с | 60 Славы |
| `odin_slam_hammer` | добивать только ударом-приземлением и молотом (`forbidden_sources`: melee*, ranged, dash) | особая руна |
| `hild_record` | `target` 10 убийств за 30 с, зал получает `extra_waves` 2 доп. волны | 80 Славы |
| `loki_lava` | пол — лава: стоять на полу дольше `lava_grace` 0.4 с — ожог `lava_tick_damage` 6 HP каждые `lava_tick` 0.5 с; ожог суммарно больше `lava_max_burn` 4 с — провал | особая руна |
Дверь «Испытание» — 10 % (`run/rewards/trial.tres`).

## Обучение — `run/tutorial.gd`
`max_runs` 2 (в скольких забегах показывать, если не пройдено), `first_delay` 2 с, `step_gap` 1.2 с (пауза между подсказками), `step_timeout` 14 с (не сделал — следующая подсказка; подсказка о дверях ждёт дверей).
