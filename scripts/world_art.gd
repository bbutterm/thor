extends RefCounted
class_name WorldArt
## Графика мира (комплект владельца, docs/world_art/): небо мира, декали на полу, декор на стенах,
## атмосферные частицы залов (искры факелов и очага, пылинки, низкий туман у земли).
## Правило фризов (CLAUDE.md «Важно»): на текстуру и вид — ОДИН StandardMaterial3D без instance uniform,
## создаётся при прогреве (ShaderWarmup → warmup) или загрузке зала и живёт до конца игры (static).
## Статичный декор не занимает буфер instance-переменных GL Compatibility (FX.INSTANCE_SLOTS_GL).
## Подпалины и лужи браги (затухают) — пулы FX на шейдере fx_sprite (FX.scorch, BrewPuddle).
## Числа — data/world_art.tres (WorldArtTuning); что включено в мире (небо, туман, цвета) — RunMap.

const DECAL_DIR := "res://assets/decals/"
const DECOR_DIR := "res://assets/decor/"
const PARTICLE_DIR := "res://sprites/vfx/"
const TUNING_PATH := "res://data/world_art.tres"

## Декор на стенах (WallDecor, квады с альфой): щиты, знамёна, гобелен, плакаты, вывеска ларька
const SHIELDS := ["shield_crossed_stripes", "shield_quartered", "shield_raven", "shield_spiral",
	"shield_sun", "shield_tree", "shield_triangles", "shield_waves"]
const BANNERS := ["banner_axes", "banner_bear", "banner_hammer", "banner_lightning", "banner_raven",
	"banner_serpent", "banner_tree", "banner_wolf"]
const POSTERS := ["tapestry", "odin_poster", "wanted_poster", "shop_sign"]
## Светящиеся круги на полу: прыжковая руна и круги под дверьми-наградами (по цвету награды)
const CIRCLES := ["rune_circle_jump", "rune_circle_blue", "rune_circle_gold", "rune_circle_green", "rune_circle_red"]
## Статичные декали на полу (FloorDecal, ключ "decals" у зала): лежат весь зал, без затухания
const FLOOR_DECALS := ["scorch", "puddle_mead", "footprints_giant", "slam_crack_small", "slam_crack_medium", "slam_crack_large",
	"ichor_splat_01", "ichor_splat_02", "ichor_splat_03", "ichor_splat_04"]
## Рисованные текстуры мира на блоках и полу залов (генератор: MIDGARD_BLOCKS, ключ "floor_tex")
const ROOM_TEXTURES := ["res://assets/textures/midgard/stone_wall.webp", "res://assets/textures/midgard/dirt_straw.webp"]
## Частицы атмосферы (fire — полоса vfx_fire из VFX-комплекта: языки пламени очага)
const PARTICLES := ["ember", "dust", "fog_puff_01", "fog_puff_02", "fog_puff_03", "fog_puff_04", "fire"]
## Кадров в полосе огня (data/ui_manifest.json → animations, как FX.STRIPS.fire)
const FIRE_FRAMES := 8

## Сколько материалов графики мира создано за игру (тест: после прогрева не растёт)
static var materials_created: int = 0
static var _mats: Dictionary = {}
static var _skies: Dictionary = {}
static var _ramps: Dictionary = {}
static var _cfg: WorldArtTuning

## Настройки (data/world_art.tres; нет файла — значения по умолчанию).
static func cfg() -> WorldArtTuning:
	if _cfg == null:
		if ResourceLoader.exists(TUNING_PATH):
			_cfg = load(TUNING_PATH) as WorldArtTuning
		if _cfg == null:
			_cfg = WorldArtTuning.new()
	return _cfg

## Путь к текстуре по ключу (декор, декаль, частица).
static func texture_path(key: String) -> String:
	if key == "fire":
		return PARTICLE_DIR + "vfx_fire.webp"
	if key in CIRCLES:
		return DECAL_DIR + key + ".webp"
	if key in PARTICLES:
		return PARTICLE_DIR + key + ".webp"
	# Любая другая декаль на пол (FloorDecal, ключ "decals" зала): assets/decals/<ключ>.webp
	if ResourceLoader.exists(DECAL_DIR + key + ".webp"):
		return DECAL_DIR + key + ".webp"
	return DECOR_DIR + key + ".webp"

static func texture(key: String) -> Texture2D:
	var p := texture_path(key)
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

