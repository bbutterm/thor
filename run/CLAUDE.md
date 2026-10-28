# run/ — забег: Слава, руны, тела, двери-награды, серебро и ларёк, испытания, открытия

## Что здесь
- `run_manager.gd` (автозагрузка `Run`, класс `RunManager`) — забег, Слава, руны, мини-боссы, серебро; всё состояние забега. Компоненты (этап 5 рефакторинга): `parts/run_mjolnir.gd` (`RunMjolnir`, `Run.mjolnir`: трейты Мьёльнира — правила, уровни, несовместимость, связки, выбор, наковальня) и `parts/run_doors.gd` (`RunDoors`, `Run.doors`: порядок залов, награды, двери). Их функции доступны и как `Run.xxx` (обёртки).
- `odin.gd` (`Odin`) — короткие реплики Одина, тонкая обёртка над `Dialogue` (пулы `data/dialogues/odin.json`): `Odin.say(событие)` = пузырь HUD из пула `odin.<событие>`, лимит 12 с в бою.
- `tutorial.gd` (`Tutorial`, узел в сцене игры) — обучение в первом зале первых забегов: шаги `Tutorial.STEPS`, реплики `ravens.tutorial_<шаг>` (`{key_<действие>}` → клавиша из InputMap; `Tutorial.key_name(действие)`), пройдено — событие `tutorial_done` в сохранении.
- `run_tracker.gd` (`RunTracker`, узел в сцене игры) — время забега, причина смерти, бой-реплики «ДВИГАЙСЯ!»/мульти-килл/«Скуф…»/«Позорище» (добил ренжем).
- Тела: `body_def.gd` (`BodyDef`: стиль движения, пассивка, изъян, цена, `dash_charges`), `bodies/`, `movement/<стиль>.tres` (`MovementProfile`, см. `player/CLAUDE.md`), `passive_def.gd` + `passives/*.tres|.gd`, `body_trait_handler.gd`.
- Руны: `rune_def.gd` + `runes/` (`RuneDef`: категория, уровни, `implemented`).
- Структура забега: `run_map.gd`, `maps/`, `reward_def.gd`, `rewards/`, `reward_flow.gd`.
- Экономика: `economy.gd` + `economy.tres`, `silver.gd`, `silver_coin.gd`, `barrel_watch.gd`, `heal_orb.gd`, `shop.gd`, `shop_item_def.gd`, `shop/`.
- Испытания: `trial_def.gd`, `trials/`, `trial_runner.gd`.
- Открытия: `unlock_def.gd` + `unlocks/*.tres`.

## Публичный API
- `Run.kill_registered(source)` — сигнал убийства; `Run.enemy_killed(source)` — убийства с источником (испытания); `Run.register_kill`, `Run.style_glory_mult`, `Run.rune_power` — руны ×N.
- `Run.silver` (`add_silver`, `spend_silver`, сигнал `silver_changed`).
- `Run.mjolnir_traits`, `Run.active_combos()`, сигнал `Run.mjolnir_combo_unlocked`, `Run.rules()`, `Run.random_mjolnir_trait_choices(count, kinds)`, `mjolnir_offer_ok`, `can_level_up`, `mjolnir_trait_conflict`, `Run.trait_rerolls` (см. `weapons/CLAUDE.md`).
- `Run.miniboss_rooms`, `Run.miniboss_arena`, `Run._place_miniboss_arenas`, `Run.BOSS_SCENE`, `Run.ROOM_SCENES`.
- `Run.combat_clock` — боевые часы (см. ниже).
- **Источник урона по Тору:** перед `player.take_damage()` вызывай `RunTracker.note_damage("barrel")` или `RunTracker.note_hit(enemy)` (id из `enemy_id`/`death_source_id`/`kind`). Падение определяется само.

## Тела смертных (блок Л)
Пассивки/изъяны — `body_trait_handler.gd` (`BodyTraitHandler`: `on_kill`/`on_hit`/`on_damaged`/`on_dash`/`on_slam`/`on_jump`/`on_room_start`, `damage_mult`, `modify(stat)`), скрипты `passives/<id>.gd` во вложенном `PassiveDef.handler`; у игрока копии — `player.body_handlers`, `player.modify_stat()`. Экран выбора тела — `ui/body_select.gd` (`BodySelect`, сигнал `closed(body_id)`), открывают `main_menu.gd` и `Game._after_run`. Ларёк (блок К) должен спрашивать `player.modify_stat("sharpen_cost_mult", 1.0)`, парирование — `"parry_window_mult"`/`"parry_heal"`.

## Данные по GDD (блок Г)
`enemies/enemy_def.gd` + `enemies/defs/*.tres` (враги всех миров), `passive_def.gd` + `passives/*.tres` (пассивки/изъяны тел), расширенные `BodyDef` (стиль движения, пассивка, изъян, цена) и `RuneDef` (категория, уровни, `implemented`). Поле `implemented` = механика уже есть; без неё вещь в пул не попадает.

