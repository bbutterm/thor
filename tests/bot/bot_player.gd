extends Node
## Бот-плейтестер (блок Б5): играет за Тора «честно-ish» — через настоящий ввод (Input.action_press:
## движение, прыжок, рывок, удар-приземление, ЛКМ, ПКМ) и API оружия (свитч на ренж), сам выбирает
## руны, трейты, двери и покупки (политика с сидом). Бессмертия нет: урон от врагов — обычный, может умереть.
## Ограничения (см. docs/balance_*.md): навигация «напрямую к цели» без поиска пути; если застрял надолго —
## «подсадка» (телепорт к цели, считается в статистике); к луту и дверям — телепорт (выбор — по политике).
## Сам себя не запускает: им управляет tests/bot/balance_runner.gd (или bot_test).
## const BotPlayer := preload("res://tests/bot/bot_player.gd")

## Навыки бота (0..1): насколько часто уворачивается от телеграфа, ловит молот идеально и т. п.
var skill := {
	"dodge": 0.45,          # шанс увернуться рывком от замаха/тарана/фитиля (решение один раз на телеграф)
	"perfect": 0.35,        # шанс идеального хвата (ПКМ сразу после поимки, в окне)
	"aim_jitter_deg": 4.0,  # разброс прицела
	"turn_speed": 9.0,      # рад/с — как быстро поворачивает камеру
	"heavy": 0.2,           # доля сильных ударов по крепким целям
	"slam_jump": 0.35,      # шанс прыгнуть и ударить-приземлиться в толпу (за решение)
	"think": 0.12,          # период решений, с
	"reaction": 0.22,       # с: от смены цели до первого удара/броска
	"view_deg": 55.0,       # «видит» врагов в конусе ±view_deg от взгляда (или ближе hear_dist, или ударивших)
	"hear_dist": 3.5,
	"search_turn": 3.0,     # рад/с — оглядывается, когда никого не видит
}

## Профили навыка: «skilled» — опытный игрок (по умолчанию), «average» — средний, «novice» — новичок
## (не ловит молот идеально, почти не уворачивается, медленно целится).
const PROFILES := {
	"skilled": {},
	"average": {"dodge": 0.25, "perfect": 0.12, "aim_jitter_deg": 7.0, "turn_speed": 6.0, "heavy": 0.1, "slam_jump": 0.2,
		"think": 0.18, "reaction": 0.35},
	"novice": {"dodge": 0.1, "perfect": 0.0, "aim_jitter_deg": 10.0, "turn_speed": 4.0, "heavy": 0.05, "slam_jump": 0.05,
		"think": 0.25, "reaction": 0.5, "view_deg": 45.0, "search_turn": 2.0},
}

func set_profile(name: String) -> void:
	for k in PROFILES.get(name, {}):
		skill[k] = PROFILES[name][k]

var game: Game
var rng := RandomNumberGenerator.new()
var active: bool = false

# --- Статистика (читает раннер) ---
var stats: Dictionary = {}
var rooms: Array = []
var cur_room: Dictionary = {}
var rank_time: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0])
var picks: Array = []

# --- Внутреннее ---
var _held: Dictionary = {}       # action → кадров до отпускания (-1 — держать)
var _target: Enemy
var _think_t: float = 0.0
var _strafe: float = 1.0
var _strafe_t: float = 0.0
var _attack_t: float = 0.0
var _throw_t: float = 0.0
var _hammer_out_t: float = 0.0
var _hold_throw_t: float = 0.0
var _jump_plan: int = 0          # 0 — нет, 1 — прыгнул, ждём второго, 2 — второй сделан, ждём удара
var _jump_t: float = 0.0
var _jitter := Vector2.ZERO
var _jitter_t: float = 0.0
var _dodged: Dictionary = {}     # instance_id телеграфа → решено
var _progress_best: float = INF
var _progress_t: float = 0.0
var _stuck_tries: int = 0
var _ui_wait: float = 0.0
var _room_index: int = -1
var _room_obj: Room
var _post_clear: int = 0         # 0 — бой, 1 — лут, 2 — дверь
var _post_t: float = 0.0
var _shop_done: bool = false
var _boss: Dictionary = {}
var _react_t: float = 0.0
## Кого бот «знает» (видел/слышал): instance_id → до какого времени помнит
var _known: Dictionary = {}
var _searching: bool = false
var _clock: float = 0.0
## Слава по источникам: kill (база за врага с множителями), multikill, streak, прочее по награде зала
var glory_src: Dictionary = {}
var _glory_prev: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().physics_frame.connect(_tick)

