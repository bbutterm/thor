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
| Руны Мьёльнира | `dash_recharge` | 2.5 с | Одна руна восстанавливается только на земле; рывок и каждый воздушный прыжок тратят по руне |
| Рывок | `dash_invuln` | 0.15 | Неуязвимость в начале рывка |
| Рывок | `dash_exit_keep` | 0.55 | Сколько скорости остаётся после рывка |
| Приземление | `slam_speed` | 34 | Скорость падения при Ctrl |
| Приземление | `slam_base_radius` + `slam_radius_per_meter` | 3.5 + 0.25/м | Радиус волны растёт с высотой |
| Приземление | `slam_base_damage` + `slam_damage_per_meter` | 20 + 3/м | Урон волны |
| Приземление | `slam_base_knockback` + `slam_knockback_per_meter` | 10 + 0.8/м | Отбрасывание |
| Удар-приземление | `slam_min_height` / `slam_hint_cooldown` | 3 м / 8 с | С обычного прыжка недоступен; после воздушного прыжка, специальных подбросов или с высоты над миром/предметом — доступен |
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
| Прыжковая руна | `height` / `radius` / `cooldown` (`rooms/jump_pad.gd`) | 8–9 м / 1.2 / 0.4 с | Светящийся круг на полу (залы 2 и 3, ключ `jump_pads` в генераторе) подбрасывает, восстанавливает прыжки |
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
Хитбокс — узел **Head/Camera/AxeHitbox** (ShapeCast3D, коробка 2.6×2×1.6, до 128 пересечений; ширина и дальность множатся данными оружия). При попадании по двум врагам за взмах — отдельный звук `axe_multi_hit`, приёмы используют то же событие. Три обычных звука и случайный pitch остаются.

## Мьёльнир — узел **Mjolnir** (`weapons/mjolnir_hand.gd`)

База по GDD 10: `throw_speed` 32, `base_damage` 33 (1.5 У), `max_range` 25 м (дальше — возврат), `auto_return_after` 1.5 с (полёт без попадания в стену), `sticks_to_world` вкл. (втыкается в стену/пол), `stuck_auto_return` 0.8 с (сколько воткнутый молот ждёт ПКМ; трейты «на воткнутый» продлевают до 3–5 с; 0 — ждёт всегда), `return_speed` 36, `return_turn_accel` 140 (дуга возврата), `max_wall_bounces` 0 (было 2: теперь отскоки даёт Рикошет), `chain_targets` 0 (базовой молнии нет — это стихия «Молния»), `chain_damage_ratio` 0.5, `chain_radius` 7, `hit_hitstop` 0.04.
Без молота: `dash_recharge_bonus` 0.2 (руны на земле восстанавливаются на 20 % быстрее); `catch_runes` 1 — обычная поимка возвращает руну и, в воздухе, прыжки; идеальный хват заполняет запас. Перехват в воздухе: `restore_dash` / `restore_dash_lvl2` 1 / 2 дополнительных руны, `hop_lvl2` 5 м/с. Идеальный хват: `perfect_window` 0.15 с (ПКМ до или после поимки), `perfect_damage_mult` 2.

## Трейты Мьёльнира (блок Б4: стихии × приёмы) — `weapons/mjolnir_traits/*.tres`, связки — `combos/*.tres`

Открой `.tres` → поле **handler** → числа трейта. Вид (`kind`: element / technique / combo), название, описания уровней (`description`, `_lvl2`…`_lvl4`), руна, цвет, группа несовместимости `group`, список `conflicts`, `max_level`, открытия по уровням `level_pool_ids` — в самом `.tres`. Новая стихия — наследник `MjolnirElementHandler` (`weapons/mjolnir_element.gd`), приём или связка — `MjolnirTraitHandler`.

**Правила** — `weapons/mjolnir_rules.tres` (`MjolnirRules`): `max_elements` 1, `element_swap` выкл. (стихия одна на забег), `max_techniques` 2, `offer_count` 3, `mix_kinds` вкл. (у мини-босса в наборе и стихия, и приём), `anvil_enabled` вкл. (дверь «Наковальня Эйтри»), `combo_card_time` 3.2 с (плашка «СВЯЗКА!»). Наковальня в мире — `run/maps/midgard.tres`: `anvil_per_world` 1, `anvil_earliest_room` 2, `anvil_latest_room` 3.

**Стихии** (общие поля `MjolnirElementHandler`): след — `trail_spacing` 1.8 м, `trail_radius` 1.1, `trail_duration` 3 с, `trail_max_height` 4 м, `trail_max_zones` 10; аура — `aura_interval` 1 с, `aura_radius` 4 м, `aura_damage` 8, `aura_stuck_hold` 5 с; с неба — `sky_max_distance` 40, `sky_radius` 3, `sky_damage` 33 (1.5 У); связка — `slam_reach` 2 м (насколько дальше радиуса удара-приземления), окружение — `world_radius` 1.6.

| Стихия | Свои числа |
|---|---|
| Огонь | поджог `burn_dps` 6.6 (0.3 У/с) × `burn_time` 3 с, перекидывается в `spread_radius` 2.5 м раз в `spread_interval` 1 с, не дальше `spread_max_gen` 2; вспышка `flare_radius` 3, `flare_damage` 22, `flare_knockback` 8; след `trail_dps` 6.6, с ур. 3 `trail_radius_lvl3` 1.6 / `trail_duration_lvl3` 5 с, свет у каждого `trail_light_every` 3-го; столб — `sky_fire_time` 3 с, `sky_fire_dps` 13.2 |
| Лёд | замерзает на `freeze_hits` 3-м попадании, промерзание `chill_time` 3 с, `slow_per_stack` 0.25, не медленнее `slow_min_mult` 0.4, заморозка `freeze_time` 2 с; раскол ×`shatter_mult` 2 урона удара, осколки `shard_radius` 3 / `shard_damage` 11; след — стан `trail_fall_stun` 0.5 (с ур. 3 `_lvl3` 1 с), `trail_slide_push` 6 (`weapons/ice_zone.gd`) |
| Молния | цепь `chain_targets` 3 (с ур. 3 `_lvl3` 5), `chain_damage` 11, `chain_radius` 7, под током `shock_time` 5 с; разряд `discharge_radius` 18, `discharge_damage` 15, `discharge_stun` 0.4, не больше `discharge_max` 8 молний (ближайшие); след — `trail_tick` 0.5 с × `trail_damage` 4; Громоотвод `aura_damage` 15, на ур. 4 `aura_interval_lvl4` 0.6; Гром небесный `sky_stun` 1 с; брага — `brew_shock_time` 4 с, `brew_shock_damage` 6 |
| Земля | прибить `pin_time` 1.5 с, с ур. 2 — всех в `splash_radius` 2 м; вторая волна — рядом с прибитым (`pinned_reach` 3 м), `wave_delay` 0.12, `radius_mult`/`damage_mult` 1 (как удар-приземление); на ур. 4 третья волна `third_wave_delay` 0.35 / `third_wave_radius_mult` 1.4; разлом `trail_pin` 0.6; Землетрясение — `quake_trigger_distance` 5 м, дрожь `aura_pin` 0.5; глыба `sky_pin` 1.5 |
| Ветер | отброс `knockback` 16 + `lift` 5 (боссов ×`boss_factor` 0.3); вихрь удара-приземления — радиус ×`gust_radius_mult` 1.6, `gust_knockback` 18, `gust_lift` 6, `gust_damage` 5; порывы следа `trail_push` 9 / `trail_lift` 3; аура `aura_push` 11; смерч `sky_lift` 11 |

Состояния на враге — `weapons/element_status.gd` (`ElementStatus`; боссов не замедляет и не останавливает: «заморозка» босса — только отметка для раскола на `BOSS_FREEZE_MULT` 0.5 времени; искр горения не больше `BURN_FX_PER_FRAME` 2 за кадр), пятна следа молнии/земли/ветра — `weapons/element_zone.gd` (общий диск, общий материал).

**Приёмы** (ур. 1 / ур. 2):

| Приём | Группа / не вместе с | Главные числа |
|---|---|---|
| Притяжение к молоту | к молоту | `speed` 30, `max_time` 1.2 с, `damage` 22 (1 У), `hit_radius` 1.6, `knockback` 11, `exit_up` 10, `mantle_height` 2.2 м, `stuck_hold` 3 с; ур. 2 — `arrive_slam_*` |
| Магнит | — | `radius` 6 / 9 м, `pull_speed` 7, `hold_distance` 1.6, `boss_factor` 0.25, `blast_damage` 11, `blast_knockback` 15, `stuck_hold` 3 с |
| Бумеранг | Магнит, Ступенька, Пёс, Пике | `speed_mult` 1.25, `loop_time` 0.5 с, `turn_rate` 3.6 рад/с; ур. 2 — две петли |
| Рикошет | — | `ricochets` 3 / 5, `seek_radius` 14 м |
| Буря | удержание ПКМ | `hold_delay` 0.18 с, `duration` 3 / 5 с, `radius` 3, `tick` 0.3 с, `tick_damage` 11; ур. 2 — `pull_speed_lvl2` 5, `pull_radius_lvl2` 7 |
| Два молота | — | копии веером через `spread_deg` 12°, каждый ×`damage_mult` 0.6 |
| Молот-ступенька | — | прыжок ×`jump_mult` 1.5 / 1.85, ждёт `stuck_hold` 6 / 10 с, площадка `platform_size` 1 × 0.2 × 0.9 м, стена — `max_wall_normal_y` 0.5 |
| Обмен | к молоту | неуязвимость `arrive_invuln` 0.35 с; ур. 2 — волна `burst_radius` 3, `burst_damage` 11, `burst_knockback` 9 |
| Пике молотом | — | взгляд ниже `min_down_angle` 30°, бросок ×`throw_speed_mult` 1.6, Тор летит `follow_speed` 40, бонус высоты `height_bonus` 4 / 7 м, `max_follow_time` 1.5 с. Разрешение на удар проверяется при броске и действует до посадки или завершения залезания |
| Праща | удержание ПКМ | крутится после `spin_delay` 0.2 с, `orbit_radius` 1.9, `spin_speed` 9 рад/с, `tick` 0.25 с × `spin_damage` 11, `spin_knockback` 8, до `max_spin` 4 / 6 с; бросок ×`launch_speed_mult` 1.4, ×`launch_damage_mult` 1.3 / 1.6, пробивает щиты |
| Заряд | удержание ПКМ | короче `min_hold` 0.12 с — обычный бросок; полный за `charge_time` 0.8 / 0.55 с: урон до ×`max_damage_mult` 2.2 / 2.6, скорость ×`max_speed_mult` 1.4, дальность ×`max_range_mult` 1.8, пробитие с `pierce_at` 0.95; ур. 2 — оглушение `stun_lvl2` 0.8 с |
| Перехват в воздухе | — | `restore_dash` / `restore_dash_lvl2` 1 / 2 дополнительных руны, ур. 2 — подброс `hop_lvl2` 5 м/с |
| Верный пёс | — | раз в `interval` 1 / 0.6 с бьёт ближайшего в `radius` 8 м на `damage` 15 (0.7 У), `knockback` 6, ждёт `stuck_hold` 6 / 9 с |

