extends RefCounted
class_name FX
## Общие эффекты «сочности»: hit-stop, всплывающий урон, вспышки, линии молний.

static var _hitstop_left: float = 0.0
static var _hitstop_scale: float = 1.0
## Кадр, в котором последний раз менялся Engine.time_scale, и масштаб, бывший до этого в начале кадра
static var _scale_frame: int = -1
static var _scale_before: float = 1.0

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

## Замедление времени на долю секунды при попадании.
## Отсчёт идёт в реальном времени через FX.tick() из автозагрузки Run.
static func hitstop(duration: float, scale: float = 0.05) -> void:
	if duration <= 0.0:
		return
	_hitstop_left = maxf(_hitstop_left, duration)
	_hitstop_scale = minf(_hitstop_scale, scale) if _hitstop_left > 0.0 else scale
	_set_time_scale(_hitstop_scale)

## Вызывается каждый кадр. Run передаёт delta / текущий time_scale; пересчитываем по масштабу,
## с которым движок на самом деле умножил delta этого кадра (см. real_delta).
static func tick(passed_real_delta: float) -> void:
	sync_fades()
	if _hitstop_left <= 0.0:
		return
	_hitstop_left -= real_delta(passed_real_delta * maxf(Engine.time_scale, 0.0001))
	if _hitstop_left <= 0.0:
		_hitstop_left = 0.0
		_hitstop_scale = 1.0
		_set_time_scale(1.0)

## Реальная длительность кадра по delta из _process. Движок умножает delta на time_scale, каким он был
## В НАЧАЛЕ кадра; удары (и hit-stop) случаются в физике этого же кадра. Если делить на новый 0.05,
## первый же тик насчитывал 1/60 / 0.05 = 0.33 с и стоп заканчивался в кадре, где начался.
static func real_delta(scaled_delta: float) -> float:
	var s := _scale_before if Engine.get_process_frames() == _scale_frame else Engine.time_scale
	return scaled_delta / maxf(s, 0.0001)

static func _set_time_scale(s: float) -> void:
	var f := Engine.get_process_frames()
	if f != _scale_frame:
		_scale_frame = f
		_scale_before = Engine.time_scale
	Engine.time_scale = s

static func reset_time() -> void:
	_hitstop_left = 0.0
	_hitstop_scale = 1.0
	_set_time_scale(1.0)

## Всплывающая цифра урона в мире.
static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color = Color(1, 0.9, 0.3), big: bool = false) -> void:
	Perf.mark("fx_damage_number")
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0018 if big else 0.0013
	label.font_size = 48
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.8)
	var font: Font = load("res://fonts/RussoOne-Regular.ttf")
	if font:
		label.font = font
	parent.add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position", label.global_position + Vector3(0, 1.2, 0), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)

## Молния между точками: текстурные ленты vfx_lightning_01..04 (по отрезку на cfg().lightning_segment м,
## каждая повёрнута к камере вокруг своей оси) и тонкая ломаная-сердцевина. Гаснет за lifetime с мерцанием.
static func lightning(parent: Node, from: Vector3, to: Vector3, lifetime: float = 0.25, color: Color = Color(0.55, 0.85, 1.0)) -> void:
	Perf.mark("fx_lightning")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	if c.lightning_core_alpha > 0.0:
		var mesh := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		fx_apply(mi, "alpha", color, 2.5)
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		mi.transparency = 1.0 - c.lightning_core_alpha
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var segments := 8
		var prev := from
		for i in range(1, segments + 1):
			var t := float(i) / segments
			var p := from.lerp(to, t)
			if i < segments:
				p += Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(-0.35, 0.35))
			mesh.surface_add_vertex(prev)
			mesh.surface_add_vertex(p)
			prev = p
		mesh.surface_end()
		var tw := mi.create_tween()
		tw.tween_property(mi, "transparency", 1.0, lifetime)
		tw.tween_callback(mi.queue_free)
	_lightning_ribbons(parent, from, to, lifetime, color)

## Вспышка-шар (удар, приземление).
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.3) -> void:
	Perf.mark("fx_burst")
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = shared_mesh("sphere")
	fx_apply(mi, "alpha_nocull", color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mi, "transparency", 1.0, lifetime)
	tw.chain().tween_callback(mi.queue_free)

## Плоское кольцо на земле (волна удара-приземления, телеграф босса).
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.35) -> void:
	Perf.mark("fx_ring")
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = shared_mesh("ring")
	fx_apply(mi, "alpha", color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.3, 0.15, 0.3)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.15, radius), lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "transparency", 1.0, lifetime)
	tw.chain().tween_callback(mi.queue_free)

## Разлёт частиц: искры от ударов, пыль от приземления, щепки.
static func sparks(parent: Node, pos: Vector3, color: Color, amount: int = 14, speed: float = 6.0, gravity: float = 14.0, size: float = 0.07, lifetime: float = 0.45) -> void:
	Perf.mark("fx_sparks")
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.2 * size
	p.mesh = shared_mesh("box")
	fx_apply(p, "unshaded", color)
	if _shrink_curve == null:
		_shrink_curve = Curve.new()
		_shrink_curve.add_point(Vector2(0, 1))
		_shrink_curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = _shrink_curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := p.get_tree().create_timer(lifetime + 0.3, true, false, true)
	t.timeout.connect(p.queue_free)
	# Рисованные звёзды vfx_sparks_* поверх частиц — только у ярких искр (не у пыли и щепок)
	var cf := cfg()
	if color.get_luminance() >= cf.spark_min_luma and cf.sparks_max > 0:
		var n := clampi(amount / maxi(cf.sparks_per_star, 1), 1, cf.sparks_max)
		var k := clampf(size / 0.07, 0.6, 1.5)
		for i in n:
			var off := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)) * cf.spark_spread * k
			spark_star(parent, pos + off, color, randf_range(cf.spark_size.x, cf.spark_size.y) * k)

