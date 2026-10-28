extends RefCounted
class_name FXElements
## Эффекты стихий: языки огня зоны, ленты молнии, лёд при попадании.
## Модуль фасада FX (этап 5 рефакторинга): только static-функции; состояние, константы и вызовы снаружи — через FX.

## Языки пламени vfx_fire (петля 8 кадров) в зоне огня — дочерние узлы зоны, гаснут вместе с ней.
static func fire_sprites(zone: Node3D, radius: float, duration: float) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if zone == null:
		return out
	var c := FXSpriteKit.cfg()
	var n := clampi(int(ceil(radius * c.fire_per_meter)), 1, maxi(c.fire_max, 1))
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = FXShared.shared_mesh("quad_bottom")
		mi.material_override = FXSpriteKit.sprite_material("fire")
		FXShared._track_fade(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		FXSpriteKit.sprite_color(mi, Color.WHITE, 1.25)
		FXSpriteKit.set_sprite(mi, float(randi() % int(FX.STRIPS.fire)), 2, 0.0, c.fire_fps * randf_range(0.85, 1.15))
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
	var c := FXSpriteKit.cfg()
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var cam := FXSpriteKit._camera(parent)
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
		var mi := FXSpriteKit._sprite("lightning", parent, FXSpriteKit.random_variant("lightning"), mid, 1.0, color, 0, c.lightning_limit, "quad", c.lightning_energy)
		# Отрезки внахлёст: рисованная молния не доходит до краёв текстуры
		mi.transform = Transform3D(Basis(x, seg * c.lightning_overlap, z), mid)
		var tw := FXSpriteKit._tween(mi)
		var t := maxf(lifetime, 0.05)
		tw.tween_property(mi, "transparency", 0.55, t * 0.12)
		tw.tween_property(mi, "transparency", 0.0, t * 0.12)
		tw.tween_property(mi, "transparency", 1.0, t * 0.76).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.hide)

## Ледяная элита попала по Тору (enemies/elite/ice.gd): наледь под ногами на время замедления
## и кристаллы vfx_ice_shard_* вокруг — вырастают, стоят и уходят в пол.
static func ice_hit(parent: Node, pos: Vector3, duration: float) -> void:
	Perf.mark("fx_ice")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var patch := FXSpriteKit._floor_sprite("ice_patch", parent, "ice_patch", pos, c.ice_patch_size, Color.WHITE, c.ice_patch_limit)
	if patch:
		var b := patch.basis
		patch.basis = b.scaled(Vector3.ONE * 0.5)
		var tw := FXSpriteKit._tween(patch)
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
		var mi := FXSpriteKit._sprite("ice_shard", parent, FXSpriteKit.random_variant("ice_shard"), p, h * 0.15, Color.WHITE, 2, c.ice_shard_limit, "quad_bottom")
		var tw := FXSpriteKit._tween(mi)
		tw.tween_property(mi, "scale", Vector3.ONE * h, c.ice_shard_grow).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(maxf(duration * c.ice_shard_stay, 0.1))
		tw.tween_property(mi, "scale", Vector3(h, h * 0.1, h), 0.25).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mi, "transparency", 1.0, 0.25)
		tw.tween_callback(mi.hide)
