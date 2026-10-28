extends Resource
class_name MinibossDef
## Мини-босс (GDD 14.1): враг (сцена base_kind) с переопределёнными характеристиками и поведением босса
## (Kind.BOSS: удар по площади с телеграфом, не сбивается). Появляется последней волной зала из
## Run.miniboss_rooms; за победу — выбор трейта Мьёльнира (scenes/game.gd).
## Толстый Свен — base_kind "sven" (enemies/bosses/sven.gd: таран на бочке, лужи браги, взрыв),
## его арена — rooms/sven_arena.tscn (маркер MinibossSpot — где он появляется).

@export var id: String = "fat_sven"
## Имя на полосе HP (HUD.show_boss)
@export var title: String = "ТОЛСТЫЙ СВЕН"
## Ключ ENEMY_SCENES в room.gd: на какой сцене строится
@export var base_kind: String = "grunt"
@export_group("Характеристики")
## 25 У (GDD 14.1)
@export var max_health: float = 550.0
@export var move_speed: float = 4.2
@export_range(0.0, 1.0) var knock_resist: float = 0.6
## П4: броня от спама мили — урон обычных ударов мили (melee / melee_finisher) × это число
@export_range(0.05, 1.0, 0.05) var melee_resist: float = 0.5
## П4, «старое» по F6 (FeelSwitch boss_armor): HP до брони; 0 — как max_health
@export var legacy_max_health: float = 0.0
@export var attack_range: float = 2.6
@export var attack_damage: float = 18.0
@export var windup_time: float = 0.75
@export var recover_time: float = 0.9
@export var attack_cooldown: float = 1.0
@export var slam_radius: float = 4.5
@export var slam_damage: float = 20.0
@export var slam_windup: float = 0.9
## Удар по площади издалека — реже, чем у финального босса (иначе Свен почти не подходит)
@export var far_slam_chance: float = 0.004
## Слава за победу (GDD 15.2: мини-босс — 50)
@export var glory: int = 50
@export_group("Вид")
@export var model_scale: float = 1.5
## Дополнительная «толщина» по X/Z
@export var fatness: float = 1.35
@export var outfit: String = "outfits/Male_Peasant.gltf"
@export var hair: String = "hair/Hair_Beard.gltf"
@export var skin_tint: Color = Color(0.55, 0.7, 0.6)
@export var cloth_tint: Color = Color(0.7, 0.5, 0.32)
@export var eye_glow: Color = Color(1.0, 0.7, 0.2)
@export var weapon: String = "club"
@export_group("Свита")
## Сколько обычных врагов выходит вместе с ним
@export var escort_count: int = 2
@export var escort_kind: String = "grunt"
## Свита — отряд (SquadDef, enemies/squads/<id>.tres) вместо escort_count × escort_kind (Хёвдинг: дружина)
@export var escort_squad: String = ""
@export var escort_squad_override: Dictionary = {}
@export_group("Арена")
## Своя арена (ручная сцена с маркером MinibossSpot): Run подставляет её в зал мини-босса. Пусто — обычный зал.
@export var arena: String = ""
@export_group("Реплики")
## Пулы data/dialogues (пузырь в углу): при появлении и при смерти; пусто — не говорит
@export var intro_pool: String = "sven.intro"
@export var death_pool: String = "sven.death"

## Добавить залу волну с мини-боссом (и свитой). hud — для подсказки при появлении (может быть null).
func add_to_room(room: Room, hud: Node = null) -> void:
	var spots := _spawn_spots(room)
	if spots.is_empty():
		return
	var markers: Array[Node3D] = []
	var m := Marker3D.new()
	m.name = "Miniboss"
	m.set_meta("kind", base_kind)
	m.set_meta("setup", func(e: Enemy) -> void: apply(e, hud))
	room.spawns.add_child(m)
	m.global_position = spots[0]
	markers.append(m)
	if escort_squad != "" and SquadDef.find(escort_squad):
		var sm := Marker3D.new()
		sm.name = "MinibossSquad"
		sm.set_meta("kind", "squad")
		sm.set_meta("squad", escort_squad)
		if not escort_squad_override.is_empty():
			sm.set_meta("squad_override", escort_squad_override)
		room.spawns.add_child(sm)
		sm.global_position = spots[1] if spots.size() > 1 else spots[0]
		markers.append(sm)
		room.add_wave(markers)
		return
	for i in mini(escort_count, spots.size() - 1):
		var em := Marker3D.new()
		em.set_meta("kind", escort_kind)
		room.spawns.add_child(em)
		em.global_position = spots[i + 1]
		markers.append(em)
	room.add_wave(markers)