static func make_material(color: Color, roughness: float = 0.85, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static var _fx_mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _shrink_curve: Curve

const FX_SHADERS := {
	"unshaded": preload("res://shaders/fx_unshaded.gdshader"),
	"alpha": preload("res://shaders/fx_alpha.gdshader"),
	"alpha_nocull": preload("res://shaders/fx_alpha_nocull.gdshader"),
	"glow": preload("res://shaders/fx_glow.gdshader"),
}

## Общий материал эффекта. Новый материал на каждую вспышку — это компиляция пайплайна при каждом
## эффекте (замерено на Forward+). Поэтому на вид эффекта — один материал, цвет и яркость задаются
## на экземпляре (fx_apply), затухание — через GeometryInstance3D.transparency.
## Виды: "unshaded", "alpha", "alpha_nocull", "glow" (освещённый, светится).
static func fx_material(kind: String) -> ShaderMaterial:
	if _fx_mats.has(kind):
		return _fx_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = FX_SHADERS[kind]
	_fx_mats[kind] = m
	materials_created += 1
	return m

## В GL Compatibility выделенный блок instance-переменных занимает 16 ячеек независимо от их числа.
## Номинальный буфер на 4096 ячеек даёт до 256 блоков; запас зависит от настроек и глобальных параметров.
## Снятие материала не гарантирует освобождения блока: ранее заданные параметры могут жить до удаления RID.
## При переполнении появляется «Too many instances using shader instance variables», и эффекты теряют параметры.
const INSTANCE_SLOTS_GL := 256

static var _iu_shaders: Dictionary = {}

## Узлы под root с текущим override/overlay, чей шейдер совпадает с текстовым признаком _has_iu.
## Это не занятые слоты: поверхностные материалы, next_pass, сохранённые параметры и удалённые из дерева RID
## здесь не учитываются; текстовый признак также может ошибаться (диагностика: Perf F3, тесты).
static func instance_uniform_users(root: Node) -> int:
	if root == null:
		return 0
	var n := 0
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if _has_iu(gi.material_override) or _has_iu(gi.material_overlay):
			n += 1
	return n

static func _has_iu(m: Material) -> bool:
	var sm := m as ShaderMaterial
	if sm == null or sm.shader == null:
		return false
	var s := sm.shader
	if not _iu_shaders.has(s):
		_iu_shaders[s] = s.code.contains("instance uniform") or s.code.contains("fx_common")
	return _iu_shaders[s]

## Назначить эффекту общий материал вида kind и задать цвет/яркость экземпляра.
static func fx_apply(gi: GeometryInstance3D, kind: String, color: Color, energy: float = 1.0) -> void:
	gi.material_override = fx_material(kind)
	gi.set_instance_shader_parameter("color", color)
	gi.set_instance_shader_parameter("energy", energy)
	_track_fade(gi)

# --- Затухание в GL Compatibility ---
# GeometryInstance3D.transparency там не работает: узел не становится прозрачнее, и все затухания эффектов
# (вспышки, кольца, искры, ихор) обрывались, а телеграфы, лужи, огонь, лава были сплошными пятнами.
# Узлы с материалами эффектов регистрируются, и раз в кадр (FX.tick) их transparency копируется в
# instance uniform fade (shaders/fx_common.gdshaderinc, fx_sprite). В Forward+ список пуст — работает сам движок.

static var _gl: int = -1
static var _fade_nodes: Array = []

static func uses_fade_emulation() -> bool:
	if _gl < 0:
		_gl = 1 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0
	return _gl == 1

static func _track_fade(gi: GeometryInstance3D) -> void:
	if not uses_fade_emulation():
		return
	# Материал назначен заново — принудительно отправим fade, независимо от состояния сервера
	gi.set_meta("_fade", -1.0)
	if not gi.has_meta("_fade_tracked"):
		gi.set_meta("_fade_tracked", true)
		_fade_nodes.append(gi)

## Раз в кадр: transparency → fade у зарегистрированных узлов (только GL Compatibility).
static func sync_fades() -> void:
	if _fade_nodes.is_empty():
		return
	var keep: Array = []
	for n in _fade_nodes:
		if not is_instance_valid(n):
			continue
		var gi := n as GeometryInstance3D
		keep.append(gi)
		if gi.material_override == null:
			continue
		var f := 1.0 - gi.transparency
		if absf(f - float(gi.get_meta("_fade", -1.0))) > 0.002:
			gi.set_meta("_fade", f)
			gi.set_instance_shader_parameter("fade", f)
	_fade_nodes = keep

## Общие меши эффектов единичного размера (масштабируются узлом) — не строим примитив на каждую вспышку.
static func shared_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 16
			sm.rings = 8
			m = sm
		"ring":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.85
			tm.outer_radius = 1.0
			tm.rings = 32
			tm.ring_segments = 6
			m = tm
		"box":
			m = BoxMesh.new()
		"disc":
			# Плоский диск радиуса 1 (огонь на земле, телеграф босса) — масштабируется по X/Z
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.0
			cm.height = 1.0
			cm.radial_segments = 32
			cm.rings = 1
			m = cm
		"quad", "quad_bottom", "quad_floor":
			# Квад 1×1 для текстурных эффектов (fx_sprite): по центру / с опорой на нижний край
			# (огонь, кристаллы льда растут от пола) / лёжа на полу (пятна, трещины, волна)
			var qm := QuadMesh.new()
			if kind == "quad_bottom":
				qm.center_offset = Vector3(0, 0.5, 0)
			elif kind == "quad_floor":
				qm.orientation = PlaneMesh.FACE_Y
			m = qm
	_meshes[kind] = m
	return m

# --- VFX-комплект владельца (sprites/vfx/*): текстурные эффекты на одном шейдере ---
# Правило фризов: на текстуру — один ShaderMaterial (shaders/fx_sprite.gdshader), создаётся при прогреве
# (ShaderWarmup → warmup_sprites) и живёт до конца игры; кадр, цвет, billboard — instance uniform.
# Узлы эффектов — из пулов с лимитами (cfg().*_limit): сверх лимита переиспользуется самый старый.
# Числа — data/vfx_tuning.tres (VfxTuning).

const VFX_DIR := "res://sprites/vfx/"
const TUNING_PATH := "res://data/vfx_tuning.tres"
const SPRITE_SHADER := preload("res://shaders/fx_sprite.gdshader")
## Полосы-атласы (data/ui_manifest.json → animations): кадров по X
const STRIPS := {"hit_flash": 6, "smoke": 8, "fire": 8}
## Наборы вариантов: vfx_<имя>_01.webp … _NN.webp
const VARIANTS := {"sparks": 12, "lightning": 4, "ichor_splash": 3, "ichor_splat": 3, "ice_shard": 5}
## Одиночные текстуры
const SINGLES := ["shockwave", "ice_patch", "crack_decal_small", "crack_decal_medium", "crack_decal_large"]
## Текстуры графики мира (assets/decals/, docs/world_art) на том же шейдере: затухающие декали из пулов
## (подпалина огня/взрыва — FX.scorch, лужа браги Свена — BrewPuddle). Статичные декали — WorldArt (без instance uniform).
const EXTRA_SPRITES := {
	"scorch": "res://assets/decals/scorch.webp",
	"puddle_mead": "res://assets/decals/puddle_mead.webp",
}

## Сколько материалов эффектов создано за игру (тест: после прогрева в бою не растёт)
static var materials_created: int = 0
static var _cfg: VfxTuning
static var _sprite_mats: Dictionary = {}
static var _holder: Node3D
static var _pools: Dictionary = {}

## Настройки VFX (data/vfx_tuning.tres; нет файла — значения по умолчанию).
static func cfg() -> VfxTuning:
	if _cfg == null:
		if ResourceLoader.exists(TUNING_PATH):
			_cfg = load(TUNING_PATH) as VfxTuning
		if _cfg == null:
			_cfg = VfxTuning.new()
	return _cfg

## Все ключи текстурных эффектов (для прогрева и тестов).
static func sprite_keys() -> PackedStringArray:
	var out := PackedStringArray(STRIPS.keys())
	for v in VARIANTS:
		for i in int(VARIANTS[v]):
			out.append(variant_key(v, i))
	out.append_array(PackedStringArray(SINGLES))
	out.append_array(PackedStringArray(EXTRA_SPRITES.keys()))
	return out

static func variant_key(set_name: String, i: int) -> String:
	return "%s_%02d" % [set_name, i + 1]

static func random_variant(set_name: String) -> String:
	return variant_key(set_name, randi() % int(VARIANTS.get(set_name, 1)))

## Общий материал текстуры vfx_<key>.webp. Создаётся один раз и не умирает (иначе выкинутся пайплайны).
static func sprite_material(key: String) -> ShaderMaterial:
	if _sprite_mats.has(key):
		return _sprite_mats[key]
	var m := ShaderMaterial.new()
	m.shader = SPRITE_SHADER
	var path: String = EXTRA_SPRITES.get(key, VFX_DIR + "vfx_" + key + ".webp")
	if ResourceLoader.exists(path):
		m.set_shader_parameter("tex", load(path))
	m.set_shader_parameter("grid", Vector2(float(STRIPS.get(key, 1)), 1.0))
	_sprite_mats[key] = m
	materials_created += 1
	return m

## Все созданные материалы текстурных эффектов (тесты).
static func sprite_materials() -> Array:
	return _sprite_mats.values()

## Прогрев: по квадрату каждой текстуры перед камерой (ShaderWarmup, экран затемнён) во всех режимах billboard.
static func warmup_sprites(parent: Node3D, center: Vector3, right: Vector3) -> void:
	# Материалы — все сразу (создание материала и загрузка текстуры — здесь, не в бою); рисовать хватит
	# трёх квадов: шейдер один, пайплайн один на вид меша, а буфер instance-переменных не резиновый
	for key in sprite_keys():
		sprite_material(key)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = shared_mesh(["quad", "quad_bottom", "quad_floor"][i])
		mi.material_override = sprite_material(["hit_flash", "fire", "ichor_splat_01"][i])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite_color(mi, Color(1, 1, 1, 0.05))
		set_sprite(mi, 0.0, i, 0.0, 16.0 if i == 1 else 0.0)
		parent.add_child(mi)
		mi.global_position = center + right * (i * 0.3 - 0.3) + Vector3(0, 0.4, 0)
		mi.scale = Vector3.ONE * 0.22

## Узел-хранилище пулов: верхнего уровня (мировые координаты), умирает вместе с родителем или при смене зала
## (метка transient — Game._load_room чистит такие).
static func _holder_for(parent: Node) -> Node3D:
	if _holder and is_instance_valid(_holder) and _holder.is_inside_tree() and not _holder.is_queued_for_deletion():
		return _holder
	_pools.clear()
	_holder = Node3D.new()
	_holder.name = "FXSprites"
	_holder.top_level = true
	_holder.set_meta("transient", true)
	parent.add_child(_holder)
	return _holder

## Сколько узлов в пуле вида kind (тесты: не больше лимита).
static func pool_size(kind: String) -> int:
	var pool: Array = _pools.get(kind, [])
	return pool.filter(func(n: Variant) -> bool: return is_instance_valid(n)).size()

## Сколько эффектов вида kind сейчас видно.
static func pool_active(kind: String) -> int:
	var pool: Array = _pools.get(kind, [])
	return pool.filter(func(n: Variant) -> bool: return is_instance_valid(n) and (n as Node3D).visible).size()

## Узлы пула вида kind (тесты).
static func pool_nodes(kind: String) -> Array:
	var pool: Array = _pools.get(kind, [])
	return pool.filter(func(n: Variant) -> bool: return is_instance_valid(n))

## Узел из пула: свободный, новый (пока меньше limit) или самый старый (его эффект обрывается).
static func _take(kind: String, parent: Node, limit: int) -> MeshInstance3D:
	var h := _holder_for(parent)
	var pool: Array = _pools.get(kind, [])
	pool = pool.filter(func(n: Variant) -> bool: return is_instance_valid(n))
	_pools[kind] = pool
	var mi: MeshInstance3D = null
	for n in pool:
		if not (n as MeshInstance3D).visible:
			mi = n
			break
	if mi == null and pool.size() < maxi(limit, 1):
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Скрытый свободный узел снимает override; прежние instance-параметры могут удерживать блок до удаления RID.
		# При повторном использовании _sprite назначает тот же общий материал, без создания нового.
		mi.visibility_changed.connect(func() -> void:
			if not mi.visible:
				mi.material_override = null)
		h.add_child(mi)
		pool.append(mi)
	if mi == null:
		for n in pool:
			if mi == null or int(n.get_meta("t", 0)) < int(mi.get_meta("t", 0)):
				mi = n
	if mi.has_meta("tw"):
		var old := mi.get_meta("tw") as Tween
		if old and old.is_valid():
			old.kill()
	mi.set_meta("t", Time.get_ticks_usec())
	mi.visible = true
	mi.transparency = 0.0
	mi.transform = Transform3D.IDENTITY
	return mi

## Текстурный эффект из пула. billboard: 0 — по узлу, 1 — к камере, 2 — к камере вокруг Y.
static func _sprite(kind: String, parent: Node, key: String, pos: Vector3, size: float, color: Color, billboard: int,
		limit: int, mesh: String = "quad", energy: float = 1.0) -> MeshInstance3D:
	var mi := _take(kind, parent, limit)
	mi.mesh = shared_mesh(mesh)
	mi.material_override = sprite_material(key)
	_track_fade(mi)
	sprite_color(mi, color, energy)
	set_sprite(mi, 0.0, billboard)
	mi.position = pos
	mi.scale = Vector3.ONE * maxf(size, 0.001)
	return mi

## Общий материал текстурного эффекта key узлу не из пула (лужа браги и т. п.): оттенок, кадр 0, без billboard.
static func sprite_apply(gi: GeometryInstance3D, key: String, color: Color = Color.WHITE, energy: float = 1.0) -> void:
	gi.material_override = sprite_material(key)
	_track_fade(gi)
	sprite_color(gi, color, energy)
	set_sprite(gi, 0.0, 0)

## Оттенок и яркость текстурного эффекта (instance uniform color: rgb — оттенок, a — яркость).
## Альфа цвета → прозрачность узла (у этого шейдера альфа экземпляра занята яркостью).
static func sprite_color(gi: GeometryInstance3D, color: Color, energy: float = 1.0) -> void:
	gi.set_instance_shader_parameter("color", Color(color.r, color.g, color.b, energy))
	if color.a < 1.0:
		gi.transparency = 1.0 - color.a

## Параметры текстурного эффекта (instance uniform vec4 sprite): кадр, режим billboard, поворот, скорость петли.
static func set_sprite(gi: GeometryInstance3D, frame: float, billboard: int = 0, spin: float = 0.0, anim_fps: float = 0.0) -> void:
	var v := Vector4(frame, float(billboard), spin, anim_fps)
	gi.set_meta("sp", v)
	gi.set_instance_shader_parameter("sprite", v)

static func _sprite_param(gi: GeometryInstance3D, axis: int, value: float) -> void:
	var v: Vector4 = gi.get_meta("sp") if gi.has_meta("sp") else Vector4.ZERO
	v[axis] = value
	gi.set_meta("sp", v)
	gi.set_instance_shader_parameter("sprite", v)

static func sprite_frame(gi: GeometryInstance3D) -> float:
	return (gi.get_meta("sp") as Vector4).x if gi.has_meta("sp") else 0.0

static func _tween(mi: MeshInstance3D) -> Tween:
	var tw := mi.create_tween()
	mi.set_meta("tw", tw)
	return tw

## Прогнать кадры полосы 0..frames-1 за time (игровое время: во время hit-stop кадр «стоит»).
static func _play_frames(tw: Tween, mi: MeshInstance3D, frames: int, time: float) -> void:
	tw.tween_method(func(f: float) -> void: _sprite_param(mi, 0, f), 0.0, float(frames) - 0.001, maxf(time, 0.01))

static func _camera(n: Node) -> Camera3D:
	return n.get_viewport().get_camera_3d() if n and n.is_inside_tree() else null

## Пол под точкой: {position, normal} или пусто (под точкой пропасть).
static func _floor(n: Node3D, pos: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos + Vector3(0, -6.0, 0), 1)
	return n.get_world_3d().direct_space_state.intersect_ray(q)

## Квад на полу (пятно, трещина, наледь, волна): лежит по нормали пола, повёрнут случайно.
static func _floor_sprite(kind: String, parent: Node, key: String, pos: Vector3, size: float, color: Color, limit: int, energy: float = 1.0) -> MeshInstance3D:
	var h := _holder_for(parent)
	var hit := _floor(h, pos)
	if hit.is_empty():
		return null
	var n: Vector3 = hit.normal
	var mi := _sprite(kind, parent, key, (hit.position as Vector3) + n * cfg().decal_lift, size, color, 0, limit, "quad_floor", energy)
	var b := Basis(Vector3.UP, randf() * TAU)
	if n.dot(Vector3.UP) < 0.999:
		b = Basis(Quaternion(Vector3.UP, n)) * b
	mi.basis = b.scaled(Vector3.ONE * size)
	return mi

## Анимированная вспышка попадания vfx_hit_flash (6 кадров за cfg().hit_flash_time).
static func hit_flash(parent: Node, pos: Vector3, size: float, color: Color = Color(1, 0.95, 0.8)) -> void:
	Perf.mark("fx_hit_flash")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var cam := _camera(parent)
	if cam:
		pos += (cam.global_position - pos).normalized() * c.hit_flash_push
	var mi := _sprite("hit_flash", parent, "hit_flash", pos, size, color, 1, c.hit_flash_limit, "quad", 1.4)
	_sprite_param(mi, 2, randf() * TAU)
	var tw := _tween(mi)
	_play_frames(tw, mi, int(STRIPS.hit_flash), c.hit_flash_time)
	tw.tween_callback(mi.hide)

## Рисованная звезда-искра (случайная из vfx_sparks_01..12): вспыхивает, крутится, гаснет.
static func spark_star(parent: Node, pos: Vector3, color: Color, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var mi := _sprite("sparks", parent, random_variant("sparks"), pos, size * 0.3, color.lerp(Color.WHITE, 0.25), 1, c.sparks_limit, "quad", 1.3)
	var spin0 := randf() * TAU
	_sprite_param(mi, 2, spin0)
	var tw := _tween(mi)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, c.spark_time * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_method(func(a: float) -> void: _sprite_param(mi, 2, a), spin0, spin0 + randf_range(-1.2, 1.2), c.spark_time)
	tw.tween_property(mi, "transparency", 1.0, c.spark_time * 0.6).set_delay(c.spark_time * 0.4)
	tw.chain().tween_callback(mi.hide)

## Брызги ихора нежити (vfx_ichor_splash_01..03): вылетают и гаснут.
static func ichor_splash(parent: Node, pos: Vector3, size: float) -> void:
	Perf.mark("fx_ichor")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var mi := _sprite("ichor_splash", parent, random_variant("ichor_splash"), pos, size * 0.5, Color.WHITE, 1, c.ichor_splash_limit)
	_sprite_param(mi, 2, randf_range(-0.7, 0.7))
	var tw := _tween(mi)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, c.ichor_splash_time * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "position", pos + Vector3(0, -0.35, 0), c.ichor_splash_time).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "transparency", 1.0, c.ichor_splash_time * 0.5).set_delay(c.ichor_splash_time * 0.5)
	tw.chain().tween_callback(mi.hide)

