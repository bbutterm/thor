# player/ — Тор: движение, урон, руки, шкала стиля

## Что здесь
- `player.gd` — движение (рывок, двойной прыжок, удар-приземление, супер-прыжок; GDD 7.2: отскок от удара-приземления, прыжок по головам, залезание на уступ, отскок от стены, пике, отмена удара-приземления рывком — блок «Прыжки по GDD 7.2»), урон. Сцена `player.tscn` генерируется (`tools/build_scenes.gd`).
- `camera_fx.gd` — тряска/FOV/наклон.
- `movement_profile.gd` — `MovementProfile` (стиль движения тела; данные `run/movement/<стиль>.tres`).
- `style_meter.gd`, `style_tuning.gd` + `style_tuning.tres` — шкала «ДОСТОЙНО!».
- `viewmodel_arm.gd`, `viewmodel_motion.gd` (+ `viewmodel_motion_tuning.gd`, `viewmodel_motion.tres`) — руки от первого лица.

## Публичный API (зовут снаружи)
- **Урон Тора по врагу — только через `player.deal_damage(target, dmg, knock, source)`** (множители тела/берсерка + `on_hit`). Урон по Тору — `take_damage()`; перед ним вызывай `RunTracker.note_damage("barrel")` или `RunTracker.note_hit(enemy)` (см. `run/CLAUDE.md`).
- `player.modify_stat(stat, default)` — статы тела/перков (`hammer_cooldown_mult`, `style_gain_mult`, `sharpen_cost_mult`, `parry_window_mult`/`parry_heal`).
- `player.equip(def)`, `current_weapon()`, `current_melee_style()` — оружие (`weapons/weapon_holder.gd`).
- `Player.restore_mjolnir_runes`, `Player.can_start_slam()`, `slam_surface_hit`, сигнал `slam_unavailable`, `Player.is_berserk()`, `Player.music_intensity(fighting)`, `Player.outgoing_damage_mult`, `effective_move_speed`.

## Руны Мьёльнира и удар-приземление (Н1–Н2)
`Player.dash_charges` — общий запас для рывка и каждого воздушного прыжка; на земле восстанавливается по `dash_recharge`, в воздухе таймер стоит и его доля остаётся видимой. `Player.restore_mjolnir_runes` — восстановление при поимке; обычная поимка возвращает `MjolnirHand.catch_runes`, идеальная заполняет запас, в воздухе также восстанавливаются прыжки. База у тела (`BodyDef.dash_charges`), приём `air_catch` добавляет руны сверх базовой поимки. HUD — `RuneHammer` в `ui/hud.gd`, шкала высоты в рукояти. `Player.can_start_slam()` проверяет воздушный прыжок, специальный подброс/отскок или высоту `slam_min_height`; ближайшая поверхность мира или предмета для проверки и HUD определяется через `slam_surface_hit`. При запрете сигнал `slam_unavailable` с кулдауном показывает подсказку. Пике, разрешённое в момент броска, действует до следующей посадки (`_slam_ground_contacts`). Данные — `TUNING.md`; проверки — `tests/runes_test.tscn`, `tests/slam_gate_test.tscn` и `tests/dive_gate_test.tscn`.

Мосты и настилы залов (`Balcony.slam_breakable`) ломает удар-приземление — `Player._slam_break_floor`. Помощь: `GameSettings.slam_slowmo()` → `Player._slam_assist_tick`.

## Тела смертных (блок Л)
Стиль движения — `MovementProfile` (данные `run/movement/<стиль>.tres`), игрок копирует числа в поля (`Player.apply_movement_profile`; таран, подкат, тройной прыжок, тяжёлый удар-приземление — флаги/множители в `player.gd`, блоки «Таран», «Подкат», «Стиль движения тела»). Пассивки/изъяны — `run/body_trait_handler.gd` (см. `run/CLAUDE.md`); у игрока копии — `player.body_handlers`, `player.modify_stat()`.

