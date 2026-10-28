extends RefCounted
class_name Outline
## Комиксовая чёрная обводка (GDD 20, решение владельца GDD 26 п. 5): враги и боссы, оружие на полу,
## сундуки, ящики патронов, бочки и ящики (Destructible), Мьёльнир в мире. Стены и декор — без обводки.
##
## Как: один общий ShaderMaterial (shaders/outline.gdshader — «вывернутая оболочка») в material_overlay узла.
## Слот оверлея у врагов делит со вспышкой урона (shaders/hit_flash.tres): пока вспышка горит, оверлей —
## материал вспышки, а обводка — его next_pass (Enemy._set_overlay берёт Outline.overlay() вместо null).
## В GL у каждого врага отдельный материал вспышки с обычными uniform, у всех частей врага он общий.
## Шейдер без instance uniform сам не требует новых параметров; прежний блок узла может сохраняться до удаления RID.
## Толщина и цвет — uniform общего материала,
## смена настройки — без компиляции. Прогрев — ShaderWarmup (warming = true: образцы с обводкой при любой настройке).
##
## API: add(root) — обвести все меши под root (кроме глаз/бровей), add_meshes(list), overlay() — что класть в
## material_overlay, когда своего нет; apply_settings() — из GameSettings (вкл/выкл и толщина вживую).
## Числа — data/outline_tuning.tres (OutlineTuning).

const SHADER := preload("res://shaders/outline.gdshader")
const TUNING_PATH := "res://data/outline_tuning.tres"
## Группа обведённых мешей: по ней переключается настройка
const GROUP := &"outlined"
## Множитель толщины из настроек
const WIDTH_MIN := 0.5
const WIDTH_MAX := 2.0

static var _material: ShaderMaterial
static var _cfg: OutlineTuning
static var _on: bool = true
static var _room_width_multiplier: float = 1.0
static var _settings_read: bool = false
## Прогрев (ShaderWarmup): образцы получают обводку, даже если она выключена — включение потом без компиляции
static var warming: bool = false

static func cfg() -> OutlineTuning:
	if _cfg == null:
		_cfg = load(TUNING_PATH) as OutlineTuning if ResourceLoader.exists(TUNING_PATH) else null
		if _cfg == null:
			_cfg = OutlineTuning.new()
	return _cfg

## Единственный материал обводки на всю игру (живёт вечно — пайплайны не выкидываются)
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.resource_name = "outline"
		_push_params()
	return _material

static func _push_params() -> void:
	var c := cfg()
	_material.set_shader_parameter("outline_color", c.color)
	_material.set_shader_parameter("width_px", c.width_px * _room_width_multiplier)
	_material.set_shader_parameter("near_dist", c.near_dist)
	_material.set_shader_parameter("min_scale", c.min_scale)
	_material.set_shader_parameter("depth_push", c.depth_push)
	_material.set_shader_parameter("width_scale", width_scale())

## Сохраняет пользовательский width_scale: профиль зала меняет только базовую толщину.
static func set_room_width_multiplier(multiplier: float) -> void:
	_room_width_multiplier = clampf(multiplier, 0.5, 2.0)
	if _material != null:
		_material.set_shader_parameter("width_px", cfg().width_px * _room_width_multiplier)

static func _read_settings() -> void:
	if _settings_read:
		return
	_settings_read = true
	_on = bool(GameSettings.get_value("video", "outline"))

static func enabled() -> bool:
	_read_settings()
	return _on

static func width_scale() -> float:
	return clampf(float(GameSettings.get_value("video", "outline_width")), WIDTH_MIN, WIDTH_MAX)

## Что положить в material_overlay обведённого узла, когда своего оверлея нет
static func overlay() -> Material:
	return material() if enabled() or warming else null