**Связки** (`combos/*.tres`): Огненный смерч — `radius_mult` 1.35, тянет в `pull_radius` 7 со `pull_speed` 6, поджог раз в `ignite_tick` 0.3 с, огонь под смерчем раз в `fire_every` 0.7 с (`fire_radius` 2, `fire_time` 2, `fire_dps` 6.6, `max_fires` 3); Ледяной рикошет — корка `crust_radius` 1.6, `crust_time` 4, `crust_fall_stun` 0.8, промерзание в `chill_radius` 2.5, `max_crusts` 6; Грозовой магнит — разряд раз в `interval` 0.6 с на `damage` 8, на возврате цепь `recall_chain` 2 × `recall_chain_damage` 11; Ураганный рывок — путь `path_radius` 2.6 / `path_push` 14, прилёт `arrive_radius` 5.5, `arrive_push` 18, `arrive_lift` 6, `arrive_damage` 5; Кратер — радиус удара ×`radius_mult` 1.5, `pin_time` 1.5, `damage` 11 (корм погибает).

**Шкала стиля** (`player/style_tuning.tres` → `points`): `air_catch` 6, `element_slam` 6, `hammer_dive` 6, `hammer_step` 6, `hammer_swap` 5, `shatter` 8.

Правила выбора: несовместимый приём заменяет старый (на экране — второе нажатие), повтор — уровень выше, на максимуме не выпадает, в одном наборе нет несовместимых. Связка складывается сама; карточка, которая её сложит, — с легендарной рамкой и строкой «+ СВЯЗКА».

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

**Маршруты ярусов:** только в зале с `EnemyNavigation` и настоящими навигационными поверхностями; иначе ИИ не меняется. На узле `Room`: `nav_refresh_interval` 0.3 с — распределённая проверка цели/регионов; `nav_target_move` 0.75 м — после какого сдвига цели запрашивать новый путь; `nav_point_distance` 0.35 м / `nav_target_distance` 0.65 м — допуски пунктов маршрута; `nav_surface_tolerance` 1.2 м — максимальный отступ от навигационной поверхности для начала маршрута; `nav_walk_layers` 1 — ходовые поверхности и связи, `nav_jump_layers` 2 — односторонние связи прыжка. `nav_max_simultaneous_jumps` 1 ограничивает одновременно занятые прыжки, включая прерванные до приземления; `nav_jump_landing_clearance` 0.05 м — подъём расчётной точки над целевым полом, не перенос тела; остальные параметры дуги используются из группы входа врагов. При отклонённой дуге враг переходит на ходовой путь. Пустая/отсутствующая поверхность не считается достижимой.

**Обнаружение Тора:** `notice_radius` 20 м по горизонтали; громкого Берсерка враги замечают с 30 м (`notice_radius_mult` ×1.5). Если игрок не подошёл, враг вступает в бой через `notice_fallback_time` 3 с; попадание и толчок будят сразу. Однажды заметив игрока, враг его не забывает; боссы и призванные во время боя враги начинают бой сразу.

| | Грунт | Метатель | Босс |
|---|---|---|---|
| `max_health` | 60 | 40 | 480 |
| `move_speed` | 4.4 | 3.8 | 3.6 |
| `attack_damage` | 12 | 10 (снаряд) | 20 / удар по площади 25 |
| `windup_time` (телеграф) | 0.6 | 0.55 | 0.8 / 1.0 |
| `knock_resist` | 0 | 0 | 0.75 |

Ещё: `wall_splat_speed` 8.5 (с какой скорости отбрасывания враг «шмякается» об стену), `wall_splat_damage` 12, `wall_splat_stun` 1.0, `keep_min_dist`/`keep_max_dist` 8/12 (метатель), `melee_vertical_reach` 1.6 м (обычные враги не начинают ближнюю атаку и не попадают сквозь настил или при большей разнице высот), `boss_slam_radius` 6.5, `fall_kill_height` 6 / `fall_damage` 44 / `fall_hit_window` 1.5 с (сброшенный после удара с 6+ м: корм насмерть, остальным 2 У; сам спрыгнувший — без урона), отражённый снаряд — ×1.8 (`REFLECT_DAMAGE_MULT` в `enemy_projectile.gd`). **Удар босса по площади попадает, только если ты на земле — прыгай!**

Метатель и наёмник подают звук при начале замаха. Если все аудиоканалы заняты, предупреждение может подождать до `warning_deadline_fraction` 0.5 длительности замаха; после этого или при прерывании атаки оно пропускается, чтобы не звучать после выстрела. Версии владельца можно задать событиями `thrower_aim` и `merc_aim` в `data/owner_audio.json`; пока используются имеющиеся звуки.

Реакция: `flinch_distance` 0.13 м × масштаб модели, `flinch_time` 0.12 с — сдвиг только вида, без добавочного прерывания атак. Если входящий толчок нулевой, направление берётся от Тора. Сброшенный с высоты `fall_kill_height` 6 м получает обычный исход падения, а при гибели дополнительно даёт `ledge_kill` 3 очка стиля и слово «YEET!».

Трупы: `max_debris` 10 (сколько «рэгдоллов» лежит одновременно, лишние исчезают). Корм сохраняется до гибели всех врагов своей волны и выхода её очереди; поскольку волны могут идти одновременно, окончание считается отдельно для каждой. После волны тела тают 0.3 с. Вне активной волны и у других врагов `debris_lifetime` 4 с.

Окончание каждой волны (`Room`): `wave_end_slow_time` 0.3 с реального времени, `wave_end_slow_scale` 0.35; если действует hit-stop, замедление начинается после него. Hit-stop для мультикилла (`VfxTuning`) 0.11 с, крупного — 0.14 с. `hitstop_budget_per_second` 0.35 с суммарно в скользящей секунде; перекрывающиеся попадания не складываются. `Audio.identical_sfx_per_frame` 2 — лимит одинакового разрешённого файла при постановке в очередь за кадр.

## Враги Мидгарда (блок З, GDD 12.1) — `enemies/fodder.tscn`, `bloated.tscn`, `shieldbearer.tscn`, `shaman.tscn`, `merc.tscn`

HP / скорость / урон / Слава — из `enemies/defs/*.tres` (`EnemyDef`, 1 У = 22), остальное — `@export` в сцене (`enemies/enemy.gd`).

| | Корм | Раздутый | Щитоносец | Шаман | Наёмник Локи |
|---|---|---|---|---|---|
| HP (`hp_u`) | 0.35 У = 7.7 | 1 У = 22 | 4 У = 88 | 2 У = 44 | 2 У = 44 |
| `move_speed` | 3.5 | 5 | 3 | 3 | 4 |
| урон (`damage`) | 5 | 44 (2 У) взрыв | 15 + толчок | — (лечит) | 15 × `merc_bullet_mult` 0.5 = 7.5 за пулю |
| `windup_time` (телеграф) | 0.55 | `boss_slam_windup` 0.7 (фитиль, диск радиусом взрыва) | 0.75 | 1.0 (обряд: зелёное кольцо) | 0.8 (лазер) |
| `knock_resist` | 0 | 0.2 | 0.6 | 0.1 | 0 |

- **Корм:** одна модель (тело + один комплект одежды, без оружия/волос/случайной сборки), мычит реже (15 % замахов).
- **Дальний корм:** `fodder_lod_distance` 20 м и `fodder_lod_frames` 3; в погоне направление и поза анимации пересчитываются раз в три физических кадра, с разнесением по врагам. Физика, обнаружение, таймеры, атака и сближение обновляются каждый кадр; вблизи частота сразу полная. Боссы и стрелки не используют этот режим.
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

`wave_delay` 0.9 (пауза перед следующей волной), `spawn_interval` 0.12 + `spawn_batch` 3 (поток: по 3 врага каждые 0.12 с — GDD 12.5 «2–3 за кадр»; вся волна сразу давала фриз), `next_wave_fraction` 0.3 и `next_wave_timeout` 25 с (следующая волна, когда живых меньше 30 % текущей или прошло 25 с — GDD 12.5). В обычных залах `max_alive` 60: если лимит достигнут, очередь ждёт освобождения места; дополнительные призывы в заполненный зал не создаются. `max_alive` 0 — без ограничения (ручные арены). Вход с края или через проём использует `entry_target`; параметры зала `entry_jump_speed` 8 м/с, `entry_timeout` 4 с, `entry_min_drop` 0.6 м, `entry_max_drop` 5 м, `entry_max_distance` 10 м и `entry_arrival_tolerance` 0.18 м задаются в инспекторе. У таких маркеров `entry_batch` 1; `spread_axes` задаёт разброс вдоль и поперёк края. Перед входом проверяются опора и путь; попадание прерывает движение.