## Начать забег: game — свежая сцена игры.
func begin(g: Game, seed_value: int) -> void:
	release_all()
	game = g
	rng.seed = seed_value
	seed(seed_value)
	active = true
	stats = {"assists": 0, "perfect": 0, "slams": 0, "throws": 0, "dodges": 0, "heavy": 0, "shots": 0, "dashes": 0,
		"falls_saved": 0, "deaths_room": -1}
	rooms.clear()
	cur_room = {}
	rank_time = PackedFloat32Array([0, 0, 0, 0, 0])
	picks.clear()
	_room_index = -1
	_room_obj = null
	_boss = {}
	_target = null
	game.player.hurt.connect(_on_hurt)
	game.player.mjolnir.perfect_catch.connect(func() -> void: stats.perfect += 1)
	game.player.slammed.connect(func(_p: float) -> void: stats.slams += 1)
	glory_src = {}
	_glory_prev = Run.glory
	if not Run.glory_changed.is_connected(_on_glory):
		Run.glory_changed.connect(_on_glory)
		Run.kill_registered.connect(_on_kill)

## Слава пришла: копим как «прочее», убийство (kill_registered сразу после) перенесёт её в kill/multikill/streak.
var _pending_glory: int = 0

func _on_glory(total: int) -> void:
	if not active:
		return
	var d := total - _glory_prev
	_glory_prev = total
	if d == 0:
		return
	_pending_glory += d
	_flush_glory.call_deferred()

func _on_kill(source: String) -> void:
	if not active:
		return
	var ks: Dictionary = stats.get("kill_src", {})
	ks[source] = int(ks.get(source, 0)) + 1
	stats.kill_src = ks
	if _pending_glory == 0:
		return
	var mult := (Run.body.glory_mult if Run.body else 1.0) * (1.0 + Run.rune_value("ancestor_glory"))
	var mk := int(round(Run.glory_multikill_bonus * maxi(0, Run._recent_kill_times.size() - 1) * mult))
	var stk := int(round(Run.glory_streak_bonus * mult)) if Run.streak > 0 and Run.streak % 10 == 0 else 0
	var is_boss_kill := _pending_glory >= int(Run.glory_boss_kill * mult * 0.9)
	mk = mini(mk, _pending_glory)
	stk = mini(stk, _pending_glory - mk)
	var boss := int(round(Run.glory_boss_kill * mult)) if is_boss_kill else 0
	_add_glory_src("multikill", mk)
	_add_glory_src("streak", stk)
	_add_glory_src("boss", boss)
	_add_glory_src("kill", _pending_glory - mk - stk - boss)
	_pending_glory = 0

func _flush_glory() -> void:
	if _pending_glory != 0:
		var key := "bonus_" + (Run.current_reward() if game and is_instance_valid(game) else "?")
		if game and is_instance_valid(game) and game.room and game.room._is_cleared and Run.current_reward() != "trial":
			key = "room_clear" if _pending_glory <= int(Run.glory_room_clear * 2.5) else key
		_add_glory_src(key, _pending_glory)
		_pending_glory = 0

func _add_glory_src(k: String, v: int) -> void:
	if v != 0:
		glory_src[k] = int(glory_src.get(k, 0)) + v

func stop() -> void:
	active = false
	release_all()
	_close_room()

func release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "dash", "slam", "attack", "throw", "interact"]:
		Input.action_release(a)
	_held.clear()

# --- Ввод ---

## Нажать действие на frames кадров (до отпускания). Нажатие — в начале кадра физики (до узлов), как в smoke_test.
func tap(action: String, frames: int = 1) -> void:
	if _held.has(action):
		return
	Input.action_press(action)
	_held[action] = frames

func hold(action: String, on: bool, strength: float = 1.0) -> void:
	if on:
		Input.action_press(action, strength)
		_held[action] = -1
	elif _held.get(action, 0) == -1:
		Input.action_release(action)
		_held.erase(action)

func _update_held() -> void:
	for a in _held.keys():
		var left: int = _held[a]
		if left == -1:
			continue
		left -= 1
		if left <= 0:
			Input.action_release(a)
			_held.erase(a)
		else:
			_held[a] = left

# --- Кадр ---

func _tick() -> void:
	_update_held()
	if not active or game == null or not is_instance_valid(game):
		return
	var p := game.player
	if p == null or p.is_dead:
		release_all()
		return
	var dt := 1.0 / 60.0
	_track_room(p)
	if _handle_ui(dt):
		return
	if get_tree().paused:
		return
	var room := game.room
	if room == null or not is_instance_valid(room):
		return
	if room._is_cleared or (Run.is_peaceful_room() and Run.doors_enabled):
		_after_clear(p, room, dt)
		return
	if not room._started:
		_stop_moving()
		return
	# Бой
	cur_room.fight_time = float(cur_room.get("fight_time", 0.0)) + dt
	var st := p.style
	if st:
		rank_time[clampi(st.rank, 0, 4)] += dt
	_track_boss(room, dt)
	_fight(p, room, dt)

