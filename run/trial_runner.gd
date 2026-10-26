extends Node3D
class_name TrialRunner
## Идущее испытание в зале (блок Ф, GDD 15.1): следит за условием TrialDef, ведёт таймер, показывает HUD,
## ведущий (Один / Хильд / Локи) комментирует старт, успех и провал. Узел «Trial» — ребёнок зала
## (умирает вместе с залом). Награду после зачистки выдаёт RewardFlow по is_success().

signal finished(success: bool)

const LAVA_COLOR := Color(1.0, 0.27, 0.04)

var def: TrialDef
var room: Room
var player: Player
## ready → running → passed / failed
var state: String = "ready"
var elapsed: float = 0.0
var kills: int = 0
## Суммарный ожог лавой, с
var burn: float = 0.0
var fail_reason: String = ""
var hud: TrialHUD
var _contact: float = 0.0
var _tick: float = 0.0
var _floor_y: float = 0.0
var _lava: MeshInstance3D

## Случайное испытание по весам (forced — id для тестов).
static func pick(forced: String = "") -> TrialDef:
	var pool: Array = Run.all_trials
	if forced != "":
		for t in pool:
			if (t as TrialDef).id == forced:
				return t
	var total := 0.0
	for t in pool:
		total += maxf(0.0, (t as TrialDef).weight)
	if pool.is_empty() or total <= 0.0:
		return null
	var x := randf() * total
	for t in pool:
		x -= maxf(0.0, (t as TrialDef).weight)
		if x <= 0.0:
			return t
	return pool[pool.size() - 1]

## Подготовить испытание в зале (до room.start): доп. волны, лава.
static func attach(r: Room, d: TrialDef) -> TrialRunner:
	var t := TrialRunner.new()
	t.name = "Trial"
	t.def = d
	t.room = r
	r.add_child(t)
	t._prepare()
	return t

func _prepare() -> void:
	Perf.mark("trial_prepare")
	_floor_y = room.global_position.y
	if def.kind == "kill_count" and def.extra_waves > 0:
		var base: Array[Node3D] = []
		for m in room.spawns.get_children():
			base.append(m as Node3D)
		for w in def.extra_waves:
			var copies: Array[Node3D] = []
			for m in base:
				var c := Marker3D.new()
				c.set_meta("kind", m.get_meta("kind", "grunt"))
				c.position = m.position + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
				copies.append(c)
			room.add_wave(copies)
	if def.kind == "floor_lava":
		_build_lava()

func _build_lava() -> void:
	var half_w := 12.0
	var wall := room.get_node_or_null("Geometry/WallE") as Node3D
	if wall:
		half_w = wall.position.x - 0.5
	var north := room.door.position.z + 0.3 if room.door else -12.0
	var south := 12.0
	var ws := room.get_node_or_null("Geometry/WallS") as Node3D
	if ws:
		south = ws.position.z - 0.5
	_lava = MeshInstance3D.new()
	_lava.name = "Lava"
	_lava.mesh = FX.shared_mesh("box")
	FX.fx_apply(_lava, "alpha", Color(LAVA_COLOR, 0.7), 1.3)
	_lava.scale = Vector3(half_w * 2.0, 0.02, south - north)
	_lava.position = Vector3(0, 0.035, (north + south) * 0.5)
	_lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lava)
	var tw := _lava.create_tween().set_loops()
	tw.tween_property(_lava, "transparency", 0.45, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_lava, "transparency", 0.15, 0.8).set_trans(Tween.TRANS_SINE)

## Старт (вместе с первой волной): ведущий объявляет условие.
func start(p: Player) -> void:
	player = p
	state = "running"
	elapsed = 0.0
	Perf.mark("trial_start")
	Save.bump_event("challenge")
	Run.kill_registered.connect(_on_kill)
	room.cleared.connect(_on_room_cleared)
	hud = TrialHUD.new()
	hud.name = "TrialHUD"
	add_child(hud)
	hud.setup(def)
	Audio.play("sounds/sfx/trial_start.wav")
	Dialogue.bark_pool(def.pool("intro"))

func _exit_tree() -> void:
	if Run.kill_registered.is_connected(_on_kill):
		Run.kill_registered.disconnect(_on_kill)