Маркеры врагов (узел `Spawns`): метаданные `kind` (grunt / thrower / boss / fodder / bloated / shieldbearer / shaman / merc), `wave`, необязательные `count` (толпа из одного маркера) и `spread` (радиус толпы, м). В генераторе — `room_defs()`: `[kind, позиция, волна, сколько, разброс]`.

В вертикальном зале `floor_openings` задаёт прямоугольные проёмы, а `enemy_fall_y` −0.5 м — локальную высоту гибели врага ниже дна. Добыча упавшего врага остаётся на полу у входа. Если этих данных нет, другие залы сохраняют прежнее поведение.

## Комиксовые слова — автозагрузка `scripts/comic_fx.gd` (`ComicFX`)

Поля `@export` в начале скрипта (автозагрузка — правятся в коде). Словарь, цвета букв/«взрыва» и приоритеты событий — `data/comic_words.json`. Рисованный «взрыв» — положи `sprites/comic/<событие>.png` (как есть) или общий `sprites/comic/burst.png` (красится цветом события); иначе берётся случайный из комплекта `sprites/vfx/comic_burst_01..06.webp`, перекрашенный в цвет события (`burst` в JSON).

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
| Вид | `kit_burst_scale` / `kit_burst_max_aspect` | 1.75 / 1.9 | Рисованный «взрыв» комплекта (`sprites/vfx/comic_burst_01..06`, случайный): во сколько раз больше букв, предел вытягивания по ширине |
| Вид | `kit_tint_strength` / `kit_burst_tilt_deg` / `kit_shadow_alpha` | 0.85 / ±10° / 0.55 | Перекраска в цвет события (0 — авторский цвет), доворот, тень |
| Анимация | `pop_in_time` / `pop_overshoot` | 0.1 с / 1.3 | Появление 0 → 1.3 → 1.0 (реальное время — видно во время hit-stop) |
| Анимация | `shake_time` / `shake_px` / `shake_deg` | 0.15 с / 7 / 3° | Дрожь |
| Анимация | `hold_time` / `fade_time` / `rise_px` | 0.05 / 0.15 с / 40 | Пауза и исчезновение с подъёмом (игровое время — во время стопа слово «стоит») |
| Анимация | `big_time_mult` | 2.2 | Крупные слова живут дольше |

Игрок может выключить слова и поменять их размер (50–160 %) в паузе и в «Настройках» главного меню; сохраняется в `user://settings.cfg`, секция `[comic]`.

## VFX-комплект — `data/vfx_tuning.tres` (`scripts/vfx_tuning.gd`, `VfxTuning`) и узел **VfxScreen** (`scripts/vfx_screen.gd`)

Текстуры — `sprites/vfx/*.webp` (комплект владельца). Мировые эффекты (`FX.*` в `scripts/fx.gd`) берут числа из `data/vfx_tuning.tres` — открой его в инспекторе Godot. Лимит пула: сверх него переиспользуется самый старый эффект того же вида.

> **27.10:** прозрачность и затухание эффектов (`*_transparency`, `*_fade`, мерцание огня, проявление телеграфов) раньше не действовали: шейдеры эффектов присваивали `ALPHA`, а GL Compatibility вообще не поддерживает `GeometryInstance3D.transparency`. Теперь работают в обоих рендерерах (в GL — через instance uniform `fade`, `FX.sync_fades`), поэтому эффекты стали прозрачнее, чем выглядели до этого: если что-то кажется бледным — подними здесь число, а не яркость текстуры.

| Группа | Параметр | По умолчанию | Что делает |
|---|---|---|---|
| Вспышка | `hit_flash_size` / `hit_flash_big_mult` / `hit_flash_ranged_mult` | 0.9 м / ×1.6 / ×0.55 | Размер вспышки попадания; крупный удар (финишер, тяжёлый, удар-приземление) / ренж |
| Вспышка | `hit_flash_time` | 0.25 с | 6 кадров полосы (манифест: 24 fps); игровое время — во время hit-stop «стоит» |
| Вспышка | `hit_flash_push` / `hit_flash_limit` | 0.45 м / 12 | Сдвиг к камере (не тонет в теле), пул |
| Искры | `sparks_per_star` / `sparks_max` | 6 / 3 | Рисованных звёзд поверх частиц `FX.sparks` (1 на 6 частиц, не больше 3) |
| Искры | `spark_size` / `spark_time` / `spark_spread` | 0.35–0.7 м / 0.22 с / 0.45 м | Размер, жизнь и разлёт звезды |
| Искры | `spark_min_luma` / `sparks_limit` | 0.55 / 24 | Темнее — пыль/щепки, звёзд нет; пул |
| Ихор | `ichor_splash_size` / `ichor_splash_time` / `ichor_splash_limit` | 0.7–1.1 м / 0.35 с / 16 | Брызги при уроне нежити (все враги, кроме Наёмника Локи и ледяных; метаданные врага `ichor` переопределяют) |
| Ихор | `splat_chance` | 0.35 | Шанс пятна на полу от обычного удара (крупный удар и смерть — всегда) |
| Ихор | `splat_size` / `splat_death_mult` | 0.9–1.5 м / ×1.5 | Размер пятна; при смерти крупнее |
| Ихор | `splat_life` / `splat_fade` / `splat_transparency` / `splat_limit` | 10 / 2 с / 0.1 / 24 | Сколько лежит, затухание, прозрачность, пул (старые исчезают) |
| Дым | `smoke_size` / `smoke_per_radius` | 1.6 м / 0.9 | Облако при исчезновении трупа и взрыве (+ радиус взрыва × 0.9) |
| Дым | `smoke_time` / `smoke_rise` / `smoke_transparency` / `smoke_limit` | 0.5 с / 0.8 м / 0.15 / 12 | 8 кадров, подъём, прозрачность, пул |
| Дым | `barrel_dust_size` | 1.3 м | Пыль разбитой бочки (`run/barrel_watch.gd`) |
| Серебро | `coin_glint_size` / `coin_glint_interval` | 0.3 м / 0.06 с | Блеск-звёздочка при вылете монеты (0 — нет), не чаще |
| Огонь | `fire_per_meter` / `fire_max` | 2.0 / 7 | Языков пламени в зоне огня (на метр радиуса, максимум) |
| Огонь | `fire_height` / `fire_fps` / `fire_fade` | 1.2–1.9 м / 16 / 0.25 с | Высота языка, кадров в секунду (петля в шейдере), появление и угасание |
| Молния | `lightning_segment` / `lightning_width` / `lightning_overlap` | 2.6 м / 0.5 / ×1.35 | Длина отрезка-текстуры (длинная молния — несколько), ширина ленты к длине, нахлёст отрезков |
| Молния | `lightning_energy` / `lightning_core_alpha` / `lightning_limit` | 2.2 / 0.6 / 32 | Яркость, тонкая линия-сердцевина (0 — нет), пул отрезков |
| Удар-приземление | `shockwave_scale` / `shockwave_time` / `shockwave_transparency` / `shockwave_limit` | 2.1 / 0.38 с / 0.45 / 4 | Ударная волна: в конце поперёк столько радиусов удара; длительность; прозрачность в начале; пул (и у босса) |
| Удар-приземление | `crack_medium_height` / `crack_large_height` | 4 / 10 м | С какой высоты падения трещина средняя / крупная |
| Удар-приземление | `crack_sizes` | 2.2 / 3.6 / 5.5 м | Размер малой / средней / крупной трещины |
| Удар-приземление | `crack_life` / `crack_fade` / `crack_limit` | 6 / 1.5 с / 6 | Сколько лежит, затухание, пул |
| Лёд | `ice_patch_size` / `ice_patch_limit` | 2.2 м / 4 | Наледь под Тором от удара ледяной элиты (на время замедления) |
| Лёд | `ice_shards` / `ice_shard_height` / `ice_shard_radius` | 3 / 0.45–0.8 м / 0.8 м | Кристаллы вокруг |
| Лёд | `ice_shard_grow` / `ice_shard_stay` / `ice_shard_limit` | 0.12 с / 0.5 / 16 | Рост, сколько стоят (доля замедления), пул |
| Пол | `decal_lift` | 0.025 м | Высота пятен/трещин над полом (против мерцания) |

**VfxScreen** (создаёт `Game._ready`, поля — в коде скрипта):

| Группа | Параметр | По умолчанию | Что делает |
|---|---|---|---|
| Линии скорости | `speed_alpha` / `speed_from` | 0.7 / 0.12 | Прозрачность на полной скорости; ниже порога силы (`camera_fx.speed_lines`) линий нет |
| Линии скорости | `speed_vertical` | 13 → 28 м/с | Вертикальная скорость (супер-прыжок, падение): с первой появляются, на второй полные |
| Линии скорости | `speed_follow` / `speed_flicker_hz` / `speed_pulse_scale` | 12 / 12 Гц / 0.04 | Сглаживание, «бег» (зеркалирование текстуры), дыхание масштабом |
| Линии скорости | `speed_color` / `speed_rage_color` | белый / оранжевый | Цвет; в берсерке |
| Виньетка берсерка | `rage_alpha` / `rage_pulse` / `rage_pulse_hz` | 0.85 / 0.15 / 1.6 Гц | Виньетка в берсерке и её пульсация |
| Виньетка берсерка | `rage_breathe_scale` / `rage_start_flash` / `rage_flash_decay` | 0.03 / 1.0 / 1.5 | Дыхание масштабом, вспышка при включении и её спад |
| Виньетка берсерка | `rage_tease_from` / `rage_tease_alpha` / `rage_follow` | 0.8 / 0.22 / 8 | Шкала почти полная — слабое мерцание; сглаживание |
| Идеальный хват | `catch_size_px` / `catch_grow` / `catch_time` / `catch_limit` | 170 px / ×2.2 / 0.32 с / 2 | Золотое кольцо у руки: размер, рост, длительность, пул |

