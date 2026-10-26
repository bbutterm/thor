# Тор: Достойная смерть — заметки для агента

Прототип рогалик-шутера от первого лица. Godot **4.6.3** (не .NET), физика Jolt, GDScript со статической типизацией. Общение с владельцем — на русском.

## Где что
- `player/player.gd` — движение (рывок, двойной прыжок, удар-приземление, супер-прыжок), урон; `player/camera_fx.gd` — тряска/FOV/наклон.
- `weapons/` — топор (`axe.gd`), Мьёльнир (`mjolnir_hand.gd` + `mjolnir_projectile.gd`), огонь (`fire_zone.gd`).
- `enemies/enemy.gd` — один скрипт на грунта/метателя/босса (поле `kind`); `enemy_projectile.gd`.
- `rooms/room.gd` + `rooms/*.tscn` — залы, волны (маркеры в `Spawns` с метаданными `kind`/`wave`), дверь, выход.
- `run/run_manager.gd` (автозагрузка `Run`) — забег, Слава, руны; `run/odin.gd` (`Odin`) — реплики из `data/odin_lines.json`.
- `ui/` — HUD, выбор рун, пауза, экран конца, меню (всё строится кодом, `.tscn` — пустые обёртки со скриптом).
- `scripts/fx.gd` — hit-stop (тикает из `Run._process`), цифры урона, молнии, кольца, искры.

## Важно
- Сцены игрока, врагов, бочек, залов, UI и `scenes/game.tscn` **генерирует** `tools/build_scenes.gd`. Меняешь структуру сцены — правь генератор и перезапускай его. ⚠️ Если владелец правил залы руками в редакторе, генератор их перезапишет — спроси сначала.
- Блоки уровней — StaticBody3D, не CSG (CSG давал провалы сквозь пол в первые кадры).
- Слои физики: 1 world, 2 player, 3 enemies, 4 props, 5 projectiles, 6 triggers, 7 debris.
- Вьюмодель рук — слой отображения 2, отдельный SubViewport (`Head/Camera/ViewmodelContainer`).
- Все «ощущенческие» числа — `@export`; при изменении обнови `TUNING.md`.
- Звуки в `sounds/sfx/` синтезирует `tools/make_sfx.py`.
- `_kit_original/` — исходная демо-сцена кита, игнорируется Godot (`.gdignore`).

## Проверки (запускать после изменений)
```
godot --headless --path . --import
godot --headless --path . res://tools/build_scenes.tscn              # если менялись генерируемые сцены
godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn # полный забег, ожидается 0 FAIL
godot --headless --path . --fixed-fps 60 res://tests/reach_test.tscn # достижимость платформ
godot --headless --path . --fixed-fps 60 res://tests/ai_test.tscn    # враги доходят и бьют во всех залах
```
Скриншоты (нужен xvfb): `xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/screenshots.tscn -- <папка>`.

Экспорт: `godot --headless --path . --export-release "Windows Desktop" export/windows/ThorDostoynayaSmert.exe` (нужны export templates 4.6.3). Проверка сборки: `<exe> --headless -- --selftest`.
