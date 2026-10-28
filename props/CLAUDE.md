# props/ — разрушаемое: бочки, ящики, взрывные бочки, обломки

## Что здесь
- `destructible.gd` (`Destructible extends RigidBody3D` — скрипт на `barrel|crate|barrel_explosive.tscn`, их делает генератор `build_props`).
- `prop_debris.gd` (`PropDebris`) — обломки.
- `destruct_tuning.gd` + `destruct_tuning.tres` — числа.

## Публичный API
- `take_hit(dmg, knock, source)`, огонь `ignite()`.
- `Destructible.hit_area(...)` — удары по площади и взрывы (blast, ракета, удар босса, прыжок Ярла, таран `BossEnemy`), `ignite_area` — огонь (`weapons/fire_zone.gd`).
- `roll_surprises(room)` — часть бочек взрывные (из `RewardFlow.on_room_loaded`).

## Как устроено
HP, правило скорости (бывший `BarrelWatch` — тот теперь только для пропсов без скрипта, `run/barrel_watch.gd`), содержимое (бочка — серебро, ящик — `Economy.crate_*`, взрывная — `Blast` + цепная реакция). Обломки — модель режется на куски по своим треугольникам один раз на тип (в `ShaderWarmup`) — те же материалы, общий лимит на зал, группа `prop_debris` (не `debris` — та для трупов), слой 7. Урон Тора по пропсу: `deal_damage` отдаёт его сразу в `take_hit` — без множителей, критов, рун и `on_hit` (шкалу стиля и руны «за удар» пропсы не кормят, Славы нет). Обводятся комиксовой обводкой (узел `Model`).

Мосты и настилы залов — `Balcony.slam_breakable` (генератор: блок `"wood"` толщиной ≤ 0.5 м с низом выше 1 м — мост деревни, Биврёст), ломает удар-приземление (`Player._slam_break_floor`); балконы Ярла — нет.

## Новый разрушаемый пропс
Ветка в `build_props` (RigidBody слой 4, группа `props`, `set_script(destructible.gd)`, узел `Model` — из него режутся обломки; поля `max_health`, `debris_mode` radial|box, `loot`, `break_sound`), путь — в `AssetCache.FILES` и `Destructible.warmup_samples`, в зал — вид в `props` словаря `room_defs()`.

## Тесты
`destructible_test` (все источники урона, обломки, содержимое, взрывные, мосты, балконы Ярла); кадры — `tests/destruct_shots.tscn`.