# --- Учёт залов ---

func _track_room(p: Player) -> void:
	if game.room != _room_obj:
		_close_room()
		_room_obj = game.room
		_room_index = Run.room_index
		_post_clear = 0
		_post_t = 0.0
		_shop_done = false
		_progress_best = INF
		_progress_t = 0.0
		_stuck_tries = 0
		_target = null
		cur_room = {"index": Run.room_index, "scene": Run.current_room_path().get_file().get_basename(),
			"reward": Run.current_reward(), "t_start": _run_time(), "hp_start": p.health, "hp_max": p.max_health,
			"dmg": 0.0, "hits": 0, "src": {}, "kills0": Run.kills, "glory0": Run.glory, "silver0": Run.silver_earned,
			"fight_time": 0.0, "cleared": false, "assists": 0}
		if _room_obj:
			_room_obj.cleared.connect(func() -> void:
				cur_room.cleared = true
				cur_room.t_clear = _run_time() - float(cur_room.t_start), CONNECT_ONE_SHOT)
			_room_obj.boss_spawned.connect(_on_boss_spawned)

func _close_room() -> void:
	if cur_room.is_empty():
		return
	cur_room.kills = Run.kills - int(cur_room.kills0)
	cur_room.glory = Run.glory - int(cur_room.glory0)
	cur_room.silver = Run.silver_earned - int(cur_room.silver0)
	if game and is_instance_valid(game) and game.player:
		cur_room.hp_end = game.player.health
	if not _boss.is_empty():
		cur_room.boss = _boss.duplicate()
		_boss = {}
	rooms.append(cur_room)
	cur_room = {}

func _run_time() -> float:
	return game.tracker.run_time if game and is_instance_valid(game) and game.tracker else 0.0

func _on_hurt(amount: float) -> void:
	if cur_room.is_empty():
		return
	if amount >= 9000.0:
		amount = clampf(game.player.health + amount, 0.0, game.player.max_health)  # падение: сколько HP было
	cur_room.dmg = float(cur_room.dmg) + amount
	cur_room.hits = int(cur_room.hits) + 1
	var src := game.tracker.last_hit_by if game.tracker else "unknown"
	if game.player.global_position.y < -14.0:
		src = "fall"
	# Ударили — оборачивается: все враги в 6 м становятся «известны»
	if game.room:
		for e in game.room.alive_enemies():
			if is_instance_valid(e) and e.global_position.distance_to(game.player.global_position) < 6.0:
				_known[e.get_instance_id()] = _clock + 2.5
	var d: Dictionary = cur_room.src
	d[src] = float(d.get(src, 0.0)) + amount
	if not _boss.is_empty() and not _boss.has("t_end"):
		_boss.dmg = float(_boss.dmg) + amount

func _on_boss_spawned(boss: Enemy) -> void:
	var id := "jarl" if boss is JarlBoss else ("sven" if boss.has_meta("miniboss") else "boss")
	_boss = {"id": id, "t_spawn": _run_time(), "dmg": 0.0, "hp_at_spawn": game.player.health, "max_hp": boss.max_health,
		"phase_t": {}}
	boss.died.connect(func(_e: Enemy) -> void:
		if not _boss.is_empty():
			_boss.t_end = _run_time()
			_boss.time = float(_boss.t_end) - float(_boss.t_spawn)
			_boss.killed = true, CONNECT_ONE_SHOT)

func _track_boss(_room: Room, _dt: float) -> void:
	if _boss.is_empty() or _boss.has("t_end"):
		return
	for e in game.room.alive_enemies():
		if e is JarlBoss:
			var ph := str((e as JarlBoss).phase)
			var pt: Dictionary = _boss.phase_t
			if not pt.has(ph):
				pt[ph] = _run_time() - float(_boss.t_spawn)
			_boss.hp_left = e.health / maxf(1.0, e.max_health)
		elif e.kind == Enemy.Kind.BOSS and e.has_meta("miniboss"):
			_boss.hp_left = e.health / maxf(1.0, e.max_health)

# --- Экраны выбора ---

