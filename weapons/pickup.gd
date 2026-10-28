extends Node3D
class_name WeaponPickup
## Оружие на полу: парит и крутится, под ним светится кольцо (золото — мили, лёд — ренж).
## E рядом — взять (WeaponHolder.interact). Если из сундука «одно из двух» — остальные из группы исчезают.

const MELEE_COLOR := Color(1.0, 0.75, 0.3)
const RANGED_COLOR := Color(0.45, 0.8, 1.0)

var item: WeaponItem
## Выбор «одно из двух»: подобрал одно — остальные с тем же choice_group исчезают
var choice_group: String = ""
var _model: Node3D
var _spin: Node3D
var _ready_to_take: bool = true

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("pickups")
	set_meta("transient", true)
	_spin = Node3D.new()
	_spin.name = "Spin"
	add_child(_spin)
	if item and item.def:
		_model = WeaponMeshes.build(item.def.model)
		_model.scale = Vector3.ONE * item.def.pickup_scale
		# Лежит «плашмя»: рукоять горизонтально, по центру
		_model.rotation_degrees = Vector3(0, 0, 90) if not item.is_ranged() else Vector3.ZERO
		_model.position = Vector3(0.35 * item.def.pickup_scale, 0, 0) if not item.is_ranged() else Vector3.ZERO
		_spin.add_child(_model)
		for mi in _model.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Комиксовая обводка (GDD 20) — только модель, не кольцо и не луч
		Outline.add(_model)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = FX.shared_mesh("ring")
	FX.fx_apply(ring, "alpha", Color(_color(), 0.85), 1.0)
	ring.scale = Vector3(0.6, 0.3, 0.6)
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = FX.shared_mesh("box")
	FX.fx_apply(beam, "alpha_nocull", Color(_color(), 0.18), 1.0)
	beam.scale = Vector3(0.05, 1.6, 0.05)
	beam.position.y = 0.8
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var tw := _spin.create_tween().set_loops()
	tw.tween_property(_spin, "rotation:y", TAU, 3.0).from(0.0)

func _color() -> Color:
	return RANGED_COLOR if item and item.is_ranged() else MELEE_COLOR

## Положить на пол в точку ground; from — откуда прилетает дугой.
func place(ground: Vector3, from: Vector3 = Vector3.INF) -> void:
	var rest := ground
	if from == Vector3.INF:
		global_position = rest
		_spin.position.y = 0.6
		return
	global_position = rest
	_ready_to_take = false
	_spin.position = from - rest
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_spin, "position:x", 0.0, 0.45)
	tw.tween_property(_spin, "position:z", 0.0, 0.45)
	tw.tween_property(_spin, "position:y", 0.6, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void: _ready_to_take = true)

func can_interact() -> bool:
	return _ready_to_take and item != null

func prompt_text(holder: WeaponHolder) -> String:
	var cls := tr("ренж") if item.is_ranged() else tr("мили")
	var cur := holder.ranged if item.is_ranged() else holder.melee
	var txt := tr("[E] Взять: %s (%s, ур. %d)") % [tr(item.def.display_name), cls, item.level]
	if cur and cur.def.id == item.def.id and item.level <= cur.level and item.is_ranged():
		txt = tr("[E] Забрать патроны: %s") % tr(item.def.display_name)
	elif cur:
		txt += tr(" — бросить %s") % cur.title()
	return txt.replace("[E]", "[%s]" % GameSettings.current_binding("interact"))

func interact(holder: WeaponHolder) -> void:
	if not can_interact():
		return
	Perf.mark("weapon_pickup")
	var cur := holder.ranged if item.is_ranged() else holder.melee
	if item.is_ranged() and cur and cur.def.id == item.def.id and item.level <= cur.level:
		# То же оружие — только патроны
		cur.add_ammo(item.mag + item.reserve)
		holder.ammo_changed.emit(cur.mag, cur.reserve)
		holder.slots_changed.emit()
		Audio.play("sounds/sfx/ammo_pickup.wav")
	else:
		holder.equip_item(item, true)
		Audio.play("sounds/sfx/weapon_pickup.wav")
		if item.is_ranged() and randf() < 0.5:
			Odin.say("ranged_pickup")
	if choice_group != "":
		for n in get_tree().get_nodes_in_group("pickups"):
			if n != self and n is WeaponPickup and (n as WeaponPickup).choice_group == choice_group:
				FX.burst(n.get_parent(), (n as Node3D).global_position + Vector3(0, 0.6, 0), 0.4, Color(1, 1, 1, 0.5), 0.2)
				n.queue_free()
	item = null
	queue_free()
