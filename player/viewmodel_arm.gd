extends Node3D
class_name ViewmodelArm
## Рука от первого лица (блок Б2): CC0-руки Drillimpact «PSX First Person Arms» (assets/arms/drillimpact_psx,
## одна сторона на узел — другая рука сжата в точку), кожа — своя текстура с татуировками (tools/make_arm_texture.py),
## кожаный наруч с обмоткой — процедурные меши на кости предплечья.
## Соглашение пивота оружия: этот узел = точка хвата (0,0,0), рукоять вдоль +Y, лезвие/боёк в -Z.
##
## Как стоит рука: кисть и предплечье жёстко держат хват (поза «кулак» из анимации пакета, наклон запястья —
## wrist_pitch / forearm_yaw), плечо тянется от локтя к якорю shoulder_anchor за краем кадра (в системе камеры рук),
## при нехватке длины плечо растягивается (до max_upper_stretch) — обреза руки в кадре не бывает.
## Модель — top_level под камерой рук; позу ставит update_pose() каждый кадр (после ViewmodelMotion).
## Пальцы: grip 1 — кулак (держит оружие), 0 — раскрытая ладонь; open_style — какая «ладонь» (push / grab / relax).

const RIG := "res://assets/arms/drillimpact_psx/arms_rig.glb"
const SKIN_TEX := "res://assets/arms/drillimpact_psx/thor_arm.png"
const FINGERS := ["palm.01", "f_index.01", "f_index.02", "f_index.03", "thumb.01", "thumb.02", "thumb.03",
	"palm.02", "f_middle.01", "f_middle.02", "f_middle.03", "palm.03", "f_ring.01", "f_ring.02", "f_ring.03",
	"palm.04", "f_pinky.01", "f_pinky.02", "f_pinky.03"]

@export_enum("right", "left") var side: String = "right"

@export_group("Размер и посадка")
## Масштаб всей руки (модель пакета — человек ~1.75 м)
@export var rig_scale: float = 1.7
## Кисть относительно руки (Тор — лапища)
@export var hand_scale: float = 1.3
## Предплечье: толще и чуть длиннее (равномерный масштаб сегмента)
@export var forearm_bulk: float = 1.3
## Плечо: толщина (равномерный масштаб сегмента, не меньше)
@export var upper_bulk: float = 1.35
## Плечо тянется не длиннее этого (×длина)
@export var max_upper_stretch: float = 1.8
## Куда уходит плечо (система камеры рук, для правой руки; левая — зеркально по X)
@export var shoulder_anchor: Vector3 = Vector3(0.55, -0.95, 0.05)
## Наклон предплечья вниз от кисти, градусов (вокруг поперечной оси хвата)
@export var wrist_pitch: float = 22.0
## Разворот предплечья вокруг рукояти, градусов (+ — локоть наружу)
@export var forearm_yaw: float = 35.0
## Сдвиг кулака относительно рукояти (система хвата; м в масштабе модели)
@export var grip_offset: Vector3 = Vector3(0.0, 0.0, 0.0)

@export_group("Пальцы")
## Поза «кулак» и «ладонь»: анимация пакета и доля её длины (у push/grab — суффикс стороны _R/_L)
@export var fist_anim: String = "guard_idle"
@export var fist_time: float = 0.3
@export var open_anim: String = "push"
@export var open_time: float = 0.5
@export var grab_anim: String = "grab"
@export var grab_time: float = 0.25
## Скорость сжатия/разжатия пальцев (1/с)
@export var grip_speed: float = 16.0

@export_group("Вид")
@export var skin_tint: Color = Color(0.86, 0.68, 0.56)
## Множитель цвета кожи поверх цвета тела (текстура нейтральная — здесь «загар»)
@export var skin_multiply: Color = Color(0.98, 0.82, 0.72)
## Наруч (цвет рукава тела); обмотка и заклёпки — общие материалы
@export var sleeve_tint: Color = Color(0.4, 0.26, 0.16)
## Наруч: от какой доли предплечья (0 — локоть, 1 — запястье) до какой; радиус — по вершинам меша
## предплечья ×bracer_fit (облегает руку, не проваливается)
@export var bracer_from: float = 0.42
@export var bracer_to: float = 0.9
@export var bracer_fit: float = 1.1
@export var layer: int = 2