## Пятно ихора на полу (vfx_ichor_splat_01..03): растекается, лежит cfg().splat_life, исчезает.
## Пул cfg().splat_limit — сверх него исчезает самое старое.
static func splat(parent: Node, pos: Vector3, size: float) -> void:
	Perf.mark("fx_splat")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var mi := _floor_sprite("splat", parent, random_variant("ichor_splat"), pos, size, Color.WHITE, c.splat_limit)
	if mi == null:
		return
	mi.transparency = c.splat_transparency
	var b := mi.basis
	mi.basis = b.scaled(Vector3.ONE * 0.4)
	var tw := _tween(mi)
	tw.tween_property(mi, "basis", b, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(maxf(c.splat_life - c.splat_fade, 0.0))
	tw.tween_property(mi, "transparency", 1.0, maxf(c.splat_fade, 0.01))
	tw.tween_callback(mi.hide)

## Клуб дыма vfx_smoke (8 кадров за cfg().smoke_time): смерть, взрыв.
static func smoke(parent: Node, pos: Vector3, size: float, color: Color = Color(0.85, 0.83, 0.8)) -> void:
	Perf.mark("fx_smoke")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var mi := _sprite("smoke", parent, "smoke", pos, size, color, 1, c.smoke_limit)
	mi.transparency = c.smoke_transparency
	_sprite_param(mi, 2, randf_range(-0.4, 0.4))
	var tw := _tween(mi)
	tw.set_parallel(true)
	_play_frames(tw, mi, int(STRIPS.smoke), c.smoke_time)
	tw.tween_property(mi, "position", pos + Vector3(0, c.smoke_rise, 0), c.smoke_time).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.25, c.smoke_time)
	tw.chain().tween_callback(mi.hide)