## Все текстуры графики мира, что используются в игре (AssetCache держит их в памяти) + небо мира.
static func preload_paths(map: RunMap = null) -> PackedStringArray:
	var out := PackedStringArray()
	for k in SHIELDS + BANNERS + POSTERS + CIRCLES + PARTICLES + FLOOR_DECALS:
		var p := texture_path(k)
		if p in out:
			continue
		if ResourceLoader.exists(p):
			out.append(p)
	for k in FX.EXTRA_SPRITES:
		if not FX.EXTRA_SPRITES[k] in out:
			out.append(FX.EXTRA_SPRITES[k])
	for p in ROOM_TEXTURES:
		if ResourceLoader.exists(p):
			out.append(p)
	if map and map.sky != "" and ResourceLoader.exists(map.sky):
		out.append(map.sky)
	return out

## Все ключи материалов, что создаёт прогрев: [ключ, вид].
static func material_specs() -> Array:
	var out: Array = []
	for k in SHIELDS + BANNERS + POSTERS:
		out.append([k, "decor"])
	for k in CIRCLES:
		out.append([k, "glow"])
	for k in FLOOR_DECALS:
		out.append([k, "decal"])
	out.append(["ember", "particle_add"])
	out.append(["dust", "particle_add"])
	out.append(["fire", "flipbook"])
	for i in 4:
		out.append(["fog_puff_%02d" % (i + 1), "fog"])
	return out

## Общий материал текстуры key вида kind. Создаётся один раз и не умирает (иначе выкинутся пайплайны).
## Виды: "decor" — освещённый, alpha scissor, двусторонний (щиты, знамёна, плакаты);
## "glow" — без света, светится (круги рун на полу); "decal" — освещённая картинка на полу, смешение,
## без тени (статичные декали зала); "particle_add" — частицы-billboard, сложение;
## "flipbook" — то же с полосой кадров (огонь); "fog" — лежачий квад, смешение (клубы тумана).
static func material(key: String, kind: String = "decor") -> StandardMaterial3D:
	var id := kind + ":" + key
	if _mats.has(id):
		return _mats[id]
	var c := cfg()
	var m := StandardMaterial3D.new()
	m.resource_name = "world_art_" + id
	m.albedo_texture = texture(key)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"decor":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = c.alpha_scissor
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.92
		"glow":
			# Смешение, а не сложение: на светлом полу сложение выжигало круг в белое; яркость > 1 — свечение в Glow
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var e := c.jump_circle_energy if key == "rune_circle_jump" else c.door_circle_energy
			m.albedo_color = Color(e, e, e, 1.0)
		"decal":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.95
			m.disable_receive_shadows = false
		"particle_add", "flipbook":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.vertex_color_use_as_albedo = true
			if key == "dust":
				# Пылинки у самой камеры гаснут (иначе крупные «блёстки» перед глазами)
				m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
				m.distance_fade_min_distance = 1.0
				m.distance_fade_max_distance = 3.5
			if kind == "flipbook":
				m.particles_anim_h_frames = FIRE_FRAMES
				m.particles_anim_v_frames = 1
				m.particles_anim_loop = true
		"fog":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.vertex_color_use_as_albedo = true
	_mats[id] = m
	materials_created += 1
	return m

## Все созданные материалы графики мира (тесты).
static func materials() -> Array:
	return _mats.values()

# ---------------- Декор и декали ----------------

## Какую долю высоты текстуры занимает сама картинка (вокруг — прозрачные поля; замерено по альфе):
## знамёна 512×1024 — ткань ≈ 55 %, щиты ≈ 78 %, плакаты, гобелен и вывеска ≈ 91 %.
static func content_fraction(key: String) -> float:
	if key.begins_with("banner_"):
		return 0.55
	if key.begins_with("shield_"):
		return 0.775
	return 0.91

## Картинка на стене: квад по пропорциям текстуры, видимая часть — height м, лицом к +Z узла parent.
static func decor_quad(parent: Node3D, key: String, height: float) -> MeshInstance3D:
	var tex := texture(key)
	if parent == null or tex == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Quad"
	mi.mesh = FX.shared_mesh("quad")
	mi.material_override = material(key, "decor")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var aspect := float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	var h := height / content_fraction(key)
	mi.scale = Vector3(h * aspect, h, 1.0)
	mi.position = Vector3(0, 0, cfg().wall_offset)
	parent.add_child(mi)
	return mi

