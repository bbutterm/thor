# weapons/ — Мьёльнир, трейты, оружие правой руки, лут

## Что здесь
- `axe.gd` — любое мили из `WeaponDef` (сильный удар — зажать ЛКМ); `ranged.gd` (`RangedWeapon`: луч, пробитие, отдача, трассеры, гильзы); `fire_zone.gd` — огонь.
- Мьёльнир: `mjolnir_hand.gd` (`MjolnirHand`) + `mjolnir_projectile.gd` (`MjolnirProjectile`: состояния OUT / HOVER / STUCK «воткнулся» / RETURN, идеальный хват).
- Трейты: `mjolnir_trait.gd`, `mjolnir_trait_handler.gd`, `mjolnir_element.gd`, `element_status.gd`, `element_zone.gd`, `mjolnir_rules.tres`, `mjolnir_traits/<id>.tres|.gd`, `mjolnir_traits/combos/`.
- Оружие: `weapon_def.gd` (`WeaponDef`, данные `defs/*.tres`), `weapon_item.gd`, `weapon_holder.gd`, `loot.gd`, `pickup.gd`, `ammo_pickup.gd`, `chest.gd`.

## Публичный API
- `player.equip(def)`, `current_weapon()`, `current_melee_style()` (узел `Player/Weapons` = `weapon_holder.gd`: 2 слота мили/ренж, свитч, подбор по E, патроны).
- Источники урона: `melee` / `melee_finisher` / `melee_heavy` / `ranged`. Весь урон по врагу — `player.deal_damage` (см. `player/CLAUDE.md`).
- `MjolnirHand`: сигналы `perfect_catch`, `catch_timing(result, offset)`, `throw_blocked(left)`; `catch_cooldown`/`perfect_catch_cooldown`, `cooldown_left`/`cooldown_total`, `effective_cooldown(perfect)`, `reset_cooldown()`, `perfect_window_left()`, `effective_perfect_window()`, `catch_runes`; `hand.traits` + `hand.combo_traits`, `hand.element_handler()`, `hand.trait_handler(id)`, `hand.begin_hold/release_hold`, `hand.next_throw`.
- `MjolnirProjectile.catch_eta()`, `MjolnirProjectile.pierce` → `Enemy.armor_pierce_hit`.
- `Loot.make_elite`, `Loot.on_enemy_died`.

## Перезарядка броска Мьёльнира
Перезарядка начинается **при поимке** (GDD 26.4, П1): `MjolnirHand.catch_cooldown` (1.5 с после обычной поимки, ставит `on_caught`) и `perfect_catch_cooldown` (0 — идеальный хват снимает перезарядку в `_grant_perfect`, бросай сразу); в полёте перезарядки нет. Качается — трейт `modify(&"catch_cooldown"/"perfect_catch_cooldown")`, тело/перк `player.modify_stat("hammer_cooldown_mult")` (`effective_cooldown(perfect)`). Бросок на перезарядке — осечка (`throw_blocked`, звук, полоска у молота в HUD краснеет); служебный возврат `force_return_instant` (новый зал, смена трейтов) — без перезарядки. Тесты, где важны броски подряд, ставят `hand.catch_cooldown = 0`; сама перезарядка — в `catch_test`.

Подсказка идеального хвата — `ui/catch_assist.gd` (см. `ui/CLAUDE.md`), по `MjolnirProjectile.catch_eta()` (прокрутка того же возврата вперёд; точно до кадра) и `MjolnirHand.perfect_window_left()`.