## Оружие в кулаке (строится при запуске — см. WeaponMeshes.build)
@export var weapon_kind: String = ""
@export var weapon_offset: Vector3 = Vector3.ZERO
@export var weapon_rotation: Vector3 = Vector3.ZERO
@export var weapon_scale: float = 1.0
var weapon: Node3D

## 1 — кулак, 0 — ладонь (плавно идёт к grip_target)
var grip: float = 1.0
var grip_target: float = 1.0
## Какая раскрытая поза: 0 — ладонь (push), 1 — «хватающая» (grab)
var open_style: float = 0.0
## Дополнительный наклон запястья (град.), ставит ViewmodelMotion (замах, ловля)
var extra_wrist: Vector3 = Vector3.ZERO

var model: Node3D
var skeleton: Skeleton3D
var cam: Camera3D

var _b_shoulder := -1
var _b_upper := -1
var _b_fore := -1
var _b_hand := -1
var _b_other := -1
var _fingers: PackedInt32Array = []
var _fist: Array[Quaternion] = []
var _open: Array[Quaternion] = []
var _grab: Array[Quaternion] = []
## Опорная поза (кулак), система скелета
var _ref_shoulder: Transform3D
var _ref_upper: Transform3D
var _ref_fore: Transform3D
var _ref_hand: Transform3D
var _grip_ref: Transform3D
var _l1: float = 0.3
var _l2: float = 0.24
var _bracer: Node3D
var _skin_mesh: MeshInstance3D
var _last_grip: float = -1.0
var _last_style: float = -1.0

static var _rig_scene: PackedScene
static var _skin_mats: Dictionary = {}
static var _leather_mats: Dictionary = {}
static var _skin_mult: Color = Color(1, 1, 1)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# После ViewmodelMotion (он ставит пивоты), до отрисовки
	process_priority = 100
	build()

func build() -> void:
	if model:
		return
	if _rig_scene == null:
		_rig_scene = load(RIG) as PackedScene
	model = _rig_scene.instantiate() as Node3D
	model.name = "ArmModel"
	model.top_level = true
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var s := "R" if side == "right" else "L"
	var o := "L" if side == "right" else "R"
	_b_shoulder = skeleton.find_bone("shoulder." + s)
	_b_upper = skeleton.find_bone("upper_arm." + s)
	_b_fore = skeleton.find_bone("forearm." + s)
	_b_hand = skeleton.find_bone("hand." + s)
	_b_other = skeleton.find_bone("shoulder." + o)
	_fingers.clear()
	for f in FINGERS:
		_fingers.append(skeleton.find_bone("%s.%s" % [f, s]))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.layers = layer
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_skin_mesh = m
	var ap := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_open = _capture(ap, "%s_%s" % [open_anim, s], open_time)
	_grab = _capture(ap, "%s_%s" % [grab_anim, s], grab_time)
	_fist = _capture(ap, fist_anim, fist_time)
	# Опорная поза — кулак
	_ref_shoulder = skeleton.get_bone_global_pose(_b_shoulder)
	_ref_upper = skeleton.get_bone_global_pose(_b_upper)
	_ref_fore = skeleton.get_bone_global_pose(_b_fore)
	_ref_hand = skeleton.get_bone_global_pose(_b_hand)
	_l1 = _ref_upper.origin.distance_to(_ref_fore.origin)
	_l2 = _ref_fore.origin.distance_to(_ref_hand.origin)
	_grip_ref = _grip_frame()
	ap.stop()
	ap.active = false
	ap.queue_free()
	_build_bracer()
	_skin_mult = skin_multiply
	recolor(skin_tint, sleeve_tint)
	cam = _find_camera()
	if weapon_kind != "":
		set_weapon(weapon_kind, weapon_offset, weapon_rotation, weapon_scale)
	update_pose(0.0)

## Повороты пальцев позы anim в момент t (доля длины). Нет анимации — пустой массив (останется кулак).
func _capture(ap: AnimationPlayer, anim: String, t: float) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	if not ap.has_animation(anim):
		return out
	ap.play(anim)
	ap.seek(t * ap.current_animation_length, true)
	for b in _fingers:
		out.append(skeleton.get_bone_pose_rotation(b) if b >= 0 else Quaternion.IDENTITY)
	return out