Комиксовые слова на рисованных «взрывах» `sprites/vfx/comic_burst_01..06` — поля `kit_*` в `scripts/comic_fx.gd` (раздел выше).

## Отладка — автозагрузка `scripts/perf.gd` (`Perf`)

F3 — оверлей кадров. `hitch_ms` 33: кадр дольше этого пишется в `user://hitches.log`.

## Забег — автозагрузка `run/run_manager.gd`

`rooms_per_run` 7 (запасной вариант без карты мира; с картой — `RunMap.rooms`), `miniboss_rooms` [3] (берётся из карты). **Слава по GDD 15.2** (блок Г): база — Слава врага из `enemies/defs/*.tres` (корм 1, боец 3, особый 5), элита `glory_elite_kill` 15, босс `glory_boss_kill` 150, мини-босс — 50 (в `MinibossDef`); враг без описания — `glory_per_kill` 3. Множители: добивание мили ×1.5 (`glory_melee_kill_mult`), ренжем ×0.5 (`glory_ranged_kill_mult`), ранг шкалы стиля ×1…×1.6 (`Run.style_glory_mult`, раздел «Шкала стиля»), тело (`BodyDef.glory_mult`: Трэлл ×2, Солдат ×0.7). У обычного корма `glory_fodder_flat` true: на базовую награду и бонусы убийства не действуют множители оружия и ранга, но множители тела и руны остаются. Бонусы: серия 10 убийств `glory_streak_bonus` +10, мультикилл `glory_multikill_bonus` +1 за каждого; корм в денежный мультикилл не входит и его не получает (`glory_fodder_multikill` false), но считается в общей серии, шкале и комиксе. Шмяк об стену `glory_wall_splat_bonus` +1, зал зачищен `glory_room_clear` +5, финишер `glory_combo_finisher_bonus` 0. Например, 20 корма и 5 бойцов, убитых мили за 0.6 с при ранге и множителе тела ×1: 20 базовых за корм + 20 за серии + 25 базовых за бойцов + 10 за мультикилл бойцов = 75 Славы. Вердикт — `verdict()` (80 «Сойдёт», 200 «Вальхалла»).

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

## Звук и голос владельца — `scripts/audio.gd` (`Audio`), `data/owner_audio.json`, `tools/import_owner_audio.py`

| Где | Параметр | По умолчанию | Что делает |
|---|---|---|---|
| Audio | `voice_volume_db` | 0 | Громкость голоса (клипы ≈ −16 LUFS, шина Voice) |
| Audio | `grunt_chance` / `grunt_cooldown` | 0.3 / 6 с | «Хха!» Тора на сильном ударе и ударе-приземлении |
| Audio | `pain_chance` / `pain_cooldown` | 0.6 / 4 с | «Ух!» Тора при уроне |
| owner_audio.json | `sfx.<звук>.pitch` / `db` / `min_interval` | 1 / 0 / 0 | Высота (поверх случайных 0.9–1.1), поправка громкости, «не чаще» для звука владельца |

Один голос за раз: реплика пузыря/`Odin.say` не перебивает звучащий голос (остаётся без озвучки), реплика окна новеллы перебивает, кряхтение никого не перебивает. Громкость файлов (`import_owner_audio.py`): эффекты — пик ≤ −1 дБTP и не громче синтеза, который заменяют (потолок громкости 300 мс — таблица `SFX`), голос ≈ −16 LUFS (пик −1.5 дБTP), музыка ≈ −14 LUFS.

## Бой-реплики и причина смерти — `run/run_tracker.gd`

`idle_time` 4 с / `idle_speed` 0.6 («ДВИГАЙСЯ!»), `multikill_count` 3 за `multikill_window` 0.8 с («Хоть что-то»), `big_damage_fraction` 0.35 HP за `big_damage_window` 3 с («Скуф…»), `quick_death_time` 45 с («быстро сдох»), `long_life_time` 420 с («долго жил»), `fall_death_y` −15 (ниже — смерть от падения).

Тексты — `data/dialogues/*.json`: правь прямо в JSON (формат в `STORY.md`).

## «План тренировок» — `run/unlocks/*.tres` (`run/unlock_def.gd`), `ui/training_plan.gd`

Цены и эффекты — в файлах открытий (инспектор): `price`, `amount` (для перков: `move_speed_pct` 0.05, `max_health` 20, `dash_charges` 1, `catch_window` +0.05 с, `start_silver` 30, `shop_discount` 0.15, `first_rune_level` 2), `requires`, `available` (перк уже работает). На экране: `card_height` 92, `glory_pulse_time` 0.25.
Цены открытий увеличены ×5 и округлены до 50; самое дешёвое стоит 400. Уже накопленная Слава не меняется.
Слава за забег целиком уходит в копилку (`Save.data.glory.bank`).
Обычный JSON: событие → список фраз. Добавляй сколько хочешь.

## Оружие правой руки (этап 1) — `weapons/defs/*.tres` (`weapons/weapon_def.gd`)

Каждое оружие — отдельный ресурс: дублируй `.tres`, поменяй поля — оружие появится само (в пуле выпадения, если `in_drop_pool`). 1 У (GDD) = 22 урона.

| Оружие | Урон | Скорость | Бег | Особое | В пуле |
|---|---|---|---|---|---|
| Топор `axe` | 30, комбо 3: ×1 ×1 ×2.2 | 0.7 | ×1.0 | вертушка и воздушная рубка | да |
| Меч `sword` | 14, комбо 4: ×1 ×1 ×1 ×1.8 | 1.5 | ×1.1 | выпад и парирование | да |
| Посох `staff` | 16, комбо 3: ×1 ×1 ×1.8 | 1.0 | ×1.0 | шест и волна | нет |
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

Поля мили: `attack_speed` (делитель базовых таймингов топора), `reach` (ход хитбокса вперёд), `arc` (ширина хитбокса), `combo_count`, `stage_damage_mult`, `swing_set` (slash/thrust), `knockback_mult`, `max_targets`, `stun_on_hit`, `backstab_mult` (в спину, по умолчанию 1.5), `stunned_mult`, `heavy_damage_mult` 2 / `heavy_windup` 0.4 (для оружия без приёма), `hitstop_mult`.

**Приёмы Д2** — поля группы «Приём» в `WeaponDef`; удержание ЛКМ `skill_hold_time` 0.35 с. Базовый урон каждого оружия масштабируется по уровню через `level_mult`: ×1 / ×1.2 / ×1.4.

- **Топор, вертушка:** `skill_duration` 0.6 с, `skill_radius` 2.5 м, `skill_damage_mult` 1.0, `skill_knockback` 3, скорость передвижения `skill_move_mult` ×0.45. На ур. 3 радиус `skill_lvl3_radius_mult` ×1.4 и `skill_lvl3_turns` 2 оборота. Воздушная рубка: `skill_dive_speed` 18 м/с, `skill_dive_radius` 2 м, `skill_dive_damage_mult` 0.4 — 12 урона на ур. 1 и 16.8 на ур. 3.
- **Меч, выпад:** `skill_lunge_distance` 5 м за `skill_lunge_duration` 0.3 с, радиус линии `skill_lunge_hit_radius` 0.8 м. На ур. 3 длина `skill_lunge_lvl3_distance_mult` ×1.3 и `skill_lunge_lvl3_count` 2 выпада. Парирование: `skill_parry_window` 0.2 с, `skill_parry_lvl3_window_mult` ×1.5, оглушение `skill_parry_stun` 1.5 с.
- **Посох, шест:** `skill_vault_height_mult` ×1.6 высоты обычного прыжка, волна радиусом `skill_wave_radius` 2.5 м и отбрасывание `skill_wave_knockback` 5. На ур. 3 отбрасывание `skill_wave_lvl3_knockback_mult` ×1.6 и урон `skill_wave_lvl3_damage_mult` ×0.8 базового.
- Очки стиля: `melee_whirl` 6, `melee_lunge` 6, `melee_vault` 5, `melee_dive` 7, `melee_wave` 5; парирование использует существующий `reflect` 8.
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
Слои: `base` (фон: бас и пэды) → `drums` (бой: есть живые враги) → `full` (шкала стиля: ранг «Достойно» и выше в бою или берсерк — `Player.music_intensity`). Треки: `menu`, `plan` («План тренировок»), `midgard`, `miniboss`, `boss`, `shop` (включается `Music.play_track("shop")`).
Заглушки синтезирует `python3 tools/make_sfx.py music` (нужен ffmpeg). Настоящие треки — положить файлы с теми же именами (.ogg или .wav), все слои трека одной длины.
**Треки владельца (блок Б6)** — `sounds/owner/music/<трек>/` (`midgard`, `jarl`, `shop`; `jotunheim`, `helheim` — на будущее, не в экспорте), важнее синтеза. Слои — одна петля 30 с через НЧ-фильтр: `base` 1000 Гц (−2.5 дБ), `drums` 3800 Гц (−1 дБ), `full` — оригинал ≈ −14 LUFS (`tools/import_owner_audio.py`, `LAYERS`, `MUSIC_LUFS`). Они **сменяют** друг друга (перекрёстно за `layer_fade`, линейно по амплитуде), а не складываются. Темп — `data/owner_audio.json` → `music.<трек>.bpm` (Мидгард 120, Ярл 125, ларёк 100).