## true — открыт экран (бой не ведём).
func _handle_ui(dt: float) -> bool:
	var open := game.trait_pick.visible or game.rune_pick.visible or game.rewards.choice.visible \
		or (game.rewards.shop != null and game.rewards.shop.is_open())
	if not open:
		_ui_wait = 0.0
		return false
	_stop_moving()
	_ui_wait += dt
	if _ui_wait < 0.25:
		return true
	_ui_wait = 0.0
	if game.trait_pick.visible:
		var ch: Array = game.trait_pick._choices
		var i := _pick_trait(ch)
		picks.append("trait:" + str(ch[i].id))
		game.trait_pick._open_time = -10.0
		game.trait_pick.choose(i, true)
	elif game.rune_pick.visible:
		var ch2: Array = game.rune_pick._choices
		var j := _pick_rune(ch2)
		picks.append("rune:" + str(ch2[j].id))
		game.rune_pick._open_time = -10.0
		game.rune_pick.choose(j)
	elif game.rewards.choice.visible:
		var c: ChoicePick = game.rewards.choice
		var k := _pick_choice(c._choices)
		picks.append("choice:" + str(c._choices[k].get("id", "")))
		c.choose(k, true)
	elif game.rewards.shop and game.rewards.shop.is_open():
		game.rewards.shop.close()
	return true

## Руны: случайно, но «Лечение» — когда мало HP, и чуть чаще — урон/здоровье (простая эвристика).
func _pick_rune(ch: Array) -> int:
	var p := game.player
	var best := 0
	var best_w := -1.0
	for i in ch.size():
		var r: RuneDef = ch[i]
		var w := rng.randf()
		if r.id == "heal":
			w += 0.8 if p.health < p.max_health * 0.5 else -0.4
		if r.id in ["axe_damage", "hammer_power", "max_health", "bear_skin"]:
			w += 0.25
		if w > best_w:
			best_w = w
			best = i
	return best

func _pick_trait(ch: Array) -> int:
	return rng.randi() % maxi(1, ch.size())

func _pick_choice(ch: Array) -> int:
	var p := game.player
	var ids: Array = ch.map(func(c: Dictionary) -> String: return str(c.get("id", "")))
	var enabled := func(id: String) -> bool:
		var i := ids.find(id)
		return i >= 0 and bool(ch[i].get("enabled", true))
	var want := ""
	if "heal" in ids:  # отдых
		want = "heal" if p.health < p.max_health * 0.75 or not enabled.call("upgrade") else "upgrade"
	elif "refuse" in ids:  # Локи
		var r := rng.randf()
		if r < 0.35:
			want = "refuse"
		elif r < 0.7 and p.health > p.max_health * 0.6 and enabled.call("blood"):
			want = "blood"
		else:
			want = "cursed" if "cursed" in ids else ("dice" if "dice" in ids else "refuse")
	var idx := ids.find(want)
	if idx < 0 or not bool(ch[idx].get("enabled", true)):
		idx = 0
		for i in ch.size():
			if bool(ch[i].get("enabled", true)):
				idx = i
				break
	return idx

# --- После зачистки: лут, ларёк, дверь ---

func _after_clear(p: Player, room: Room, dt: float) -> void:
	_stop_moving()
	_post_t += dt
	if _post_t < 0.6:
		return
	if Run.current_reward() == "shop" and not _shop_done:
		_shop_done = true
		_shop(p)
		return
	if _post_clear == 0:
		_post_clear = 1
		_loot(p, room)
		_post_t = 0.3
		return
	if game.rewards.doors.is_empty():
		return
	if _post_t < 1.6:  # арки поднимаются из пола, монеты долетают
		return
	_take_door(p)

func _loot(p: Player, room: Room) -> void:
	var holder := p.weapons
	if holder == null:
		return
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Chest and not (n as Chest).opened and is_instance_valid(n):
			(n as Chest).interact(holder)
	# Оружие из сундука/элиты/Локи появляется не сразу — подбираем следующим кадром (через _post_clear)
	get_tree().create_timer(0.7, false).timeout.connect(func() -> void: _take_weapons(p))

func _take_weapons(p: Player) -> void:
	if not active or p == null or not is_instance_valid(p) or p.is_dead:
		return
	var holder := p.weapons
	var taken := {}
	for n in get_tree().get_nodes_in_group("interactable"):
		if not n is WeaponPickup or not is_instance_valid(n):
			continue
		var wp := n as WeaponPickup
		if wp.item == null:
			continue
		var group := wp.choice_group
		if group != "" and taken.has(group):
			continue
		var want := false
		if wp.item.is_ranged():
			want = holder.ranged == null or wp.item.level > holder.ranged.level or rng.randf() < 0.3
		else:
			want = holder.melee == null or (holder.melee.def.id == "axe" and rng.randf() < 0.6) or wp.item.level > holder.melee.level
		if want:
			picks.append("weapon:" + wp.item.def.id)
			wp._ready_to_take = true
			wp.interact(holder)
			if group != "":
				taken[group] = true

