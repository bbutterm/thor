extends MjolnirTraitHandler
## Приём «Заряд» (блок Б4, группа «удержание ПКМ» — с Бурей и Пращой не берётся).
## Чем дольше держишь ПКМ с молотом в руке, тем сильнее бросок: больше урона, быстрее и дальше летит;
## в полную силу — пробивает щиты и броню элиты. Отпустил — бросок. Короткое нажатие — обычный бросок.
## Ур. 2 — заряжается быстрее, бросок сильнее и оглушает задетых.
## Вид: рука с молотом отходит назад, на полном заряде — искры и звук; полоска заряда — в HUD молота.

## Сколько держать до полного заряда (с)
@export var charge_time: float = 0.8
@export var charge_time_lvl2: float = 0.55
## Короче этого — обычный бросок (с)
@export var min_hold: float = 0.12
@export var max_damage_mult: float = 2.2
@export var max_damage_mult_lvl2: float = 2.6
@export var max_speed_mult: float = 1.4
@export var max_range_mult: float = 1.8
## С какой доли заряда бросок пробивает щиты и броню
@export_range(0.0, 1.0) var pierce_at: float = 0.95
## Ур. 2: оглушение задетых полным зарядом (с)
@export var stun_lvl2: float = 0.8
## Насколько рука отходит назад на полном заряде
@export var pull_back: Vector3 = Vector3(0.06, -0.06, 0.28)

## Подпись удержания в HUD (tr при показе)
const HOLD_LABEL := "ЗАРЯД"

var _full: bool = false
## Заряд последнего броска 0…1 (для тестов)
var last_charge: float = 0.0

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"hold_throw":
		return true
	return value

func charge_of(held: float) -> float:
	if held < min_hold:
		return 0.0
	return clampf((held - min_hold) / maxf(float(lvl(charge_time, charge_time_lvl2)), 0.01), 0.0, 1.0)

func on_hold_start(_h: MjolnirHand) -> void:
	_full = false

func on_hold_tick(h: MjolnirHand, held: float, _delta: float) -> void:
	var k := charge_of(held)
	if k <= 0.0:
		return
	h.hold_label = HOLD_LABEL
	h.hold_progress = k
	if h.pivot:
		h.pivot.position = MjolnirHand.REST_POS + pull_back * k
	if k >= 1.0 and not _full:
		_full = true
		FX.sparks(h.player.get_parent(), h.hand_point() + h.player.get_aim_forward() * 0.6, Color(1.0, 0.9, 0.5), 14, 4.0)
		h.player.camera_fx.kick_fov(3.0)
		Audio.play("sounds/sfx/perfect_catch.wav")
		mark("full")

func on_hold_release(h: MjolnirHand, held: float) -> void:
	if h.pivot:
		h.pivot.position = MjolnirHand.REST_POS
	if held < 0.0:
		return
	var k := charge_of(held)
	last_charge = k
	if k <= 0.0:
		return
	var dm := lerpf(1.0, float(lvl(max_damage_mult, max_damage_mult_lvl2)), k)
	h.next_throw["damage_mult"] = float(h.next_throw.get("damage_mult", 1.0)) * dm
	h.next_throw["speed_mult"] = float(h.next_throw.get("speed_mult", 1.0)) * lerpf(1.0, max_speed_mult, k)
	h.next_throw["range_mult"] = float(h.next_throw.get("range_mult", 1.0)) * lerpf(1.0, max_range_mult, k)
	if k >= pierce_at:
		h.next_throw["pierce"] = true
		if level >= 2:
			h.next_throw["stun"] = stun_lvl2
	mark("throw")
