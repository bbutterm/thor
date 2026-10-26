extends Node3D
class_name ViewmodelArm
## Рука от первого лица: настоящая рука персонажа Quaternius (рукав, наруч, кисть), застывшая
## в позе хвата и выровненная так, что оружие (дочерний узел пивота) лежит у неё в кулаке.
## Соглашение пивота оружия: точка хвата = (0,0,0), рукоять вдоль +Y, лезвие/боёк в -Z.
##
## Поменять руку (например, на Synty): замени parts / pose или положи вместо этого узла свою модель руки.

@export_enum("right", "left") var side: String = "right"
@export var parts: PackedStringArray = ["parts/Male_Ranger_Arms.gltf"]
@export var sleeve_tint: Color = Color(0.72, 0.58, 0.45)
@export var skin_tint: Color = Color(0.95, 0.85, 0.78)
## Поза кисти (кулак) — кадр из библиотеки анимаций.
@export var pose_anim: String = "Sword_Idle"
@export var pose_time: float = 0.3
## Куда (в системе пивота) идёт предплечье от кисти к локтю: назад к камере и вниз.
@export var forearm_dir: Vector3 = Vector3(0.25, -0.55, 0.8)
## Сдвиг кулака вдоль рукояти (м, в масштабе модели)
@export var grip_offset: float = 0.02
## Наклон предплечья вниз, градусов
@export var wrist_pitch: float = 35.0
@export var layer: int = 2
## Оружие в кулаке (строится при запуске — см. WeaponMeshes.build)
@export var weapon_kind: String = ""
@export var weapon_offset: Vector3 = Vector3.ZERO
@export var weapon_rotation: Vector3 = Vector3.ZERO
@export var weapon_scale: float = 1.0
var weapon: Node3D

var model: HumanoidModel

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	build()

func build() -> void:
	if model:
		return
	model = HumanoidModel.new()
	model.outfit = ""
	model.parts = parts
	var tints: Array[Color] = []
	for i in parts.size():
		tints.append(sleeve_tint)
	model.part_tints = tints
	model.skin_tint = skin_tint
	model.arm_only = side
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.layers = layer
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.play(pose_anim, 0.0)
	model.anim.seek(pose_time, true)
	model.anim.pause()
	# Анимация застыла; отключаем её, чтобы поза не перезаписывалась, и сжимаем пальцы
	model.anim.active = false
	_make_fist()
	_align()
	if weapon_kind != "":
		weapon = WeaponMeshes.build(weapon_kind, layer)
		weapon.name = "Weapon"
		weapon.position = weapon_offset
		weapon.rotation_degrees = weapon_rotation
		weapon.scale = Vector3.ONE * weapon_scale
		add_child(weapon)

## Сжатые пальцы: у позы кулак только в правой руке — для левой зеркалим вращения пальцев правой.
func _make_fist() -> void:
	var sk := model.skeleton
	if side != "left":
		return
	for f in ["index", "middle", "ring", "pinky", "thumb"]:
		for n in ["01", "02", "03"]:
			var r := sk.find_bone("%s_%s_r" % [f, n])
			var l := sk.find_bone("%s_%s_l" % [f, n])
			if r < 0 or l < 0:
				continue
			var q := sk.get_bone_pose_rotation(r)
			sk.set_bone_pose_rotation(l, Quaternion(q.x, -q.y, -q.z, q.w))

## Ставит модель так, чтобы кулак оказался в начале координат, а рукоять — вдоль +Y.
func _align() -> void:
	var sk := model.skeleton
	var s := "r" if side == "right" else "l"
	var hand := _bone_pos(sk, "hand_" + s)
	var elbow := _bone_pos(sk, "lowerarm_" + s)
	var mid := _bone_pos(sk, "middle_01_" + s)
	var thumb := _bone_pos(sk, "thumb_01_" + s)
	var index := _bone_pos(sk, "index_01_" + s)
	var pinky := _bone_pos(sk, "pinky_01_" + s)
	# Центр кулака — между основаниями пальцев и ладонью
	var fist := hand.lerp(mid, 0.75)
	var back := (elbow - hand).normalized()            # от кисти к локтю
	# Ось рукояти проходит сквозь кулак: от мизинца к указательному пальцу
	var handle := (index - pinky).normalized()
	handle = (handle - back * handle.dot(back)).normalized()
	if handle.length() < 0.1:
		handle = (thumb - hand).normalized()
	# Рукоять «вверх» — противоположно направлению к локтю по вертикали пивота
	var y := handle
	var x := y.cross(back).normalized()
	var z := x.cross(y).normalized()
	if back.dot(z) < 0.0:
		x = -x
		z = -z
	var grip := Transform3D(Basis(x, y, z), fist + y * grip_offset)
	# Хотим: grip → единичная матрица в пивоте, а «назад» (к локтю) → forearm_dir.
	# Крутим только вокруг рукояти (Y), чтобы оружие осталось как было.
	var target_back := forearm_dir.normalized()
	var cur_back := grip.basis.inverse() * back
	var cb := Vector3(cur_back.x, 0, cur_back.z).normalized()
	var tb := Vector3(target_back.x, 0, target_back.z).normalized()
	var yaw := atan2(cb.cross(tb).y, cb.dot(tb))
	var fix := Basis(Vector3.UP, yaw)
	# Наклон кисти: предплечье уходит вниз к камере (поворот вокруг оси X пивота через кулак)
	var side_axis := Vector3(target_back.z, 0, -target_back.x).normalized()
	fix = Basis(side_axis, deg_to_rad(wrist_pitch)) * fix
	model.transform = Transform3D(fix, Vector3.ZERO) * grip.affine_inverse()

## Перекраска кожи и рукава (смена тела).
func recolor(skin: Color, sleeve: Color) -> void:
	if model == null:
		build()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible:
			continue
		for sidx in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(sidx) as BaseMaterial3D
			if src == null:
				continue
			var nm := src.resource_name.to_lower()
			var is_skin := HumanoidModel.is_skin_material(src)
			if not is_skin and sleeve.a <= 0.0:
				continue
			var c := src.duplicate() as BaseMaterial3D
			c.albedo_color = skin if is_skin else sleeve
			m.set_surface_override_material(sidx, c)

static func _bone_pos(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	if i < 0:
		return Vector3.ZERO
	return sk.get_bone_global_pose(i).origin

# --- Смена оружия в кулаке (этап 1: слоты оружия) ---
var _weapon_cache: Dictionary = {}

## Показать в кулаке оружие kind (WeaponMeshes.build). Построенные модели кешируются и переиспользуются,
## чтобы свитч не собирал меши заново. Возвращает узел оружия.
func set_weapon(kind: String, offset: Vector3, rot_deg: Vector3, scl: float) -> Node3D:
	if model == null:
		build()
	if weapon and is_instance_valid(weapon):
		if _weapon_cache.values().has(weapon):
			weapon.visible = false
		else:
			weapon.queue_free()
	var w: Node3D = _weapon_cache.get(kind)
	if w == null or not is_instance_valid(w):
		w = WeaponMeshes.build(kind, layer)
		w.name = "Weapon_" + kind
		add_child(w)
		_weapon_cache[kind] = w
	w.visible = true
	w.position = offset
	w.rotation_degrees = rot_deg
	w.scale = Vector3.ONE * scl
	weapon = w
	weapon_kind = kind
	return w