## Взрыв (enemies/blast.gd: Раздутый, элита «Взрывной», взрывная бочка, Свен): вместо плоского шара-диска —
## вспышка-ядро vfx_hit_flash, короткий огненный шар из языков vfx_fire, клубы тёмного дыма, ударная волна
## vfx_shockwave по полу на радиус урона (радиус читается), звёзды-искры. Всё — пулы и общие материалы FX.
static func explosion(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.45, 0.15)) -> void:
	Perf.mark("fx_explosion")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var hot := color.lerp(Color(1.0, 0.92, 0.7), 0.45)
	hit_flash(parent, pos, radius * c.explosion_flash, hot)
	var ground := pos
	var hit := _floor(_holder_for(parent), pos)
	if not hit.is_empty():
		ground = hit.position
	# Огненный шар: языки пламени вокруг центра, держатся explosion_fire_time и гаснут вместе с узлом
	if c.explosion_fire_time > 0.0:
		var ball := Node3D.new()
		ball.name = "ExplosionFire"
		ball.set_meta("transient", true)
		parent.add_child(ball)
		ball.global_position = ground
		ball.scale = Vector3.ONE * c.explosion_fire_scale
		fire_sprites(ball, maxf(radius * c.explosion_fire, 0.4), c.explosion_fire_time)
		var tw := ball.create_tween()
		tw.tween_property(ball, "scale", Vector3.ONE * c.explosion_fire_scale * 1.25, c.explosion_fire_time).set_ease(Tween.EASE_OUT)
		tw.tween_interval(c.fire_fade + 0.1)
		tw.tween_callback(ball.queue_free)
	for i in maxi(c.explosion_smoke, 0):
		var a := TAU * float(i) / maxf(c.explosion_smoke, 1) + randf_range(-0.5, 0.5)
		var off := Vector3(cos(a), randf_range(0.1, 0.5), sin(a)) * radius * 0.35
		smoke(parent, pos + off, radius * c.explosion_smoke_size * randf_range(0.85, 1.15), c.explosion_smoke_color)
	shockwave(parent, ground, radius, hot)
	for i in maxi(c.explosion_stars, 0):
		var off2 := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.8), randf_range(-1, 1)) * radius * 0.3
		spark_star(parent, pos + off2, hot, c.explosion_star_size * randf_range(0.8, 1.2))