## Круг на полу (лежит в плоскости XZ узла parent): светящийся, общий материал, без instance uniform.
static func floor_circle(parent: Node3D, key: String, diameter: float) -> MeshInstance3D:
	if parent == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Circle"
	mi.mesh = FX.shared_mesh("quad_floor")
	mi.material_override = material(key, "glow")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.scale = Vector3(diameter, 1.0, diameter)
	mi.position.y = cfg().decal_lift
	parent.add_child(mi)
	return mi

## Статичная декаль на полу (FloorDecal): освещённая, смешение, общий материал, без instance uniform.
## Затухающие следы боя — не сюда, а в пулы FX (FX.scorch, FX.splat, FX.crack).
static func floor_decal(parent: Node3D, key: String, size: float) -> MeshInstance3D:
	if parent == null or texture(key) == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Decal"
	mi.mesh = FX.shared_mesh("quad_floor")
	mi.material_override = material(key, "decal")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.scale = Vector3(size, 1.0, size)
	mi.position.y = cfg().decal_lift
	parent.add_child(mi)
	return mi

## Круг под дверью-наградой по цвету награды: синий / золотой / зелёный / красный.
static func circle_for_color(col: Color) -> String:
	if col.s < 0.25:
		return "rune_circle_gold"
	var h := col.h * 360.0
	if h < 22.0 or h >= 330.0:
		return "rune_circle_red"
	if h < 70.0:
		return "rune_circle_gold"
	if h < 175.0:
		return "rune_circle_green"
	return "rune_circle_blue"

# ---------------- Небо мира ----------------

## Небо по панораме (одно на файл, живёт до конца игры: шейдер неба не перекомпилируется).
static func sky_for(path: String, energy: float) -> Sky:
	var id := "%s@%.3f" % [path, energy]
	if _skies.has(id):
		return _skies[id]
	var tex := load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	if tex == null:
		return null
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = tex
	sm.energy_multiplier = energy
	sm.filter = true
	var sky := Sky.new()
	sky.sky_material = sm
	# Панорама неподвижна: рассеянный свет и отражения считаются один раз
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_skies[id] = sky
	materials_created += 1
	return sky

## Небо и дымка мира на WorldEnvironment сцены игры (Game._ready). Окружение копируется — общий
## scenes/game_environment.tres не меняется (у мира без панорамы остаётся процедурное небо сцены).
static func apply_world(game: Node, map: RunMap) -> bool:
	if game == null or map == null or map.sky == "":
		return false
	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return false
	var sky := sky_for(map.sky, map.sky_energy)
	if sky == null:
		return false
	var env := we.environment.duplicate() as Environment
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0.0, deg_to_rad(map.sky_rotation_deg), 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = map.ambient_energy
	env.ambient_light_sky_contribution = map.ambient_sky_contribution
	env.ambient_light_color = map.ambient_color
	env.fog_light_color = map.fog_color
	env.fog_density = map.fog_density
	env.fog_sky_affect = map.fog_sky_affect
	env.tonemap_exposure = map.exposure
	we.environment = env
	game.set_meta("world_sky", map.sky)
	return true

# ---------------- Атмосфера зала ----------------

## Частицы атмосферы зала по миру (Game._load_room, экран затемнён): искры над факелами и очагом,
## пылинки в воздухе, низкий туман у земли. Всё — дети зала (уходят вместе с ним), материалы общие.
static func dress_room(room: Node3D, map: RunMap) -> void:
	if room == null or map == null or room.has_node("Atmosphere"):
		return
	var atm := Node3D.new()
	atm.name = "Atmosphere"
	room.add_child(atm)
	if map.torch_embers:
		var torches := room.get_node_or_null("Torches")
		if torches:
			for t in torches.get_children():
				if t is Node3D:
					_torch_embers(t as Node3D)
		var hearth := room.get_node_or_null("Decor/Hearth") as Node3D
		if hearth:
			_hearth(hearth)
	var size := room_size(room)
	if size == Vector2.ZERO:
		return
	if map.dust_motes:
		_dust(atm, size)
	if map.ground_fog:
		_ground_fog(atm, size, map.ground_fog_color)

## Внутренний размер зала (ширина по X, глубина по Z) по коробкам стен генератора; нет стен — ноль.
static func room_size(room: Node3D) -> Vector2:
	var we := room.get_node_or_null("Geometry/WallE") as Node3D
	var ws := room.get_node_or_null("Geometry/WallS") as Node3D
	if we == null or ws == null:
		return Vector2.ZERO
	return Vector2(absf(we.position.x) * 2.0 - 1.0, absf(ws.position.z) * 2.0 - 1.0)

