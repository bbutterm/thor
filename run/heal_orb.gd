extends SilverCoin
class_name HealOrb
## Лечение из разбитого ящика (props/destructible.gd → crate_loot): летит к Тору, как монета серебра,
## и лечит amount HP. Общий меш (шар) и общий материал эффектов — без новых материалов.

const HEAL_COLOR := Color(0.45, 1.0, 0.55)

var amount: float = 10.0

func _ready() -> void:
	set_meta("transient", true)
	add_to_group("heal_orbs")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = FX.shared_mesh("sphere")
	FX.fx_apply(_mesh, "glow", HEAL_COLOR, 1.6)
	_mesh.scale = Vector3.ONE * 0.22
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

func _collect() -> void:
	Perf.mark("heal_orb_pickup")
	var p := _player()
	if p and not p.is_dead:
		p.heal(amount)
		FX.sparks(get_parent(), global_position, HEAL_COLOR, 8, 3.0, 4.0, 0.05, 0.35)
	Audio.play("sounds/sfx/coin_pickup.wav")
	queue_free()