## Портреты — `sprites/portraits/<speaker>_<emotion>.webp|png`, `ui/portrait.gd`, `ui/dialogue_box.gd`

Окно диалога: `portrait_size` 440×660 (пропорции спрайтов 2:3), `portrait_bottom` 40 (низ портрета уходит под плашку текста). Пузырь реплики: крупный план лица, `face_crop` 0.34 (сторона квадрата в долях ширины холста), центр — глаза из `data/portrait_faces.json`. Импорт портретов: WebP с потерями 0.85, не больше 1024 по высоте (иначе сборка выросла бы на ~70 МБ).
## Тела смертных (блок Л) — `run/movement/*.tres`, `run/passives/*.tres`, `run/bodies/*.tres`

**Стиль движения** — `run/movement/<стиль>.tres` (`MovementProfile`), имя файла = `BodyDef.movement_style`. Игрок копирует числа в свои поля (`Player.apply_movement_profile`), без тела — значения из группы «Стиль движения» узла Player (= Базовый). Руны Мьёльнира — у тела (`BodyDef.dash_charges`: Берсерк 1, Охотник и Гонец 3, остальные 2), чтобы перк «+1 рывок» работал у всех.

| Стиль (тела) | Что меняет | Числа |
|---|---|---|
| Базовый (Трэлл) | — | рывок 24 / 0.16 с, восстановление рун 2.5 с, двойной прыжок, 2 отскока от стены |
| Шустрый (Охотник) | короткие рывки | `dash_duration` 0.11, `dash_recharge` 1.67 |
| Шустрый+ (Гонец) | ещё быстрее перезарядка (своё решение: GDD не уточняет, чем «+» отличается) | `dash_duration` 0.13, `dash_recharge` 1.25 |
| Таран (Берсерк) | 1 длинный рывок сквозь врагов | `dash_speed` 26, `dash_duration` 0.34, `dash_recharge` 3.33, `dash_ram`; `ram_damage` 15.4 (0.7 У), `ram_knockback` 13 (в стороны), `ram_knock_up` 4, `ram_radius` 1.4, `ram_prop_impulse` 9 (бочки) |
| Прыгун (Скальд, Дева щита) | тройной прыжок, рывка на земле нет | `extra_jumps` 2, `wall_jumps` 3, `wall_jump_mult` 1.25, `dash_on_ground` false |
| Тяжёлый (Жрец, Кузнец) | нет двойного прыжка, мощный удар-приземление | `extra_jumps` 0, `slam_radius_mult` / `slam_damage_mult` 1.5, `slam_stun` 1 с, `slam_bounce_mult` 1.35 |
| Скользящий (Солдат) | рывок на земле → подкат на скорости рывка | `dash_to_slide`, `slide_friction` 0, `momentum_cap` 2.2, `keep_air_momentum` (в воздухе скорость не гасится — bunny-hop) |

**Правила ощущений (GDD 7.4)**, узел Player: `air_control` 0.7; `momentum_cap` 1.8 (предел горизонтальной скорости от рывка, подката и отскоков, × скорость бега); `dash_momentum_bonus` 3 (рывок прибавляет к текущей скорости: выход из рывка = max(24 × 0.55, скорость до рывка + 3), но не выше предела).

**Подкат (GDD 5, 7.2)** — Ctrl + Shift на земле (тратит руну Мьёльнира): `slide_speed` 13 (не ниже текущей), `slide_duration` 0.55 с, `slide_friction` 9 м/с² (у Скользящего 0), `slide_steer` 2.5 рад/с, `slide_camera_drop` 0.55 м, `slide_min_speed_ratio` 0.8 (медленнее — подкат кончается). Прыжок из подката сохраняет скорость. Камера: `crouch_speed` 12 (`camera_fx.gd`).

**Пассивки и изъяны** — `run/passives/<id>.tres` (`PassiveDef`: `implemented`, `todo`, `handler`) + скрипт `run/passives/<id>.gd` (`BodyTraitHandler`). Числа — в инспекторе вложенного ресурса `handler`:

| Черта (тело) | Поля |
|---|---|
| Кровавая ярость (Берсерк) | `damage_per_lost_pct` 1.0, `max_bonus` 0.5 |
| Орёт и плохо лечится (Берсерк) | `heal_mult` 0.5, `shout_chance` 0.3, `notice_radius_mult` 1.5 |
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
| Мастер щита (Дева щита) | `window_mult` 2, `heal_on_parry` 5; окно меча 0.4 с, на ур. 3 — 0.6 с |
| Не её оружие (Дева щита) | `ranged_mult` 0.75 |

Экран выбора тела (`ui/body_select.gd`): `columns` 3, `card_size` 230×100. Реакция Одина на смерть тела — `body_death_chance` 0.35 (`scripts/dialogue_manager.gd`).

## Шкала стиля «ДОСТОЙНО!» (блок Б3, GDD 8) — `player/style_tuning.tres` (`StyleTuning`), узел **Player/StyleMeter**

**Очки за приём** (`points`, при первом применении). Убийства — по источнику урона:

| Приём | Очки | | Приём | Очки |
|---|---|---|---|---|
| мили-убийство `kill_melee` | 4 | | сбил с края / с высоты `kill_fall` | 14 |
| финишер комбо `kill_finisher` | 6 | | убийство шмяком о стену `kill_wall` | 12 |
| сильный удар `kill_heavy` | 7 | | отражённым снарядом `kill_reflect` | 12 |
| ренжем `kill_ranged` | 2 | | рывком/тараном `kill_dash` | 7 |
| ударом-приземлением `kill_slam` | 9 | | взрывом (бочка, Раздутый) `kill_explosion` | 10 |
| прыжком по голове `kill_stomp` | 12 | | огнём `kill_fire` / прочее `kill_other` | 5 / 3 |
| Мьёльниром и его молниями `kill_hammer` | 9 | | мульти-килл 3 за 0.8 с / 5 — `multikill` / `multikill_big` | 10 / 15 |
| отскок от удара-приземления `slam_bounce` | 5 | | прыжок по головам `stomp` | 5 |
| идеальный хват `perfect_catch` | 8 | | шмяк о стену `wall_splat` | 6 |
| отражение снаряда `reflect` | 8 | | | |

| Параметр | По умолчанию | Что делает |
|---|---|---|
| `rank_points` | 0 / 15 / 35 / 60 / 100 | Начало рангов Скуф / Сойдёт / Неплохо / Достойно / ДОСТОЙНЕЙШИЙ! (100 — полная шкала, берсерк) |
| `rank_glory_mult` | 1 / 1.1 / 1.25 / 1.4 / 1.6 | Множитель Славы за убийство на ранге (`Run.register_kill`, без бонуса босса) |
| `rank_drain` | 0 / 0.6 / 1.2 / 2 / 0 очков/с | Постоянная утечка на ранге (берсерк не течёт) |
| `repeat_falloff` / `repeat_min_mult` | 0.6 / 0.15 | Повтор того же приёма: ×0.6 за каждое недавнее применение, не меньше ×0.15 |
| `repeat_memory_decay` / `repeat_memory_max` | 0.35/с / 4 | Память о приёме тает; потолок — приём «отдыхает» не дольше ~11 с |
| `idle_delay` / `idle_drain` | 2.5 с / 5 очков/с | Без новых очков — шкала пустеет (сверх утечки ранга) |
| `damage_knock_min` / `damage_knock_per_hp` | 12 / 0.8 | Урон по Тору: минус max(12, урон × 0.8) очков; в берсерке — нет |
| `multikill_count` / `multikill_big_count` / `multikill_window` | 3 / 5 / 0.8 с | Мульти-килл |
| `berserk_time` | 8 с | Берсерк на высшем ранге |
| `damage_mult` / `speed_mult` | 1.5 / 1.5 | Урон Тора (всё, что идёт через `deal_damage`) и скорость бега в берсерке |
| `hitstop_on_start` | 0.12 с | Хит-стоп при включении |
| `after_berserk_rank` | 2 | После берсерка — середина ранга «Неплохо» (47.5) |
| `music_full_rank` | 3 | С «Достойно» в бою — полный трек (`Music`, слой full), ниже — барабаны |
| `voice_rank` / `voice_cooldown` / `voice_retry_time` | 3 / 30 с / 2.5 с | «Достойно!» Одина (`odin.rank_worthy`, с лимитом 12 с; занят — пробует ещё 2.5 с), та же реплика ранга — не чаще 30 с; «ДОСТОЙНЕЙШИЙ!» (`odin.rank_top`) — без лимита, чаще 30 с — пул `berserk` |
| `rank_pop_cooldown` / `rank_pop_delay` | 4 с / 0.45 с | Слово комикса ранга (`rank_1..rank_4`): не чаще раза в 4 с на ранг, через 0.45 с после приёма (высший — сразу крупно) |

Руна «Песнь берсерка» — набор ×1.3 / ×1.55 / ×1.8. Тело может менять набор: `modify_stat("style_gain_mult")`. Только мили-убийства раз в 0.5 с держат шкалу около «Неплохо» — выше нужно разнообразие.
HUD (`ui/style_hud.gd`): `bar_width` 340, `caption_height` 58, `burst_size` 210×92, `punch_scale` 0.5 / `punch_decay` 3 (удар подписи при повышении), `vignette_alpha` 0.75; картинки комплекта `hud_rage_frame` + `hud_rage_fill`, `comic_burst_01..06`, `vfx_rage_vignette` (через `UISkin`).

