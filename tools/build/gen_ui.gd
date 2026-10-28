extends RefCounted
class_name GenUi
## Генератор: UI-сцены (пустые обёртки со скриптом) и сцена игры scenes/game.tscn.
## Компонент SceneBuilder (этап 4 рефакторинга): числа и состояние — поля SceneBuilder (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — генератор.ui; нужные снаружи функции есть и на SceneBuilder.

var gen: SceneBuilder

func _init(owner_node: SceneBuilder) -> void:
	gen = owner_node

func build_ui_scenes() -> void:
	print("UI…")
	var specs := [
		["res://ui/hud.tscn", "HUD", "res://ui/hud.gd", "CanvasLayer"],
		["res://ui/rune_pick.tscn", "RunePick", "res://ui/rune_pick.gd", "CanvasLayer"],
		["res://ui/pause_menu.tscn", "PauseMenu", "res://ui/pause_menu.gd", "CanvasLayer"],
		["res://ui/end_screen.tscn", "EndScreen", "res://ui/end_screen.gd", "CanvasLayer"],
		["res://ui/main_menu.tscn", "MainMenu", "res://ui/main_menu.gd", "Control"],
	]
	for s in specs:
		var n: Node = CanvasLayer.new() if s[3] == "CanvasLayer" else Control.new()
		n.name = s[1]
		n.set_script(load(s[2]))
		gen._save(n, s[0])

func build_game() -> void:
	print("Сцена игры…")
	var g := Node3D.new()
	g.name = "Game"
	g.set_script(load("res://scenes/game.gd"))

	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.18, 0.32)
	sm.sky_horizon_color = Color(0.85, 0.55, 0.38)
	sm.ground_horizon_color = Color(0.5, 0.36, 0.3)
	sm.ground_bottom_color = Color(0.1, 0.09, 0.1)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.45, 0.42)
	env.fog_density = 0.008
	env.ssao_enabled = true
	ResourceSaver.save(env, "res://scenes/game_environment.tres")
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = load("res://scenes/game_environment.tres")
	g.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	g.add_child(sun)

	var level := Node3D.new()
	level.name = "Level"
	g.add_child(level)

	var player := (load("res://player/player.tscn") as PackedScene).instantiate()
	player.name = "Player"
	g.add_child(player)

	for spec in [["HUD", "res://ui/hud.tscn"], ["RunePick", "res://ui/rune_pick.tscn"], ["PauseMenu", "res://ui/pause_menu.tscn"], ["EndScreen", "res://ui/end_screen.tscn"]]:
		var n := (load(spec[1]) as PackedScene).instantiate()
		n.name = spec[0]
		g.add_child(n)
	gen._save(g, "res://scenes/game.tscn")