## Система хвата в опорной позе: центр кулака, рукоять от мизинца к указательному, +Z — к локтю.
func _grip_frame() -> Transform3D:
	var s := "R" if side == "right" else "L"
	var k := Vector3.ZERO
	var m2 := Vector3.ZERO
	var m3 := Vector3.ZERO
	for f in ["f_index", "f_middle", "f_ring", "f_pinky"]:
		k += _bpos("%s.01.%s" % [f, s])
		m2 += _bpos("%s.02.%s" % [f, s])
		m3 += _bpos("%s.03.%s" % [f, s])
	k /= 4.0
	m2 /= 4.0
	m3 /= 4.0
	var center := (k + m2 + m3 + _ref_hand.origin.lerp(k, 0.8)) / 4.0
	var y := (_bpos("f_index.01." + s) - _bpos("f_pinky.01." + s)).normalized()
	var back := (_ref_fore.origin - _ref_hand.origin).normalized()
	var z := (back - y * back.dot(y)).normalized()
	var x := y.cross(z).normalized()
	var b := Basis(x, y, z)
	return Transform3D(b, center + b * grip_offset)

func _bpos(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	return skeleton.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO

func _find_camera() -> Camera3D:
	var n := get_parent()
	while n:
		if n is Camera3D:
			return n as Camera3D
		n = n.get_parent()
	return null

## true — позу ставит ViewmodelMotion (сразу после пивота), свой _process не нужен
var driven: bool = false

func _process(delta: float) -> void:
	if not driven:
		update_pose(delta)

## Ставит руку по текущему положению узла (точки хвата). delta — игровое время (замирает в hit-stop).
func update_pose(delta: float) -> void:
	if skeleton == null or not is_inside_tree():
		return
	if cam == null:
		cam = _find_camera()
	var cam_t := cam.global_transform if cam else get_parent_node_3d().global_transform
	model.global_transform = Transform3D(cam_t.basis.orthonormalized().scaled_local(Vector3.ONE * rig_scale), cam_t.origin)
	var sk_inv := skeleton.global_transform.affine_inverse()
	var g := sk_inv * global_transform
	g.basis = g.basis.orthonormalized()
	var hs := hand_scale
	var mirror := 1.0 if side == "right" else -1.0
	# Кисть: опорная поза относительно хвата
	var h_rel := _grip_ref.affine_inverse() * _ref_hand
	var f_rel := _grip_ref.affine_inverse() * _ref_fore
	var gs := g * Transform3D(Basis.from_scale(Vector3.ONE * hs), Vector3.ZERO)
	# Запястье: предплечье наклоняется вокруг точки запястья
	var wrist := h_rel.origin
	var rot := Basis(Vector3.UP, deg_to_rad((forearm_yaw + extra_wrist.y) * mirror)) \
		* Basis(Vector3.RIGHT, deg_to_rad(wrist_pitch + extra_wrist.x)) \
		* Basis(Vector3.BACK, deg_to_rad(extra_wrist.z * mirror))
	var fr := Transform3D(rot, wrist - rot * wrist) * f_rel
	var elbow := wrist + (fr.origin - wrist) * forearm_bulk
	var fore_g := Transform3D(fr.basis.orthonormalized().scaled_local(Vector3.ONE * forearm_bulk), elbow)
	var hand_s := gs * h_rel
	var fore_s := gs * fore_g
	# Плечо: от локтя к якорю за кадром
	var anchor := sk_inv * (cam_t * Vector3(shoulder_anchor.x * mirror, shoulder_anchor.y, shoulder_anchor.z))
	var e := fore_s.origin
	var to_e := e - anchor
	var dist := maxf(to_e.length(), 0.001)
	var l1 := _l1 * hs * forearm_bulk
	var su := clampf(dist / l1, upper_bulk, upper_bulk * max_upper_stretch)
	var joint := e - to_e / dist * l1 * su
	var r_align := _align(_ref_fore.origin - _ref_upper.origin, _ref_hand.origin - _ref_fore.origin,
		e - joint, hand_s.origin - e)
	var sc := hs * forearm_bulk * su
	var upper_s := Transform3D((r_align * _ref_upper.basis.orthonormalized()).scaled_local(Vector3.ONE * sc), joint)
	var shoulder_s := Transform3D((r_align * _ref_shoulder.basis.orthonormalized()).scaled_local(Vector3.ONE * sc),
		joint + r_align * (_ref_shoulder.origin - _ref_upper.origin) * sc)
	skeleton.set_bone_global_pose(_b_shoulder, shoulder_s)
	skeleton.set_bone_global_pose(_b_upper, upper_s)
	skeleton.set_bone_global_pose(_b_fore, fore_s)
	skeleton.set_bone_global_pose(_b_hand, hand_s)
	if _b_other >= 0:
		skeleton.set_bone_global_pose(_b_other, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), anchor))
	_update_fingers(delta)
	if _bracer:
		_bracer.global_transform = skeleton.global_transform * fore_s

