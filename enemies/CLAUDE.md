# enemies/ — враги, элита, мини-боссы, боссы, модели персонажей

## Что здесь
- `enemy.gd` — один скрипт на всех врагов (поле `kind`): грунт (драугр-воин), метатель, босс + Мидгард по GDD 12.1 — корм, Раздутый, Щитоносец, Шаман, Наёмник Локи (их поведение — раздел «Враги Мидгарда» в конце скрипта).
- `enemy_projectile.gd`; `blast.gd` — взрыв по площади (бьёт и Тора, и своих).
- `enemy_def.gd` + `defs/*.tres` — числа по GDD (`EnemyDef`, враги всех миров; зал применяет к врагу `apply_def` по `game_kind`).
- `elite/` — модификаторы элиты (`EliteModifier` .tres в `mods/` + обработчик-узел `EliteHandler` на враге; замедление Тора — компонент `PlayerSlow`, `player.gd` не трогается); элиту делает `Loot.make_elite`.
- `miniboss_def.gd` (`MinibossDef`, `minibosses/*.tres`), `bosses/` (`BossEnemy`, Свен, Ярл).
- `humanoid_model.gd` — сборка персонажа. Сцены врагов (`*.tscn`, кроме ручных арен) генерирует `tools/build_scenes.gd`.

## Публичный API
- `Enemy.apply_def`, `Enemy.armor_pierce_hit`, `Enemy.status_glow` (свечение стихий поверх цвета элиты в общем оверлее), `Enemy._collect_meshes` (обводка), `Enemy.FLASH_MATERIAL` (не читай `.next_pass` напрямую — `Outline.flash_next_pass()`).
- Хуки эффектов: `FX.enemy_hit` / `FX.enemy_died` (ихор — у нежити, `FX.is_undead`).
- Трюки для шкалы стиля — `StyleMeter.event(&"…")` (см. `player/CLAUDE.md`).
- Источник урона по Тору: перед `player.take_damage()` — `RunTracker.note_hit(enemy)` (id из `enemy_id`/`death_source_id`/`kind`).

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
- Вид и анимации врагов — `MODEL_LOOKS` в `tools/build_scenes.gd` (поля групп «Модель»/«Анимации» в `enemy.gd`). Замена на Synty: положить в сцену врага узел `Visual` со своим `AnimationPlayer` или поменять пути/имена анимаций там.
- Массовка/драугры: `HumanoidModel.random_look()` смешивает части одежды, волосы, цвета; у грунтов `randomize_look` + `weapon_pool` + `shield_chance`.
- Вспышка попадания — оверлей `shaders/hit_flash.tres` (`Enemy.FLASH_MATERIAL`), обводка — его `next_pass` (см. `scripts/CLAUDE.md`, «Комиксовая обводка»).

## Тесты
`enemy_test` (враги Мидгарда, щит, взрыв, шаман, волны), `ai_test` (доходят и бьют во всех залах), `elite_test` (все виды × 7 модификаторов), `boss_test` (Свен, Ярл 3 фазы), `boss_charge_telegraph_test`, `enemy_flash_test`, `awareness_test`, `fodder_lod_test`, `fodder_model_test`, `horde_*_test`, `outline_test`. Кадры — `tests/enemy_shots.tscn`, `tests/boss_shots.tscn`.
