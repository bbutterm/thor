extends MjolnirTraitHandler
## Приём «Праща» (блок Б4, группа «удержание ПКМ» — с Бурей и Зарядом не берётся).
## Держи ПКМ с молотом в руке: молот крутится на ремне вокруг Тора и бьёт всех рядом.
## Отпустил — летит с разгоном (быстрее, сильнее) и пробивает щиты и броню элиты насквозь.
## Короткое нажатие (меньше spin_delay) — обычный бросок. Ур. 2 — крутится дольше, бросок сильнее.
## Вид: копия модели молота (WeaponMeshes.hammer — общий материал) на орбите вокруг Тора.

## Через сколько секунд удержания молот начинает крутиться
@export var spin_delay: float = 0.2
@export var orbit_radius: float = 1.9
## Угловая скорость (рад/с)
@export var spin_speed: float = 9.0
## Шаг урона (с) и урон за шаг — всем в круге орбиты (0.5 У)
@export var tick: float = 0.25
@export var spin_damage: float = 11.0
@export var spin_knockback: float = 8.0
## Дольше этого не крутится — бросок сам (с)
@export var max_spin: float = 4.0
@export var max_spin_lvl2: float = 6.0
@export var launch_speed_mult: float = 1.4
@export var launch_damage_mult: float = 1.3
@export var launch_damage_mult_lvl2: float = 1.6

## Подпись удержания в HUD (tr при показе)
const HOLD_LABEL := "ПРАЩА"

var _vis: Node3D = null
var _angle: float = 0.0
var _tick_t: float = 0.0
var _hits: int = 0

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"hold_throw":
		return true
	return value

func is_spinning() -> bool:
	return _vis != null and is_instance_valid(_vis)

func on_hold_start(_h: MjolnirHand) -> void:
	_angle = 0.0
	_tick_t = 0.0

func on_hold_tick(h: MjolnirHand, held: float, delta: float) -> void:
	if held < spin_delay:
		return
	var p := h.player
	var spin_max: float = lvl(max_spin, max_spin_lvl2)
	h.hold_label = HOLD_LABEL
	h.hold_progress = clampf((held - spin_delay) / maxf(spin_max - spin_delay, 0.01), 0.0, 1.0)
	if not is_spinning():
		_vis = Node3D.new()
		_vis.name = "SlingHammer"
		_vis.set_meta("transient", true)
		var m := WeaponMeshes.hammer()
		m.scale = Vector3.ONE * 1.15
		m.rotation_degrees = Vector3(0, 0, 90)
		_vis.add_child(m)
		p.get_parent().add_child(_vis)
		if h.pivot:
			h.pivot.visible = false
		Audio.play("sounds/sfx/hammer_throw.wav")
		mark("spin")
	_angle += spin_speed * delta
	var c := p.global_position + Vector3(0, 1.1, 0)
	_vis.global_position = c + Vector3(cos(_angle), 0, sin(_angle)) * orbit_radius
	_vis.rotation = Vector3(0, -_angle, 0)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = tick
		var any := false
		for e in enemies_near(p.get_tree(), c, orbit_radius + 0.8):
			var dir := e.global_position - p.global_position
			dir.y = 0
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
			var tangent := dir.cross(Vector3.UP)
			hurt(e, spin_damage * h.damage_mult, (dir + tangent * 0.6).normalized() * spin_knockback + Vector3.UP * 2.0, "hammer")
			any = true
			_hits += 1
		FX.ring(p.get_parent(), p.global_position, orbit_radius + 0.4, Color(0.55, 0.85, 1.0, 0.45), tick)
		if any:
			Audio.play("sounds/sfx/hammer_hit.wav")
	if held >= spin_max:
		h.release_hold()

func on_hold_release(h: MjolnirHand, held: float) -> void:
	var spun := is_spinning()
	_clear(h)
	if held < 0.0 or not spun:
		return
	h.next_throw["speed_mult"] = float(h.next_throw.get("speed_mult", 1.0)) * launch_speed_mult
	h.next_throw["damage_mult"] = float(h.next_throw.get("damage_mult", 1.0)) * float(lvl(launch_damage_mult, launch_damage_mult_lvl2))
	h.next_throw["pierce"] = true
	mark("launch")

func _clear(h: MjolnirHand) -> void:
	if is_spinning():
		_vis.queue_free()
	_vis = null
	if h and h.pivot and h.in_hand:
		h.pivot.visible = true

func on_unequip(h: MjolnirHand) -> void:
	_clear(h)

## Сколько ударов нанесла праща за забег (для тестов)
func spin_hits() -> int:
	return _hits