## Дым взрыва (enemies/blast.gd): размер от радиуса.
static func blast_smoke(parent: Node, pos: Vector3, radius: float) -> void:
	var c := cfg()
	smoke(parent, pos, c.smoke_size + radius * c.smoke_per_radius, Color(0.7, 0.66, 0.62))

## Пыль разбитой бочки (run/barrel_watch.gd): дым коричневатого оттенка.
static func barrel_dust(parent: Node, pos: Vector3) -> void:
	smoke(parent, pos, cfg().barrel_dust_size, Color(0.78, 0.64, 0.48))

static var _last_glint_ms: int = -100000

## Блеск монеты серебра при вылете (run/silver_coin.gd): звёздочка vfx_sparks_*, не чаще cfg().coin_glint_interval.
static func coin_glint(parent: Node, pos: Vector3, color: Color) -> void:
	var c := cfg()
	var now := Time.get_ticks_msec()
	if now - _last_glint_ms < int(c.coin_glint_interval * 1000.0) or c.coin_glint_size <= 0.0:
		return
	_last_glint_ms = now
	spark_star(parent, pos + Vector3(0, 0.15, 0), color, c.coin_glint_size)

## «Пуф» исчезающего трупа (enemy.gd → _spawn_debris, когда тело сжимается).
static func corpse_smoke(body: Node3D) -> void:
	if body and is_instance_valid(body) and body.is_inside_tree():
		smoke(body.get_parent(), body.global_position + Vector3(0, 0.5, 0), cfg().smoke_size * 0.8)