## Поворот, переводящий опорные направления плеча и предплечья (a0, b0) в новые (a1, b1): плоскость локтя сохраняется.
static func _align(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3) -> Basis:
	var f0 := _frame(a0, b0)
	var f1 := _frame(a1, b1)
	return f1 * f0.transposed()

static func _frame(a: Vector3, b: Vector3) -> Basis:
	var x := a.normalized()
	var z := x.cross(b)
	if z.length() < 0.01:
		z = x.cross(Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT)
	z = z.normalized()
	return Basis(x, z.cross(x), z)

func _update_fingers(delta: float) -> void:
	if _fist.is_empty():
		return
	if delta > 0.0:
		grip = move_toward(grip, grip_target, delta * grip_speed * 0.25) if absf(grip - grip_target) < 0.05 \
			else lerpf(grip, grip_target, clampf(delta * grip_speed, 0.0, 1.0))
	elif delta == 0.0 and _last_grip < 0.0:
		grip = grip_target
	if is_equal_approx(grip, _last_grip) and is_equal_approx(open_style, _last_style):
		return
	_last_grip = grip
	_last_style = open_style
	for i in _fingers.size():
		var b := _fingers[i]
		if b < 0:
			continue
		var q := _fist[i]
		var open_q := _open[i] if i < _open.size() else q
		if open_style > 0.0 and i < _grab.size():
			open_q = open_q.slerp(_grab[i], open_style)
		skeleton.set_bone_pose_rotation(b, open_q.slerp(q, grip))

# --- Наруч ---

static var _cyl_mesh: CylinderMesh

func _build_bracer() -> void:
	_bracer = Node3D.new()
	_bracer.name = "Bracer"
	_bracer.top_level = true
	add_child(_bracer)
	# В системе кости предплечья: +Y — от локтя к запястью; меши — от bracer_from до bracer_to
	var a := _l2 * bracer_from
	var b := _l2 * bracer_to
	var fit := _fit_forearm(a, b)
	var c: Vector2 = fit[0]
	var r0: Vector2 = fit[1] * bracer_fit  # у локтя
	var r1: Vector2 = fit[2] * bracer_fit  # у запястья
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 1.0
	cyl.top_radius = clampf(r1.x / maxf(r0.x, 0.001), 0.5, 1.2)
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	var mid := (a + b) * 0.5
	_bracer_part("Leather", cyl, Vector3(r0.x, b - a, r0.y), Vector3(c.x, mid, c.y), null)
	if _cyl_mesh == null:
		_cyl_mesh = CylinderMesh.new()
		_cyl_mesh.top_radius = 1.0
		_cyl_mesh.bottom_radius = 1.0
		_cyl_mesh.height = 1.0
		_cyl_mesh.radial_segments = 12
		_cyl_mesh.rings = 1
	# Обмотка у запястья, посередине и кант у локтя — тёмная кожа; заклёпки — железо
	var dark := _leather("dark")
	_bracer_part("WrapWrist", _cyl_mesh, Vector3(r1.x * 1.07, _l2 * 0.07, r1.y * 1.07), Vector3(c.x, b - _l2 * 0.03, c.y), dark)
	var rm := (r0 + r1) * 0.5
	_bracer_part("WrapMid", _cyl_mesh, Vector3(rm.x * 1.05, _l2 * 0.04, rm.y * 1.05), Vector3(c.x, mid, c.y), dark)
	_bracer_part("WrapElbow", _cyl_mesh, Vector3(r0.x * 1.05, _l2 * 0.06, r0.y * 1.05), Vector3(c.x, a + _l2 * 0.03, c.y), dark)
	for k in 4:
		var ang := PI * 0.5 * k + PI * 0.25
		var stud := MeshInstance3D.new()
		stud.mesh = FX.shared_mesh("sphere")
		stud.material_override = WeaponMeshes.mat("iron")
		stud.layers = layer
		stud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var y := lerpf(a, b, 0.72)
		var r := r0.lerp(r1, 0.72)
		stud.position = Vector3(c.x + sin(ang) * r.x, y, c.y + cos(ang) * r.y)
		stud.scale = Vector3.ONE * (r.x + r.y) * 0.16
		_bracer.add_child(stud)