Бой-реплики Одина (GDD 17), лимит — `combat_cooldown` 12 с (`run/odin.gd`, «berserk» и «rank_top» — без лимита): «ДВИГАЙСЯ!» `idle_time` 4 с, мульти-килл `multikill_count` 3 за `multikill_window` 0.8 с, «Скуф…» `big_damage_fraction` 0.35 HP за `big_damage_window` 3 с, «Позорище» — добил ренжем (`run/run_tracker.gd`; мульти-килл важнее), «Вот! ВОТ!» — удар-приземление с `big_slam_height` 9 м (узел Player). Тексты — пулы `idle`, `multikill`, `big_damage`, `ranged_kill`, `big_slam`, `rank_worthy`, `rank_top`, `berserk`, `rage_over` в `data/dialogues/odin.json`.

## Руны по уровням (блок Т) — `run/runes/*.tres`

У каждой руны `level_values` (ур. 1–3) и иногда `level_values_b` (второе число), `value_kind`: add / mult / interval (как руна усиливается у Старого жреца: значение ×2, множитель (v−1)×2+1, «каждый N-й» → N/2). Повтор руны повышает уровень, максимум 3 (`Run.RUNE_MAX_LEVEL`); руны ур. 3, проклятые и без механики в обычный выбор не попадают. Числа — по таблице GDD 11 (например, Яблоко Идунн 30/55/80, Руна Тюра +25/40/60 %, Зов грома — каждый 5/4/3-й удар).
Игрок (`Player`, группа «Криты и руны»): `crit_chance_base` 0.05, `crit_mult` ×2, `crit_hitstop` 0.09 с (GDD 8, 19), `thunder_call_damage` 22 (1 У), `hiccup_period` 10 с, `spin_chance_per_sec` 0.03.
Проклятые руны Локи (`cursed = true`, выдаются `Run.random_cursed_rune()` — для сделки Локи): Икота Локи (урон ×1.5, сам подпрыгивает раз в 10 с), Вертушка Локи (+2 рывка, камера иногда крутится на 180°), Стеклянная пушка (урон ×1.8, входящий ×1.5).


## Структура забега и двери-награды (блок И, GDD 15.1)

**Мир** — `run/maps/midgard.tres` (`run/run_map.gd`, `RunMap`):
- `rooms` 7 (залов до босса), `miniboss_room` 4 (мини-босс — последней волной 4-го зала, за него трейт), `first_room_reward` combat.
- Двери: `doors_min` 2 / `doors_max` 3, `shop_per_world` 1 (ларёк гарантирован: дверь ларька в каждом наборе, пока не зайдёшь), `shop_earliest_room` 3, `no_peaceful_twice` (отдых и ларёк не подряд), `shop_scene`; наковальня Эйтри (стихия Мьёльнира, блок Б4) — `anvil_per_world` 1, в наборах к залам `anvil_earliest_room` 2 … `anvil_latest_room` 3 (награда `run/rewards/anvil.tres`, вес 0).
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

## HUD и настройки (блок С, GDD 18, 22)

**HUD** — `ui/hud.gd` (узел HUD сцены игры): `hp_bar_height` 84 (полоса HP, ширина по рамке 768×192 — ×4), `hammer_icon_size` 58 (иконка Мьёльнира), `dash_icon_size` 38 (максимальный размер руны на бойке молота), `slam_meter_min_height` 2.5 м (с какой высоты над полом видна шкала удара-приземления в рукояти молота; полная шкала — `Player.big_slam_height` 9 м), `crosshair_base_size` 30 px (точка ×1.4; множитель — настройка), `rune_icon_size` 36.
- Полосы `ui/skin_bar.gd`: след урона `trail_speed` 0.6 полосы/с после `trail_delay` 0.35 с. Полоса босса `ui/boss_bar.gd`: `trail_speed` 0.35.
- Шкала стиля `ui/style_hud.gd`: `bar_width` 340 (высота — четверть ширины), подпись ранга `caption_height` 58 (раздел «Шкала стиля»).
- Оружие `ui/weapon_hud.gd`: `slot_size` 96, `active_slot_size` 112.
- Индикаторы врагов за экраном `ui/offscreen_indicators.gd`: `max_distance` 30 м, `max_count` 8, `near_size` 40 / `far_size` 24 px, `edge_margin` 46 px.
- Карточки выбора: `RunePick.card_width` 300, `TraitPick.card_width` 340 (высота — по пропорциям card_rune/card_trait 390×522; длинный текст ужимается до размеров окна), выбор наград — 260.

**Настройки** — `scripts/settings.gd` (`GameSettings.DEFAULTS`): звук общая 100 % / музыка 80 % / эффекты 100 % / голоса 100 %; чувствительность мыши и стика ×1.0 (база 0.0022 и 3.0); FOV 85 (70–110); тряска 100 %; покачивание вкл; масштаб интерфейса 100 % (75–150 %); прицел «точка», размер 100 %, яркость 85 %, белый; индикаторы за экраном и шкала высоты — вкл; размер текста 100 %, скорость печати ×1 (0 — сразу целиком); помощь в прицеливании и замедление — выкл.
- Помощь в прицеливании: `RangedWeapon.aim_assist_cone_deg` 6° (центр разброса — на ближайшего видимого врага в конусе).
- Замедление при ударе-приземлении: `Player.slam_assist_time_scale` 0.5 (на падение и окно супер-прыжка/отскока; hit-stop главнее).

## Графика экранов (комплект владельца, 27.10)
- **Заставка босса** `ui/boss_card.gd` (`BossCard`, Свен и Ярл): `hold_time` 1.7 с на месте, `fly_in_time` 0.26 / `fly_out_time` 0.22 с, `flash_time` 0.15 с, `tilt_deg` −3°, `width_frac` 0.74 (ширина карточки от экрана). Защита от случайного пропуска — `skip_guard` 0.3 с (`ui/comic_insert.gd`, общее у вставок).
- **«Страница комикса»** `ui/comic_page.gd` (`ComicPage`): `hold_time` 2.1 с, `flash_time` 0.15 с (белая вспышка), `slam_time` 0.2 с (кадр «влетает»), `second_delay` 0.18 с (иллюстрация причины — позже), `fade_out_time` 0.22 с, наклоны `tilt_main` −3.5° / `tilt_second` 3°, `slam_scale` 1.35, `shot_max_width` 1600 px (стоп-кадр шире — уменьшается). Растр — uniform'ы `shaders/comic_page.gdshader`: `dot_spacing` 5, `dot_strength` 0.42, `levels` 7, `poster_mix` 0.55, `saturation` 1.18, `paper_mix` 0.18.
- **Загрузочный экран** `ui/loading_screen.gd`: `fade_out_time` 0.6 с (исчезает, когда зал уже загружен), `safety_time` 12 с (сам прячется, если некому скрыть).
- **Выбор тела** `ui/body_select.gd`: `columns` 2 (было 3), `card_size` 212×74, `portrait_width` 300 (портрет 2:3), `portrait_slide` 36 px за `portrait_slide_time` 0.18 с, `backdrop_alpha` 0.2 (фон-деревня).
- **«План тренировок»** `ui/training_plan.gd`: `art_size` 76 (картинка открытия на карточке), `backdrop_alpha` 0.22 (фон-комната у дивана).
- **Окно новеллы** `ui/dialogue_box.gd`: `story_fade_time` 0.35 с (наплыв сюжетного кадра), `backdrop_brightness` 0.82 (картинка-фон чуть темнее).
- Настройки `[comic]`: `page` (стоп-кадр комикса) и `boss_card` (заставка босса) — по умолчанию вкл.
## Разрушаемое — `props/destruct_tuning.tres` (`props/destruct_tuning.gd`, `DestructTuning`), поля `Destructible` на `props/*.tscn`
**Пропсы** (генератор `build_props`, поля `props/destructible.gd`): бочка `max_health` 15 (1 удар любым мили), ящик 30 (2 обычных удара; финишер, сильный, Мьёльнир 33, рывок — один), взрывная бочка 10. `break_speed` 0 = `Economy.barrel_break_speed` 8 м/с (старое правило: отбросило быстрее — удар о стену, падение с высоты). `knock_impulse` 0.6 (удар без разрушения толкает: knock × масса × 0.6). Обломки: бочка `debris_mode` "radial", `debris_sectors` 6 (+ крышка и дно = 8 кусков), ящик "box" (6 стенок). Огонь: `burn_time` 2.5 с (взрывная — 1.2), `fire_spread_delay` 1.0 с, `fire_spread_radius` 1.5 м — поджигает соседей.
- Взрывная бочка: `blast_radius` 4 м, `blast_damage` 40 (Blast: Тор, враги, пропсы), `chain_delay` 0.22 с (от чужого взрыва/огня — цепная реакция волной), `melee_fuse` 0.6 с (ударил вплотную — шипит, успей отскочить; ренж и молот — сразу).
**DestructTuning:** `source_mult` ренж ×2 (пистолет — 2 выстрела на бочку), удар-приземление ×1.5, взрывы ×1.5, удары врагов по площади ×2; `slam_full_damage` вкл (без спада к краю); `dash_damage` 40 (рывок/таран в пропс, раз за рывок); `boss_charge_damage` 80 (таран Свена/Ярла).
- Обломки (`props/prop_debris.gd`): `debris_limit` 40 на зал (сверх — старые исчезают), `debris_life` 3.5 с (±15 %), `debris_sink_time` 0.7 с / `debris_sink_depth` 0.45 м (провал в пол), разлёт `debris_knock_ratio` 0.55 от силы удара (не больше `debris_knock_max` 11 м/с), `debris_outward` 2.6, `debris_up` 2.8 м/с, `debris_spin` 9 рад/с, `debris_mass` 0.35 кг.
- Отдача: `break_hitstop` 0.035 с (если разбил Тор), `break_shake` 0.12 (ближе 6 м), `hit_chips` 5 щепок при ударе без разрушения.
**Содержимое** — `run/economy.tres`: бочка 3–8 серебра (GDD 15.2); ящик — `crate_silver_chance` 0.45 (2–5 серебра), `crate_ammo_chance` 0.2 (без ренжа — горсть серебра), `crate_heal_chance` 0.15 (`crate_heal_amount` 12 HP шаром), иначе пусто. «Сюрприз»: `explosive_barrel_chance` 0.15 на бочку, `explosive_barrel_max` 2 на зал (хотя бы 2 обычные остаются; привал и ларёк — без).
**Мосты и настилы** (`rooms/balcony.gd`): `slam_breakable` (генератор ставит у деревянных блоков над полом — мост деревни, Биврёст; балконы Ярла — нет), `slam_break_height` 1 м, тряска `shake_time` 0.45 с, доски живут `debris_lifetime` 4 с.