## Языки пламени vfx_fire (петля 8 кадров) в зоне огня — дочерние узлы зоны, гаснут вместе с ней.
static func fire_sprites(zone: Node3D, radius: float, duration: float) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if zone == null:
		return out
	var c := cfg()
	var n := clampi(int(ceil(radius * c.fire_per_meter)), 1, maxi(c.fire_max, 1))
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = shared_mesh("quad_bottom")
		mi.material_override = sprite_material("fire")
		_track_fade(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		sprite_color(mi, Color.WHITE, 1.25)
		set_sprite(mi, float(randi() % int(STRIPS.fire)), 2, 0.0, c.fire_fps * randf_range(0.85, 1.15))
		var a := randf() * TAU
		var r := 0.0 if i == 0 else radius * sqrt(randf()) * 0.75
		mi.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := randf_range(c.fire_height.x, c.fire_height.y) * clampf(0.6 + radius * 0.25, 0.6, 1.3)
		mi.scale = Vector3.ONE * h
		mi.transparency = 1.0
		zone.add_child(mi)
		var tw := mi.create_tween()
		tw.tween_property(mi, "transparency", 0.0, c.fire_fade).set_delay(randf() * 0.1)
		if duration > c.fire_fade * 2.0:
			tw.tween_interval(maxf(duration - c.fire_fade * 2.0 - 0.1, 0.0))
			tw.tween_property(mi, "transparency", 1.0, c.fire_fade)
		out.append(mi)
	return out

## Текстурные ленты молнии от from до to (FX.lightning).
static func _lightning_ribbons(parent: Node, from: Vector3, to: Vector3, lifetime: float, color: Color) -> void:
	var c := cfg()
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var cam := _camera(parent)
	var eye := cam.global_position if cam else from + Vector3(0, 0, 5)
	var count := clampi(int(ceil(length / maxf(c.lightning_segment, 0.3))), 1, 12)
	var dir := (to - from) / length
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.1:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up2 := side.cross(dir).normalized()
	var pts: Array[Vector3] = [from]
	for i in range(1, count):
		var j := (side * randf_range(-1, 1) + up2 * randf_range(-1, 1)) * length / count * 0.18
		pts.append(from.lerp(to, float(i) / count) + j)
	pts.append(to)
	for i in count:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var l := seg.length()
		if l < 0.01:
			continue
		var mid := (a + b) * 0.5
		var x := seg.cross(eye - mid)
		if x.length() < 0.001:
			x = seg.cross(Vector3.UP)
		if x.length() < 0.001:
			x = seg.cross(Vector3.RIGHT)
		x = x.normalized() * l * c.lightning_width * (1.0 if randf() < 0.5 else -1.0)
		var z := x.cross(seg).normalized()
		var mi := _sprite("lightning", parent, random_variant("lightning"), mid, 1.0, color, 0, c.lightning_limit, "quad", c.lightning_energy)
		# Отрезки внахлёст: рисованная молния не доходит до краёв текстуры
		mi.transform = Transform3D(Basis(x, seg * c.lightning_overlap, z), mid)
		var tw := _tween(mi)
		var t := maxf(lifetime, 0.05)
		tw.tween_property(mi, "transparency", 0.55, t * 0.12)
		tw.tween_property(mi, "transparency", 0.0, t * 0.12)
		tw.tween_property(mi, "transparency", 1.0, t * 0.76).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.hide)

