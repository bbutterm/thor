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

func _label(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.004
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	l.position = pos
