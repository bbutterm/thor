extends RefCounted
class_name GenEnemies
## Генератор: сцены врагов (enemies/*.tscn) по EnemyDef и MODEL_LOOKS (вид и анимации).
## Компонент SceneBuilder (этап 4 рефакторинга): числа и состояние — поля SceneBuilder (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — генератор.enemies; нужные снаружи функции есть и на SceneBuilder.

## Вид врагов: персонажи Quaternius (Universal Base Characters + одежда) и анимации UAL.
## Чтобы поменять модели — меняй здесь или прямо в сценах enemies/*.tscn (группы «Модель» и «Анимации»).
const MODEL_LOOKS := {
	"grunt": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "",
		"skin_tint": Color(0.45, 0.58, 0.66), "cloth_tint": Color(0.55, 0.55, 0.52), "eye_glow": Color(0.4, 0.85, 1.0, 1.0),
		"hand_weapon": "q_axe", "randomize_look": true, "shield_chance": 0.3,
		"weapon_pool": ["q_axe", "q_sword"],
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Zombie_Walk_Fwd_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Zombie_Scratch", "anim_attack_hit_at": 0.45, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
		# Партия 12 (роли): обычный, синеватая броня
		"role_cloth": Color(0.6, 0.85, 1.45),
	},
	"thrower": {
		"model_body": "base/Superhero_Female_FullBody.gltf", "model_outfit": "outfits/Female_Ranger.gltf", "model_hair": "",
		"skin_tint": Color(0.5, 0.58, 0.66), "cloth_tint": Color(0.5, 0.42, 0.68), "eye_glow": Color(0.75, 0.4, 1.0, 1.0),
		"hand_weapon": "staff",
		"anim_spawn": "LayToIdle", "anim_idle": "Spell_Simple_Idle_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Spell_Simple_Shoot", "anim_attack_hit_at": 0.6, "anim_hit": "Hit_Head", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
		# Партия 12 (роли): красный капюшон
		"role_cloth": Color(1.45, 0.3, 0.22), "role_parts": ["parts/Female_Ranger_Head_Hood.gltf"], "role_part_tints": [Color(1.6, 0.22, 0.16)],
	},
	"boss": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "hair/Hair_Beard.gltf",
		"skin_tint": Color(0.5, 0.72, 1.0), "cloth_tint": Color(0.55, 0.7, 1.0), "eye_glow": Color(0.5, 0.95, 1.0, 1.0),
		"hand_weapon": "club",
		"anim_spawn": "LayToIdle", "anim_idle": "Sword_Idle", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Sword_Regular_C", "anim_attack_hit_at": 0.35, "anim_slam": "Sword_Regular_C", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Ярл: огромный синеватый драугр с бородой, рука-дубина в правой руке (бросает её бумерангом)
	"jarl": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "hair/Hair_Beard.gltf",
		"skin_tint": Color(0.5, 0.72, 1.0), "cloth_tint": Color(0.55, 0.7, 1.0), "eye_glow": Color(0.5, 0.95, 1.0, 1.0),
		"hand_weapon": "club",
		"anim_spawn": "LayToIdle", "anim_idle": "Sword_Idle", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Sword_Regular_C", "anim_attack_hit_at": 0.35, "anim_slam": "Sword_Regular_C", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Толстый Свен: раздутый драугр с бородой, без оружия (бочка — своя, enemies/bosses/sven.gd)
	"sven": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "hair/Hair_Beard.gltf",
		"skin_tint": Color(0.55, 0.7, 0.6), "cloth_tint": Color(0.7, 0.5, 0.32), "eye_glow": Color(1.0, 0.7, 0.2, 1.0),
		"hand_weapon": "", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Zombie_Walk_Fwd_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Punch_Cross", "anim_attack_hit_at": 0.45, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Хёвдинг: драугр-вожак в красном, с бородой и топором (знамя и рог — свои, enemies/bosses/hovding.gd)
	"hovding": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "hair/Hair_Beard.gltf",
		"skin_tint": Color(0.5, 0.66, 0.72), "cloth_tint": Color(0.62, 0.22, 0.18), "eye_glow": Color(1.0, 0.8, 0.3, 1.0),
		"hand_weapon": "q_axe", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Sword_Idle", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Sword_Regular_C", "anim_attack_hit_at": 0.35, "anim_slam": "Sword_Regular_C", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Вёльва: колдунья в лиловом с посохом (телепорт, огненные круги — enemies/bosses/volva.gd)
	"volva": {
		"model_body": "base/Superhero_Female_FullBody.gltf", "model_outfit": "outfits/Female_Ranger.gltf", "model_hair": "hair/Hair_Long.gltf",
		"skin_tint": Color(0.62, 0.68, 0.78), "cloth_tint": Color(0.38, 0.22, 0.5), "eye_glow": Color(0.75, 0.4, 1.0, 1.0),
		"hand_weapon": "staff", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Sword_Idle", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Sword_Regular_C", "anim_attack_hit_at": 0.35, "anim_slam": "Sword_Regular_C", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Берсерк-ульфхеднар: серый «волк» с топором (серии рывков — enemies/bosses/berserker.gd)
	"berserker": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "hair/Hair_Long.gltf",
		"skin_tint": Color(0.6, 0.62, 0.66), "cloth_tint": Color(0.42, 0.4, 0.38), "eye_glow": Color(1.0, 0.25, 0.15, 1.0),
		"hand_weapon": "q_axe", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Sword_Idle", "anim_move": "Jog_Fwd_Loop", "anim_move_ref_speed": 3.0,
		"anim_attack": "Sword_Regular_C", "anim_attack_hit_at": 0.35, "anim_slam": "Sword_Regular_C", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Корм — облегчённый: одно тело + один комплект одежды, без оружия, волос и случайной сборки
	"fodder": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "",
		"skin_tint": Color(0.5, 0.6, 0.62), "cloth_tint": Color(0.42, 0.4, 0.36), "eye_glow": Color(0.35, 0.75, 1.0, 1.0),
		"hand_weapon": "", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Zombie_Walk_Fwd_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Zombie_Scratch", "anim_attack_hit_at": 0.45, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
		# Партия 12 (роли): мелкий, приземистый, серый
		"role_skin": Color(0.78, 0.78, 0.76), "role_shape": Vector3(0.9, 0.82, 0.9),
	},
	# Раздутый: толстый (bloat_fatness), желчно-зелёный, раздувается к взрыву
	"bloated": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "",
		"skin_tint": Color(0.78, 0.9, 0.5), "cloth_tint": Color(0.5, 0.42, 0.3), "eye_glow": Color(1.0, 0.55, 0.1, 1.0),
		"hand_weapon": "", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Jog_Fwd_Loop", "anim_move_ref_speed": 3.2,
		"anim_attack": "Zombie_Scratch", "anim_attack_hit_at": 0.9, "anim_slam": "Zombie_Scratch", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Щитоносец: круглый щит в левой руке всегда, меч в правой
	"shieldbearer": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "",
		"skin_tint": Color(0.45, 0.55, 0.66), "cloth_tint": Color(0.5, 0.52, 0.58), "eye_glow": Color(0.4, 0.85, 1.0, 1.0),
		"hand_weapon": "q_sword", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Idle_Shield_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Shield_OneShot", "anim_attack_hit_at": 0.4, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
		# Партия 12 (роли): широкий, огромный щит, ржаво-жёлтый
		"role_cloth": Color(1.5, 1.0, 0.32), "role_shape": Vector3(1.25, 1.02, 1.2), "role_shield_scale": 2.1,
	},
	# Шаман: зелёное свечение, посох
	"shaman": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "hair/Hair_Long.gltf",
		"skin_tint": Color(0.55, 0.68, 0.58), "cloth_tint": Color(0.32, 0.5, 0.36), "eye_glow": Color(0.4, 1.0, 0.5, 1.0),
		"hand_weapon": "q_staff", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Spell_Simple_Idle_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Spell_Simple_Shoot", "anim_attack_hit_at": 0.6, "anim_hit": "Hit_Head", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
		# Партия 12 (роли): высокий, посох и рога, зелёное свечение
		"role_cloth": Color(0.45, 1.3, 0.5), "role_shape": Vector3(0.95, 1.16, 0.95), "role_horns": true,
	},
	# Наёмник Локи — смертный (обычная кожа, без свечения глаз), с автоматом
	"merc": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "hair/Hair_Buzzed.gltf",
		"skin_tint": Color(1.0, 0.9, 0.82), "cloth_tint": Color(0.3, 0.3, 0.32), "eye_glow": Color(0, 0, 0, 0),
		"hand_weapon": "gun_smg", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Pistol_Idle_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Pistol_Aim_Neutral", "anim_attack_hit_at": 0.95, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
		# Партия 12 (роли): зелёно-золотой (наплечники — золото)
		"role_cloth": Color(0.45, 1.1, 0.4), "role_parts": ["parts/Male_Ranger_Acc_Pauldron.gltf"], "role_part_tints": [Color(1.7, 1.3, 0.35)],
	},
}