## Ударная волна vfx_shockwave по полу: кольцо растёт до радиуса удара и гаснет.
static func shockwave(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.92, 0.75)) -> void:
	Perf.mark("fx_shockwave")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var mi := _floor_sprite("shockwave", parent, "shockwave", pos, 1.0, color, c.shockwave_limit, 1.5)
	if mi == null:
		return
	var b := mi.basis.orthonormalized()
	mi.basis = b.scaled(Vector3.ONE * radius * 0.3)
	mi.transparency = c.shockwave_transparency
	var tw := _tween(mi)
	tw.set_parallel(true)
	tw.tween_property(mi, "basis", b.scaled(Vector3.ONE * radius * c.shockwave_scale), c.shockwave_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "transparency", 1.0, c.shockwave_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(mi.hide)

## Трещина на полу (vfx_crack_decal_small/medium/large — по высоте падения), лежит cfg().crack_life.
static func crack(parent: Node, pos: Vector3, height: float) -> void:
	Perf.mark("fx_crack")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var key := "crack_decal_small"
	var size := c.crack_sizes.x
	if height >= c.crack_large_height:
		key = "crack_decal_large"
		size = c.crack_sizes.z
	elif height >= c.crack_medium_height:
		key = "crack_decal_medium"
		size = c.crack_sizes.y
	var mi := _floor_sprite("crack", parent, key, pos, size, Color.WHITE, c.crack_limit)
	if mi == null:
		return
	mi.set_meta("crack", key)
	var tw := _tween(mi)
	tw.tween_interval(maxf(c.crack_life - c.crack_fade, 0.0))
	tw.tween_property(mi, "transparency", 1.0, maxf(c.crack_fade, 0.01))
	tw.tween_callback(mi.hide)

## Подпалина на полу (assets/decals/scorch): след огня (fire_zone.gd) и взрыва (blast.gd). Лежит, пока горит огонь
## (burn), и ещё cfg().scorch_life, потом исчезает. Пул cfg().scorch_limit — сверх него исчезает самая старая.
static func scorch(parent: Node, pos: Vector3, radius: float, burn: float = 0.0) -> void:
	Perf.mark("fx_scorch")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	if c.scorch_limit <= 0:
		return
	var size := clampf(radius * c.scorch_per_radius, c.scorch_size.x, c.scorch_size.y)
	var mi := _floor_sprite("scorch", parent, "scorch", pos, size, Color.WHITE, c.scorch_limit)
	if mi == null:
		return
	mi.transparency = c.scorch_transparency
	var tw := _tween(mi)
	tw.tween_interval(maxf(burn + c.scorch_life - c.scorch_fade, 0.0))
	tw.tween_property(mi, "transparency", 1.0, maxf(c.scorch_fade, 0.01))
	tw.tween_callback(mi.hide)

## Удар-приземление (player.gd → _do_slam_impact): волна по радиусу удара и трещина по высоте падения.
static func slam_impact(parent: Node, center: Vector3, radius: float, height: float) -> void:
	shockwave(parent, center, radius)
	crack(parent, center, height)

## Ледяная элита попала по Тору (enemies/elite/ice.gd): наледь под ногами на время замедления
## и кристаллы vfx_ice_shard_* вокруг — вырастают, стоят и уходят в пол.
static func ice_hit(parent: Node, pos: Vector3, duration: float) -> void:
	Perf.mark("fx_ice")
	if parent == null or not parent.is_inside_tree():
		return
	var c := cfg()
	var patch := _floor_sprite("ice_patch", parent, "ice_patch", pos, c.ice_patch_size, Color.WHITE, c.ice_patch_limit)
	if patch:
		var b := patch.basis
		patch.basis = b.scaled(Vector3.ONE * 0.5)
		var tw := _tween(patch)
		tw.tween_property(patch, "basis", b, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(maxf(duration - 0.4, 0.1))
		tw.tween_property(patch, "transparency", 1.0, 0.4)
		tw.tween_callback(patch.hide)
	var ground: Vector3 = patch.position if patch else pos
	var a0 := randf() * TAU
	for i in maxi(c.ice_shards, 0):
		var a := a0 + TAU * float(i) / maxf(c.ice_shards, 1) + randf_range(-0.4, 0.4)
		var p := ground + Vector3(cos(a), 0.0, sin(a)) * c.ice_shard_radius * randf_range(0.6, 1.0)
		var h := randf_range(c.ice_shard_height.x, c.ice_shard_height.y)
		var mi := _sprite("ice_shard", parent, random_variant("ice_shard"), p, h * 0.15, Color.WHITE, 2, c.ice_shard_limit, "quad_bottom")
		var tw := _tween(mi)
		tw.tween_property(mi, "scale", Vector3.ONE * h, c.ice_shard_grow).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(maxf(duration * c.ice_shard_stay, 0.1))
		tw.tween_property(mi, "scale", Vector3(h, h * 0.1, h), 0.25).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mi, "transparency", 1.0, 0.25)
		tw.tween_callback(mi.hide)

## Идеальный хват Мьёльнира (mjolnir_hand.gd): золотое кольцо vfx_perfect_catch на экране у руки.
static func perfect_catch(world_pos: Vector3) -> void:
	Perf.mark("fx_perfect_catch")
	if VfxScreen.instance and is_instance_valid(VfxScreen.instance):
		VfxScreen.instance.perfect_catch(world_pos)

## Нежить ли враг (брызги и пятна ихора): все, кроме смертных (Наёмник Локи) и ледяных (Йотунхейм).
## Переопределить — метаданные врага "ichor" (true/false).
static func is_undead(enemy: Node) -> bool:
	if enemy.has_meta("ichor"):
		return bool(enemy.get_meta("ichor"))
	if enemy.get("kind") == Enemy.Kind.MERC:
		return false
	var d := enemy.get("enemy_def") as EnemyDef
	return d == null or d.world != "jotunheim"

## Попадание по врагу (enemy.gd → take_hit): вспышка, у нежити — брызги ихора и пятно на полу.
static func enemy_hit(enemy: Node3D, damage: float, source: String, big: bool) -> void:
	if enemy == null or not enemy.is_inside_tree() or source == "fire" or damage <= 0.0:
		return
	var c := cfg()
	var parent := enemy.get_parent()
	var ms := minf(_model_scale(enemy), 2.0)
	var chest := enemy.global_position + Vector3(0, 1.1 * ms, 0)
	var ranged := source == "ranged"
	var size := c.hit_flash_size * ms * (c.hit_flash_big_mult if big else 1.0) * (c.hit_flash_ranged_mult if ranged else 1.0)
	var col := Color(1.0, 0.92, 0.7)
	if source in ["hammer", "lightning"]:
		col = Color(0.7, 0.9, 1.0)
	elif ranged:
		col = Color(1.0, 0.95, 0.85)
	hit_flash(parent, chest, size, col)
	if not is_undead(enemy):
		return
	var off := Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.2), randf_range(-0.25, 0.25))
	ichor_splash(parent, chest + off, randf_range(c.ichor_splash_size.x, c.ichor_splash_size.y) * ms * (1.3 if big else 1.0) * (0.7 if ranged else 1.0))
	if big or randf() < c.splat_chance:
		splat(parent, enemy.global_position + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)), randf_range(c.splat_size.x, c.splat_size.y) * ms)

## Смерть врага (enemy.gd → _die): у нежити — крупное пятно и брызги.
static func enemy_died(enemy: Node3D, _source: String) -> void:
	if enemy == null or not enemy.is_inside_tree() or not is_undead(enemy):
		return
	var c := cfg()
	var parent := enemy.get_parent()
	var ms := minf(_model_scale(enemy), 2.0)
	splat(parent, enemy.global_position, randf_range(c.splat_size.x, c.splat_size.y) * c.splat_death_mult * ms)
	ichor_splash(parent, enemy.global_position + Vector3(0, 0.9 * ms, 0), c.ichor_splash_size.y * 1.3 * ms)

static func _model_scale(enemy: Node) -> float:
	var s: Variant = enemy.get("model_scale")
	return float(s) if s != null else 1.0
