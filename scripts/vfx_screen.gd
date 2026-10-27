extends CanvasLayer
class_name VfxScreen
## Экранные эффекты VFX-комплекта (sprites/vfx/*, 1920×1080, растягиваются на экран):
## - линии скорости vfx_speed_lines — рывок, высокая скорость, супер-прыжок, падение и удар-приземление;
## - виньетка берсерка vfx_rage_vignette — высший ранг шкалы стиля (player/style_meter.gd), слабое мерцание у почти полной шкалы;
## - золотое кольцо идеального хвата vfx_perfect_catch у руки (FX.perfect_catch из mjolnir_hand.gd).
## Слой под HUD (затемнение между залами его закрывает). Каждый кадр читает состояние игрока — хуков в player.gd нет.
## Рисуется стандартным 2D-материалом (TextureRect/Sprite2D, цвет — modulate): новых шейдеров и материалов нет.
## Создаёт Game._ready: VfxScreen.attach(game).

const SPEED_TEX := "res://sprites/vfx/vfx_speed_lines.webp"
const RAGE_TEX := "res://sprites/vfx/vfx_rage_vignette.webp"
const CATCH_TEX := "res://sprites/vfx/vfx_perfect_catch.webp"

static var instance: VfxScreen

@export_group("Линии скорости")
## Прозрачность линий на полной скорости (0..1)
@export var speed_alpha: float = 0.7
## Ниже этой силы (camera_fx.speed_lines, 0..1) линий нет
@export var speed_from: float = 0.12
## Вертикальная скорость, м/с: с первой линии появляются, на второй — полные (супер-прыжок, падение)
@export var speed_vertical: Vector2 = Vector2(13.0, 28.0)
## Как быстро линии догоняют нужную силу (1/с)
@export var speed_follow: float = 12.0
## «Бег» линий: столько раз в секунду текстура зеркалится
@export var speed_flicker_hz: float = 12.0
## Линии чуть «дышат» масштабом (доля)
@export var speed_pulse_scale: float = 0.04
@export var speed_color: Color = Color(1.0, 1.0, 1.0)
## Цвет линий в берсерке
@export var speed_rage_color: Color = Color(1.0, 0.6, 0.35)

@export_group("Виньетка берсерка")
## Прозрачность виньетки в берсерке (0..1)
@export var rage_alpha: float = 0.85
## Пульсация ± и её частота, Гц
@export var rage_pulse: float = 0.15
@export var rage_pulse_hz: float = 1.6
## Виньетка «дышит» масштабом (доля)
@export var rage_breathe_scale: float = 0.03
## Вспышка в момент включения берсерка (прозрачность) и как быстро гаснет (1/с)
@export var rage_start_flash: float = 1.0
@export var rage_flash_decay: float = 1.5
## Шкала заполнена больше чем на столько — слабое мерцание по краям (предвкушение)
@export_range(0.0, 1.0) var rage_tease_from: float = 0.8
@export var rage_tease_alpha: float = 0.22
## Как быстро виньетка догоняет нужную прозрачность (1/с)
@export var rage_follow: float = 8.0

@export_group("Идеальный хват")
## Размер кольца в начале, px (при 1280×720), во сколько раз вырастает и за сколько гаснет, с
@export var catch_size_px: float = 170.0
@export var catch_grow: float = 2.2
@export var catch_time: float = 0.32
## Сколько колец одновременно (пул)
@export var catch_limit: int = 2

var player: Player
var speed_rect: TextureRect
var rage_rect: TextureRect
var _catch: Array[Sprite2D] = []
var _speed_shown: float = 0.0
var _rage_shown: float = 0.0
var _rage_flash: float = 0.0
var _flicker_t: float = 0.0
var _t: float = 0.0
var _warm_frames: int = 0
var _rage: StyleMeter

## Создать слой для игры (один на сцену). Процедурные дубли в HUD (линии скорости шейдером,
## градиентная виньетка StyleHUD) прячем — рисованные текстуры их заменяют.
static func attach(game: Node, p: Player) -> VfxScreen:
	var s := VfxScreen.new()
	s.name = "VfxScreen"
	s.player = p
	game.add_child(s)
	var hud := game.get("hud") as Node
	if hud:
		var sr: Variant = hud.get("_speed_rect")
		if sr is CanvasItem:
			(sr as CanvasItem).visible = false
		var rh := hud.get_node_or_null("StyleHUD")
		var vig: Variant = rh.get("_vignette") if rh else null
		if vig is CanvasItem:
			(vig as CanvasItem).visible = false
	return s

func _ready() -> void:
	instance = self
	layer = 4  # под HUD (5): шкалы и затемнение между залами — поверх
	process_mode = Node.PROCESS_MODE_PAUSABLE
	speed_rect = _overlay(SPEED_TEX)
	rage_rect = _overlay(RAGE_TEX)
	var tex: Texture2D = load(CATCH_TEX) if ResourceLoader.exists(CATCH_TEX) else null
	for i in maxi(catch_limit, 1):
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.visible = false
		add_child(sp)
		_catch.append(sp)
	if player:
		CatchAssist.attach(self, player)
	if player and player.style:
		_rage = player.style
		_rage.berserk_started.connect(func() -> void: _rage_flash = rage_start_flash)

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _overlay(path: String) -> TextureRect:
	var r := TextureRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture = load(path) if ResourceLoader.exists(path) else null
	r.modulate.a = 0.0
	r.visible = false
	add_child(r)
	return r

