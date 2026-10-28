extends Node3D
class_name HazardZone
## Опасная зона на полу (GDD 12.6, «void zone»): круг / линия / конус.
## Телеграф: контур сразу во весь размер, заливка растёт telegraph секунд, звук начала → удар
## (урон Тору, если он внутри и стоит на полу: прыжок спасает, рывок — неуязвимость) →
## по желанию лужа на puddle_time секунд (урон puddle_dps и/или замедление, пока стоишь в ней).
## Всё на общих мешах и материалах эффектов (FX.shared_mesh, FX.fx_apply "alpha"/"alpha_nocull"),
## цвет и прозрачность — на экземпляре: новая зона не создаёт материал (правило фризов).
## Лимит одновременных зон на зал — Room.max_zones (EnemyRangedAttacks.can_add_zone); отражения нет.

enum Shape { CIRCLE, LINE, CONE }

var shape: Shape = Shape.CIRCLE
## Круг и конус: радиус (м). Линия: длина (м) по +Z узла.
var radius: float = 3.0
## Линия: ширина (м)
var width: float = 1.6
## Конус: половина угла (градусы)
var half_angle_deg: float = 35.0
## Сколько секунд заполняется контур до удара (GDD 12.6: 0.8–1.2)
var telegraph: float = 1.0
## Урон удара (0 — зона только лужа)
var damage: float = 15.0
var knock: float = 6.0
## Лужа после удара: секунды, урон в секунду и замедление (множитель скорости; 1 — без замедления)
var puddle_time: float = 0.0
var puddle_dps: float = 0.0
var puddle_slow: float = 1.0
var puddle_tick: float = 0.5
var color: Color = Color(1.0, 0.3, 0.15)
## Кто поставил (для причины смерти Тора и сигнала элиты) и запасной id
var source_node: Node = null
var source_id: String = "hazard"
## Ноги Тора выше зоны на столько — удар его не достаёт (прыжок спасает)
const JUMP_CLEARANCE := 0.45
## Тор на другом ярусе (ниже/выше больше этого) — не задевает
const TIER_LIMIT := 1.6

signal struck(hit_player: bool)

var _t: float = 0.0
var _struck := false
var _tick_t: float = 0.0
var _outline: MeshInstance3D
var _base: MeshInstance3D
var _fill: MeshInstance3D

static func make(shape_: Shape, pos: Vector3, facing: Vector3, size: float, telegraph_: float, damage_: float, color_: Color, source: Node = null) -> HazardZone:
	var z := HazardZone.new()
	z.shape = shape_
	z.radius = size
	z.telegraph = telegraph_
	z.damage = damage_
	z.color = color_
	z.source_node = source
	z.set_meta("_pos", pos)
	z.set_meta("_facing", facing)
	return z

## Поставить зону в parent (точка ставится на пол под pos).
func place(parent: Node) -> HazardZone:
	Perf.mark("hazard_zone")
	parent.add_child(self)
	var pos: Vector3 = get_meta("_pos", Vector3.ZERO)
	global_position = Loot.floor_point(self, pos) + Vector3(0, 0.05, 0)
	var f: Vector3 = get_meta("_facing", Vector3.FORWARD)
	f.y = 0.0
	if f.length() > 0.01:
		rotation.y = atan2(f.x, f.z)
	return self

func _ready() -> void:
	add_to_group("hazard_zones")
	set_meta("transient", true)
	match shape:
		Shape.CIRCLE:
			_outline = _mesh("ring", "alpha", Color(color, 0.95), 2.2)
			_outline.scale = Vector3(radius, 0.4, radius)
			_base = _mesh("disc", "alpha", Color(color, 0.22), 1.0)
			_base.scale = Vector3(radius, 0.02, radius)
			_fill = _mesh("disc", "alpha", Color(color, 0.7), 1.6)
		Shape.LINE:
			_outline = _mesh("box", "alpha", Color(color, 0.25), 1.2)
			_outline.scale = Vector3(width, 0.02, radius)
			_outline.position = Vector3(0, 0, radius * 0.5)
			_base = _mesh("box", "alpha", Color(color, 0.9), 2.2)
			_base.scale = Vector3(width + 0.2, 0.01, 0.12)
			_fill = _mesh("box", "alpha", Color(color, 0.7), 1.6)
		Shape.CONE:
			var sx := tan(deg_to_rad(clampf(half_angle_deg, 5.0, 80.0)))
			_outline = _mesh("wedge", "alpha_nocull", Color(color, 0.25), 1.2)
			_outline.scale = Vector3(radius * sx, 1.0, radius)
			_base = _mesh("ring", "alpha", Color(color, 0.9), 2.2)
			_base.scale = Vector3(0.35, 0.4, 0.35)
			_fill = _mesh("wedge", "alpha_nocull", Color(color, 0.7), 1.6)
			_fill.set_meta("sx", sx)
	_fill.position.y = 0.01
	_apply_fill(0.0)
	if has_meta("_warmup"):
		remove_from_group("hazard_zones")
	elif telegraph > 0.0:
		Audio.sfx("hazard_warn", "sounds/sfx/hazard_warn.wav")
	else:
		_strike()