## Графика мира — `data/world_art.tres` (`scripts/world_art_tuning.gd`, `WorldArtTuning`) и `run/maps/<мир>.tres`
**Небо и атмосфера мира** (группа «Небо и атмосфера» у `RunMap`, Мидгард): `sky` = `assets/sky/midgard.webp`, `sky_energy` 1.0, `sky_rotation_deg` −35, `exposure` 0.88 (блок Б0, ACES; было 0.78 с Filmic), `ambient_energy` 0.3, `ambient_sky_contribution` 0.4, `ambient_color` (0.62, 0.52, 0.46), `fog_color` (0.66, 0.47, 0.38), `fog_density` 0.008, `fog_sky_affect` 0 (иначе дымка закрашивает панораму), `ground_fog`/`dust_motes`/`torch_embers` — вкл, `ground_fog_color` (0.95, 0.84, 0.78, α 0.3).
- **Декали:** круг прыжковой руны — диаметр × 2.5 радиуса руны, яркость 1.3, «дыхание» 5 %; круг двери — 3.6 м, яркость 1.2, на 0.7 м перед аркой; над полом 0.03 м. Подпалина (`data/vfx_tuning.tres`, группа «Подпалина»): размер = радиус × 1.7 (1.4–6 м), лежит 8 с после огня, гаснет 2.5 с, прозрачность 0.12, пул 10. Лужа браги: квад = радиус замедления × 2.5 (`BrewPuddle.DECAL_SCALE`).
- **Декор:** отступ от стены 0.06 м (+ `WALL_INSET` 0.03 у генератора), порог альфы 0.4. Высота (видимая часть): знамёна сбоку 2.3 м, у выхода 2.1 м, щиты 1.05–1.15 м, плакаты 1.4–1.9 м, гобелен 3.0–3.6 м, вывеска ларька 1.7 м (`ShopStall.SIGN_HEIGHT`).
- **Искры факелов:** 5 шт., живут 1.3 с, 0.06–0.12 м, подъём 0.5–1.1 м/с. **Очаг:** 18 искр, 2.4 с, 0.05–0.1 м, 1.2–2.6 м/с; 7 языков пламени 1.1–1.7 м.
- **Пылинки:** 3.5 на 100 м² (до 40), 9 с, 0.06–0.14 м, на высоте 0.6–4.5 м, α 0.18; у камеры гаснут (1–3.5 м).
- **Низкий туман:** 4 клуба на 100 м² (до 26 на вариант, 2 варианта текстуры), 16 с, 3.5–6 м, высота 0.12–0.85 м, дрейф до 0.18 м/с.

## Одевание залов и свет мира (блок Б0) — `run/maps/<мир>.tres` (группы «Свет и цвет», «Закрытый зал»), `rooms/materials/*.tres`, `data/vfx_tuning.tres`
**Свет мира** (`RunMap`, Мидгард): `sky_rotation_deg` −35 (солнце панорамы — с юго-запада, как прежний свет; середина панорамы = +Z), `sky_sun_uv` (0.5, 0.478) — где диск на `midgard.webp` (замер по яркости), `sun_elevation_deg` 50 (на панораме диск у горизонта — тени во весь зал нечитаемы; 38 — тень стены с частоколом закрывала ползала), `sun_color` (1, 0.82, 0.64), `sun_energy` 1.2, `exposure` 0.88 (было 0.78: ACES темнее Filmic).
- Тонмаппинг ACES, `tonemap_white` 6; `adjust_contrast` 1.06, `adjust_saturation` 1.06; кривая цвета `grade_shadows` (0.035, 0, 0.06) — фиолетовые тени, `grade_midtones` (0.53, 0.48, 0.45), `grade_highlights` (1, 0.95, 0.86) — тёплые света (GDD 16: закат).
- SSAO `ssao_intensity` 1.8 / `ssao_radius` 1.2 м; SSIL вкл., 0.7; glow 0.65 / bloom 0.06; объёмный туман `volumetric_fog_density` 0.006, альбедо (0.95, 0.76, 0.62), свечение (0.03, 0.015, 0.01), длина 48 м. В GL Compatibility SSAO/SSIL/объёмного тумана нет — затемнение запечено в пол (цвет вершин) и полосы у стен.
- Тени факелов `torch_shadows` 2 (Forward+; сначала у выхода, двойной параболоид, bias 0.08).
- **Закрытый зал** (`Room.indoor`, длинный дом Ярла): фон (0.04, 0.03, 0.025), рассеянный (0.62, 0.46, 0.34) × 1.0, дымка (0.24, 0.17, 0.12) плотностью 0.01, экспозиция 1.25, объёмный туман 0.01, солнце — 0. Очаг 2.4 / 13 м, огни у двух люстр 1.3 / 11 м (`tools/dress_arenas.gd`). Крыша: уклон 28°, свес 0.4 м (`ROOF_PITCH`, `ROOF_OVERHANG`).

**Поверхности** (`shaders/world_surface.gdshader`, параметры — `SURFACES` в `tools/room_dresser.gd`, после правки — перезапуск генератора): `uv_scale` — повторов на метр; второй отсчёт текстуры ×`detail_scale` 0.61, поворот 0.7 рад, смешение по шуму 1/`antitile_scale` = 14 м; пятна яркости `macro_scale` 0.035 (≈ 29 м), сила `macro_strength` 0.25–0.45; второй слой `overlay_*` (доля, масштаб, мягкость, тяга к верхним граням); грязь у основания вертикальных граней до `grime_height` 0.9 м, сила 0.55; `vertex_ao` 1.
| Материал | Текстура | Второй слой |
|---|---|---|
| `surface_floor_brick` | кирпич MegaKit, uv 0.35, нормали 0.8 | пятна земли `dirt_straw` 36 % (масштаб 0.075) |
| `surface_floor_dirt` | `dirt_straw` владельца, uv 0.3 | булыжник `UnevenBrick` 30 % |
| `surface_stone` | `stone_wall` владельца, uv 0.3 | мох 20 %, тяга вверх 0.45 |
| `surface_rock` (валуны, обломки) | RockTrim, uv 0.9 | мох 32 %, вверх 0.8 |
| `surface_wood` (брёвна, частокол) | WoodTrim, uv 0.5 | копоть 22 % |
| `surface_plank` (помосты, настилы, крыша-фронтоны) | `wood_floor` владельца, uv 0.35 | грязь 20 % |
| `surface_pillar` | UnevenBrick, uv 0.45 | мох 16 % |
| `surface_ground`, `surface_cliff` (даль) | `dirt_straw` uv 0.1 / RockTrim uv 0.12 | трава/мох 40–50 % |

**Разброс** (константы `RoomDresser`): кант 0.5 × 0.12 м, куски ≤ 1.6 м, ±1.5°; балки 0.22–0.24 м, куски ≤ 2.6 м, ±0.8°; частокол — шаг 0.34 м, колья r 0.13–0.17, высота 1.0–1.6 м, наклон ±4°; верхний ряд модулей стен — высота ×0.97–1.07, ±0.5°; кучка обломков — 1–2 валуна (×0.45–1.0, утоплены) + 2–4 кирпича (×1.1–1.9) через 1.4–3.4 м вдоль стен (70 %); затемнение пола у стен до 0.42 (в углах — произведение), у блоков 0.5, у колонн 0.55, зона 1.5 / 1.1 / 1.0 м; полоса у стен — 1.5 м, альфа 0.62 → 0; декалей 14 (арены 14–16); даль — 120 сосен на 38–72 м (×0.55–1.15 от 10 м), 26 скал-берег на 72–80 м, 12 скал-островов на 110–220 м.

**Взрыв** (`data/vfx_tuning.tres`, группа «Взрыв»): вспышка `explosion_flash` 1.15 × радиус; огненный шар `explosion_fire` 0.45 × радиус, языки ×`explosion_fire_scale` 1.5 (растут до ×1.25), горит `explosion_fire_time` 0.55 с; дым `explosion_smoke` 3 клуба × `explosion_smoke_size` 0.85 радиуса, цвет (0.36, 0.32, 0.3); звёзды `explosion_stars` 3 × `explosion_star_size` 1.1 м; радиус урона читается по ударной волне `vfx_shockwave` и подпалине.

