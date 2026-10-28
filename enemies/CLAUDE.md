# enemies/ — враги, элита, мини-боссы, боссы, модели персонажей

## Что здесь
- `enemy.gd` (`Enemy`) — один скрипт на всех врагов (поле `kind`): грунт (драугр-воин), метатель, босс + Мидгард по GDD 12.1 — корм, Раздутый, Щитоносец, Шаман, Наёмник Локи. В нём — все `@export`-числа и состояние, `_physics_process` (машина состояний), выбор действия по `kind` (`_think_chase`, `_begin_windup`, `_execute_attack`, `_setup_special`, `_update_special`), атаки грунта/босса/метателя, `take_hit`, `apply_def`, оглушение, `_die`. Эти функции переопределяют `BossEnemy`, Свен и Ярл — их в компоненты не выносить.
- **Компоненты** `parts/` (этап 3 рефакторинга; `RefCounted`, создаёт `Enemy._init`, доступ `enemy.<имя>`; состояние — поля `Enemy`):

| Файл | Класс, `enemy.` | Что внутри |
|---|---|---|
| `parts/enemy_notice.gd` | `EnemyNotice`, `notice` | обнаружение Тора: слух, запасной таймер, `alert_to_player` |
| `parts/enemy_fodder_lod.gd` | `EnemyFodderLod`, `fodder_lod` | дальний корм реже думает и реже обновляет позу |
| `parts/enemy_motion.gd` | `EnemyMotion`, `motion` | движение с отбрасыванием, `apply_knockback_only`, падение с высоты, застревание, шмяк об стену |
| `parts/enemy_shield.gd` | `EnemyShield`, `shield` | Щитоносец: блок спереди, `hit_breaks_armor`, удар щитом, щит на корпусе |
| `parts/enemy_shaman.gd` | `EnemyShaman`, `shaman` | Шаман: отход, обряд (лечение, корм), `summon_around` (и элита-Призыватель) |
| `parts/enemy_merc.gd` | `EnemyMerc`, `merc` | Наёмник Локи: лазер, очередь |
| `parts/enemy_visual.gd` | `EnemyVisual`, `visual` | анимации по состоянию, вздрагивание, вспышка/свечение `_set_overlay`, `_collect_meshes`, оружие в руке, заглушка, труп |
| `parts/enemy_ranged_attacks.gd` | `EnemyRangedAttacks`, `ranged` | снаряды и зоны GDD 12.6: выбор особой атаки (`choose_*`, `wants_spear`), выполнение (`fire_fan`, `fire_lob`, `cast_orb`, `cast_curse`, `throw_spear`, `throw_grenade`, `bloated_puddle`), лимиты зала `can_fire`/`can_add_zone` |
| `parts/enemy_tactics.gd` | `EnemyTactics`, `tactics` | роли поведения: окружение, фланг, прикрытие за щитоносцем, свита, засада, отступление раненого стрелка |

  Почему не подклассы на каждый вид: `kind` меняют на ходу — `MinibossDef` делает из любого врага `Kind.BOSS`, тесты переключают вид на одном экземпляре; с подклассами щитоносец-мини-босс сохранил бы щит. Функции компонентов, нужные снаружи, есть и на `Enemy` (обёртки в конце `enemy.gd`). Раздутый и метатель — несколько строк в `enemy.gd` (`_update_special`, `_die`, `_throw_projectile`). Новый вид: `Kind` (только в конец), ветки в диспетчерах, логика — новый `parts/enemy_<вид>.gd`.
- `enemy_projectile.gd` (`EnemyProjectile`, виды STRAIGHT / LOB / ORB / GRENADE / SPEAR; поля до `launch`); `hazard_zone.gd` (`HazardZone`, опасная зона на полу: круг / линия / конус, телеграф → удар → лужа); `blast.gd` — взрыв по площади (бьёт и Тора, и своих).
- `enemy_def.gd` + `defs/*.tres` — числа по GDD (`EnemyDef`, враги всех миров; зал применяет к врагу `apply_def` по `game_kind`).
- `elite/` — модификаторы элиты (`EliteModifier` .tres в `mods/` + обработчик-узел `EliteHandler` на враге; замедление Тора — компонент `PlayerSlow`, `player.gd` не трогается); элиту делает `Loot.make_elite`.
- `miniboss_def.gd` (`MinibossDef`, `minibosses/*.tres`), `bosses/` (`BossEnemy`, Свен, Ярл).
- `humanoid_model.gd` — сборка персонажа. Сцены врагов (`*.tscn`, кроме ручных арен) генерирует `tools/build_scenes.gd`.

## Публичный API
- `Enemy.apply_def`, `Enemy.armor_pierce_hit`, `Enemy.status_glow` (свечение стихий поверх цвета элиты в общем оверлее), `EnemyVisual._collect_meshes` (обводка), `Enemy.FLASH_MATERIAL` (не читай `.next_pass` напрямую — `Outline.flash_next_pass()`).
- Хуки эффектов: `FX.enemy_hit` / `FX.enemy_died` (ихор — у нежити, `FX.is_undead`).
- Трюки для шкалы стиля — `StyleMeter.event(&"…")` (см. `player/CLAUDE.md`).
- Источник урона по Тору: перед `player.take_damage()` — `RunTracker.note_hit(enemy)` (id из `enemy_id`/`death_source_id`/`kind`).

