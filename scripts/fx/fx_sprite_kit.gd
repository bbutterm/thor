extends RefCounted
class_name FXSpriteKit
## VFX-комплект владельца (sprites/vfx/*): числа, материал на текстуру, прогрев, пулы узлов FXSprites,
## параметры экземпляра (кадр, billboard, поворот), спрайты на полу.
## Модуль фасада FX (этап 5 рефакторинга): только static-функции; состояние, константы и вызовы снаружи — через FX.

## Настройки VFX (data/vfx_tuning.tres; нет файла — значения по умолчанию).
static func cfg() -> VfxTuning:
	if FX._cfg == null:
		if ResourceLoader.exists(FX.TUNING_PATH):
			FX._cfg = load(FX.TUNING_PATH) as VfxTuning
		if FX._cfg == null:
			FX._cfg = VfxTuning.new()
	return FX._cfg

## Все ключи текстурных эффектов (для прогрева и тестов).
static func sprite_keys() -> PackedStringArray:
	var out := PackedStringArray(FX.STRIPS.keys())
	for v in FX.VARIANTS:
		for i in int(FX.VARIANTS[v]):
			out.append(variant_key(v, i))
	out.append_array(PackedStringArray(FX.SINGLES))
	out.append_array(PackedStringArray(FX.EXTRA_SPRITES.keys()))
	return out

static func variant_key(set_name: String, i: int) -> String:
	return "%s_%02d" % [set_name, i + 1]

static func random_variant(set_name: String) -> String:
	return variant_key(set_name, randi() % int(FX.VARIANTS.get(set_name, 1)))

## Общий материал текстуры vfx_<key>.webp. Создаётся один раз и не умирает (иначе выкинутся пайплайны).
static func sprite_material(key: String) -> ShaderMaterial:
	if FX._sprite_mats.has(key):
		return FX._sprite_mats[key]
	var m := ShaderMaterial.new()
	m.shader = FX.SPRITE_SHADER
	var path: String = FX.EXTRA_SPRITES.get(key, FX.VFX_DIR + "vfx_" + key + ".webp")
	if ResourceLoader.exists(path):
		m.set_shader_parameter("tex", load(path))
	m.set_shader_parameter("grid", Vector2(float(FX.STRIPS.get(key, 1)), 1.0))
	FX._sprite_mats[key] = m
	FX.materials_created += 1
	return m

## Все созданные материалы текстурных эффектов (тесты).
static func sprite_materials() -> Array:
	return FX._sprite_mats.values()

## Прогрев: по квадрату каждой текстуры перед камерой (ShaderWarmup, экран затемнён) во всех режимах billboard.
static func warmup_sprites(parent: Node3D, center: Vector3, right: Vector3) -> void:
	# Материалы — все сразу (создание материала и загрузка текстуры — здесь, не в бою); рисовать хватит
	# трёх квадов: шейдер один, пайплайн один на вид меша, а буфер instance-переменных не резиновый
	for key in sprite_keys():
		sprite_material(key)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = FXShared.shared_mesh(["quad", "quad_bottom", "quad_floor"][i])
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
	if FX._holder and is_instance_valid(FX._holder) and FX._holder.is_inside_tree() and not FX._holder.is_queued_for_deletion():
		return FX._holder
	FX._pools.clear()
	FX._holder = Node3D.new()
	FX._holder.name = "FXSprites"
	FX._holder.top_level = true
	FX._holder.set_meta("transient", true)
	parent.add_child(FX._holder)
	return FX._holder

## Сколько узлов в пуле вида kind (тесты: не больше лимита).
static func pool_size(kind: String) -> int:
	var pool: Array = FX._pools.get(kind, [])
	return pool.filter(func(n: Variant) -> bool: return is_instance_valid(n)).size()

## Сколько эффектов вида kind сейчас видно.
static func pool_active(kind: String) -> int:
	var pool: Array = FX._pools.get(kind, [])
	return pool.filter(func(n: Variant) -> bool: return is_instance_valid(n) and (n as Node3D).visible).size()

## Узлы пула вида kind (тесты).
static func pool_nodes(kind: String) -> Array:
	var pool: Array = FX._pools.get(kind, [])
	return pool.filter(func(n: Variant) -> bool: return is_instance_valid(n))

## Узел из пула: свободный, новый (пока меньше limit) или самый старый (его эффект обрывается).
static func _take(kind: String, parent: Node, limit: int) -> MeshInstance3D:
	var h := _holder_for(parent)
	var pool: Array = FX._pools.get(kind, [])
	pool = pool.filter(func(n: Variant) -> bool: return is_instance_valid(n))
	FX._pools[kind] = pool
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
	mi.mesh = FXShared.shared_mesh(mesh)
	mi.material_override = sprite_material(key)
	FXShared._track_fade(mi)
	sprite_color(mi, color, energy)
	set_sprite(mi, 0.0, billboard)
	mi.position = pos
	mi.scale = Vector3.ONE * maxf(size, 0.001)
	return mi

## Общий материал текстурного эффекта key узлу не из пула (лужа браги и т. п.): оттенок, кадр 0, без billboard.
static func sprite_apply(gi: GeometryInstance3D, key: String, color: Color = Color.WHITE, energy: float = 1.0) -> void:
	gi.material_override = sprite_material(key)
	FXShared._track_fade(gi)
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
