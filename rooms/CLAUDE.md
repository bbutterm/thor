# rooms/ — залы, волны, двери, одевание, декор

## Что здесь
- `room.gd` + `*.tscn` — залы, волны (маркеры в `Spawns` с метаданными `kind`/`wave`, толпа — `count`/`spread`, отряд — `kind = "squad"` + `squad`/`squad_options`/`squad_override` (`enemies/squad_def.gd`); лимиты снарядов и зон `max_projectiles`/`max_zones`; поток пачками, следующая волна при < 30 % или через 25 с; `spawn_extra` — враг сверх волн), дверь, выход. `Room.add_wave`, `Room.indoor`.
- `balcony.gd` (`Balcony`) — балконы Ярла и ломаемые мосты/настилы (`slam_breakable`).
- `reward_door.gd` (`RewardDoor`) — арка с иконкой и триггером (см. `run/CLAUDE.md`, «Структура забега»).
- `wall_decor.gd` (`WallDecor`: `art`, `height` — видимая высота), `floor_decal.gd` (`FloorDecal`: `art`, `size`, `glow`).
- `room_dress.gd` (`RoomDress`: меши `meshes/*.res`, материалы `materials/*.tres`), `dress_scatter.gd` (`DressScatter`), `backdrop_midgard.tscn` (даль).
- `shop_room.tscn` + `shop_stall.gd` — ларёк (см. `run/CLAUDE.md`, «Серебро и ларёк»).
- `jump_pad.gd`, `enemy_navigation.gd`.

## Генерируемые и ручные сцены
- **Обычные боевые залы** (`room_defs()` в `tools/build_scenes.gd`; данные зала — `tools/rooms/<зал>.gd`; `room_01…11.tscn`) и зал-ларёк **генерирует** генератор — меняешь структуру, правь генератор и перезапускай его (коммить только намеренно изменённые .tscn).
- **Арены боссов и сюжетные залы — ручные сцены** (`MANUAL_SCENES` в генераторе: `boss_arena.tscn`, `sven_arena.tscn`; новые арены — добавлять туда же): правятся в редакторе, генератор их не создаёт и не перезаписывает (`_save` отказывается, проверка — `tests/generator_test.tscn`).
- Убранство длинного дома (стропила, люстры, очаг, столы — узел `Decor`, без коллизии) добавлено разовым `tools/dress_longhouse.tscn` (повторный запуск заменяет `Decor`); картинки длинного дома — `tools/dress_longhouse_art.tscn` (`Decor/WallArt`, `Banners`). Ручную арену Свена обновляет `tools/dress_arenas.tscn`. Скрипты-правки сцен запускать сценой, не `-s`, — иначе нет автозагрузок и скрипты сцены не грузятся.
- Блоки уровней — StaticBody3D, не CSG (CSG давал провалы сквозь пол в первые кадры).

## Новый боевой зал
Новый файл `tools/rooms/<зал>.gd` (`static func def()` возвращает словарь; помощники — `tools/rooms/room_kit.gd`) + строка в `ROOM_DATA` генератора. Ключи словаря: `blocks` — материал `"none"` = только коллизия, `pillars`, `jump_pads`, `models` — декор без коллизии [путь, позиция, поворот Y, масштаб], `houses` — дома из модулей MegaKit вокруг блока [индекс блока, сторона двери, "Plaster"|"UnevenBrick"] (`_house`), `enemies`, `props`, `balconies`, `markers`, `watchtowers`, `decor`, `decals`, `no_auto`, `floor_tex`, `dress`. Плюс путь в `Run.ROOM_SCENES` + маршрут наверх в `reach_test`; кадры — `tests/room_shots.tscn -- <папка> room_07 …`. Перед экспортом — `python3 tools/check_export_assets.py`.