## Трейты Мьёльнира — стихии × приёмы (блок Б4, GDD 10)
`mjolnir_trait.gd` (`MjolnirTrait`: `kind` element/technique/combo, описания уровней 1–4, `group` + `conflicts` — несовместимость приёмов, `level_pool_ids` — id открытий бывших трейтов по уровням стихии, `all_ids()` для `Save.target_exists`) и `mjolnir_trait_handler.gd` (`MjolnirTraitHandler`, хуки `on_throw`/`on_flight_tick`/`on_hit_enemy`/`on_hit_world`/`on_stuck_tick`/`on_recall_start`/`on_recall_tick`/`on_caught`/`on_player_slam`/`on_perfect_catch`, удержание ПКМ `on_hold_start/tick/release`, события для связок `on_pull_arrive`/`on_dive_slam`/`on_swap`, `modify(stat)` — в т. ч. `hold_throw`; урон — `hurt()` = `player.deal_damage`). Стихии (огонь, лёд, молния, земля, ветер) — наследники `MjolnirElementHandler` (`mjolnir_element.gd`: уровни = способ доставки 1 попадание / 2 след / 3 аура воткнутого / 4 с неба, `apply_element`, `slam_combo`, `world_effect` — брага `BrewPuddle.electrify_near/ignite_near`, бочки; `hit_fx()` + `hit_signature()` — свой вид попадания у каждой стихии), состояния на враге — `element_status.gd` (`ElementStatus`, свечение `_update_glow` через `Enemy.status_glow`), пятна следа — `element_zone.gd`. Приёмы и стихии — `mjolnir_traits/<id>.tres` + `<id>.gd`, связки — `mjolnir_traits/combos/` (включаются сами: `Run.active_combos()`, сигнал `Run.mjolnir_combo_unlocked` → `Game._on_combo_unlocked`: `ui/combo_announce.gd`, слово `combo`, `Odin.say("combo_<id>")`). Правила (1 стихия, до 2 приёмов, наковальня) — `mjolnir_rules.tres` (`MjolnirRules`, `Run.rules()`); выбор — `Run.random_mjolnir_trait_choices(count, kinds)`, `mjolnir_offer_ok`, `can_level_up`, `mjolnir_trait_conflict`. Активные — `Run.mjolnir_traits` (связок там нет), рука собирает копии. Где дают: мини-босс (стихия или приём) и дверь «Наковальня Эйтри» (`run/rewards/anvil.tres`, `RunMap.anvil_*`, `RewardFlow._offer_anvil`). Выбор — `ui/trait_pick.gd` (связка — особая карточка), иконки — `ui/mjolnir_traits_hud.gd` (+ полоска удержания). «Обслуживание Мьёльнира» без трейтов — `Run.trait_rerolls`, кнопка «ПЕРЕБРОС [R]» в `ui/trait_pick.gd`.

## Оружие правой руки (этап 1)
Новое оружие = новый `.tres` в `defs/` (`WeaponDef`: урон, скорость, досягаемость, отброс, `move_speed_mult`). `weapon_item.gd` — экземпляр: уровень 1–3, патроны. `loot.gd` — пул выпадения, элита, сундук, патроны, прогрев; `pickup.gd` / `ammo_pickup.gd` / `chest.gd` (сундук ещё даёт серебро). HUD — `ui/weapon_hud.gd`. Пул оружия должен спрашивать `Save.is_in_pool("weapon", id)` (закрытое не выпадает).

## Модели оружия (код — `scripts/weapon_meshes.gd`)
- Модели `q_*` из `assets/quaternius/weapons/` (материалы подменяются на наши) + процедурные (Мьёльнир, дубина, вилы, факел). Слой 2 = вьюмодель.
- Огнестрел — Quaternius Ultimate Gun Pack (FBX) в `assets/quaternius/guns/`, ключи `gun_*` в `WeaponMeshes.GUN_MODELS`; арбалет и болт — процедурные.
- **Рисованное оружие «RPG Items»** (владелец; WC3 .mdx → .glb `tools/mdx2glb.py`): `assets/painted/rpg_items/`, ключи `p_axe/p_sword/p_hammer/p_staff/p_shield` (+ варианты `…2` — у врагов через `WeaponMeshes.ALIASES` вместо `q_axe/q_sword/q_shield/staff`), таблица `WeaponMeshes.PAINTED` [файл, длина м, доля до хвата]; материал — общий на файл (`_painted_mat`). Лицензия не подтверждена — `CREDITS.md`.
- Мьёльнир — модель владельца `assets/mjolnir/` (`WeaponMeshes.mjolnir`, общий PBR-материал `mjolnir_material()`, длина/хват — `MJOLNIR_LENGTH/GRIP` (0.82 м; в левой руке ещё `weapon_scale` 1.2); кадры `tests/mjolnir_shots.tscn`), без неё — `p_hammer`, без него — `hammer_procedural`.
- Кадры всего оружия: `xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 640x360 res://tests/weapon_shots.tscn -- <папка>`.

## Тесты
`catch_test` (с `-- <папка>` под xvfb — кадры), `trait_test` (`-- elements|techniques|combos` — часть), `weapon_test`, `weapon_skill_test`, `destructible_test`, `elite_test`, `smoke_test`.