## Сечение предплечья по вершинам меша (в системе кости предплечья, опорная поза): центр (x,z) и полуоси
## у локтя и у запястья на участке [a, b] по длине кости.
func _fit_forearm(a: float, b: float) -> Array:
	var fallback := [Vector2.ZERO, Vector2(0.045, 0.045), Vector2(0.036, 0.036)]
	if _skin_mesh == null or _skin_mesh.skin == null:
		return fallback
	var skin := _skin_mesh.skin
	var bind := -1
	for i in skin.get_bind_count():
		var bn := skin.get_bind_name(i)
		var bi := skin.get_bind_bone(i)
		if (bn != "" and skeleton.find_bone(bn) == _b_fore) or (bn == "" and bi == _b_fore):
			bind = i
	if bind < 0:
		return fallback
	var arr := _skin_mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(1, verts.size())
	var inv := skin.get_bind_pose(bind)
	var pts: Array[Vector3] = []
	var center := Vector2.ZERO
	for v in verts.size():
		# Вершина принадлежит предплечью, если его вес самый большой
		var best := -1
		var bw := 0.0
		for j in per:
			if weights[v * per + j] > bw:
				bw = weights[v * per + j]
				best = bones[v * per + j]
		if best != bind:
			continue
		var p := inv * verts[v]
		if p.y < a or p.y > b:
			continue
		pts.append(p)
		center += Vector2(p.x, p.z)
	if pts.size() < 6:
		return fallback
	center /= pts.size()
	var r0 := Vector2(0.01, 0.01)
	var r1 := Vector2(0.01, 0.01)
	var mid := (a + b) * 0.5
	for p in pts:
		var d := Vector2(absf(p.x - center.x), absf(p.z - center.y))
		if p.y < mid:
			r0 = r0.max(d)
		else:
			r1 = r1.max(d)
	return [center, r0, r1]

func _bracer_part(nm: String, mesh: Mesh, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = size
	_bracer.add_child(mi)

## Общий материал кожи (наруча) цвета key: "dark" — обмотка, иначе цвет рукава тела.
static func _leather(key: Variant) -> StandardMaterial3D:
	var k := str(key)
	if _leather_mats.has(k):
		return _leather_mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.17, 0.11, 0.07) if k == "dark" else (key as Color)
	m.roughness = 0.65
	_leather_mats[k] = m
	return m

static func _skin(c: Color) -> StandardMaterial3D:
	c = Color(c.r * _skin_mult.r, c.g * _skin_mult.g, c.b * _skin_mult.b)
	var k := c.to_html()
	if _skin_mats.has(k):
		return _skin_mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(SKIN_TEX)
	m.albedo_color = c
	m.roughness = 0.75
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 0.8
	_skin_mats[k] = m
	return m

## Перекраска кожи и наруча (смена тела). Материалы общие на цвет — новых на каждое действие нет.
func recolor(c: Color, sleeve: Color) -> void:
	if model == null:
		build()
		return
	if _skin_mesh:
		_skin_mesh.material_override = _skin(c)
	var lm := _leather(sleeve if sleeve.a > 0.0 else sleeve_tint)
	if _bracer:
		var leather := _bracer.get_node_or_null("Leather") as MeshInstance3D
		if leather:
			leather.material_override = lm

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

## Показать/спрятать оружие в кулаке (молот улетел — рука пустая).
func set_weapon_visible(on: bool) -> void:
	if weapon and is_instance_valid(weapon):
		weapon.visible = on