## Руки от первого лица (блок Б2) — `player/viewmodel_motion.tres` (`player/viewmodel_motion_tuning.gd`, `ViewmodelMotionTuning`) и поля `ViewmodelArm` (`player/viewmodel_arm.gd`, узлы `…/AxePivot/Hand`, `…/HammerPivot/Hand`)
Смещения — м в системе камеры рук (x вправо, y вверх, z к камере), повороты — градусы (x — кивок, y — рыскание, z — крен). Время рук — игровое: в hit-stop замирают, в замедлении — медленнее.
- **Рука (ViewmodelArm):** `rig_scale` 1.7 (модель Drillimpact — человек ~1.75 м), `hand_scale` 1.3 (кисть ×), `forearm_bulk` 1.3 (предплечье толще и длиннее), `upper_bulk` 1.35, `max_upper_stretch` 1.8 (плечо тянется к якорю, не длиннее), `shoulder_anchor` (0.55, −0.95, 0.05) — куда за кадр уходит плечо правой руки (левая — зеркально), `wrist_pitch` 22 (предплечье вниз от кисти), `forearm_yaw` 35 (локоть наружу), `grip_offset` (0, 0, 0) — кулак вдоль рукояти. Пальцы: `fist_anim` guard_idle @0.3, `open_anim` push @0.5, `grab_anim` grab @0.25, `grip_speed` 16. Вид: `skin_multiply` (0.98, 0.82, 0.72) поверх `BodyDef.hand_color`, наруч цвета `BodyDef.sleeve_color`, `bracer_from`/`bracer_to` 0.42–0.9 длины предплечья, `bracer_fit` 1.1 (радиус по вершинам меша).
- **Пружины:** `spring_stiffness` 170, `spring_damping` 17 (отдача, ловля, приземление), `sway_stiffness` 90, `sway_damping` 13, `settle_epsilon` 0.004 (рука «в покое»).
- **Бег:** `bob_side` 0.022, `bob_up` 0.018, `bob_roll` 1.4°, `bob_freq_per_speed` 0.19 (шагов/с на 1 м/с), `bob_max_speed_ratio` 1.6, `bob_when_disabled` 0 (настройка «покачивание» выкл.), дыхание `idle_breath` 0.004 м @ 0.35 Гц.
- **Мышь:** `sway_pos_per_rad` 0.09 м, `sway_rot_per_rad` 9°, пределы `sway_max_pos` 0.06, `sway_max_rot` 6°.
- **Прыжок/приземление/рывок:** `jump_kick` 0.55, `air_jump_kick` 0.35, `land_kick_per_meter` 0.24 (с `land_min_fall` 0.6 м, предел `land_kick_max` 1.6), `slam_land_kick` 2.6, `land_tilt` 60, рывок `dash_pull` (0, −0.05, 0.14) + `dash_tilt` (−8, 0, 0) + `dash_kick` 0.8, подкат `slide_offset` (0.02, −0.06, 0.04) + `slide_roll` 7°, в воздухе `air_lift_per_speed` 0.03, сглаживание `offset_smooth` 14.
- **Мили:** запястье `windup_wrist` (−18, 0, 0) / `strike_wrist` (14, 0, 0), `strike_follow` 0.9 (доводка по ходу взмаха), `hit_recoil` 180 (вздрагивание от попадания), `recovery_blend` 0.45, `finisher_kick` 1.4, `heavy_tremor` 1.6°, `heavy_release_kick` 1.9. Позы ударов — `POSES`/`THRUST_POSES`/`HEAVY_POSE` в `weapons/axe.gd` (замах сильного — над правым плечом).
- **Мьёльнир:** бросок `throw_cock_pos/rot` → `throw_release_pos/rot` за `throw_time` 0.07 → пустая рука `empty_pos/rot` за `empty_time` 0.28; возврат `recall_pos` (0.14, 0.06, −0.12), `recall_rot` (90, 75, −12) — ладонь навстречу, `recall_track` 0.12 (тянется к молоту по экрану), `recall_time` 0.18; ловля `catch_kick` 1.2 / `catch_tilt` 260; идеальный хват `perfect_kick` 2.0 / `perfect_tilt` 420, прокрут `perfect_twirl_time` 0.32 с × `perfect_twirl_turns` 1.
- **Ренж:** `fire_kick_per_deg` 0.55 и `fire_tilt_per_deg` 75 на 1° `recoil_kick_deg` оружия (пределы `fire_kick_max` 2.2, `fire_tilt_max` 300; тяжёлое ещё и возвращается медленнее), перезарядка `reload_low_pos` (−0.1, −0.07, 0.02) / `reload_low_rot` (8, 22, 48) + толчок «магазин» `reload_slap` 0.7, `gun_view_scale` 1.4 (огнестрел крупнее в кулаке Тора).
- **Свитч:** `switch_down_pos` (0.05, −0.55, 0.2), `switch_down_rot` (−45, 0, 0); время — `WeaponHolder.switch_time`.
- **Берсерк:** `berserk_tremor` 0.9°, `tremor_freq` 22.

## Подсказка идеального хвата (`ui/catch_assist.gd`, `MjolnirHand`)
| Число | Значение | Что делает |
|---|---|---|
| `CatchAssist.lead_time` | 0.8 с | за сколько до поимки появляется сходящееся кольцо |
| `CatchAssist.target_radius` | 34 px | целевое кольцо вокруг прицела (при 720p) |
| `CatchAssist.px_per_second` | 150 px | насколько шире кольцо за каждую секунду до поимки |
| `CatchAssist.window_pulse_hz` | 9 Гц | пульс золотого кольца в окне хвата |
| `CatchAssist.feedback_time` | 0.7 с | сколько висит «ИДЕАЛЬНО!/РАНО/ПОЗДНО» |
| `MjolnirHand.catch_feedback_range` | 0.6 с | промах дальше этого — обычное нажатие, без «РАНО/ПОЗДНО» |

## Плейтест владельца 27.10 (вечер)
| Число | Было → стало | Зачем |
|---|---|---|
| `MjolnirHand.throw_cooldown` | — → 7 с | молот спамился; бросок — решение, а не кнопка «всегда» |
| `MjolnirHand.perfect_cooldown_refund` | — → 5 с | идеальный хват — способ бросать чаще |
| `ComicFX.cooldown` | 0.4 → 1.1 с | слова мельтешили |
| `ComicFX.routine_chance` | — → 0.45 | обычные слова (priority < `important_priority` 50) — через раз |
| `ComicFX.fullscreen_events` | любое big → boss_kill, slam (≥ 10 м), rank_4, combo | остальные «big» — крупное слово у места удара (`world_big_scale` 1.6) |
| `ComicFX.multikill_big_count` | 5 → 8 | крупный мульти-килл реже |
| `StyleTuning.rank_pop_delay`, приоритет `rank_1..3` | 0.45 с → 1.15 с; 5–8 → 50–54 | слово ранга — после паузы между словами, не отсекается |
| `ComicFX.distance_ref` / `min_distance_scale` | — → 6 м / 0.45 | слово у далёкой цели мельче |
| Кровь нежити (`sprites/vfx/vfx_ichor_*`, `assets/decals/ichor_splat_*`) | бирюзовая → тёмно-красная | по просьбе владельца |
| Мили-оружие `weapons/defs/*.tres` (урон / скорость / отброс) | нож 11/1.7/0.6 → 7/2.4/0.05; меч 15.4/1.3/1 → 14/1.5/0.6; топор 22/1/1 → 30/0.7/1.5 (шире, тяжелее стоп-кадр); дубина 28.6/0.75/1.6 → 36/0.55/2.2; кирка 26.4/0.75/1 → 34/0.6/1.3; коса 17.6/0.8 → 20/0.75 (ширина 2.0); копьё 19.8/1/0.8 → 18/1.1/0.7 (дальность 1.9) | оружие отличается ощущением: быстрое-слабое против медленного-тяжёлого; DPS примерно равен |
| Хват Мьёльнира | повторное нажатие на возврате засчитывалось → одна попытка | нажал раньше окна — «РАНО», провал на этот возврат |
| Подсветка состояния стихий на враге (`ElementStatus` → `Enemy.status_glow`) | — → горит оранжевый, заморожен голубой, ток жёлтый, прибит коричневый | стихии читаются; тот же оверлей-материал, без новых |
| Цвета стихий | молния голубая → жёлтая (1, 0.9, 0.35), земля → янтарная | не путать молнию со льдом |


## Открытые границы и вышки (Н3)
- Наружные стены открытых залов: только коллизия, низ прежний, верх 24 м (`BOUNDARY_HEIGHT`, `RoomDresser._open_edges`), чтобы прыжковая руна не выбрасывала из уровня. Выход оформлен отдельными воротами; редкие валуны и лесная даль стоят за границей без коллизии. Факелы и знамёна закреплены на отдельных опорах.
- Длинный дом Ярла остаётся закрытым зданием с прежними стенами; арена Свена открыта.
- Наблюдательные вышки залов 1 и 6: площадка на высоте 3.75 м, четыре ступени с северной стороны по 0.75 м; в зале 1 дополнительная прыжковая руна подбрасывает на 8 м. Геометрия и координаты — `watchtowers`/`jump_pads` в `room_defs()`, шаблон — `_watchtower()`. Проверка подъёма — `tests/tower_test.tscn`.
## Комиксовая обводка — `data/outline_tuning.tres` (`OutlineTuning`)

Один общий `ShaderMaterial` (`shaders/outline.gdshader`) для врагов, боссов, оружия на полу, сундуков, ящиков, бочек и Мьёльнира в полёте; стены и руки от первого лица без обводки. Числа меняются в ресурсе: `color` (0.03, 0.02, 0.02), `width_px` 5 px при высоте кадра 1080, `near_dist` 6 м, `min_scale` 0.4, `depth_push` 0.04 м. В «Экран» — выключатель и множитель `outline_width` от 0.5 до 2.0 (по умолчанию 1.0); при выключении существующие вспышки и подсветка стихий сохраняются. Обводка не использует instance uniform, её материал прогревается при входе в зал.