## Ларёк: шаурма при малом HP, потом руна, потом обслуживание молота / заточка — пока хватает серебра.
func _shop(p: Player) -> void:
	for id in ["shawarma", "rune", "mjolnir_service", "sharpen", "rune"]:
		var it := Shop.get_item(id)
		if it == null:
			continue
		if id == "shawarma" and p.health > p.max_health * 0.7:
			continue
		if not Shop.can_buy(game, it):
			continue
		var arg := ""
		if id == "rune":
			var rs := Run.random_rune_choices(3)
			if rs.is_empty():
				continue
			arg = rs[_pick_rune(rs)].id
		var res := Shop.buy(game, it, arg)
		if res.get("ok", false):
			picks.append("shop:" + id + (":" + arg if arg != "" else ""))

## Дверь: ларёк — если есть серебро, отдых — если мало HP, иначе случайно (боевые чуть чаще).
func _take_door(p: Player) -> void:
	var doors: Array[RewardDoor] = game.rewards.doors
	var best: RewardDoor = null
	var best_w := -INF
	for d in doors:
		if not is_instance_valid(d) or d.used:
			continue
		var w := rng.randf()
		match d.reward_id:
			"shop":
				w += 0.8 if Run.silver >= 60 else -0.3
			"rest":
				w += 0.9 if p.health < p.max_health * 0.5 else -0.2
			"combat", "freya":
				w += 0.2
		if w > best_w:
			best_w = w
			best = d
	if best == null:
		return
	picks.append("door:" + best.reward_id)
	p.global_position = best.trigger_position()
	p.velocity = Vector3(0, 0, -2)
	_post_t = -5.0  # ждём перехода

# --- Бой ---

func _stop_moving() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "attack"]:
		hold(a, false)

func _fight(p: Player, room: Room, dt: float) -> void:
	_think_t -= dt
	_attack_t -= dt
	_throw_t -= dt
	_strafe_t -= dt
	_jitter_t -= dt
	_react_t -= dt
	_clock += dt
	var enemies := room.alive_enemies().filter(func(e: Enemy) -> bool: return is_instance_valid(e) and not e.is_dead)
	if enemies.is_empty():
		_stop_moving()
		return
	if _think_t <= 0.0 or _target == null or not is_instance_valid(_target) or _target.is_dead:
		_think_t = float(skill.think)
		_target = _choose_target(p, enemies)
		_dodge_check(p, enemies)
	if _target == null:
		return
	var tpos := _target.global_position + Vector3(0, 1.0 * _target.model_scale, 0)
	var to := tpos - p.get_aim_origin()
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var dy := _target.global_position.y - p.global_position.y
	_aim(p, to, dt)
	_hammer(p, dist, dy, dt)
	var holder := p.weapons
	var ranged_ok := holder != null and holder.ranged != null and (holder.ranged.mag + holder.ranged.reserve) > 0
	var use_ranged := ranged_ok and (dist > 7.0 or dy > 2.5) and not _target.kind == Enemy.Kind.BOSS
	if holder:
		if use_ranged and not holder.is_ranged_active() and not holder.is_switching():
			holder.switch_to(WeaponHolder.RANGED)
		elif not use_ranged and holder.is_ranged_active() and not holder.is_switching() and dist < 5.0:
			holder.switch_to(WeaponHolder.MELEE)
	var reach := 2.3 * (holder.melee.def.reach if holder and holder.melee and holder.melee.def else 1.0)
	_move(p, flat, dist, dy, reach, dt)
	if holder and holder.is_ranged_active():
		_shoot(p, holder, dist)
	elif dist < reach + 0.4 and absf(dy) < 2.0 and _react_t <= 0.0 and _aimed(p, 0.85):
		_melee(p, dt)
	else:
		hold("attack", false)
	_slam_logic(p, enemies, dist, dy, dt)

func _aimed(p: Player, min_dot: float) -> bool:
	var to := _target.global_position + Vector3(0, 1.0 * _target.model_scale, 0) - p.get_aim_origin()
	return p.get_aim_forward().dot(to.normalized()) > min_dot

## Осведомлённость: видит в конусе взгляда (с прямой видимостью), слышит вплотную, помнит 2.5 с.
func _update_known(p: Player, enemies: Array) -> Array:
	var out: Array = []
	var fwd := p.get_aim_forward()
	fwd.y = 0
	fwd = fwd.normalized()
	var cos_v := cos(deg_to_rad(float(skill.view_deg)))
	for e: Enemy in enemies:
		var d := e.global_position - p.global_position
		var flat := Vector3(d.x, 0, d.z)
		var id := e.get_instance_id()
		var sees := flat.length() < float(skill.hear_dist) or e.kind == Enemy.Kind.BOSS
		if not sees and flat.length() > 0.01 and fwd.dot(flat.normalized()) > cos_v and _has_los(p, e):
			sees = true
		if sees:
			_known[id] = _clock + 2.5
		if float(_known.get(id, -1.0)) > _clock:
			out.append(e)
	return out

