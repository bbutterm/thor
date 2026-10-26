extends Node3D
## Рендер витрины ассетов: xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tools/preview_assets.tscn -- <out.png> [набор]

var out := "user://preview.png"
var set_name := "characters"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		set_name = args[1]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_m.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.25, 0.28)
	floor_m.material_override = fm
	add_child(floor_m)
	var cam := Camera3D.new()
	add_child(cam)
	match set_name:
		"fparm":
			floor_m.visible = false
			e.background_color = Color(0.25, 0.22, 0.2)
			cam.fov = 60
			cam.near = 0.05
			cam.position = Vector3.ZERO
			var defs := [["right", "axe", Vector3(0.48, -0.42, -1.0), Vector3(-8, 12, -14)], ["left", "hammer", Vector3(-0.52, -0.44, -1.05), Vector3(-10, -15, 12)]]
			for d in defs:
				var pv := Node3D.new()
				add_child(pv)
				pv.scale = Vector3.ONE * 0.62
				pv.position = d[2]
				pv.rotation_degrees = d[3]
				var arm := ViewmodelArm.new()
				arm.side = d[0]
				arm.layer = 1
				pv.add_child(arm)
				var wpn := WeaponMeshes.build(d[1])
				wpn.position.y = -0.28 if d[1] == "axe" else -0.06
				pv.add_child(wpn)
			var l2 := OmniLight3D.new()
			l2.position = Vector3(0.3, 0.6, 0.6)
			l2.light_energy = 1.0
			add_child(l2)
		"fp":
			# Вид от первого лица: руки персонажа + оружие, камера на уровне глаз
			floor_m.visible = false
			for i in 3:
				_place("res://assets/quaternius/village/Wall_UnevenBrick_Straight.gltf", Vector3(-2 + i * 2, 0, 4), PI)
			var h := HumanoidModel.new()
			h.body = "base/Superhero_Male_FullBody.gltf"
			h.outfit = ""
			h.parts = PackedStringArray(["parts/Male_Ranger_Arms.gltf"])
			h.part_tints = [Color(0.75, 0.6, 0.45)]
			add_child(h)
			var att := BoneAttachment3D.new()
			att.bone_name = "hand_r"
			h.skeleton.add_child(att)
			att.add_child(WeaponMeshes.build("axe"))
			var att2 := BoneAttachment3D.new()
			att2.bone_name = "hand_l"
			h.skeleton.add_child(att2)
			att2.add_child(WeaponMeshes.build("hammer"))
			var pose := OS.get_cmdline_user_args()[2] if OS.get_cmdline_user_args().size() > 2 else "Sword_Idle"
			var at := float(OS.get_cmdline_user_args()[3]) if OS.get_cmdline_user_args().size() > 3 else 0.3
			h.play(pose, 0.0)
			h.anim.seek(at, true)
			h.anim.pause()
			# голова скрыта (обрезка голова-только + без головы: прячем базовое тело целиком)
			for mi in h.skeleton.get_children():
				if mi is MeshInstance3D and (mi.name.begins_with("SuperHero") or mi.name.begins_with("Superhero") or mi.name.begins_with("Eye")):
					mi.visible = false
			cam.fov = 70
			cam.near = 0.03
			if OS.get_cmdline_user_args().size() > 4 and OS.get_cmdline_user_args()[4] == "side":
				cam.position = Vector3(3.0, 1.5, 1.0)
				cam.look_at(Vector3(0, 1.3, 0.3))
			else:
				# Камера — на кости головы, смотрит вперёд персонажа (+Z)
				var head_i := h.skeleton.find_bone("Head")
				var head_pos := h.skeleton.global_transform * h.skeleton.get_bone_global_pose(head_i).origin
				print("HEAD ", head_pos)
				cam.global_position = head_pos + Vector3(0, 0.08, 0.1)
				cam.look_at(cam.global_position + Vector3(0, -0.25, 1.0))
		"weapons":
			var names := ["axe", "sword", "dagger", "spear", "scythe", "shield-round", "bow", "staff", "pickaxe"]
			for i in names.size():
				var n := _place("res://assets/quaternius/weapons/%s.glb" % names[i], Vector3((i - 4) * 0.9, 0.0, 0), 0.0)
				var box := _aabb(n)
				print("W %-14s %s" % [names[i], box])
				_label(names[i], Vector3((i - 4) * 0.9, 2.1, 0))
			var hm := WeaponMeshes.hammer()
			add_child(hm)
			hm.position = Vector3(4.6, 0, 0)
			_label("mjolnir (свой)", Vector3(4.6, 2.1, 0))
			cam.position = Vector3(0.3, 1.0, 4.2)
			cam.look_at(Vector3(0.3, 0.65, 0))
		"grip":
			var rots := [Vector3(0, 0, 0), Vector3(90, 0, 0), Vector3(-90, 0, 0), Vector3(0, 0, 90), Vector3(0, 0, -90), Vector3(180, 0, 0)]
			for i in rots.size():
				var h := HumanoidModel.new()
				h.outfit = "outfits/Male_Peasant.gltf"
				add_child(h)
				h.position = Vector3((i - 2.5) * 1.2, 0, 0)
				var att := BoneAttachment3D.new()
				att.bone_name = "hand_r"
				h.skeleton.add_child(att)
				var w := WeaponMeshes.build("spear")
				w.rotation_degrees = rots[i]
				att.add_child(w)
				h.play("Sword_Idle", 0.0)
				_label(str(rots[i]), Vector3((i - 2.5) * 1.2, 2.3, 0))
			cam.position = Vector3(0, 1.4, 5.5)
			cam.look_at(Vector3(0, 1.1, 0))
		"crowd":
			e.background_color = Color(0.1, 0.1, 0.13)
			for i in 6:
				_place("res://assets/quaternius/village/Wall_UnevenBrick_Straight.gltf", Vector3(-10 + i * 4, 0, -4.5), 0.0)
			fm.albedo_color = Color(0.32, 0.3, 0.28)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var anims := ["Idle_Loop", "Sword_Idle", "Idle_Talking_Loop", "Idle_FoldArms_Loop", "Idle_Torch_Loop", "Walk_Loop", "Idle_Shield_Loop", "Sword_Regular_Combo", "Punch_Jab", "Yes"]
			for i in 14:
				var look := HumanoidModel.random_look(rng, rng.randf() < 0.35)
				var h := HumanoidModel.new()
				h.body = look.body; h.outfit = ""; h.parts = look.parts; h.part_tints = look.part_tints; h.skin_tint = look.skin_tint
				add_child(h)
				var row := i / 7
				var col := i % 7
				h.position = Vector3((col - 3) * 1.15 + (0.55 if row == 1 else 0.0), 0, -row * 1.6)
				h.rotation.y = rng.randf_range(-0.5, 0.5)
				var w: String = WeaponMeshes.CROWD_WEAPONS[i % WeaponMeshes.CROWD_WEAPONS.size()]
				var att := BoneAttachment3D.new()
				att.bone_name = "hand_r"
				h.skeleton.add_child(att)
				var wn := WeaponMeshes.build(w)
				wn.rotation_degrees = Vector3(0, 0, -90)
				wn.position = Vector3(0, 0.08, 0)
				att.add_child(wn)
				if rng.randf() < 0.35:
					var att2 := BoneAttachment3D.new()
					att2.bone_name = "hand_l"
					h.skeleton.add_child(att2)
					var sh := WeaponMeshes.build("q_shield")
					sh.rotation_degrees = Vector3(0, 0, 90)
					att2.add_child(sh)
				h.play(anims[rng.randi() % anims.size()], 0.0)
				h.anim.seek(rng.randf() * 1.0, true)
			cam.position = Vector3(0.0, 1.55, 3.6)
			cam.fov = 60
			cam.look_at(Vector3(0.0, 1.05, -0.6))
		"lineup":
			e.background_color = Color(0.08, 0.08, 0.11)
			sun.light_energy = 0.9
			# Стена позади
			for i in 5:
				_place("res://assets/quaternius/village/Wall_UnevenBrick_Straight.gltf", Vector3(-10 + i * 4, 0, -2.5), 0.0)
			fm.albedo_color = Color(0.3, 0.28, 0.26)
			var specs := [
				["Драугр", "base/Superhero_Male_FullBody.gltf", "outfits/Male_Peasant.gltf", "", Color(0.45, 0.6, 0.68), Color(0.55, 0.55, 0.52), Color(0.4, 0.8, 1.0, 1), "ual2/Zombie_Idle_Loop", 1.0],
				["Шаман", "base/Superhero_Female_FullBody.gltf", "outfits/Female_Ranger.gltf", "", Color(0.5, 0.6, 0.66), Color(0.55, 0.45, 0.7), Color(0.7, 0.4, 1.0, 1), "ual1/Spell_Simple_Idle_Loop", 1.0],
				["Хримтурс", "base/Superhero_Male_FullBody.gltf", "outfits/Male_Peasant.gltf", "hair/Hair_Beard.gltf", Color(0.5, 0.72, 1.0), Color(0.55, 0.7, 1.0), Color(0.5, 0.9, 1.0, 1), "ual1/Sword_Idle", 2.0],
				["Смертный (тело Тора)", "base/Superhero_Male_FullBody.gltf", "outfits/Male_Ranger.gltf", "hair/Hair_Long.gltf", Color.WHITE, Color.WHITE, Color(0,0,0,0), "ual1/Idle_Loop", 1.0],
			]
			for i in specs.size():
				var sp: Array = specs[i]
				var h := HumanoidModel.new()
				h.body = sp[1]; h.outfit = sp[2]; h.hair = sp[3]
				h.skin_tint = sp[4]; h.cloth_tint = sp[5]; h.eye_glow = sp[6]
				add_child(h)
				var x: float = [-2.6, -0.9, 1.3, 3.4][i]
				h.position = Vector3(x, 0, 0)
				h.scale = Vector3.ONE * sp[8]
				h.rotation.y = 0.25 if i < 2 else -0.2
				var parts: PackedStringArray = (sp[7] as String).split("/")
				h.play(parts[1], 0.0)
				_label(sp[0], Vector3(x, 2.05 * sp[8] + 0.15, 0))
			var tl := OmniLight3D.new()
			tl.position = Vector3(0, 3, 1.5)
			tl.light_color = Color(1, 0.88, 0.75)
			tl.light_energy = 1.2
			tl.omni_range = 9
			add_child(tl)
			cam.position = Vector3(0.4, 1.8, 5.2)
			cam.look_at(Vector3(0.4, 1.35, 0))
		"characters":
			var items := [
				["res://assets/quaternius/characters/base/Superhero_Male_FullBody.gltf", "Idle_Loop"],
				["res://assets/quaternius/characters/outfits/Male_Ranger.gltf", "Idle_Loop"],
				["res://assets/quaternius/characters/outfits/Male_Peasant.gltf", "Idle_Loop"],
				["res://assets/quaternius/characters/outfits/Female_Ranger.gltf", "Idle_Loop"],
				["res://assets/quaternius/characters/outfits/Female_Peasant.gltf", "Idle_Loop"],
			]
			for i in items.size():
				var n := _place(items[i][0], Vector3((i - 2) * 1.3, 0, 0), 0.0)
				_label(items[i][0].get_file().get_basename(), Vector3((i - 2) * 1.3, 2.15, 0))
			cam.position = Vector3(0, 1.3, 5.2)
			cam.look_at(Vector3(0, 1.0, 0))
		"village":
			var names := ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Door_Round", "Wall_Plaster_WoodGrid", "Wall_Arch", "Wall_Plaster_Window_Wide_Round", "Floor_UnevenBrick", "Floor_WoodDark", "Stairs_Exterior_Straight", "Prop_Crate", "Prop_Wagon", "Prop_Support"]
			var x := -10.0
			for nm in names:
				var n := _place("res://assets/quaternius/village/%s.gltf" % nm, Vector3(x, 0, 0), 0.0)
				var w := 4.2
				_label(nm, Vector3(x + 1.0, 4.6, 0.5))
				x += w
			cam.position = Vector3(-1, 6, 16)
			cam.look_at(Vector3(-1, 1.8, 0))
		"props":
			var dir := DirAccess.open("res://assets/quaternius/props")
			var files: Array = []
			for f in dir.get_files():
				if f.ends_with(".gltf"):
					files.append(f)
			for i in files.size():
				var p := Vector3((i % 6 - 2.5) * 1.6, 0, -floor(i / 6.0) * 1.8)
				_place("res://assets/quaternius/props/" + files[i], p, 0.0)
				_label(files[i].get_basename(), p + Vector3(0, 1.7, 0.4))
			cam.position = Vector3(0, 3.5, 6.5)
			cam.look_at(Vector3(0, 0.6, -0.8))
	for i in 50:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()

func _place(path: String, pos: Vector3, yaw: float) -> Node3D:
	if not ResourceLoader.exists(path):
		print("missing ", path)
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	add_child(n)
	n.position = pos
	n.rotation.y = yaw
	var ap := n.find_children("*", "AnimationPlayer", true, false)
	if ap.size() > 0:
		var a := ap[0] as AnimationPlayer
		if a.get_animation_list().size() > 0:
			a.play(a.get_animation_list()[0])
	return n

func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _label(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.004
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	l.position = pos