## Структура забега (блок И)
- Двери-награды (GDD 15.1): `run_map.gd` (`RunMap`) + `maps/midgard.tres` — структура мира (7 залов, мини-босс в 4-м, 2–3 двери, числа наград; также «Небо и атмосфера», «Свет и цвет» — см. `scripts/CLAUDE.md`, «Графика мира»); `reward_def.gd` + `rewards/*.tres` (`RewardDef`) — награды дверей, частоты, иконки `sprites/ui/icons/door_<icon>` из UI-манифеста (у финальной двери — `door_boss.webp` с Ярлом); `reward_flow.gd` (`RewardFlow`, узел `Game.rewards`) — выдача награды зала и показ дверей; `rooms/reward_door.gd` (`RewardDoor`) — арка с иконкой и триггером; `ui/choice_pick.gd` (`ChoicePick`) — выбор из 2–3 с портретом (отдых, Локи).
- Состояние в `Run`: `room_order` (сцены залов на мир), `room_rewards` (награда каждого зала), `reward_visits`, `current_reward()`, `roll_door_offers()`, `choose_door(id)`, `is_peaceful_room()` (отдых/ларёк — без врагов, `room.start` не вызывается).
- Тесты задают порядок залов через `Run.room_order` (после `Run.start_run`), наборы дверей — `Run.forced_offers`; `Run.doors_enabled = false` — старая одна дверь после руны. Общие шаги тестов — `tests/door_helper.gd` (`resolve_reward`, `take_door`).
- Проверка: `run_map_test`.

## Серебро и ларёк (блок К)
- Серебро — `Run.silver`, сгорает с новым забегом. Источники — `silver.gd` (`Silver.drop/on_enemy_died`, числа в `economy.tres`): враги через `Loot.on_enemy_died`, бочки — `barrel_watch.gd` (узел в `RewardFlow`; бочка «разбита», если отброшена быстрее порога; для пропсов без скрипта `Destructible`), сундук — строка в `weapons/chest.gd`. Монета — `silver_coin.gd` (общий меш-диск и материал `FX`). Счётчик — `ui/silver_hud.gd` (встраивается под Славу в HUD).
- Ларёк: зал `rooms/shop_room.tscn` (генератор: `shop_room_def()` + узел `ShopStall`), ларёк и гномы — `rooms/shop_stall.gd` (собирается при запуске, E у прилавка), товары — `shop/*.tres` (`ShopItemDef`), логика — `shop.gd` (`Shop.price/buy/reaction_pool`), экран — `ui/shop.gd` (`ShopScreen`, `RewardFlow.open_shop()`). Реплики — `data/dialogues/dwarves.json` (пулы `shop_*`, `eitri`, сцена `dwarves_shop_first`).
- Проверка: `shop_test`.

## Испытания (блок Ф)
- `trial_def.gd` + `trials/*.tres` (`TrialDef`: ведущий, вид условия, числа, награда, пулы реплик) — новое испытание = новый .tres. `trial_runner.gd` (`TrialRunner`, узел `Trial` в зале) — условие, таймер, лава, итог; `ui/trial_hud.gd` — панель испытания.
- `RewardFlow`: дверь «Испытание» → `TrialRunner.attach` при загрузке зала, `start` вместе с волнами, награда в `_grant_trial` (Слава или особая руна, провал — ничего). Тесты: `Run.forced_trial = "<id>"`.
- Проверка: `trial_test`.

## Открытия «Плана тренировок» (GDD 15.3)
`unlock_def.gd` + `unlocks/*.tres`: `kind` weapon/trait/body/rune/perk, `target_id` (+`extra_target_ids`), цена, поле `icon` (`sprites/unlocks/`). **Пулы:** `Save.is_in_pool(kind, id)` — закрытое не выпадает (руны и тела уже подключены в `run_manager.gd`; оружию и трейтам — подключить в своих пулах). Id целей: оружие `spear, scythe, pickaxe, knife, assault_rifle, smg, sawed_off, nailgun, rocket_launcher`; трейты `boomerang, ice_trail, heaviness, lightning_rod, storm, earthquake, two_hammers, sky_thunder`; тела `priest, soldier, skald, courier, smith, shieldmaiden`. Нет определения цели в игре (`weapons/defs/`, `weapons/mjolnir_traits/`, `bodies/`, `runes/`) — на экране «скоро». Перки: `Save.perk("catch_window")` и т. п.; +HP/+рывок/скорость применяет `Save.apply_permanent_to_body()` в `Game._ready`. Экран — `ui/training_plan.gd` (после диалога у дивана и из главного меню).

## Боевые часы
Окна мультикилла, недавнего попадания и шмяка используют `Run.combat_clock`: реальная длительность кадров `FX.real_delta`, в том числе при паузе и hit-stop. Это сохраняет их поведение в игре и при `--fixed-fps`; не заменяй их системными часами при headless-измерениях. Проверка — `combat_clock_test`.

## Тесты
`run_map_test`, `shop_test`, `trial_test`, `body_test`, `rune_test`, `runes_test`, `save_test`, `tutorial_test`, `style_test`, `combat_clock_test`, `smoke_test`.