func _choose_target(p: Player, all_enemies: Array) -> Enemy:
	var enemies := _update_known(p, all_enemies)
	_searching = enemies.is_empty()
	if _searching:
		enemies = all_enemies  # никого не видно — оглядывается в сторону ближайшего (как на звук)
	var best: Enemy = null
	var best_s := INF
	for e: Enemy in enemies:
		var d := e.global_position - p.global_position
		var s := Vector2(d.x, d.z).length() + absf(d.y) * 2.5
		match e.kind:
			Enemy.Kind.SHAMAN:
				s -= 4.0
			Enemy.Kind.BLOATED:
				s -= 1.5
			Enemy.Kind.BOSS:
				s += 3.0 if enemies.size() > 4 else 0.0
		if e == _target:
			s -= 1.5  # не дёргаться между целями
		if e.state == Enemy.State.SPAWNING:
			s += 2.0
		if s < best_s:
			best_s = s
			best = e
	if best != _target:
		_react_t = float(skill.reaction)
		_progress_best = INF
		_progress_t = 0.0
		_stuck_tries = 0
	return best

func _aim(p: Player, to: Vector3, dt: float) -> void:
	if _jitter_t <= 0.0:
		_jitter_t = 0.3
		var j := deg_to_rad(float(skill.aim_jitter_deg))
		_jitter = Vector2(rng.randf_range(-j, j) * 0.5, rng.randf_range(-j, j))
	var flat := Vector2(to.x, to.z).length()
	var want_yaw := atan2(-to.x, -to.z) + _jitter.y
	var want_pitch := clampf(atan2(to.y, maxf(flat, 0.01)) + _jitter.x, deg_to_rad(-80), deg_to_rad(80))
	var cur := p.rotation_target
	var max_step := float(skill.search_turn if _searching else skill.turn_speed) * dt
	var dyaw := wrapf(want_yaw - cur.y, -PI, PI)
	cur.y += clampf(dyaw, -max_step, max_step)
	cur.x += clampf(want_pitch - cur.x, -max_step, max_step)
	p.rotation_target = cur

## Движение: подойти на дистанцию удара, потом кружить (стрейф); застрял — прыжок, рывок вбок, потом «подсадка».
func _move(p: Player, flat: Vector3, dist: float, dy: float, reach: float, dt: float) -> void:
	var want_close := dist > reach * 0.85
	var ranged := p.weapons and p.weapons.is_ranged_active()
	if ranged:
		want_close = dist > 14.0
	# Раздутый с фитилём рядом — отходим
	var back := false
	if _target.kind == Enemy.Kind.BLOATED and _target.state == Enemy.State.WINDUP and dist < 4.5:
		back = true
		want_close = false
	var forward_ok := _floor_ahead(p, flat.normalized())
	if want_close and not forward_ok and dy > -6.0:
		want_close = false  # обрыв — не прыгаем в пропасть, бьём молотом/ренжем
	hold("move_forward", want_close)
	if _strafe_t <= 0.0:
		_strafe_t = rng.randf_range(0.6, 1.6)
		_strafe = [-1.0, 0.0, 1.0][rng.randi() % 3]
	var strafe_on := not want_close or dist < reach * 1.5
	if strafe_on and _strafe != 0.0 and not _floor_ahead(p, p.global_transform.basis.x * _strafe):
		_strafe = -_strafe  # край сбоку — в другую сторону
		strafe_on = _floor_ahead(p, p.global_transform.basis.x * _strafe)
	if back and not _floor_ahead(p, p.global_transform.basis.z):
		back = false
	hold("move_back", back or (not want_close and dist < reach * 0.45 and _floor_ahead(p, p.global_transform.basis.z)))
	hold("move_left", strafe_on and _strafe < 0.0)
	hold("move_right", strafe_on and _strafe > 0.0)
	# Сближение рывком
	if want_close and dist > 9.0 and p.dash_charges >= 2 and p.is_on_floor() and rng.randf() < 0.02:
		tap("dash")
		stats.dashes += 1
	# Цель выше: прыжок (+ двойной), залезание на уступ — сам игрок
	if want_close and dy > 1.2 and dist < 6.0 and p.is_on_floor() and rng.randf() < 0.08:
		tap("jump", 2)
	_check_stuck(p, dist, want_close, dt)

