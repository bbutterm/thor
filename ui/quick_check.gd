extends Control
class_name QuickCheck
## «Быстрая проверка» (NOW.md, П0): рабочий инструмент владельца, не для релиза.
## Список «что нового в этой сборке»; «Попробовать» — сразу в подходящий зал с нужным оружием, без забега,
## диалогов и обучения. В зале F6 переключает «старое / новое» (FeelSwitch) для изменений ощущений партии.
## Кнопка в главном меню — только в сборках для плейтеста (признак экспорта playtest) и в отладочном запуске.

signal closed

## Пункты партии: что поменялось, где попробовать, какое оружие дать; old_room — старая сцена зала (F6 перезапускает зал)
const ITEMS := [
	{"title": "Рисованные текстуры залов", "text": "Земля, брусчатка и доски — рисованные текстуры владельца. F6 — старые текстуры.", "room": "res://rooms/room_08.tscn", "weapon": "axe"},
	{"title": "Причал — зал как путь", "text": "Берег → пирс → палуба → башня-ворота, двери видны с порога. Мачта с лестницей, вода. F6 — старый причал.", "room": "res://rooms/room_07.tscn", "weapon": "axe", "old_room": "res://rooms/quick_old/room_07_old.tscn"},
	{"title": "Деревня — улица в гору", "text": "Набережная → рынок → площадь → двор, путь по крышам. Дома MegaKit: крыши, ставни, двери с навесами. F6 — старая деревня.", "room": "res://rooms/room_09.tscn", "weapon": "axe", "old_room": "res://rooms/quick_old/room_09_old.tscn"},
	{"title": "Молот как в God of War", "text": "Гул на самом молоте (слышно, откуда летит), возврат по дуге с доворотом к врагам, не дольше 1,5 с. F6 — старый возврат.", "room": "res://rooms/room_04.tscn", "weapon": "axe"},
	{"title": "Боссы не падают от спама мили", "text": "Простые удары по боссу — вполсилы; молот и удар-приземление — полный урон.", "room": "boss", "weapon": "axe"},
]

## Идёт проверка (Game показывает плашку и ловит F6; меню возвращает всё как было)
static var active: bool = false

static func available() -> bool:
	return OS.has_feature("playtest") or OS.is_debug_build()

## Пункт, который сейчас проверяют (F6 у пункта с old_room перезапускает зал в старой сцене)
static var current: int = -1

## Вход в зал пункта i: короткий «забег» из одного зала, без сюжетных сцен и обучения.
## keep_switch — не сбрасывать «старое/новое» (перезапуск зала по F6).
static func start(tree: SceneTree, i: int, keep_switch: bool = false) -> void:
	var item: Dictionary = ITEMS[i]
	active = true
	current = i
	if not keep_switch:
		FeelSwitch.set_all_old(false)
	Dialogue.in_run_scenes = false
	Run.start_run()
	var room: String = Run.BOSS_SCENE if item.room == "boss" else str(item.room)
	if FeelSwitch.is_old(&"hammer_cooldown") and item.has("old_room") and ResourceLoader.exists(str(item.old_room)):
		room = str(item.old_room)
	Run.room_order.assign([room, room])
	Run.set_meta("quick_check_weapon", str(item.weapon))
	tree.change_scene_to_file("res://scenes/game.tscn")

## Конец проверки (главное меню): всё по-новому, сюжетные сцены снова включены.
static func finish() -> void:
	if not active:
		return
	active = false
	current = -1
	FeelSwitch.set_all_old(false)
	Dialogue.in_run_scenes = true
	if Run.has_meta("quick_check_weapon"):
		Run.remove_meta("quick_check_weapon")

func _ready() -> void:
	UIStyle.full_rect(self)
	UISkin.apply(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	UIStyle.full_rect(bg)
	add_child(bg)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	add_child(center)
	var panel := UIStyle.panel(Color(0.08, 0.08, 0.1, 0.96), Color(UIStyle.GOLD, 0.6), "window")
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(UIStyle.label(tr("Быстрая проверка"), 34, UIStyle.GOLD, 8))
	vb.add_child(UIStyle.label(tr("Что нового в этой сборке. В зале F6 — сравнить со старым."), 16, UIStyle.TEXT_DIM, 3))
	var first: Button = null
	for i in ITEMS.size():
		var item: Dictionary = ITEMS[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.custom_minimum_size = Vector2(560, 0)
		texts.add_child(UIStyle.label(tr(str(item.title)), 22, UIStyle.TEXT, 4))
		var desc := UIStyle.label(tr(str(item.text)), 15, UIStyle.TEXT_DIM, 3)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(desc)
		row.add_child(texts)
		var b := UIStyle.button(tr("Попробовать"), 20, "secondary")
		b.custom_minimum_size = Vector2(200, 48)
		b.pressed.connect(QuickCheck.start.bind(get_tree(), i))
		row.add_child(b)
		vb.add_child(row)
		if first == null:
			first = b
	var back := UIStyle.button(tr("Назад"), 20, "danger")
	back.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	var back_box := CenterContainer.new()
	back_box.add_child(back)
	vb.add_child(back_box)
	if first:
		first.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()


## Плашка в зале: что сейчас включено, F6 — переключить. Создаёт Game._ready при QuickCheck.active.
class Overlay extends CanvasLayer:
	var _label: Label

	func _ready() -> void:
		layer = 20
		process_mode = Node.PROCESS_MODE_ALWAYS
		_label = UIStyle.label("", 18, UIStyle.GOLD, 6)
		_label.position = Vector2(20, 96)
		add_child(_label)
		_refresh()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F6:
			FeelSwitch.set_all_old(not FeelSwitch.is_old(&"hammer_cooldown"))
			_refresh()
			get_viewport().set_input_as_handled()
			# Пункт со старой сценой зала — перезапустить зал в другой раскладке
			if QuickCheck.current >= 0 and QuickCheck.ITEMS[QuickCheck.current].has("old_room"):
				get_tree().paused = false
				QuickCheck.start(get_tree(), QuickCheck.current, true)

	func _refresh() -> void:
		var old := FeelSwitch.is_old(&"hammer_cooldown")
		_label.text = tr("БЫСТРАЯ ПРОВЕРКА · F6 — старое/новое: %s") % (tr("СТАРОЕ") if old else tr("НОВОЕ"))
		_label.modulate = Color(1.0, 0.55, 0.45) if old else Color.WHITE
