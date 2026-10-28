extends RefCounted
class_name EnemyTactics
## Роли поведения поверх вида врага (GDD 12.6). Ограничения числа атакующих нет — роли только меняют,
## КУДА враг идёт, а бьёт каждый, кто дошёл.
##   SURROUND — боец встаёт в свою точку круга вокруг Тора (угол — «золотой» шаг), а не в одну кучу;
##   FLANK    — боец обходит сбоку/сзади (от взгляда Тора), потом сходится;
##   COVER    — стрелок/шаман держится за ближайшим щитоносцем (со стороны от Тора); при сближении — отход;
##   ESCORT   — свита держится кольцом вокруг якоря (шаман отряда), пока Тор не рядом;
##   LURK     — Раздутый прячется за спинами своих и выбегает, когда Тор занят (рядом с ним другие враги);
##   отступление — раненый стрелок (< tactics_retreat_hp) отбегает tactics_retreat_time с обстрелом.
## Роль ставит assign() (из Enemy._setup_special); отряд (SquadDef) может задать её метаданными
## "tactic_role" и якорь "tactic_anchor" до add_child. Числа — поля Enemy (группа «Роли»), TUNING.md.
## Компонент Enemy (этап 3 рефакторинга): состояние — поля Enemy (_role, _slot_angle, _retreat_left…).

enum Role { NONE, SURROUND, FLANK, COVER, ESCORT, LURK }

const ROLE_NAMES := {"surround": Role.SURROUND, "flank": Role.FLANK, "cover": Role.COVER, "escort": Role.ESCORT, "lurk": Role.LURK, "none": Role.NONE}

## Следующий угол круга (золотой угол — соседи по порядку появления встают далеко друг от друга)
static var _slot_counter: int = 0

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

func assign() -> void:
	_slot_counter += 1
	enemy._slot_angle = fmod(float(_slot_counter) * 2.39996, TAU)
	enemy._flank_sign = 1.0 if _slot_counter % 2 == 0 else -1.0
	if enemy.has_meta("tactic_role"):
		enemy._role = ROLE_NAMES.get(str(enemy.get_meta("tactic_role")), Role.NONE)
		return
	match enemy.kind:
		Enemy.Kind.GRUNT:
			enemy._role = Role.FLANK if randf() < enemy.tactics_flank_chance else Role.SURROUND
		Enemy.Kind.THROWER, Enemy.Kind.MERC, Enemy.Kind.SHAMAN:
			enemy._role = Role.COVER
		_:
			enemy._role = Role.NONE

func role_name() -> String:
	for k in ROLE_NAMES:
		if ROLE_NAMES[k] == enemy._role:
			return k
	return "none"

func _ground_dir(to: Vector3) -> Vector3:
	var d := to - enemy.global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO

func _anchor() -> Node3D:
	if not enemy.has_meta("tactic_anchor"):
		return null
	var a: Variant = enemy.get_meta("tactic_anchor")
	# Якорь (шаман) мог погибнуть и быть удалён — тогда свита идёт в бой
	if not is_instance_valid(a):
		enemy.remove_meta("tactic_anchor")
		return null
	var n := a as Node3D
	if n == null or (n is Enemy and (n as Enemy).is_dead):
		return null
	return n

## Ближний бой: куда идти вместо прямой к Тору (dir — к Тору, dist — до него).
func melee_dir(dist: float, dir: Vector3) -> Vector3:
	var p := enemy.player
	if p == null or dir == Vector3.ZERO:
		return dir
	var engage := enemy.attack_range + 0.6
	match enemy._role:
		Role.SURROUND:
			var slot_dir := Vector3(sin(enemy._slot_angle), 0, cos(enemy._slot_angle))
			if dist <= engage + enemy.tactics_surround_orbit:
				# Рядом с Тором: если своя точка круга далеко по углу — обходим по кругу к ней
				var from_p := enemy.global_position - p.global_position
				from_p.y = 0.0
				if from_p.length() < 0.05 or rad_to_deg(from_p.angle_to(slot_dir)) < enemy.tactics_surround_slot_deg:
					return dir
				var tangent := Vector3.UP.cross(from_p.normalized())
				if tangent.dot(slot_dir) < 0.0:
					tangent = -tangent
				var radial := -from_p.normalized() * clampf(from_p.length() - enemy.tactics_surround_radius, -1.0, 1.0)
				return (tangent + radial * 0.6).normalized()
			var to := _ground_dir(p.global_position + slot_dir * enemy.tactics_surround_radius)
			# Далеко — ближе к прямой (не бегать по дуге через весь зал)
			var w := clampf((dist - engage) / 10.0, 0.0, 0.7)
			return (to * (1.0 - w) + dir * w).normalized()
		Role.FLANK:
			if dist <= enemy.tactics_flank_radius + 0.5:
				return dir
			var back := p.global_transform.basis.z  # взгляд Тора — -Z
			back.y = 0.0
			back = back.normalized() if back.length() > 0.05 else -dir
			var side := back.rotated(Vector3.UP, deg_to_rad(enemy.tactics_flank_angle_deg) * enemy._flank_sign)
			var r := clampf(dist * 0.6, enemy.tactics_flank_radius, 8.0)
			return _ground_dir(p.global_position + side * r)
		Role.ESCORT:
			var a := _anchor()
			if a and dist > enemy.tactics_escort_engage:
				var ring := Vector3(sin(enemy._slot_angle), 0, cos(enemy._slot_angle)) * enemy.tactics_escort_radius
				var target := a.global_position + ring
				var d := target - enemy.global_position
				d.y = 0.0
				return d.normalized() if d.length() > 0.6 else Vector3.ZERO
		Role.LURK:
			if dist > enemy.tactics_lurk_rush_dist and not _player_busy():
				var cover := _nearest_ally(enemy.tactics_cover_search, [Enemy.Kind.GRUNT, Enemy.Kind.SHIELD, Enemy.Kind.FODDER])
				if cover:
					var away := cover.global_position - p.global_position
					away.y = 0.0
					var spot := cover.global_position + away.normalized() * enemy.tactics_cover_offset
					var d := spot - enemy.global_position
					d.y = 0.0
					return d.normalized() if d.length() > 0.8 else Vector3.ZERO
	return dir