func _check_stuck(p: Player, dist: float, want_close: bool, dt: float) -> void:
	if not want_close:
		_progress_t = 0.0
		_progress_best = minf(_progress_best, dist)
		return
	if dist < _progress_best - 0.5:
		_progress_best = dist
		_progress_t = 0.0
		_stuck_tries = 0
		return
	_progress_t += dt
	if _progress_t > 1.5:
		_progress_t = 0.0
		_stuck_tries += 1
		if _stuck_tries <= 2:
			tap("jump", 2)
			get_tree().create_timer(0.3, false).timeout.connect(func() -> void: tap("jump", 2))
		elif _stuck_tries <= 4:
			_strafe = -_strafe if _strafe != 0.0 else 1.0
			if p.dash_charges > 0:
				tap("dash")
				stats.dashes += 1
		else:
			_assist(p)

## «Подсадка»: бот не умеет искать путь — ставим Тора рядом с целью (на её пол). Считается в отчёте.
func _assist(p: Player) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dir := p.global_position - _target.global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	var to := _target.global_position + dir * 2.0 + Vector3(0, 0.3, 0)
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_target.global_position + Vector3(0, 1.0, 0), to + Vector3(0, 0.7, 0), 1)
	if not space.intersect_ray(q).is_empty():
		to = _target.global_position + Vector3(0, 2.2 * _target.model_scale + 0.3, 0)
	p.global_position = to
	p.velocity = Vector3.ZERO
	stats.assists += 1
	cur_room.assists = int(cur_room.get("assists", 0)) + 1
	_stuck_tries = 0
	_progress_best = INF

func _floor_ahead(p: Player, dir: Vector3) -> bool:
	if dir.length() < 0.1:
		return true
	var space := p.get_world_3d().direct_space_state
	var off := dir if dir.length() > 1.4 else dir.normalized() * 1.4
	var from := p.global_position + off + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -9.0, 0), 1)
	return not space.intersect_ray(q).is_empty()

func _melee(p: Player, _dt: float) -> void:
	var axe := p.axe
	if axe == null or not axe.active:
		return
	if _attack_t > 0.0:
		return
	var tough := _target.kind in [Enemy.Kind.BOSS, Enemy.Kind.SHIELD] or _target.has_meta("elite")
	if tough and rng.randf() < float(skill.heavy) and not axe.is_busy():
		tap("attack", int(ceil(axe.heavy_hold_time * 60.0)) + 3)
		stats.heavy += 1
		_attack_t = 0.7
	else:
		tap("attack", 1)
		_attack_t = rng.randf_range(0.12, 0.24)

func _shoot(p: Player, holder: WeaponHolder, dist: float) -> void:
	var it := holder.ranged
	if it == null:
		return
	if not _aimed(p, 0.97) or _react_t > 0.0 or dist > it.def.max_range:
		hold("attack", false)
		return
	if it.def.automatic:
		hold("attack", true)
	elif _attack_t <= 0.0:
		tap("attack", 1)
		_attack_t = maxf(it.def.fire_interval, 0.12) + rng.randf_range(0.02, 0.12)
		stats.shots += 1

## Мьёльнир: бросок по дальним/высоким/опасным целям, возврат, идеальный хват (ПКМ сразу после поимки).
func _hammer(p: Player, dist: float, dy: float, dt: float) -> void:
	var h := p.mjolnir
	if h == null:
		return
	if h.holding:
		_hold_throw_t -= dt
		hold("throw", _hold_throw_t > 0.0)
		return
	if h.in_hand:
		_hammer_out_t = 0.0
		if not _aimed(p, 0.95) or _react_t > 0.0:
			return
		# Идеальный хват: сразу после поимки — следующий бросок усилен
		if h.perfect_window_left() > 0.02 and dist < 22.0:
			if rng.randf() < float(skill.perfect) / 2.0:  # решение за кадр окна (~4–5 кадров)
				_press_throw(h)
			return
		if _throw_t > 0.0:
			return
		var want := false
		if dist > 4.5 and dist < 24.0:
			want = rng.randf() < 0.5
		if dy > 2.0 or _target.kind in [Enemy.Kind.SHAMAN, Enemy.Kind.BLOATED, Enemy.Kind.THROWER, Enemy.Kind.MERC]:
			want = want or rng.randf() < 0.6
		if _target is JarlBoss and (_target as JarlBoss).is_perched():
			want = true
		if dist <= 4.5 and rng.randf() < 0.12:
			want = true
		_throw_t = rng.randf_range(0.6, 1.4)
		if want and _has_los(p, _target):
			_press_throw(h)
	else:
		_hammer_out_t += dt
		var proj := h.projectile
		if proj and is_instance_valid(proj) and proj.state != MjolnirProjectile.State.RETURN:
			var stuck := proj.state in [MjolnirProjectile.State.STUCK, MjolnirProjectile.State.HOVER]
			if (stuck and _hammer_out_t > 0.5) or _hammer_out_t > rng.randf_range(1.1, 2.2):
				tap("throw", 1)

