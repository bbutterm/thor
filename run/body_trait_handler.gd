extends Resource
class_name BodyTraitHandler
## Обработчик пассивки или изъяна тела (GDD 6) — как у трейтов Мьёльнира (weapons/mjolnir_trait_handler.gd).
## Скрипт конкретной черты наследует этот класс и переопределяет нужные хуки; его @export-поля — числа черты
## (хранятся в .tres черты, run/passives/<id>.tres, как вложенный ресурс).
## На забег игрок делает копию (duplicate), поэтому в полях можно хранить состояние (например, «удар в зале уже был»).
##
## Кто вызывает хуки (player/player.gd, блок «Пассивки и изъяны тела»):
##   on_equip — тело применено (старт забега); on_room_start — начало зала (Game._load_room);
##   on_kill — убийство (Run.kill_registered); on_hit — Тор попал по врагу (Player.deal_damage);
##   on_damaged — Тора бьют (Player.take_damage, может уменьшить урон); on_dash — рывок/подкат;
##   on_slam — удар-приземление; on_jump — прыжок с земли.
##   damage_mult — множитель исходящего урона (по цели и источнику); modify — числа тела (см. ниже).

var player: Player
var def: PassiveDef

## Изменение числа. stat:
##   "heal_mult" (float) — лечение; "rune_power" (int) — во сколько раз считаются руны (Run.rune_count);
##   "ranged_move_mult" (float) — замедление ренжем; "air_dash" (bool) — рывок в воздухе;
##   "aim_wobble_deg" (float) — покачивание прицела; "start_weapon_level" (int) — уровень стартового оружия;
##   "parry_window_mult", "parry_heal" — окно парирования и лечение при успехе;
##   "sharpen_cost_mult" — заточка у Эйтри (run/shop.gd → Shop.price).
func modify(_stat: StringName, value: Variant) -> Variant:
	return value

## Множитель урона по цели target (Enemy или null) источником source ("melee", "melee_heavy", "ranged", "hammer", "slam"…)
func damage_mult(_target: Object, _source: String) -> float:
	return 1.0

func on_equip(_p: Player) -> void:
	pass

func on_room_start(_p: Player) -> void:
	pass

func on_kill(_p: Player, _source: String) -> void:
	pass

func on_hit(_p: Player, _target: Object, _damage: float, _source: String) -> void:
	pass

## Тора бьют на amount. Вернуть итоговый урон (0 — удар не ранит).
func on_damaged(_p: Player, amount: float) -> float:
	return amount

func on_dash(_p: Player) -> void:
	pass

func on_slam(_p: Player, _power: float, _hits: int) -> void:
	pass

func on_jump(_p: Player) -> void:
	pass

# --- Помощники ---

## Тор бьёт врага в спину: враг смотрит от Тора (как у axe.gd, порог -0.35)
static func is_behind(p: Player, target: Object) -> bool:
	var e := target as Node3D
	if e == null or p == null or not (target is Enemy):
		return false
	var to_p := p.global_position - e.global_position
	to_p.y = 0
	return to_p.length() > 0.01 and e.global_transform.basis.z.dot(to_p.normalized()) < -0.35

## Тор бьёт врага в лицо: враг смотрит на Тора
static func is_front(p: Player, target: Object) -> bool:
	var e := target as Node3D
	if e == null or p == null or not (target is Enemy):
		return false
	var to_p := p.global_position - e.global_position
	to_p.y = 0
	return to_p.length() > 0.01 and e.global_transform.basis.z.dot(to_p.normalized()) > 0.35

func mark(what: String = "") -> void:
	Perf.mark("body_" + (def.id if def else "?") + ("_" + what if what != "" else ""))
