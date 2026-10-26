extends Control
## Главное меню: начать забег, выход, подсказка по управлению.

func _ready() -> void:
	FX.reset_time()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIStyle.full_rect(self)
	UISkin.apply(self)
	# Фон и эмблема из комплекта владельца (menu_background, logo_emblem); нет картинок — тёмный фон
	var bg_tex := UISkin.texture("menu_background")
	if bg_tex:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		UIStyle.full_rect(bg)
		add_child(bg)
		# Левая треть — под меню: мягкое затемнение, чтобы читались кнопки
		var shade := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.78))
		g.set_color(1, Color(0, 0, 0, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0.0, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 4
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		shade.offset_right = 760
		add_child(shade)
	else:
		var bgc := ColorRect.new()
		UIStyle.full_rect(bgc)
		bgc.color = Color(0.05, 0.05, 0.07)
		add_child(bgc)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 60
	col.offset_right = 520
	col.offset_top = 16
	col.offset_bottom = -16
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var vb := col

	var logo_tex := UISkin.texture("logo_emblem")
	if logo_tex:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(0, 150)
		vb.add_child(logo)
	var title := UIStyle.label("ТОР", 64, UIStyle.GOLD, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UIStyle.label("ДОСТОЙНАЯ СМЕРТЬ", 30, UIStyle.TEXT, 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var tag := UIStyle.label("Тор скуфнулся. Один вселяет его в смертных воинов — возвращать форму.", 16, UIStyle.TEXT_DIM, 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vb.add_child(spacer)

	var start := UIStyle.button("Начать забег", 28)
	start.custom_minimum_size = Vector2(360, 64)
	start.pressed.connect(_on_start)
	var start_box := CenterContainer.new()
	start_box.add_child(start)
	vb.add_child(start_box)
	var plan := UIStyle.button("План тренировок", 22, "secondary")
	plan.custom_minimum_size = Vector2(320, 54)
	plan.pressed.connect(_on_plan)
	var plan_box := CenterContainer.new()
	plan_box.add_child(plan)
	vb.add_child(plan_box)
	var settings := UIStyle.button("Настройки", 22, "secondary")
	settings.custom_minimum_size = Vector2(320, 54)
	settings.pressed.connect(func() -> void:
		var sp := SettingsPanel.new()
		sp.closed.connect(settings.grab_focus)
		add_child(sp))
	var settings_box := CenterContainer.new()
	settings_box.add_child(settings)
	vb.add_child(settings_box)
	var quit := UIStyle.button("Выход", 22, "danger")
	quit.custom_minimum_size = Vector2(320, 54)
	quit.pressed.connect(func() -> void: get_tree().quit())
	var quit_box := CenterContainer.new()
	quit_box.add_child(quit)
	vb.add_child(quit_box)

	# Подсказка по управлению — справа внизу, поверх фона
	var controls := UIStyle.panel(Color(0.08, 0.08, 0.1, 0.9), Color(UIStyle.ICE, 0.35))
	controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls.offset_right = -24
	controls.offset_bottom = -20
	controls.modulate.a = 0.92
	var cl := UIStyle.label(
		"WASD — бег  ·  Пробел — прыжок / двойной\n" +
		"Shift — рывок  ·  Ctrl или C в воздухе — удар-приземление\n" +
		"Ctrl+Shift — подкат  ·  Пробел после приземления — СУПЕР-ПРЫЖОК\n" +
		"ЛКМ — удар (комбо из 3)  ·  ПКМ — метнуть / вернуть Мьёльнир\n" +
		"Q — сменить оружие  ·  E — подобрать  ·  Esc — пауза", 15, UIStyle.TEXT_DIM, 3)
	controls.add_child(cl)
	add_child(controls)
	start.grab_focus()
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest.call_deferred()

## «План тренировок Одина» из меню: «В бой» — сразу забег, «Назад» — в меню.
func _on_plan() -> void:
	var tp := TrainingPlan.new()
	add_child(tp)
	tp.open("Назад")
	if await tp.closed:
		tp.queue_free()
		_on_start()
	else:
		tp.queue_free()

## «Начать забег»: экран выбора тела (ui/body_select.gd), потом забег этим телом.
func _on_start() -> void:
	var bs := BodySelect.new()
	bs.name = "BodySelect"
	add_child(bs)
	bs.open("Назад", Run.body.id if Run.body else "")
	var id: String = await bs.closed
	bs.queue_free()
	if id != "":
		_start_with(id)

func _start_with(body_id: String) -> void:
	Run.start_run(body_id)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

## Проверка собранной игры: ./Thor.exe -- --selftest  (печатает, что ресурсы на месте, и выходит)
func _selftest() -> void:
	print("SELFTEST bodies=%d runes=%d odin=%s" % [Run.all_bodies.size(), Run.all_runes.size(), Odin.pick("death") != ""])
	get_tree().root.add_child(SelfTestRunner.new())
	_start_with("")

class SelfTestRunner extends Node:
	func _ready() -> void:
		for i in 240:
			await get_tree().process_frame
		var g := get_tree().current_scene
		print("SELFTEST scene=%s room=%s enemies=%d" % [g.name, Run.current_room_path(), get_tree().get_nodes_in_group("enemies").size()])
		get_tree().quit()