func _press_throw(h: MjolnirHand) -> void:
	if bool(h.trait_modify(&"hold_throw", false)):
		_hold_throw_t = rng.randf_range(0.25, 1.0)
		hold("throw", true)
	else:
		tap("throw", 1)
	stats.throws += 1

func _has_los(p: Player, e: Enemy) -> bool:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.get_aim_origin(), e.global_position + Vector3(0, 1.0, 0), 1)
	return space.intersect_ray(q).is_empty()

## Удар-приземление: в воздухе над целью — бьём; в толпе — прыжок, второй прыжок, удар.
func _slam_logic(p: Player, enemies: Array, dist: float, dy: float, dt: float) -> void:
	var on_floor := p.is_on_floor()
	if not on_floor and not p.is_slamming and dist < 4.5 and dy < -1.6:
		tap("slam", 1)
		_jump_plan = 0
		return
	match _jump_plan:
		0:
			if on_floor and _think_t >= float(skill.think) - dt * 0.5:  # раз за решение
				var near := 0
				for e: Enemy in enemies:
					if e.global_position.distance_to(p.global_position) < 5.0:
						near += 1
				if near >= 3 and rng.randf() < float(skill.slam_jump) * 0.25:
					tap("jump", 2)
					_jump_plan = 1
					_jump_t = 0.0
		1:
			_jump_t += dt
			if _jump_t > 0.32:
				tap("jump", 2)
				_jump_plan = 2
				_jump_t = 0.0
		2:
			_jump_t += dt
			if not on_floor and p.velocity.y < 1.0 and not p.is_slamming:
				tap("slam", 1)
				_jump_plan = 0
			elif on_floor and _jump_t > 0.3 or _jump_t > 2.0:
				_jump_plan = 0

## Увороты: замах рядом, таран с полосой, фитиль Раздутого, лазер наёмника, прыжок Ярла с волной.
func _dodge_check(p: Player, enemies: Array) -> void:
	for e: Enemy in enemies:
		var d := e.global_position - p.global_position
		var dist := Vector2(d.x, d.z).length()
		var key := 0
		var kind := ""
		if e is BossEnemy:
			var b := e as BossEnemy
			var strip: Variant = b.get("_strip")
			if b.act != 0 and strip != null and is_instance_valid(strip) and (strip as Node3D).visible and dist < 24.0:
				key = b.get_instance_id() * 31 + b.act
				kind = "charge"
			elif b is JarlBoss and b.act == JarlBoss.Act.SLAM_LEAP and b.act_time > (b as JarlBoss).slam_leap_time - 0.4:
				key = b.get_instance_id() * 31 + 7
				kind = "jump"
		if key == 0 and e.state == Enemy.State.WINDUP:
			var r := e.attack_range + 1.2
			if e.kind == Enemy.Kind.BLOATED or e._doing_slam:
				r = e.boss_slam_radius + 0.8
			if e.kind == Enemy.Kind.MERC:
				r = 30.0
			if dist < r:
				key = e.get_instance_id() * 31 + int(e._attack_count)
				kind = "away"
		if key == 0 or _dodged.has(key):
			continue
		_dodged[key] = true
		if _dodged.size() > 200:
			_dodged.clear()
		if rng.randf() >= float(skill.dodge):
			continue
		stats.dodges += 1
		match kind:
			"jump":
				tap("jump", 2)
			_:
				if p.dash_charges <= 0:
					tap("jump", 2)
					continue
				# Рывок вбок (перпендикулярно направлению на врага) — относительно взгляда игрока: влево/вправо
				var side := "move_left" if rng.randf() < 0.5 else "move_right"
				if kind == "away" and e.kind == Enemy.Kind.BLOATED:
					side = "move_back"
				var dirs := {"move_left": -p.global_transform.basis.x, "move_right": p.global_transform.basis.x, "move_back": p.global_transform.basis.z}
				if not _floor_ahead(p, dirs[side] * 3.0):
					side = "move_right" if side == "move_left" else "move_left"
					if not _floor_ahead(p, dirs[side] * 3.0):
						tap("jump", 2)  # с обеих сторон обрыв — подпрыгнуть
						continue
				hold("move_forward", false)
				Input.action_press(side)
				_held[side] = 6
				tap("dash", 2)
				stats.dashes += 1