## Снаряды, зоны, роли (ночь 29.10, Н2, GDD 12.6)
Бьют все, очереди атак нет. Особая атака выбирается в `_think_chase` (`_attack_mode` = `&"fan"|"lob"|"orb"|"curse"|"spear"|"grenade"`, `&""` — обычная атака вида; ручной `_begin_windup` из тестов — всегда обычная), телеграф — `ranged.windup_telegraph`, выполнение — `ranged.execute` из `_execute_attack` (обычная — `_execute_kind_attack`). Перезарядка особых — `Enemy._special_cd`. Лимиты — `Room.max_projectiles`/`max_zones` (группы `enemy_projectiles`, `hazard_zones`): сверх — обычная атака или ожидание. Зона: `HazardZone.make(shape, pos, facing, size, telegraph, damage, color, source).place(parent)`, поля `puddle_*`; удар — только по Тору на полу (прыжок спасает, рывок — неуязвимость), через `RunTracker.note_hit`. Сфера (ORB) сбивается летящим Мьёльниром (группа `mjolnir_projectiles`). Отражение топором — все виды снарядов. Роль — `EnemyTactics.assign()` из `_setup_special`; отряд задаёт метаданные `tactic_role` (`surround|flank|cover|escort|lurk|none`) и `tactic_anchor` до `add_child`. Боссам — тот же API (`HazardZone`, `EnemyRangedAttacks`). Прогрев — `ShaderWarmup` (`HazardZone.warmup_sample`, копьё, граната). Звуки `hazard_warn`, `hazard_strike`, `orb_cast` — `tools/make_sfx.py`. Числа — TUNING.md. Тест `hazard_test`, кадры `tests/hazard_shots.tscn -- <папка>`.

## Мини-босс
`MinibossDef` — обычный враг с переопределёнными числами и `Kind.BOSS`; добавляется последней волной (`Room.add_wave`) в залах `Run.miniboss_rooms`, после него `Game` открывает выбор трейта, потом руны.

## Боссы со своими атаками (блоки Н, О)
`bosses/boss_enemy.gd` (`BossEnemy extends Enemy`: «действия» `act` поверх обычного ИИ, таран `charge_begin/charge_step` с полосой-телеграфом `strip_show`, `act_move`).
- **Толстый Свен** — `bosses/sven.gd` (`FatSven`, сцена `sven.tscn`, `MinibossDef.base_kind = "sven"`): таран на бочке, плевки `brew_glob.gd` → лужи `brew_puddle.gd` (замедление — `PlayerSlow`), раздувание и взрыв (`Blast`). Его арена `rooms/sven_arena.tscn` (маркер `MinibossSpot`) подменяет зал мини-босса (`Run.miniboss_arena`, `Run._place_miniboss_arenas`). Реплики — `data/dialogues/sven.json`; для Свена подготовлены собственные портреты пяти эмоций.
- **Ярл Бьорн** (финальный босс Мидгарда, блок О) — `bosses/jarl.gd` (`JarlBoss`, сцена `jarl.tscn`, числа — `defs/jarl.tres`, 60 У), арена `rooms/boss_arena.tscn` = `Run.BOSS_SCENE` («Длинный дом ярла»: балконы `rooms/balcony.gd` (`Balcony`, группа `balconies`, `break_apart()` → доски на слое 7), маркеры `JarlPerches`/`FodderGates`). Фазы: 1 — рука-бумеранг `jarl_arm.gd` (окно 3 с), 2 (66 %) — балкон + корм (`room.spawn_extra`, мета `jarl_summon`), сбить — `slam`/`stomp`/`hammer`/`lightning`, 3 (33 %) — ломает балконы, бодается (таран `BossEnemy`), прыжок с волной. При смерти голова катится, свита рассыпается. Тема — трек `jarl` (`Music`, синтез `make_sfx.py music_jarl`).
- Старый Хримтурс (`boss.tscn`) — в генераторе для Йотунхейма, в забеге не участвует.
- Удары боссов по пропсам (удар босса, прыжок Ярла, таран `BossEnemy`) — через `Destructible.hit_area(...)`.

## Модели персонажей (Quaternius, CC0)
- `assets/quaternius/characters/` — тела, одежда, волосы, анимации (`gaits.glb` = UAL1, `animations.glb` = UAL2). Скелет у всех один (65 костей, правая кисть `hand_r`).
- `humanoid_model.gd` собирает персонажа: тело + одежда + волосы на одном скелете, красит, добавляет библиотеки анимаций `ual1/…`, `ual2/…`. Godot при импорте отрезает суффикс `_Loop` — `HumanoidModel.resolve()` ищет оба варианта. Общий тонированный материал — `HumanoidModel._tinted`.
- Вид и анимации врагов — `MODEL_LOOKS` в `tools/build/gen_enemies.gd` (поля групп «Модель»/«Анимации» в `enemy.gd`). Замена на Synty: положить в сцену врага узел `Visual` со своим `AnimationPlayer` или поменять пути/имена анимаций там.
- Массовка/драугры: `HumanoidModel.random_look()` смешивает части одежды, волосы, цвета; у грунтов `randomize_look` + `weapon_pool` + `shield_chance`.
- Вспышка попадания — оверлей `shaders/hit_flash.tres` (`Enemy.FLASH_MATERIAL`), обводка — его `next_pass` (см. `scripts/CLAUDE.md`, «Комиксовая обводка»).

## Тесты
`enemy_test` (враги Мидгарда, щит, взрыв, шаман, волны), `hazard_test` (зоны, снаряды, лимиты, роли), `ai_test` (доходят и бьют во всех залах), `elite_test` (все виды × 7 модификаторов), `boss_test` (Свен, Ярл 3 фазы), `boss_charge_telegraph_test`, `enemy_flash_test`, `awareness_test`, `fodder_lod_test`, `fodder_model_test`, `horde_*_test`, `outline_test`. Кадры — `tests/enemy_shots.tscn`, `tests/boss_shots.tscn`, `tests/hazard_shots.tscn`.