## Обвести все меши под root (и сам root, если это меш). Глаза и брови (Eye*) — нет: крошечные.
static func add(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		_add_one(root as GeometryInstance3D)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		_add_one(n as GeometryInstance3D)

static func add_meshes(list: Array) -> void:
	for g in list:
		if g is MeshInstance3D and is_instance_valid(g):
			_add_one(g as GeometryInstance3D)

static func _add_one(gi: GeometryInstance3D) -> void:
	if gi.name.begins_with("Eye"):
		return
	gi.add_to_group(GROUP)
	# Чужой оверлей (вспышка врага) не трогаем: обводка у него в next_pass
	if gi.material_overlay == null or gi.material_overlay == _material:
		gi.material_overlay = overlay()

## Убрать обводку с узла (и из группы)
static func remove(root: Node) -> void:
	if root == null:
		return
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.append(root)
	for n in list:
		var gi := n as GeometryInstance3D
		if gi.is_in_group(GROUP):
			gi.remove_from_group(GROUP)
			if gi.material_overlay == _material:
				gi.material_overlay = null

## Настройки игрока → материал и все обведённые узлы (вызывает GameSettings при изменении [video] outline*)
static func apply_settings() -> void:
	_settings_read = true
	_on = bool(GameSettings.get_value("video", "outline"))
	var m := material()
	m.set_shader_parameter("width_scale", width_scale())
	# Обводка во время вспышки урона/свечения элиты
	_flash().next_pass = m if _on else null
	_sync_gl_flash_passes()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var ov := overlay()
	for n in tree.get_nodes_in_group(GROUP):
		var gi := n as GeometryInstance3D
		if gi == null or (gi.material_overlay != null and gi.material_overlay != _material):
			# Свой оверлей узла (в том числе вспышку врага) нельзя заменять настройкой.
			continue
		gi.material_overlay = ov

## Общий оверлей вспышки врагов (shaders/hit_flash.tres): обводка — его next_pass.
## Только через эту функцию: «Enemy.FLASH_MATERIAL.next_pass» GDScript сворачивает как константу при компиляции
## (читается null навсегда), а присвоить свойство константе нельзя вовсе.
static func flash_next_pass() -> Material:
	return _flash().next_pass

static func _flash() -> ShaderMaterial:
	return Enemy.FLASH_MATERIAL

## GL-материалы принадлежат врагам, а не одному общему ресурсу. Меняем next_pass
## только у активных оверлеев и только раз на материал; при следующем включении
## неактивный материал синхронизируется с _flash() в Enemy._set_overlay.
static func _sync_gl_flash_passes() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var seen := {}
	for n in tree.get_nodes_in_group(GROUP):
		var gi := n as GeometryInstance3D
		if gi == null:
			continue
		var m := gi.material_overlay as ShaderMaterial
		if m == null or m.shader != Enemy.FLASH_GL_SHADER or seen.has(m.get_instance_id()):
			continue
		seen[m.get_instance_id()] = true
		m.next_pass = _flash().next_pass

static func is_flash(m: Material) -> bool:
	if m == _flash():
		return true
	var shader_material := m as ShaderMaterial
	return shader_material != null and shader_material.shader == Enemy.FLASH_GL_SHADER

## Прогрев: обводка на образцах (и в next_pass вспышки) при любой настройке — до end_warmup()
static func begin_warmup() -> void:
	warming = true
	_flash().next_pass = material()
	_sync_gl_flash_passes()

static func end_warmup() -> void:
	warming = false
	_flash().next_pass = material() if enabled() else null
	_sync_gl_flash_passes()

## Сколько узлов сейчас рисуют обводку (тесты, F3)
static func active_count(root: Node = null) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var n := 0
	for g in tree.get_nodes_in_group(GROUP):
		var gi := g as GeometryInstance3D
		if gi == null or (root and not root.is_ancestor_of(gi)):
			continue
		if gi.material_overlay == _material or (is_flash(gi.material_overlay) and gi.material_overlay.next_pass == _material):
			n += 1
	return n