## Окружение: бить с места или сначала обойти к своей точке круга (рядом уже стоит свой — толкучка).
## Не очередь: ждать не дольше tactics_surround_patience, потом бьёт откуда стоит.
func strike_ok(delta: float) -> bool:
	if enemy._role != Role.SURROUND or enemy.player == null:
		return true
	var from_p := enemy.global_position - enemy.player.global_position
	from_p.y = 0.0
	var slot_dir := Vector3(sin(enemy._slot_angle), 0, cos(enemy._slot_angle))
	if from_p.length() < 0.05 or rad_to_deg(from_p.angle_to(slot_dir)) < enemy.tactics_surround_slot_deg or not _crowded():
		enemy._reposition_t = 0.0
		return true
	enemy._reposition_t += delta
	if enemy._reposition_t >= enemy.tactics_surround_patience:
		enemy._reposition_t = 0.0
		return true
	return false

## У Тора уже есть другой боец ближнего боя (ближе tactics_surround_crowd к Тору) — тогда своя точка круга важна.
func _crowded() -> bool:
	var pp := enemy.player.global_position
	for e in enemy._enemies_now():
		var en := e as Enemy
		if en == null or en == enemy or not is_instance_valid(en) or en.is_dead or en.kind == Enemy.Kind.FODDER:
			continue
		if en.global_position.distance_to(pp) < enemy.tactics_surround_crowd:
			return true
	return false

## Тор занят: рядом с ним (в пределах tactics_busy_radius) хотя бы tactics_busy_count других врагов.
func _player_busy() -> bool:
	var n := 0
	for e in enemy._enemies_now():
		var en := e as Enemy
		if en == null or en == enemy or not is_instance_valid(en) or en.is_dead:
			continue
		if en.global_position.distance_to(enemy.player.global_position) < enemy.tactics_busy_radius:
			n += 1
			if n >= enemy.tactics_busy_count:
				return true
	return false

func _nearest_ally(radius: float, kinds: Array) -> Enemy:
	var best: Enemy = null
	var bd := radius
	for e in enemy._enemies_now():
		var en := e as Enemy
		if en == null or en == enemy or not is_instance_valid(en) or en.is_dead or not (en.kind in kinds):
			continue
		var d := en.global_position.distance_to(enemy.global_position)
		if d < bd:
			bd = d
			best = en
	return best

## Стрелок/шаман: поправка к обычному «держу дистанцию» (move). Отступление раненого — у всех стрелков.
func ranged_move(dist: float, dir: Vector3, move: Vector3, delta: float) -> Vector3:
	var p := enemy.player
	if p == null:
		return move
	# Отступление раненого: один раз, когда HP упало ниже порога
	if not enemy._retreated and enemy.health < enemy.max_health * enemy.tactics_retreat_hp:
		enemy._retreated = true
		enemy._retreat_left = enemy.tactics_retreat_time
	if enemy._retreat_left > 0.0:
		enemy._retreat_left -= delta
		var away := -dir.rotated(Vector3.UP, 0.5 * enemy._flank_sign)
		if enemy._has_floor_ahead(away):
			return away
		if enemy._has_floor_ahead(-dir):
			return -dir
		return move
	if enemy._role == Role.COVER and dist > enemy.keep_min_dist:
		var shield := _nearest_ally(enemy.tactics_cover_search, [Enemy.Kind.SHIELD])
		if shield:
			var behind := shield.global_position - p.global_position
			behind.y = 0.0
			if behind.length() > 0.1:
				var spot := shield.global_position + behind.normalized() * enemy.tactics_cover_offset \
					+ behind.normalized().cross(Vector3.UP) * enemy._flank_sign * 1.2
				var d := spot - enemy.global_position
				d.y = 0.0
				if d.length() > 0.8 and enemy._has_floor_ahead(d.normalized()):
					return d.normalized()
				return Vector3.ZERO
	return move

## Стрелок прикрыт: между ним и Тором — щитоносец (для тестов и отладки).
func is_covered() -> bool:
	var p := enemy.player
	if p == null:
		return false
	var shield := _nearest_ally(enemy.tactics_cover_search, [Enemy.Kind.SHIELD])
	if shield == null:
		return false
	var to_p := p.global_position - enemy.global_position
	var to_s := shield.global_position - enemy.global_position
	to_p.y = 0.0
	to_s.y = 0.0
	return to_s.length() < to_p.length() and to_s.normalized().dot(to_p.normalized()) > 0.6