## Точки появления: маркеры зала, ближайший к их центру — мини-боссу, остальные — свите.
func _spawn_spots(room: Room) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	# Своя арена: точка мини-босса задана маркером MinibossSpot (не волна)
	var spot := room.get_node_or_null("MinibossSpot") as Node3D
	# Сначала маркеры грунтов (они на полу; метатели бывают на возвышениях)
	for want in ["grunt", ""]:
		for c in room.spawns.get_children():
			var k := str(c.get_meta("kind", "grunt"))
			if c is Node3D and k != "boss" and (want == "" or k == want):
				pts.append((c as Node3D).global_position)
		if not pts.is_empty():
			break
	if pts.is_empty():
		return pts
	var center := Vector3.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(center) < b.distance_to(center))
	if spot:
		pts.insert(0, spot.global_position)
	return pts

## HP мини-босса: max_health; «старое» по F6 (FeelSwitch boss_armor) — legacy_max_health, если задан
func health() -> float:
	return legacy_max_health if legacy_max_health > 0.0 and FeelSwitch.is_old(&"boss_armor") else max_health

## Переопределить характеристики врага (до его _ready).
func apply(e: Enemy, hud: Node = null) -> void:
	Perf.mark("miniboss_spawn")
	e.kind = Enemy.Kind.BOSS
	e.set_meta("miniboss", true)
	e.set_meta("boss_title", title)
	e.max_health = health()
	e.move_speed = move_speed
	e.knock_resist = knock_resist
	e.melee_resist = melee_resist
	e.attack_range = attack_range
	e.attack_damage = attack_damage
	e.windup_time = windup_time
	e.recover_time = recover_time
	e.attack_cooldown = attack_cooldown
	e.boss_slam_radius = slam_radius
	e.boss_slam_damage = slam_damage
	e.boss_slam_windup = slam_windup
	e.boss_far_slam_chance = far_slam_chance
	e.wall_splat_speed = 99.0
	e.model_scale = model_scale
	e.randomize_look = false
	e.model_outfit = outfit
	e.model_hair = hair
	e.skin_tint = skin_tint
	e.cloth_tint = cloth_tint
	e.eye_glow = eye_glow
	e.hand_weapon = weapon
	e.weapon_pool = PackedStringArray()
	e.shield_chance = 0.0
	# Коллайдер под размер (форма из сцены общая для всех грунтов — делаем свою)
	var col := e.get_node_or_null("Collider") as CollisionShape3D
	if col and col.shape is CapsuleShape3D:
		var cap := (col.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		cap.radius *= model_scale * fatness * 0.85
		cap.height *= model_scale
		col.shape = cap
		col.position.y = cap.height * 0.5
	e.ready.connect(func() -> void:
		if e._visual:
			e._visual.scale = Vector3(fatness, 1.0, fatness) * model_scale, CONNECT_ONE_SHOT)
	var dp := death_pool
	e.died.connect(func(_e: Enemy) -> void:
		Run.add_glory(glory)
		if dp != "" and Dialogue.has_pool(dp):
			Dialogue.bark_pool(dp)
		Odin.say("miniboss_death"), CONNECT_ONE_SHOT)
	Odin.say("miniboss_start")
	if intro_pool != "" and Dialogue.has_pool(intro_pool):
		Dialogue.bark_pool(intro_pool)
	if hud and hud.has_method("toast"):
		hud.call("toast", title + "!")
