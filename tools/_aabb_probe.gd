extends SceneTree
func _init() -> void:
	var names := OS.get_cmdline_user_args()
	for n in names:
		var ps := load("res://assets/quaternius/village/%s.gltf" % n) as PackedScene
		if ps == null:
			print(n, " MISSING"); continue
		var root := ps.instantiate() as Node3D
		var ab := AABB()
		var first := true
		var surf := 0
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var a: AABB = m.transform * m.mesh.get_aabb()
			var p := m.get_parent()
			while p and p != root:
				a = (p as Node3D).transform * a
				p = p.get_parent()
			ab = a if first else ab.merge(a)
			first = false
			surf += m.mesh.get_surface_count()
		print("%s pos=%s size=%s surf=%d" % [n, ab.position.snapped(Vector3.ONE*0.01), ab.size.snapped(Vector3.ONE*0.01), surf])
		root.free()
	quit()