func _mesh(mesh_kind: String, mat_kind: String, c: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = FX.shared_mesh(mesh_kind)
	FX.fx_apply(mi, mat_kind, c, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi

## Доля заполнения контура (0…1).
func progress() -> float:
	return 1.0 if _struck else clampf(_t / maxf(telegraph, 0.01), 0.0, 1.0)

func is_puddle() -> bool:
	return _struck and puddle_time > 0.0

func _apply_fill(k: float) -> void:
	var e := maxf(k, 0.04)
	match shape:
		Shape.CIRCLE:
			_fill.scale = Vector3(radius * e, 0.03, radius * e)
		Shape.LINE:
			_fill.scale = Vector3(width, 0.03, radius * e)
			_fill.position.z = radius * e * 0.5
		Shape.CONE:
			var sx: float = _fill.get_meta("sx", 1.0)
			_fill.scale = Vector3(radius * sx * e, 1.0, radius * e)
	# Заливка гуще к удару
	_fill.transparency = lerpf(0.75, 0.3, k)

func _physics_process(delta: float) -> void:
	_t += delta
	if not _struck:
		var k := progress()
		_apply_fill(k)
		# Контур мигает чаще к удару
		_outline.transparency = 0.15 + 0.25 * (0.5 + 0.5 * sin(_t * (8.0 + 26.0 * k)))
		if _t >= telegraph:
			_strike()
		return
	var left := puddle_time - (_t - telegraph)
	if left <= 0.0:
		queue_free()
		return
	# Лужа: заливка пульсирует, последнюю секунду тает
	var fade := clampf(1.0 - left, 0.0, 1.0)
	_fill.transparency = lerpf(0.45 + 0.1 * sin(_t * 4.0), 1.0, fade)
	_base.transparency = lerpf(0.3, 1.0, fade)
	_outline.transparency = lerpf(0.4, 1.0, fade)
	var p := _player()
	if p == null or not contains(p.global_position):
		return
	if puddle_slow < 1.0:
		PlayerSlow.apply(p, puddle_slow, 0.35)
	if puddle_dps > 0.0:
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = puddle_tick
			_hurt(p, puddle_dps * puddle_tick, Vector3.ZERO)

func _strike() -> void:
	if _struck:
		return
	_struck = true
	Perf.mark("hazard_strike")
	_apply_fill(1.0)
	var parent := get_parent()
	var hit := false
	if damage > 0.0:
		var c := global_position + Vector3(0, 0.1, 0)
		match shape:
			Shape.CIRCLE:
				FX.ring(parent, global_position, radius, Color(color, 0.9), 0.35)
				FX.shockwave(parent, global_position, radius, color.lightened(0.3))
			_:
				FX.burst(parent, c + global_transform.basis.z * radius * 0.5, radius * 0.35, Color(color, 0.5), 0.2)
		Audio.sfx("hazard_strike", "sounds/sfx/hazard_strike.wav")
		var p := _player()
		if p and contains(p.global_position):
			var d := p.global_position - global_position
			d.y = 0.0
			var dir := d.normalized() if d.length() > 0.05 else global_transform.basis.z
			hit = _hurt(p, damage, dir * knock + Vector3.UP * knock * 0.5) > 0.0
		if p and not hit:
			p.camera_fx.add_trauma(0.12)
	struck.emit(hit)
	if puddle_time <= 0.0:
		var tw := create_tween()
		tw.tween_property(_fill, "transparency", 1.0, 0.25)
		tw.parallel().tween_property(_outline, "transparency", 1.0, 0.25)
		tw.parallel().tween_property(_base, "transparency", 1.0, 0.25)
		tw.tween_callback(queue_free)
		set_physics_process(false)
	else:
		_tick_t = 0.0

func _hurt(p: Player, amount: float, knockback: Vector3) -> float:
	var h0 := p.health
	RunTracker.note_hit(source_node, source_id)
	p.take_damage(amount, knockback)
	var dealt := maxf(0.0, h0 - p.health)
	if dealt > 0.0 and is_instance_valid(source_node) and source_node.has_signal("struck_player"):
		source_node.emit_signal("struck_player", dealt)
	return dealt

func _player() -> Player:
	var p := get_tree().get_first_node_in_group("player") as Player
	return p if p and not p.is_dead else null

## Ноги Тора (pos) внутри формы и на полу зоны: в прыжке (выше JUMP_CLEARANCE) — нет.
func contains(pos: Vector3) -> bool:
	var dy := pos.y - global_position.y
	if dy > JUMP_CLEARANCE or dy < -TIER_LIMIT:
		return false
	var l := to_local(pos)
	match shape:
		Shape.CIRCLE:
			return Vector2(l.x, l.z).length() <= radius + 0.3
		Shape.LINE:
			return l.z >= -0.3 and l.z <= radius + 0.3 and absf(l.x) <= width * 0.5 + 0.3
		Shape.CONE:
			var r := Vector2(l.x, l.z).length()
			if r > radius + 0.3:
				return false
			return r < 0.6 or rad_to_deg(absf(atan2(l.x, l.z))) <= half_angle_deg + 4.0
	return false

## Образцы для прогрева шейдеров (ShaderWarmup): все три формы, без урона и звука.
static func warmup_sample(parent: Node3D, pos: Vector3) -> void:
	var shapes := [Shape.CIRCLE, Shape.LINE, Shape.CONE]
	for i in shapes.size():
		var z := HazardZone.new()
		z.shape = shapes[i]
		z.radius = 0.4
		z.width = 0.3
		z.telegraph = 999.0
		z.damage = 0.0
		z.set_meta("_warmup", true)
		parent.add_child(z)
		z.position = pos + Vector3((i - 1) * 0.5, 0, 0)
		z.set_physics_process(false)
		z._apply_fill(0.5)