## Затухание частицы: появляется, держится, гаснет (общая кривая на вид).
static func _ramp(kind: String) -> Gradient:
	if _ramps.has(kind):
		return _ramps[kind]
	var g := Gradient.new()
	match kind:
		"ember":
			g.set_color(0, Color(1.0, 0.95, 0.7, 0.0))
			g.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
			g.add_point(0.12, Color(1.0, 0.85, 0.45, 1.0))
			g.add_point(0.6, Color(1.0, 0.5, 0.15, 0.8))
		"flame":
			g.set_color(0, Color(1, 1, 1, 0.0))
			g.set_color(1, Color(1, 1, 1, 0.0))
			g.add_point(0.15, Color(1, 1, 1, 1.0))
			g.add_point(0.75, Color(1, 1, 1, 0.9))
		_:
			g.set_color(0, Color(1, 1, 1, 0.0))
			g.set_color(1, Color(1, 1, 1, 0.0))
			g.add_point(0.25, Color(1, 1, 1, 1.0))
			g.add_point(0.75, Color(1, 1, 1, 1.0))
	_ramps[kind] = g
	return g

static func _emitter(name: String, key: String, kind: String, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = name
	p.amount = maxi(amount, 1)
	p.lifetime = maxf(life, 0.1)
	p.preprocess = life
	p.randomness = 0.6
	p.mesh = FX.shared_mesh("quad_floor" if kind == "fog" else ("quad_bottom" if kind == "flipbook" else "quad"))
	p.material_override = material(key, kind)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.gravity = Vector3.ZERO
	p.add_to_group("world_particles")
	return p

## Искры над факелом: горсть гаснущих искр поднимается от пламени (без света).
static func _torch_embers(torch: Node3D) -> CPUParticles3D:
	var c := cfg()
	if c.torch_embers <= 0 or torch.has_node("Embers"):
		return null
	var p := _emitter("Embers", "ember", "particle_add", c.torch_embers, c.torch_ember_life)
	var flame := torch.get_node_or_null("Flame") as Node3D
	p.position = (flame.position if flame else Vector3(0, 0.38, 0.08)) + Vector3(0, 0.12, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.07
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = c.torch_ember_speed.x
	p.initial_velocity_max = c.torch_ember_speed.y
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 0.2
	p.damping_max = 0.5
	p.scale_amount_min = c.torch_ember_size.x
	p.scale_amount_max = c.torch_ember_size.y
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.color = c.ember_color
	p.color_ramp = _ramp("ember")
	torch.add_child(p)
	return p

## Очаг длинного дома: языки пламени (полоса vfx_fire, петля) и сноп искр вверх.
static func _hearth(hearth: Node3D) -> void:
	var c := cfg()
	if hearth.has_node("Embers"):
		return
	# Размер оградки — по камням (дети очага), иначе 2 × 5 м
	var ext := Vector3(0.8, 0.05, 2.2)
	var stones := hearth.get_children().filter(func(n: Node) -> bool: return n is Node3D and not n is Light3D)
	if not stones.is_empty():
		var mx := 0.0
		var mz := 0.0
		for s in stones:
			mx = maxf(mx, absf((s as Node3D).position.x))
			mz = maxf(mz, absf((s as Node3D).position.z))
		ext = Vector3(maxf(mx - 0.4, 0.3), 0.05, maxf(mz - 0.5, 0.3))
	if c.hearth_flames > 0:
		var f := _emitter("Flames", "fire", "flipbook", c.hearth_flames, 0.9)
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		f.emission_box_extents = ext * Vector3(0.8, 1.0, 0.85)
		f.position.y = 0.05
		f.direction = Vector3.UP
		f.spread = 5.0
		f.initial_velocity_min = 0.0
		f.initial_velocity_max = 0.15
		f.scale_amount_min = c.hearth_flame_size.x
		f.scale_amount_max = c.hearth_flame_size.y
		f.anim_speed_min = 0.9
		f.anim_speed_max = 1.2
		f.anim_offset_min = 0.0
		f.anim_offset_max = 1.0
		f.color = Color(1.0, 0.9, 0.8, 1.0)
		f.color_ramp = _ramp("flame")
		hearth.add_child(f)
	if c.hearth_embers > 0:
		var p := _emitter("Embers", "ember", "particle_add", c.hearth_embers, c.hearth_ember_life)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = ext
		p.position.y = 0.6
		p.direction = Vector3.UP
		p.spread = 18.0
		p.initial_velocity_min = c.hearth_ember_speed.x
		p.initial_velocity_max = c.hearth_ember_speed.y
		p.gravity = Vector3(0, 0.2, 0)
		p.damping_min = 0.3
		p.damping_max = 0.7
		p.scale_amount_min = c.hearth_ember_size.x
		p.scale_amount_max = c.hearth_ember_size.y
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -90.0
		p.angular_velocity_max = 90.0
		p.color = c.ember_color
		p.color_ramp = _ramp("ember")
		hearth.add_child(p)

## Пылинки: медленно плавают по всему залу, светятся в лучах (сложение, тёплый цвет).
static func _dust(parent: Node3D, size: Vector2) -> CPUParticles3D:
	var c := cfg()
	var n := clampi(int(size.x * size.y / 100.0 * c.dust_per_100m2), 6, maxi(c.dust_max, 6))
	var p := _emitter("Dust", "dust", "particle_add", n, c.dust_life)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(size.x * 0.5 - 1.0, (c.dust_height.y - c.dust_height.x) * 0.5, size.y * 0.5 - 1.0)
	p.position.y = (c.dust_height.x + c.dust_height.y) * 0.5
	p.direction = Vector3(1, 0.2, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.12
	p.scale_amount_min = c.dust_size.x
	p.scale_amount_max = c.dust_size.y
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -10.0
	p.angular_velocity_max = 10.0
	p.color = c.dust_color
	p.color_ramp = _ramp("soft")
	parent.add_child(p)
	return p

## Низкий туман у земли (GDD 16, Мидгард): клубы лежат у пола и медленно дрейфуют и крутятся.
## Лежачие квады ниже глаз — не режутся о пол и не «встают» перед камерой.
static func _ground_fog(parent: Node3D, size: Vector2, col: Color) -> void:
	var c := cfg()
	var variants := clampi(c.fog_variants, 1, 4)
	var total := size.x * size.y / 100.0 * c.fog_per_100m2
	for i in variants:
		var n := clampi(int(total / variants), 3, maxi(c.fog_max, 3))
		var p := _emitter("GroundFog%d" % i, "fog_puff_%02d" % (1 + (i * 2) % 4), "fog", n, c.fog_life)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(size.x * 0.5 - 1.5, (c.fog_height.y - c.fog_height.x) * 0.5, size.y * 0.5 - 1.5)
		p.position.y = (c.fog_height.x + c.fog_height.y) * 0.5
		p.direction = Vector3(1, 0, 0.3)
		p.spread = 180.0
		p.flatness = 1.0
		p.initial_velocity_min = c.fog_drift * 0.3
		p.initial_velocity_max = c.fog_drift
		p.particle_flag_rotate_y = true
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -4.0
		p.angular_velocity_max = 4.0
		p.scale_amount_min = c.fog_size.x
		p.scale_amount_max = c.fog_size.y
		p.color = col
		p.color_ramp = _ramp("soft")
		p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		parent.add_child(p)

# ---------------- Прогрев ----------------

## Прогрев (ShaderWarmup, экран затемнён): все материалы графики мира и по образцу каждого вида перед камерой.
static func warmup(parent: Node3D, center: Vector3, right: Vector3) -> void:
	for spec in material_specs():
		material(spec[0], spec[1])
	var x := -0.8
	for spec in [["shield_sun", "decor"], ["rune_circle_jump", "glow"], ["scorch", "decal"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = FX.shared_mesh("quad" if spec[1] == "decor" else "quad_floor")
		mi.material_override = material(spec[0], spec[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_position = center + right * x + Vector3(0, 0.5, 0)
		mi.scale = Vector3.ONE * 0.2
		x += 0.4
	for spec in [["ember", "particle_add"], ["fire", "flipbook"], ["fog_puff_01", "fog"]]:
		var p := _emitter("Warm", spec[0], spec[1], 1, 1.0)
		p.preprocess = 0.0
		p.scale_amount_min = 0.2
		p.scale_amount_max = 0.2
		p.color = Color(1, 1, 1, 0.05)
		parent.add_child(p)
		p.global_position = center + right * x + Vector3(0, 0.5, 0)
		x += 0.4