## Одевание залов (блок Б0)
Коробки залов — только коллизия, вид даёт `tools/room_dresser.gd` (`RoomDresser`; вызывают генератор — конец `_build_room` — и разовый `tools/dress_arenas.tscn` для ручных арен; повторный запуск заменяет узел `Dress`). Работает по собранному дереву (`Geometry/Floor|Wall*|Block*|Pillar*`, `Balconies`, `Torches`, `JumpPads`, `Props`), **коллизию не трогает**: пол — `Dress/FloorVisual` (сетка с затемнением у стен/блоков/колонн в цвете вершин — запасной AO для GL Compatibility), блоки по стилю (`stone` — скошенный меш, каменный кант, угловые колонны, обломки; `wood` — доски в раме столбов и балок; `house` — балки по краю крыши; `deck`/`balcony` — доски и балки по краям, меш настила `Mesh` остаётся для обломков; `tower` — круглая башня с площадкой; `none`), стены (частокол, колонны в углах и у ворот, валуны/обломки, тёмная полоса у пола, плющ, разброс верхнего ряда модулей), 10–20 декалей, кости в углах, даль `backdrop_midgard.tscn` (земля, вода, сосны, скалы, драккары; генерирует `build_dress`). Ключ зала `"dress"`: `styles` {индекс блока: стиль} (по умолчанию — из материала блока, `_block_style`), `floor` brick|dirt|plank, `palisade`, `rubble`, `vines`/`vine_count`, `pilasters`, `decals` (число), `bones`, `backdrop`, `corner_props` (бочка + ящик в свободных углах). Поверхности — ОДИН шейдер `shaders/world_surface.gdshader` (трипланар с анти-повтором, второй слой по шуму — мох/земля/булыжник, грязь у основания, AO из цвета вершин), материалы `materials/*.tres` различаются только параметрами (`SURFACES` в `room_dresser.gd`); меши деталей — `meshes/*.res` (`RoomDress.MESHES`); повторяющиеся детали — `DressScatter` (MultiMesh собирается в `_ready` из `xforms` — в headless буфер MultiMesh в сцену не сохраняется). Новый меш/материал — в `RoomDress` (прогрев `RoomDress.warmup` в `ShaderWarmup`, удержание — `AssetCache`).

**Вид Мидгарда в генерируемых залах (срез зала 10 → все залы, Н1 29.10):** генератор ставит каждому залу `Room.visual_map = run/maps/midgard_slice.tres` (холодное небо и дымка против тёплых факелов, туман, обводка/полутон; `GenRooms.DEFAULT_VISUAL_MAP`, ключ зала `"visual_map"` перекрывает, `""` — карта мира) и поверхности `materials/slice_*.tres` вместо `surface_*` (`GenRooms.SLICE_SURFACES`; параметры — `SURFACES` в `room_dresser.gd`, ключ `"dress": {"surface_materials": {...}}` дополняет). Ориентиры у подъёмов (`GenRooms._landmarks`): низ пандуса, ступени вышки, прыжковая руна → ближайший боковой факел переезжает на стойку рядом, под ним знамя (до 2 на зал, новых источников света нет); `"torch_overrides"` (ручная расстановка, зал 10) или `"landmarks": false` отключают. Ручные арены (длинный дом, погреб Свена) остаются на карте мира и `surface_*`.

**Открытые залы:** `RoomDresser._open_edges` оставляет физические границы и поднимает их до 24 м, а модели периметра заменяет открытой далью; факелы/знамёна стоят на опорах. Длинный дом Ярла остаётся закрытым (`backdrop = false`). Вышки на ступенях в залах 1 и 6: данные `watchtowers` в описании зала (`tools/rooms/<зал>.gd`), геометрия `GenRooms._watchtower`, подъём проверяет `tests/tower_test.tscn`.

## Декор и декали в генераторе
Картинки на стенах — `WallDecor`, декали на полу — `FloorDecal`; в генераторе — ключи зала `decor` [картинка, позиция, поворот Y, высота], `decals` [декаль, позиция, поворот Y, размер, glow], `no_auto`, `floor_tex`, авто-щиты/знамёна по стенам (`_build_wall_art`). Материалы — кеш `WorldArt.material(key, kind)` (см. `scripts/CLAUDE.md`, «Графика мира»). Атмосфера зала — `WorldArt.dress_room` (`Game._load_room`), свет под крышей — `WorldArt.apply_room` при `Room.indoor`.

## Модели окружения
- `assets/quaternius/village/` — стены 2×3.12 м (`_wall_row` в генераторе ставит их в 2 ряда), текстуры для трипланарных материалов (`_tex_mat`). `assets/quaternius/props/` — бочки, факелы, знамёна.
- Из `assets/quaternius/pirate/` (Pirate Kit) используется корабль в `room_07`.

## Тесты
`reach_test` (достижимость платформ, в т. ч. ярусы залов 7–9), `generator_test`, `tower_test`, `ai_test`, `room_transition_test`, `gate_entry_test`, `world_art_test`, `smoke_test`. Кадры — `tests/room_shots.tscn`.
