extends Node3D
class_name RewardDoor
## Дверь с наградой (GDD 15.1): каменная арка Quaternius, светящийся проём цвета награды и иконка над ней.
## Появляется после выдачи награды зала (RewardFlow), вход в проём — выбор следующего зала.
## Иконка — sprites/ui/icons/door_<icon>.png, если владелец её положил; иначе руна-глиф и подпись.

signal entered(door: RewardDoor)

const FRAME_MODEL := "res://assets/quaternius/village/DoorFrame_Round_Brick.gltf"
const FONT := "res://fonts/RussoOne-Regular.ttf"
const TRIGGER_L := 1 << 5
const PLAYER_L := 1 << 1
const WORLD_L := 1

## Масштаб арки (модель 1.6 × 2.6 м)
const FRAME_SCALE := 1.55
## Высота иконки над полом
const ICON_HEIGHT := 4.95

var reward: RewardDef
var reward_id: String = ""
var used: bool = false
var _icon: Node3D
var _portal: MeshInstance3D
var _light: OmniLight3D
var _area: Area3D

## Собрать дверь (до add_child).
static func create(def: RewardDef, id: String) -> RewardDoor:
	var d := RewardDoor.new()
	d.reward = def
	d.reward_id = id
	d.name = "RewardDoor_" + id
	return d

func _ready() -> void:
	set_meta("transient", true)
	var col := reward.color if reward else Color(0.93, 0.71, 0.3)
	if ResourceLoader.exists(FRAME_MODEL):
		var m := (load(FRAME_MODEL) as PackedScene).instantiate() as Node3D
		m.name = "Frame"
		m.scale = Vector3.ONE * FRAME_SCALE
		add_child(m)
	# Проём — общий меш и общий материал эффектов (цвет — на экземпляре)
	_portal = MeshInstance3D.new()
	_portal.name = "Portal"
	_portal.mesh = FX.shared_mesh("box")
	FX.fx_apply(_portal, "alpha", Color(col, 0.55), 1.6)
	_portal.scale = Vector3(1.6, 2.75, 0.06)
	_portal.position = Vector3(0, 1.38, 0)
	_portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_portal)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = col
	_light.light_energy = 1.6
	_light.omni_range = 5.0
	_light.position = Vector3(0, 2.0, 0.8)
	add_child(_light)
	_build_icon(col)
	# Столбы арки — твёрдые (без них сквозь камень проходят)
	var body := StaticBody3D.new()
	body.name = "Pillars"
	body.collision_layer = WORLD_L
	body.collision_mask = 0
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.35, 3.6, 0.7)
		cs.shape = bs
		cs.position = Vector3(sx * 1.1, 1.8, 0)
		body.add_child(cs)
	add_child(body)
	_area = Area3D.new()
	_area.name = "Trigger"
	_area.collision_layer = TRIGGER_L
	_area.collision_mask = PLAYER_L
	_area.monitorable = false
	var s := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 2.8, 0.9)
	s.shape = box
	s.position = Vector3(0, 1.4, 0)
	_area.add_child(s)
	add_child(_area)
	if not has_meta("warmup"):
		_area.body_entered.connect(_on_body_entered)

func _build_icon(col: Color) -> void:
	_icon = Node3D.new()
	_icon.name = "Icon"
	_icon.position = Vector3(0, ICON_HEIGHT, 0)
	add_child(_icon)
	var tex := reward.icon() if reward else null
	if tex:
		var spr := Sprite3D.new()
		spr.name = "Sprite"
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.pixel_size = 1.1 / maxf(1.0, float(tex.get_width()))
		spr.position.y = 0.45
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_icon.add_child(spr)
	else:
		_icon.add_child(_label("Glyph", reward.glyph if reward else "?", 170, col, 0.45))
	_icon.add_child(_label("Title", (reward.title if reward else reward_id).to_upper(), 62, Color(1, 0.96, 0.88), -0.3))
	if reward and reward.description != "":
		_icon.add_child(_label("Desc", reward.description, 38, Color(0.92, 0.9, 0.85), -0.68))
	var tw := _icon.create_tween().set_loops()
	tw.tween_property(_icon, "position:y", ICON_HEIGHT + 0.15, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_icon, "position:y", ICON_HEIGHT - 0.05, 0.9).set_trans(Tween.TRANS_SINE)

func _label(n: String, text: String, size: int, col: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.name = n
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = maxi(6, size / 6)
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, y, 0)
	l.width = 640.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var f := load(FONT) as Font
	if f:
		l.font = f
	return l

## Появление: арка поднимается из пола.
func appear(delay: float = 0.0) -> void:
	var y := position.y
	position.y = y - 4.2
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "position:y", y, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Точка внутри проёма (тесты, подсказки).
func trigger_position() -> Vector3:
	return global_position + Vector3(0, 0.3, 0)

func _on_body_entered(body: Node) -> void:
	if used or not body is Player:
		return
	used = true
	entered.emit(self)

## Погасить (выбрана другая дверь).
func dim() -> void:
	used = true
	if _portal:
		_portal.transparency = 0.8
	if _light:
		_light.light_energy = 0.3