## Прогрев (ShaderWarmup): показать всё почти прозрачным на несколько кадров — загрузка текстур в видеопамять.
func warmup(frames: int = 10) -> void:
	_warm_frames = frames
	for r in [speed_rect, rage_rect]:
		r.visible = true
		r.modulate.a = 0.02
	for sp in _catch:
		sp.visible = true
		sp.modulate.a = 0.02
		sp.position = get_viewport().get_visible_rect().size * 0.5

## Кольцо идеального хвата: вспыхивает у руки (точка мира проецируется камерой), растёт и гаснет.
func perfect_catch(world_pos: Vector3) -> void:
	var vp := get_viewport().get_visible_rect().size
	var pos := vp * 0.5
	var cam := get_viewport().get_camera_3d()
	if cam and not cam.is_position_behind(world_pos):
		pos = cam.unproject_position(world_pos)
	pos = pos.lerp(vp * 0.5, 0.35)  # ближе к прицелу — читается лучше
	var sp: Sprite2D = _catch[0]
	for c in _catch:
		if not c.visible:
			sp = c
			break
		if int(c.get_meta("t", 0)) < int(sp.get_meta("t", 0)):
			sp = c
	if sp.has_meta("tw"):
		var old := sp.get_meta("tw") as Tween
		if old and old.is_valid():
			old.kill()
	sp.set_meta("t", Time.get_ticks_usec())
	var k := catch_size_px / maxf(float(sp.texture.get_width()) if sp.texture else 512.0, 1.0)
	sp.visible = true
	sp.position = pos
	sp.rotation = randf() * TAU
	sp.scale = Vector2.ONE * k * 0.6
	sp.modulate = Color(1, 1, 1, 1)
	var tw := sp.create_tween()
	sp.set_meta("tw", tw)
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * k * catch_grow, catch_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(sp, "rotation", sp.rotation + 0.6, catch_time)
	tw.tween_property(sp, "modulate:a", 0.0, catch_time * 0.6).set_delay(catch_time * 0.4)
	tw.chain().tween_callback(sp.hide)

## Сколько колец хвата сейчас видно (тесты).
func catch_active() -> int:
	return _catch.filter(func(s: Sprite2D) -> bool: return s.visible).size()

## Нужная сила линий скорости 0..1.
func speed_target() -> float:
	if player == null or not is_instance_valid(player) or player.is_dead:
		return 0.0
	var s := player.camera_fx.speed_lines if player.camera_fx else 0.0
	var vy := absf(player.velocity.y)
	s = maxf(s, clampf((vy - speed_vertical.x) / maxf(speed_vertical.y - speed_vertical.x, 0.1), 0.0, 1.0))
	return 0.0 if s < speed_from else s

## Нужная прозрачность виньетки берсерка.
func rage_target() -> float:
	if _rage == null or not is_instance_valid(_rage):
		return 0.0
	if _rage.active:
		return rage_alpha * (1.0 - rage_pulse + rage_pulse * sin(_t * TAU * rage_pulse_hz))
	var v := _rage.value()
	if v >= rage_tease_from and rage_tease_from < 1.0:
		var k := (v - rage_tease_from) / (1.0 - rage_tease_from)
		return rage_tease_alpha * k * (0.6 + 0.4 * sin(_t * TAU * 3.0))
	return 0.0

func _process(delta: float) -> void:
	var real := FX.real_delta(delta)
	_t += real
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			for sp in _catch:
				sp.visible = false
		return
	var vp := get_viewport().get_visible_rect().size
	# Линии скорости
	_speed_shown = lerpf(_speed_shown, speed_target(), clampf(real * speed_follow, 0.0, 1.0))
	speed_rect.visible = _speed_shown > 0.01
	if speed_rect.visible:
		_flicker_t += real * speed_flicker_hz
		var step := int(_flicker_t) % 4
		speed_rect.flip_h = step == 1 or step == 2
		speed_rect.flip_v = step >= 2
		var berserk := _rage != null and is_instance_valid(_rage) and _rage.active
		var col := speed_rage_color if berserk else speed_color
		speed_rect.modulate = Color(col, _speed_shown * speed_alpha)
		_scale_about_center(speed_rect, vp, 1.0 + speed_pulse_scale * (1.0 - _speed_shown) + speed_pulse_scale * 0.5 * sin(_t * 40.0))
	# Виньетка берсерка
	_rage_flash = maxf(0.0, _rage_flash - real * rage_flash_decay)
	_rage_shown = lerpf(_rage_shown, rage_target(), clampf(real * rage_follow, 0.0, 1.0))
	var a := clampf(maxf(_rage_shown, _rage_flash), 0.0, 1.0)
	rage_rect.visible = a > 0.01
	if rage_rect.visible:
		rage_rect.modulate.a = a
		_scale_about_center(rage_rect, vp, 1.0 + rage_breathe_scale * (0.5 + 0.5 * sin(_t * TAU * rage_pulse_hz)) + _rage_flash * 0.04)

## Масштаб полноэкранного прямоугольника относительно центра экрана (края уходят за экран).
func _scale_about_center(r: Control, vp: Vector2, k: float) -> void:
	r.pivot_offset = vp * 0.5
	r.scale = Vector2.ONE * k