## Шкала стиля «ДОСТОЙНО!» (блок Б3, GDD 8; вместо Ярости)
`style_meter.gd` (`StyleMeter`, узел `Player/StyleMeter`, создаёт `Player._ready`; `Player.rage` — старое имя того же узла), числа — `style_tuning.tres` (`StyleTuning`: очки приёмов `points`, пороги/Слава/утечка рангов, повтор, спад, урон, берсерк, музыка, голос). Очки: убийства — из `Run.kill_registered(source)` (способ — `StyleMeter.kill_action(source)`), трюки — однострочник `StyleMeter.event(&"slam_bounce"|"stomp"|"wall_splat"|"reflect")` в `player.gd`/`enemy.gd`/`enemy_projectile.gd`, идеальный хват — сигнал `MjolnirHand.perfect_catch`; новый приём = ключ в `points` + вызов `event`. Повтор — «усталость» приёма, урон — `on_damaged` из `Player.take_damage`, тело может менять набор через `modify_stat("style_gain_mult")`, руна «Песнь берсерка» — +30…80 %. Ранги Скуф → Сойдёт → Неплохо → Достойно → ДОСТОЙНЕЙШИЙ! (`RANK_NAMES`, tr при показе): Слава — `Run.style_glory_mult` в `Run.register_kill`, музыка — `Player.music_intensity(fighting)` → `Music._auto_state`, слово комикса `rank_1..rank_4` (`data/comic_words.json`, через `rank_pop_delay`), голос — `Odin.say("rank_worthy")` (с лимитом) и `"rank_top"` (без лимита; в пределах `voice_cooldown` — пул `berserk`). Высший ранг — берсерк 8 с: урон ×1.5 (`Player.outgoing_damage_mult`), скорость ×1.5 (`effective_move_speed`), без отбрасывания (`style.is_stun_immune()` — спрашивай его, если появится стан Тора); `Player.is_berserk()`. HUD — `ui/style_hud.gd` (`StyleHUD.attach` из `hud.gd`): подпись ранга на `comic_burst_*`, рамка `hud_rage_frame` с засечками рангов, множитель Славы. Бой-реплики GDD 17: «ДВИГАЙСЯ!», мульти-килл, «Скуф…», «Позорище» (добил ренжем) — `run/run_tracker.gd`; «Вот! ВОТ!» — `player.gd` (`big_slam_height`).

## Руки от первого лица (блок Б2)
Модель — CC0-руки Drillimpact `assets/arms/drillimpact_psx/` (`viewmodel_arm.gd`, `ViewmodelArm`: одна сторона на узел, другая сжата в точку; кисть+предплечье держат хват, плечо тянется к `shoulder_anchor` за кадром; пальцы — смесь поз «кулак/ладонь/хват» из анимаций пакета, `grip`/`open_style`; кожа — `thor_arm.png` с татуировками из `tools/make_arm_texture.py`, наруч — процедурные цилиндры по вершинам предплечья; материалы общие на цвет). Движение — `viewmodel_motion.gd` (`ViewmodelMotion`, узел `Player/ViewmodelMotion` создаёт `Player._ready`): у каждой руки `ViewmodelMotion.Hand` над пивотом — поза действия (её ведут твины оружия через `hand.new_tween()/tween_to()`, тайминги остаются в оружии), пружина `kick()`, состояние `state` («melee_strike», «throw», «reload»…, потом «rest»); общий слой — бег, мышь, прыжок/приземление/рывок, берсерк. Пивоты пишет только он (оружию — не трогать `pivot.position` напрямую). Время — игровое (hit-stop замораживает руки). Числа — `viewmodel_motion.tres` + поля `ViewmodelArm`, TUNING.md. Тест `tests/hands_test.tscn`, кадры `tests/hands_shots.tscn -- <папка> [quick]` (xvfb). Оружие строится при запуске (в .tscn не сохраняется). У SubViewport рук свой мир и свет (`own_world_3d`).

Вьюмодель рук — слой отображения 2, отдельный SubViewport (`Head/Camera/ViewmodelContainer`). Руки комиксовой обводкой не обводятся (решение по кадрам).

## Типовые задачи
- Новый трюк для шкалы стиля → ключ в `style_tuning.tres` `points` + `StyleMeter.event(&"…")` в месте трюка.
- Новое «ощущенческое» число → `@export` + строка в `TUNING.md`.
- Настройки игрока (чувствительность, FOV, тряска) применяет `GameSettings.apply_to_player(p)` из `Player._ready`.

## Тесты
`jump_test`, `runes_test`, `slam_gate_test`, `dive_gate_test`, `body_test`, `style_test`, `hands_test`, `combat_clock_test`, `smoke_test` (полная карта — `tests/test_map.json`).
