extends Control
class_name CommandWords
## Слова-команды (П10, NOW.md партия 9): крупно по центру сверху на show_time, не чаще раза в gap с, одна за раз;
## опасность (красная) перебивает остальные. Виды: action — жёлтая (бой), move — синяя (движение), danger — красная.
## Подложка — картинка владельца sprites/ui/commands/plate_<вид>.webp, если есть, иначе comic_burst цвета вида;
## текст всегда кодом поверх (tr(), en — в en.po). Выключатель — [hud] commands.
## События: волна (Room.wave_started) и окна/телеграфы боссов — cue(id) из кода; остальное — опрос в _poll
## (молот близко к руке, последний враг, волна зачищена, уступ рядом с толпой, высота над толпой, мало ХП / зона,
## удар со спины). Создаёт HUD._build; CommandWords.current — для cue() из врагов.

const WORDS := {
	&"smash": ["КРУШИ!", "action"],
	&"catch": ["ЛОВИ!", "action"],
	&"hit": ["БЕЙ!", "action"],
	&"finish": ["ДОБЕЙ!", "action"],
	&"go": ["ВПЕРЁД!", "move"],
	&"up": ["ВВЕРХ!", "move"],
	&"jump": ["ПРЫГАЙ!", "move"],
	&"run": ["БЕГИ!", "danger"],
	&"behind": ["СЗАДИ!", "danger"],
	&"dodge": ["УВОРАЧИВАЙСЯ!", "danger"],
}
const KIND_COLOR := {"action": Color(1.0, 0.82, 0.2), "move": Color(0.35, 0.7, 1.0), "danger": Color(1.0, 0.25, 0.2)}
const KIND_PRIORITY := {"move": 0, "action": 1, "danger": 2}
const PLATE_DIR := "res://sprites/ui/commands/plate_%s.webp"

static var current: CommandWords

## Сколько секунд видно слово и минимальный промежуток между словами (с)
@export var show_time: float = 0.8
@export var gap: float = 3.0
## Как часто проверять условия (с)
@export var poll_interval: float = 0.1
## ЛОВИ!: до хвата меньше (с); ВВЕРХ!: уступ/руна ближе (м) и толпа рядом не меньше; ПРЫГАЙ!: высота (м) и толпа под Тором
@export var catch_eta: float = 0.5
@export var up_distance: float = 4.0
@export var up_crowd: int = 6
@export var jump_height: float = 4.0
@export var jump_crowd: int = 5
## БЕГИ!: здоровье ниже доли; СЗАДИ!: замах врага ближе (м) за спиной
@export var run_health: float = 0.25
@export var behind_distance: float = 4.0

var player: Player
var _plate: TextureRect
var _label: Label
var _left: float = 0.0
var _last_time: float = -100.0
var _last_kind: String = ""
var _shown_id: StringName = &""
var _poll_t: float = 0.0
var _room: Room
var _room_caught: bool = false
var _finish_wave: int = -1
var _go_wave: int = -1
var _low_hp: bool = false
var _in_zone: bool = false
## Последнее показанное слово (тесты)
var last_id: StringName = &""

func _ready() -> void:
	current = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Подложка владельца — 3 : 1 (1086×362), слово — по центру поверх
	offset_left = -270
	offset_right = 270
	offset_top = 120
	offset_bottom = 300
	_plate = TextureRect.new()
	_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(_plate)
	add_child(_plate)
	_label = UIStyle.label("", 50, Color.WHITE, 12)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyle.full_rect(_label)
	add_child(_label)
	modulate.a = 0.0
	pivot_offset = Vector2(270, 90)

func _exit_tree() -> void:
	if current == self:
		current = null

## Показать слово из кода игры (волна, окно или телеграф босса). Нет HUD или выключено — ничего.
static func cue(id: StringName) -> void:
	if current and is_instance_valid(current):
		current.request(id)

static func enabled() -> bool:
	return bool(GameSettings.get_value("hud", "commands"))

## true — слово показано
func request(id: StringName) -> bool:
	if not WORDS.has(id) or not enabled():
		return false
	var kind: String = WORDS[id][1]
	var now := Time.get_ticks_msec() / 1000.0
	var showing := _left > 0.0
	var urgent := int(KIND_PRIORITY[kind]) > int(KIND_PRIORITY.get(_last_kind, -1))
	# Одна за раз и не чаще gap; опасность перебивает слово попроще
	if now - _last_time < gap and not (urgent and kind == "danger" and (showing or _last_kind != "danger")):
		return false
	if showing and id == _shown_id:
		return false
	_show(id, kind)
	_last_time = now
	_last_kind = kind
	return true

