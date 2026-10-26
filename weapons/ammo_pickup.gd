extends Node3D
class_name AmmoPickup
## Ящик патронов: подбирается сам, если подойти (WeaponHolder._collect_ammo) и в ренж-слоте есть оружие
## с неполным запасом. Пополняет WeaponHolder.ammo_box_fraction от предела запаса.

func _ready() -> void:
	add_to_group("ammo_pickups")
	set_meta("transient", true)
	var box := MeshInstance3D.new()
	box.mesh = FX.shared_mesh("box")
	box.material_override = WeaponMeshes.mat("wood")
	box.scale = Vector3(0.36, 0.22, 0.24)
	box.position.y = 0.11
	add_child(box)
	var band := MeshInstance3D.new()
	band.mesh = FX.shared_mesh("box")
	band.material_override = WeaponMeshes.mat("iron")
	band.scale = Vector3(0.38, 0.05, 0.26)
	band.position.y = 0.17
	add_child(band)
	# Голубая метка «патроны» (как кольцо у ренжа)
	var ring := MeshInstance3D.new()
	ring.mesh = FX.shared_mesh("ring")
	FX.fx_apply(ring, "alpha", Color(WeaponPickup.RANGED_COLOR, 0.8), 1.0)
	ring.scale = Vector3(0.4, 0.3, 0.4)
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tw := box.create_tween().set_loops()
	tw.tween_property(self, "rotation:y", TAU, 4.0).from(0.0)