func is_running() -> bool:
	return state == "running"

func is_success() -> bool:
	return state == "passed"

func _physics_process(delta: float) -> void:
	if state != "running" or player == null or not is_instance_valid(player) or player.is_dead:
		return
	elapsed += delta
	match def.kind:
		"no_ranged":
			var h := player.weapons
			if h and h.is_ranged_active() and h.gun.is_firing():
				fail("Выстрелил из палки-стрелялки")
		"time_limit":
			if def.time_limit > 0.0 and elapsed > def.time_limit:
				fail("Не уложился в %d с" % int(def.time_limit))
		"kill_count":
			if elapsed > def.time_limit:
				fail("%d из %d за %d с" % [kills, def.target, int(def.time_limit)])
		"floor_lava":
			_lava_tick(delta)
	if hud:
		hud.update_state(self)

func _lava_tick(delta: float) -> void:
	var on_floor := player.is_on_floor() and player.global_position.y < _floor_y + 0.3
	if not on_floor:
		_contact = 0.0
		return
	_contact += delta
	if _contact < def.lava_grace:
		return
	burn += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = def.lava_tick
		RunTracker.note_damage("lava")
		player.take_damage(def.lava_tick_damage)
		FX.sparks(get_parent(), player.global_position + Vector3(0, 0.1, 0), LAVA_COLOR, 8, 4.0, 10.0, 0.06, 0.35)
	if burn > def.lava_max_burn:
		fail("Слишком долго стоял в лаве")

func _on_kill(source: String) -> void:
	if state != "running":
		return
	kills += 1
	match def.kind:
		"only_sources":
			# Провал — только добивание запрещённым (огонь, шмяк об стену и т. п. — не считаются)
			if source in def.forbidden_sources:
				fail("Добил не тем: %s" % _source_name(source))
		"no_ranged":
			if source == "ranged":
				fail("Убийство из ренжа")
		"kill_count":
			if kills >= def.target and elapsed <= def.time_limit:
				_record_best()
				pass_trial()

func _source_name(s: String) -> String:
	match s:
		"melee", "melee_finisher", "melee_heavy":
			return "оружием в руке"
		"ranged":
			return "ренжем"
		"dash":
			return "рывком"
	return s

func _on_room_cleared() -> void:
	if state != "running":
		return
	match def.kind:
		"kill_count":
			_record_best()
			fail("%d из %d — рекорд устоял" % [kills, def.target])
		"time_limit":
			if elapsed <= def.time_limit:
				pass_trial()
			else:
				fail("Не уложился в %d с" % int(def.time_limit))
		_:
			pass_trial()

func _record_best() -> void:
	var rec: Dictionary = Save.data.get("records", {})
	var key := "trial_%s_best" % def.id
	rec[key] = maxi(int(rec.get(key, 0)), kills)

func pass_trial() -> void:
	if state != "running":
		return
	state = "passed"
	Perf.mark("trial_pass")
	Audio.play("sounds/sfx/trial_win.wav")
	Dialogue.bark_pool(def.pool("win"))
	_remove_lava()
	if hud:
		hud.update_state(self)
	finished.emit(true)

func fail(reason: String) -> void:
	if state != "running":
		return
	state = "failed"
	fail_reason = reason
	Perf.mark("trial_fail")
	Audio.play("sounds/sfx/trial_fail.wav")
	Dialogue.bark_pool(def.pool("fail"))
	_remove_lava()
	if hud:
		hud.update_state(self)
	finished.emit(false)

func _remove_lava() -> void:
	if _lava and is_instance_valid(_lava):
		var tw := _lava.create_tween()
		tw.tween_property(_lava, "transparency", 1.0, 0.6)
		tw.tween_callback(_lava.queue_free)
		_lava = null

## Образцы для прогрева шейдеров: лава и панель испытания.
static func warmup_samples(parent: Node3D, right: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = FX.shared_mesh("box")
	FX.fx_apply(m, "alpha", Color(LAVA_COLOR, 0.7), 1.3)
	m.scale = Vector3(0.6, 0.02, 0.6)
	m.transparency = 0.3
	parent.add_child(m)
	m.position = right * -0.9 + Vector3(0, -0.8, 0)