func _show(id: StringName, kind: String) -> void:
	_shown_id = id
	last_id = id
	_label.text = tr(str(WORDS[id][0]))
	var col: Color = KIND_COLOR[kind]
	_label.label_settings.font_color = col.lightened(0.55)
	_label.label_settings.outline_color = Color.BLACK
	var path := PLATE_DIR % kind
	if ResourceLoader.exists(path):
		# На рисованной подложке — белое слово с тёмной обводкой цвета вида (светлое на светлом не читается)
		_plate.texture = load(path)
		_plate.modulate = Color.WHITE
		_label.label_settings.font_color = Color.WHITE
		_label.label_settings.outline_color = col.darkened(0.75)
	else:
		_plate.texture = UISkin.texture("comic_burst_0%d" % (1 + (hash(id) % 6 + 6) % 6))
		_plate.modulate = Color(col, 0.95)
	_left = show_time
	modulate.a = 1.0
	scale = Vector2.ONE * 1.25
	Perf.mark("command_" + str(id))

func _process(delta: float) -> void:
	var real := FX.real_delta(delta)
	if _left > 0.0:
		_left = maxf(0.0, _left - real)
		scale = scale.lerp(Vector2.ONE, clampf(real * 14.0, 0.0, 1.0))
		modulate.a = clampf(_left / 0.2, 0.0, 1.0)
	_poll_t -= real
	if _poll_t <= 0.0:
		_poll_t = poll_interval
		_poll()

## Условия по состоянию игры
func _poll() -> void:
	if player == null or not is_instance_valid(player) or player.is_dead or get_tree().paused or not enabled():
		return
	var game := get_tree().current_scene as Game
	var room := game.room if game and is_instance_valid(game.room) else null
	if room != _room:
		_room = room
		_room_caught = false
		_finish_wave = -1
		_go_wave = -1
		if room and not room.wave_started.is_connected(_on_wave_started):
			room.wave_started.connect(_on_wave_started)
	# Опасность
	var hp_low := player.health < player.max_health * run_health
	if hp_low and not _low_hp:
		request(&"run")
	_low_hp = hp_low
	var in_zone := player.is_on_floor() and _in_hazard()
	if in_zone and not _in_zone:
		request(&"run")
	_in_zone = in_zone
	if _enemy_behind():
		request(&"behind")
	# Бой
	var m := player.mjolnir
	if m.projectile and is_instance_valid(m.projectile) and m.projectile.state == MjolnirProjectile.State.RETURN:
		var eta := m.projectile.catch_eta()
		if eta > 0.0 and eta < catch_eta and not (_room_caught and GameSettings.catch_assist()):
			if request(&"catch"):
				_room_caught = true
	if room:
		var alive := room.alive_enemies().size()
		var queue := (room.get("_spawn_queue") as Array).size()
		var wave := int(room.get("_wave_index"))
		var waves := (room.get("_waves") as Dictionary).size()
		if alive == 1 and queue == 0 and _finish_wave != wave:
			if request(&"finish"):
				_finish_wave = wave
		if alive == 0 and queue == 0 and not bool(room.get("_is_cleared")) and wave + 1 < waves and _go_wave != wave:
			if request(&"go"):
				_go_wave = wave
	# Движение
	if _crowd_below() >= jump_crowd:
		request(&"jump")
	elif _near_ledge() and _crowd_near(10.0) >= up_crowd:
		request(&"up")

func _on_wave_started(_index: int) -> void:
	request(&"smash")

func _in_hazard() -> bool:
	for z in get_tree().get_nodes_in_group("hazard_zones"):
		if z is HazardZone and (z as HazardZone).contains(player.global_position):
			return true
	return false

func _enemy_behind() -> bool:
	var fwd := player.get_aim_forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead or e.state != Enemy.State.WINDUP:
			continue
		var to := e.global_position - player.global_position
		to.y = 0.0
		if to.length() < behind_distance and to.length() > 0.1 and fwd.dot(to.normalized()) < -0.3:
			return true
	return false

func _crowd_near(radius: float) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e as Enemy).is_dead and (e as Enemy).global_position.distance_to(player.global_position) < radius:
			n += 1
	return n

## Сколько врагов под Тором: ниже на jump_height и не дальше 7 м по горизонтали
func _crowd_below() -> int:
	var n := 0
	var p := player.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.is_dead or p.y - en.global_position.y < jump_height:
			continue
		var d := en.global_position - p
		d.y = 0.0
		if d.length() < 7.0:
			n += 1
	return n

func _near_ledge() -> bool:
	for j in get_tree().get_nodes_in_group("jump_pads"):
		if (j as Node3D).global_position.distance_to(player.global_position) <= up_distance:
			return true
	return false
