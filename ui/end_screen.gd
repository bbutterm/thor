extends CanvasLayer
class_name EndScreen
## Экран смерти / победы: вердикт Одина, причина смерти, итоги забега (слева) и сборка (справа).
## Итоги — словарь RunTracker.result() (время, убийства, хваты, ранг, удары-приземления); сборка — из Run и оружия игрока.

signal restart_requested
signal menu_requested

var _title: Label
var _verdict: Label
var _stats: Label
var _build: VBoxContainer
var _quote: Label
var _restart: Button
var _root: Control

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.85)
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.custom_minimum_size = Vector2(900, 0)
	center.add_child(vb)
	_title = UIStyle.label("", 54, UIStyle.BLOOD, 12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_verdict = UIStyle.label("", 34, UIStyle.GOLD, 10)
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_verdict)
	_quote = UIStyle.label("", 20, UIStyle.TEXT, 5)
	_quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_quote)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var panel := UIStyle.panel(UIStyle.STONE, Color(UIStyle.GOLD, 0.6), "wood")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.85
	row.add_child(panel)
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 2)
	panel.add_child(stats_box)
	stats_box.add_child(UIStyle.label(tr("ИТОГИ ЗАБЕГА"), 19, UIStyle.GOLD, 4))
	_stats = UIStyle.label("", 18, UIStyle.TEXT, 4)
	stats_box.add_child(_stats)
	var build_panel := UIStyle.panel(UIStyle.STONE, Color(UIStyle.GOLD, 0.6), "wood")
	build_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(build_panel)
	_build = VBoxContainer.new()
	_build.add_theme_constant_override("separation", 2)
	build_panel.add_child(_build)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	_restart = UIStyle.button(tr("К Одину ▸"))
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	hb.add_child(_restart)
	var menu := UIStyle.button(tr("В меню"))
	menu.pressed.connect(func() -> void: menu_requested.emit())
	hb.add_child(menu)

## stats — RunTracker.result(); пусто — последний забег из сохранения (кадры, старые вызовы).
func show_result(victory: bool, stats: Dictionary = {}) -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if stats.is_empty():
		stats = Save.data.get("last_run", {})
	if victory:
		_title.text = tr("ЗАЧЁТ СДАН!")
		_title.label_settings.font_color = UIStyle.GOLD
		_quote.text = "«%s»" % Odin.pick("victory")
	else:
		_title.text = tr("ТЫ ПАЛ")
		_title.label_settings.font_color = UIStyle.BLOOD
		_quote.text = RunTracker.describe_last_death()
	_verdict.text = tr("Вердикт Одина: %s") % Run.verdict()
	_stats.text = stats_text(victory, stats)
	_fill_build()
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.5)
	_restart.grab_focus()

func stats_text(victory: bool, stats: Dictionary) -> String:
	var t := int(float(stats.get("time", 0.0)))
	var body_name := tr(Run.body.display_name) if Run.body else "—"
	var lines: Array[String] = [
		tr("Тело: %s") % body_name,
		tr("Время: %d:%02d") % [t / 60, t % 60],
		tr("Убито врагов: %d (лучшая серия %d)") % [Run.kills, Run.best_streak],
		tr("Идеальные хваты: %d из %d") % [int(stats.get("perfect_catches", 0)), int(stats.get("catches", 0))],
		tr("Лучший ранг: %s") % tr(StyleMeter.rank_name(int(stats.get("best_rank", 0)))),
		tr("Удары-приземления: %d") % int(stats.get("slams", 0)),
		tr("Пройдено залов: %d из %d") % [Run.room_index + (1 if victory else 0), Run.total_rooms()],
		tr("Слава: %d") % Run.glory,
	]
	return "\n".join(lines)

## Сборка: Мьёльнир (трейты с уровнями), руны (×уровень), клятвы, оружие в слотах.
func _fill_build() -> void:
	for c in _build.get_children():
		c.queue_free()
	_section(tr("СБОРКА"), "")
	var traits: Array[String] = []
	for t in Run.mjolnir_traits:
		traits.append(tr("%s ур. %d") % [tr(t.title), Run.mjolnir_trait_level(t.id)])
	_section(tr("Мьёльнир"), ", ".join(traits) if not traits.is_empty() else tr("без трейтов"))
	var counts := {}
	var order: Array[RuneDef] = []
	for r in Run.runes:
		if not counts.has(r.id):
			counts[r.id] = 0
			order.append(r)
		counts[r.id] += 1
	var runes: Array[String] = []
	var oaths: Array[String] = []
	for r in order:
		if r.oath:
			oaths.append(tr(r.title))
		else:
			var lv := mini(int(counts[r.id]), Run.RUNE_MAX_LEVEL)
			runes.append(("☠ " if r.cursed else "") + tr(r.title) + ("" if lv <= 1 else " ×%d" % lv))
	_section(tr("Руны"), ", ".join(runes) if not runes.is_empty() else "—")
	_section(tr("Клятвы"), ", ".join(oaths) if not oaths.is_empty() else "—")
	var weapons: Array[String] = []
	var game := get_tree().current_scene as Game
	var holder: WeaponHolder = game.player.weapons if game and is_instance_valid(game.player) else null
	if holder:
		for w in [holder.melee, holder.ranged]:
			if w and (w as WeaponItem).def:
				weapons.append((w as WeaponItem).title())
	_section(tr("Оружие"), " · ".join(weapons) if not weapons.is_empty() else "—")

func _section(head: String, body: String) -> void:
	var h := UIStyle.label(head, 19 if body == "" else 17, UIStyle.GOLD, 4)
	_build.add_child(h)
	if body == "":
		return
	var b := UIStyle.label(body, 16, UIStyle.TEXT, 3)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 440
	_build.add_child(b)