var gen: SceneBuilder

func _init(owner_node: SceneBuilder) -> void:
	gen = owner_node

func build_enemies() -> void:
	print("Враги…")
	var defs := {
		"grunt": {"kind": Enemy.Kind.GRUNT, "hp": 60.0, "speed": 4.4, "range": 2.0, "dmg": 12.0, "windup": 0.6, "recover": 0.7, "cd": 0.9, "color": Color(0.36, 0.48, 0.38), "scale": 1.0, "resist": 0.0},
		"thrower": {"kind": Enemy.Kind.THROWER, "hp": 40.0, "speed": 3.8, "range": 12.0, "dmg": 10.0, "windup": 0.55, "recover": 0.4, "cd": 2.2, "color": Color(0.42, 0.33, 0.55), "scale": 1.0, "resist": 0.0},
		"boss": {"kind": Enemy.Kind.BOSS, "hp": 480.0, "speed": 3.6, "range": 3.6, "dmg": 20.0, "windup": 0.8, "recover": 0.9, "cd": 1.1, "color": Color(0.5, 0.26, 0.2), "scale": 2.1, "resist": 0.75},
		# Мидгард (GDD 12.1). HP/скорость/урон перекрывает EnemyDef (enemies/defs) при спавне в зале.
		"fodder": {"kind": Enemy.Kind.FODDER, "hp": 7.7, "speed": 3.5, "range": 1.8, "dmg": 5.0, "windup": 0.55, "recover": 0.6, "cd": 1.1, "color": Color(0.4, 0.5, 0.45), "scale": 0.95, "resist": 0.0,
			"extra": {"max_debris": 10}},
		"bloated": {"kind": Enemy.Kind.BLOATED, "hp": 22.0, "speed": 5.0, "range": 2.4, "dmg": 44.0, "windup": 0.7, "recover": 0.5, "cd": 0.5, "color": Color(0.6, 0.65, 0.35), "scale": 1.05, "resist": 0.2,
			"extra": {"boss_slam_radius": 3.0, "boss_slam_windup": 0.7, "bloat_trigger_range": 2.4}},
		"shieldbearer": {"kind": Enemy.Kind.SHIELD, "hp": 88.0, "speed": 3.0, "range": 2.0, "dmg": 15.0, "windup": 0.75, "recover": 0.8, "cd": 1.4, "color": Color(0.4, 0.45, 0.55), "scale": 1.08, "resist": 0.6,
			"extra": {"turn_speed": 2.6, "lunge_speed": 9.0}},
		"shaman": {"kind": Enemy.Kind.SHAMAN, "hp": 44.0, "speed": 3.0, "range": 0.0, "dmg": 15.0, "windup": 1.0, "recover": 0.6, "cd": 1.0, "color": Color(0.3, 0.5, 0.35), "scale": 1.0, "resist": 0.1,
			"extra": {}},
		"merc": {"kind": Enemy.Kind.MERC, "hp": 44.0, "speed": 4.0, "range": 14.0, "dmg": 15.0, "windup": 0.8, "recover": 0.9, "cd": 2.4, "color": Color(0.35, 0.3, 0.3), "scale": 1.0, "resist": 0.0,
			"extra": {"keep_min_dist": 7.0, "keep_max_dist": 13.0}},
		# Ярл Бьорн Мёртвый — босс Мидгарда (GDD 14.2): 60 У, три фазы (enemies/bosses/jarl.gd); HP/урон — enemies/defs/jarl.tres
		"jarl": {"kind": Enemy.Kind.BOSS, "hp": 1320.0, "speed": 3.6, "range": 3.6, "dmg": 25.0, "windup": 0.8, "recover": 0.9, "cd": 1.1, "color": Color(0.5, 0.26, 0.2), "scale": 2.1, "resist": 0.85,
			"script": "res://enemies/bosses/jarl.gd", "extra": {"lunge_speed": 5.0, "wall_splat_speed": 99.0, "boss_slam_radius": 6.0, "boss_slam_damage": 30.0, "boss_slam_windup": 1.0, "boss_far_slam_chance": 0.0}},
		# Толстый Свен — мини-босс (GDD 14.1): свой скрипт поверх enemy.gd; числа и вид перекрывает MinibossDef
		"sven": {"kind": Enemy.Kind.BOSS, "hp": 550.0, "speed": 4.2, "range": 2.6, "dmg": 18.0, "windup": 0.75, "recover": 0.9, "cd": 1.0, "color": Color(0.55, 0.62, 0.4), "scale": 1.5, "resist": 0.6,
			"script": "res://enemies/bosses/sven.gd", "extra": {"lunge_speed": 5.0, "wall_splat_speed": 99.0, "boss_slam_radius": 4.5, "boss_slam_damage": 20.0, "boss_slam_windup": 0.9, "boss_far_slam_chance": 0.004}},
		# Хёвдинг с дружиной — мини-босс (GDD 14.1): знамя-аура, рог, вторая фаза при 50 % HP; числа и вид перекрывает MinibossDef
		"hovding": {"kind": Enemy.Kind.BOSS, "hp": 484.0, "speed": 4.0, "range": 2.6, "dmg": 18.0, "windup": 0.7, "recover": 0.85, "cd": 1.0, "color": Color(0.6, 0.3, 0.25), "scale": 1.35, "resist": 0.65,
			"script": "res://enemies/bosses/hovding.gd", "extra": {"lunge_speed": 5.0, "wall_splat_speed": 99.0, "boss_slam_radius": 4.0, "boss_slam_damage": 18.0, "boss_slam_windup": 0.9, "boss_far_slam_chance": 0.0}},
		# Вёльва-ведьма и Берсерк-ульфхеднар — мини-боссы (GDD 14.1); числа и вид перекрывает MinibossDef
		"volva": {"kind": Enemy.Kind.BOSS, "hp": 396.0, "speed": 3.6, "range": 2.4, "dmg": 14.0, "windup": 0.7, "recover": 0.9, "cd": 1.2, "color": Color(0.5, 0.3, 0.6), "scale": 1.15, "resist": 0.5,
			"script": "res://enemies/bosses/volva.gd", "extra": {"lunge_speed": 4.0, "wall_splat_speed": 99.0, "boss_slam_radius": 3.5, "boss_slam_damage": 14.0, "boss_slam_windup": 0.9, "boss_far_slam_chance": 0.0}},
		"berserker": {"kind": Enemy.Kind.BOSS, "hp": 528.0, "speed": 4.6, "range": 2.4, "dmg": 18.0, "windup": 0.55, "recover": 0.7, "cd": 0.9, "color": Color(0.45, 0.42, 0.4), "scale": 1.3, "resist": 0.6,
			"script": "res://enemies/bosses/berserker.gd", "extra": {"lunge_speed": 6.0, "wall_splat_speed": 99.0, "boss_slam_radius": 3.5, "boss_slam_damage": 16.0, "boss_slam_windup": 0.8, "boss_far_slam_chance": 0.0}},
	}
	var script := load("res://enemies/enemy.gd")
	for key in defs:
		var d: Dictionary = defs[key]
		var e := CharacterBody3D.new()
		e.name = key.capitalize()
		e.set_script(load(d.script) if d.has("script") else script)
		e.set("kind", d.kind)
		e.set("max_health", d.hp)
		e.set("move_speed", d.speed)
		e.set("attack_range", d.range)
		e.set("attack_damage", d.dmg)
		e.set("windup_time", d.windup)
		e.set("recover_time", d.recover)
		e.set("attack_cooldown", d.cd)
		e.set("body_color", d.color)
		e.set("model_scale", d.scale)
		e.set("knock_resist", d.resist)
		if key == "boss":
			e.set("lunge_speed", 5.0)
			e.set("wall_splat_speed", 99.0)
		var extra: Dictionary = d.get("extra", {})
		for prop in extra:
			e.set(prop, extra[prop])
		var look: Dictionary = MODEL_LOOKS[key]
		for prop in look:
			if prop == "role_parts":
				e.set(prop, PackedStringArray(look[prop]))
			elif prop == "role_part_tints":
				var tints: Array[Color] = []
				tints.assign(look[prop])
				e.set(prop, tints)
			else:
				e.set(prop, look[prop])
		e.collision_layer = SceneBuilder.ENEMY_L
		e.collision_mask = SceneBuilder.WORLD | SceneBuilder.PLAYER_L | SceneBuilder.ENEMY_L | SceneBuilder.PROPS_L
		e.floor_snap_length = 0.3
		var shape := CollisionShape3D.new()
		shape.name = "Collider"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.45 * d.scale
		cap.height = 1.8 * d.scale
		shape.shape = cap
		shape.position = Vector3(0, 0.9 * d.scale, 0)
		e.add_child(shape)
		gen._save(e, "res://enemies/%s.tscn" % key)
