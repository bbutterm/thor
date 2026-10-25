extends Control
## Главное меню: начать забег, выход, подсказка по управлению.

func _ready() -> void:
	FX.reset_time()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIStyle.full_rect(self)
	var bg := ColorRect.new()
	UIStyle.full_rect(bg)
	bg.color = Color(0.05, 0.05, 0.07)
	add_child(bg)
	var glow := Label.new()
	glow.text = "ᛗ"
	var gls := LabelSettings.new()
	gls.font = UIStyle.font()
	gls.font_size = 520
	gls.font_color = Color(UIStyle.ICE, 0.06)
	glow.label_settings = gls
	glow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyle.full_rect(glow)
	add_child(glow)

	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)

	var title := UIStyle.label("ТОР", 110, UIStyle.GOLD, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UIStyle.label("ДОСТОЙНАЯ СМЕРТЬ", 36, UIStyle.TEXT, 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var tag := UIStyle.label("Один выгнал тебя из Асгарда. Вселяйся в смертных и умри красиво.", 18, UIStyle.TEXT_DIM, 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	vb.add_child(spacer)

	var start := UIStyle.button("Начать забег", 28)
	start.custom_minimum_size = Vector2(340, 64)
	start.pressed.connect(_on_start)
	var start_box := CenterContainer.new()
	start_box.add_child(start)
	vb.add_child(start_box)
	var quit := UIStyle.button("Выход", 22)
	quit.pressed.connect(func() -> void: get_tree().quit())
	var quit_box := CenterContainer.new()
	quit_box.add_child(quit)
	vb.add_child(quit_box)

	var controls := UIStyle.panel(Color(0.08, 0.08, 0.1, 0.9), Color(UIStyle.ICE, 0.35))
	var cl := UIStyle.label(
		"WASD — бег   ·   Пробел — прыжок / двойной\n" +
		"Shift — рывок   ·   Ctrl или C в воздухе — удар-приземление\n" +
		"Пробел сразу после приземления — СУПЕР-ПРЫЖОК\n" +
		"ЛКМ — топор (комбо из 3)   ·   ПКМ — метнуть / вернуть Мьёльнир\n" +
		"Топором можно отбивать фиолетовые снаряды   ·   Esc — пауза", 16, UIStyle.TEXT_DIM, 3)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_child(cl)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vb.add_child(spacer2)
	vb.add_child(controls)
	start.grab_focus()

func _on_start() -> void:
	Run.start_run()
	get_tree().change_scene_to_file("res://scenes/game.tscn")
