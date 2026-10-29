extends BossEnemy
class_name BerserkerBoss
## Берсерк-ульфхеднар — мини-босс Мидгарда (GDD 14.1): дуэлянт в волчьей шкуре, бой на реакцию.
## - Серия из series_count рывков: перед каждым — красная полоса на полу (телеграф dash_aim), потом рывок
##   (таран BossEnemy: перепрыгнуть или уйти рывком вбок).
## - После серии — окно уязвимости vulnerable_time: стоит, тяжело дышит, урон по нему ×vulnerable_damage_mult.
## - При rage_hp_fraction — ярость: телеграф короче, рывки быстрее, окно короче, светится красным.
## Между сериями — обычный ближний бой босса. Числа и вид перекрывает MinibossDef (minibosses/berserker.tres).

enum Act { NONE, DASH_AIM, DASH, DASH_PAUSE, VULNERABLE }

@export_group("Берсерк: серия рывков")
@export var series_interval: float = 5.0
@export var series_count: int = 3
@export var dash_aim: float = 0.6
@export_range(0.0, 1.0) var dash_lock_at: float = 0.75
@export var dash_speed: float = 17.0
@export var dash_max_dist: float = 12.0
@export var dash_damage: float = 20.0
@export var dash_knock: float = 11.0
## Пауза между рывками серии (с)
@export var dash_pause: float = 0.25
## Серия начинается, если Тор не ближе этого (м)
@export var series_min_dist: float = 3.5
@export_group("Берсерк: окно уязвимости")
@export var vulnerable_time: float = 2.0
@export var vulnerable_damage_mult: float = 1.5
@export_group("Берсерк: ярость")
@export_range(0.0, 1.0) var rage_hp_fraction: float = 0.33
@export var rage_aim_mult: float = 0.6
@export var rage_speed_mult: float = 1.2
@export var rage_window_mult: float = 0.6

var raging: bool = false
var series_done: int = 0
var dashes: int = 0
var _series_cd: float = 2.5
var _dash_left: int = 0

func _ready() -> void:
	super._ready()
	set_meta("death_source_id", "miniboss_berserker")

func _boss_think(delta: float) -> void:
	_series_cd -= delta
	if not raging and health <= max_health * rage_hp_fraction:
		_enrage()
	if not can_start_act():
		return
	if _series_cd <= 0.0 and dist_to_player() >= series_min_dist and _has_line_of_sight():
		_dash_left = series_count
		set_act(Act.DASH_AIM)

func current_aim() -> float:
	return dash_aim * (rage_aim_mult if raging else 1.0)

func current_window() -> float:
	return vulnerable_time * (rage_window_mult if raging else 1.0)

func _run_act(delta: float) -> void:
	match act:
		Act.DASH_AIM:
			var k := act_time / current_aim()
			if k < dash_lock_at:
				_face_dir(dir_to_player(), delta * 6.0)
			var dir := global_transform.basis.z
			_windup_glow = clampf(k, 0.0, 1.0)
			strip_show(dir, clear_length(dir, dash_max_dist), 0.3 + 0.4 * k)
			act_move(Vector3.ZERO, delta)
			if act_time >= current_aim():
				Perf.mark("berserker_dash")
				dashes += 1
				charge_begin(global_transform.basis.z)
				set_act(Act.DASH)
				Audio.play("sounds/sfx/dash.wav")
		Act.DASH:
			var r := charge_step(delta, dash_speed * (rage_speed_mult if raging else 1.0), dash_max_dist, dash_damage, dash_knock)
			if r != 0:
				if r == 1:
					charge_wall_hit()
				_dash_left -= 1
				set_act(Act.DASH_PAUSE if _dash_left > 0 else Act.VULNERABLE)
				if act == Act.VULNERABLE:
					_start_vulnerable()
		Act.DASH_PAUSE:
			act_move(Vector3.ZERO, delta)
			if act_time >= dash_pause:
				set_act(Act.DASH_AIM)
		Act.VULNERABLE:
			act_move(Vector3.ZERO, delta)
			_windup_glow = 0.0
			if act_time >= current_window():
				_series_cd = series_interval * (0.7 if raging else 1.0)
				set_act(Act.NONE)

func _start_vulnerable() -> void:
	Perf.mark("berserker_window")
	CommandWords.cue(&"hit")
	series_done += 1
	if _humanoid:
		_humanoid.play(anim_stun, 0.1)
	FX.burst(get_parent(), global_position + Vector3(0, 1.8 * model_scale, 0), 0.6, Color(1, 1, 1, 0.5), 0.4)
	Audio.sfx("zombie_groan" if FX.is_undead(self) else "", "sounds/sfx/enemy_growl.wav")

func is_vulnerable() -> bool:
	return act == Act.VULNERABLE

func _enrage() -> void:
	Perf.mark("berserker_rage")
	raging = true
	move_speed *= rage_speed_mult
	elite_glow = Color(1.0, 0.15, 0.1, 0.35)
	bark("berserker.rage")
	ComicFX.pop("slam", global_position + Vector3(0, 2.0 * model_scale, 0), true)

func take_hit(damage: float, knockback: Vector3, source: String = "") -> void:
	if is_dead:
		return
	if act == Act.VULNERABLE and damage < DEBUG_KILL_DAMAGE:
		damage *= vulnerable_damage_mult
	super.take_hit(damage, knockback, source)
