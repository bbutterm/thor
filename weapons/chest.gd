extends Node3D
class_name Chest
## Сундук после зачистки зала (GDD 9.3): E — открыть, выпадают два оружия на выбор («одно из двух»)
## и ящик патронов. Модель — Quaternius Fantasy Props (Chest_Wood) с анимацией открытия.

const MODEL := "res://assets/quaternius/props/Chest_Wood.gltf"
## Мили и ренж в выборе (иначе — два случайных разных)
const MIXED_CHOICE := true

var opened: bool = false
var _anim: AnimationPlayer
static var _counter: int = 0

func _ready() -> void:
	add_to_group("interactable")
	set_meta("transient", true)
	if ResourceLoader.exists(MODEL):
		var m := (load(MODEL) as PackedScene).instantiate() as Node3D
		m.name = "Model"
		m.scale = Vector3.ONE * 0.9
		add_child(m)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			_anim = aps[0] as AnimationPlayer
			if _anim.has_animation("Chest_Closed"):
				_anim.play("Chest_Closed")
	var ring := MeshInstance3D.new()
	ring.mesh = FX.shared_mesh("ring")
	FX.fx_apply(ring, "alpha", Color(1.0, 0.8, 0.35, 0.8), 1.0)
	ring.scale = Vector3(0.95, 0.3, 0.95)
	ring.position.y = 0.05
	ring.name = "Ring"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if not has_meta("warmup"):
		FX.burst(get_parent(), global_position + Vector3(0, 0.5, 0), 0.8, Color(1, 0.85, 0.4, 0.5), 0.3)
		Audio.play("sounds/sfx/chest_appear.wav")

func can_interact() -> bool:
	return not opened

func prompt_text(_holder: WeaponHolder) -> String:
	return tr("[E] Открыть сундук")

func interact(_holder: WeaponHolder) -> void:
	if opened:
		return
	opened = true
	Perf.mark("chest_open")
	if _anim and _anim.has_animation("Chest_Open"):
		_anim.play("Chest_Open")
	var r := get_node_or_null("Ring")
	if r:
		r.queue_free()
	Audio.play("sounds/sfx/chest_open.wav")
	Odin.say("chest")
	_counter += 1
	var group := "chest_%d_%d" % [get_instance_id(), _counter]
	var a := Loot.random_def("melee") if MIXED_CHOICE else Loot.random_def()
	var b := Loot.random_def("ranged") if MIXED_CHOICE else Loot.random_def("", [a.id if a else ""])
	var side := global_transform.basis.x
	var fwd := global_transform.basis.z
	var top := global_position + Vector3(0, 0.8, 0)
	var i := 0
	for d in [a, b]:
		if d == null:
			continue
		var p := Loot.spawn_weapon(get_parent(), global_position + fwd * 1.2 + side * (-0.9 if i == 0 else 0.9), WeaponItem.create(d, Loot.random_level()), top)
		p.choice_group = group
		i += 1
	Loot.spawn_ammo(get_parent(), global_position + fwd * 1.6)
	# Серебро из сундука (блок К, GDD 15.2: 20)
	Silver.drop(get_parent(), global_position + Vector3(0, 0.4, 0), Silver.cfg().chest_silver)
