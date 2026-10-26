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

`throw_speed` 32, `base_damage` 30, `auto_return_after` 1.5 с, `return_speed` 36, `return_turn_accel` 140 (дуга возврата), `max_wall_bounces` 2, `chain_damage_ratio` 0.5, `chain_radius` 7, `hit_hitstop` 0.04.

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

## Отладка — автозагрузка `scripts/perf.gd` (`Perf`)

F3 — оверлей кадров. `hitch_ms` 33: кадр дольше этого пишется в `user://hitches.log`.

## Забег — автозагрузка `run/run_manager.gd`

`rooms_per_run` 4, Слава: `glory_per_kill` 10, `glory_combo_finisher_bonus` 5, `glory_multikill_bonus` 15, `glory_wall_splat_bonus` 5, `glory_room_clear` 25, `glory_boss_kill` 150. Пороги вердикта — функция `verdict()` (150 «Сойдёт», 400 «Вальхалла»).

## Тела и руны — ресурсы `run/bodies/*.tres`, `run/runes/*.tres`

Дублируй файл → поменяй поля в инспекторе → новое тело/руна появится в игре само. Эффекты рун по `id` — в `player.gd → recalc_from_runes()` и `scenes/game.gd → _on_rune_picked()`.

## Реплики Одина — `data/odin_lines.json`

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
