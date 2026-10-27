extends ComicInsert
class_name BossCard
## Заставка босса (GDD 20, «вклейка»): при появлении Толстого Свена и Ярла Бьорна — карточка
## sprites/boss_cards/<id>.webp (ScreenArt.BOSSES): влетает с наклоном, вспышка при «ударе», имя босса
## на плашке (tr), ~2 с, клик / клавиша пропускает. Игра на паузе (ComicInsert). Интро-диалог босса
## (Dialogue.on_boss_intro) не ломает: пока идёт сцена-новелла, карточка ждёт её конца.
## Выключатель — настройка [comic] boss_card («Заставка босса»). В тестах выключено (ScreenArt.pauses_allowed).

## Сколько карточка стоит на месте, с
@export var hold_time: float = 1.7
@export var fly_in_time: float = 0.26
@export var fly_out_time: float = 0.22
@export var flash_time: float = 0.15
## Наклон карточки на месте, градусы
@export var tilt_deg: float = -3.0
## Ширина карточки — доля ширины экрана
@export var width_frac: float = 0.74

var boss_id: String = ""
var card_id: String = ""
var title: String = ""
var miniboss: bool = false
var texture: Texture2D

static var shown_count: int = 0
static var last_id: String = ""

var _root: Control
var _dim: ColorRect
var _flash: ColorRect
var _card: Control
var _plate: Control
var _out_at: float = -1.0

## Карточка для врага-босса со своей заставкой. null — у врага её нет или выключено.
static func show_for(parent: Node, boss: Node) -> BossCard:
	var info := ScreenArt.boss_info(boss)
	if info.is_empty() or parent == null or not ScreenArt.boss_card_enabled():
		return null
	var c := BossCard.new()
	c.boss_id = str(info.id)
	c.card_id = str(info.card)
	c.miniboss = bool(info.get("miniboss", false))
	c.title = str(boss.get_meta("boss_title", ""))
	c.texture = ScreenArt.tex(ScreenArt.boss_card_path(c.card_id))
	parent.add_child(c)
	return c

func _ready() -> void:
	layer = 15  # над HUD (5) и словами (6), под выбором руны/трейта (10–11) — их в этот момент нет
	await begin()
	if not is_inside_tree():
		return
	Perf.mark("boss_card")
	shown_count += 1
	last_id = boss_id
	_build()
	_tick(0.0)

func _build() -> void:
	_root = Control.new()
	UIStyle.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.04, 0.0)
	UIStyle.full_rect(_dim)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	var vp := _root.get_viewport_rect().size
	var w := vp.x * width_frac
	var size := Vector2(w, w * 9.0 / 16.0)
	# «Наклейка»: белая кайма с чёрной обводкой, картинка внутри
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.96, 0.9)
	sb.border_color = Color(0.05, 0.04, 0.05)
	sb.set_border_width_all(4)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(12, 14)
	_card.add_theme_stylebox_override("panel", sb)
	_card.size = size + Vector2(24, 24)
	_card.pivot_offset = _card.size * 0.5
	_root.add_child(_card)
	var pic := TextureRect.new()
	pic.texture = texture
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(pic)
	# Плашка с именем — внизу слева, поверх края карточки, со своим наклоном
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.05, 0.04, 0.97)
	ps.border_color = UIStyle.GOLD
	ps.set_border_width_all(3)
	ps.set_content_margin_all(12)
	ps.content_margin_left = 26
	ps.content_margin_right = 30
	ps.shadow_color = Color(0, 0, 0, 0.6)
	ps.shadow_offset = Vector2(8, 8)
	_plate.add_theme_stylebox_override("panel", ps)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	_plate.add_child(v)
	v.add_child(UIStyle.label(tr("МИНИ-БОСС") if miniboss else tr("БОСС"), 20, Color(0.95, 0.45, 0.3), 4))
	var name_l := UIStyle.label(tr(title) if title != "" else tr("БОСС"), int(clampf(vp.x * 0.045, 34, 72)), UIStyle.GOLD, 10)
	v.add_child(name_l)
	_root.add_child(_plate)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	UIStyle.full_rect(_flash)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

func _tick(t: float) -> void:
	if _root == null:
		return
	if skipped and _out_at < 0.0:
		_out_at = maxf(t, fly_in_time)
	if _out_at < 0.0 and t >= fly_in_time + hold_time:
		_out_at = t
	var vp := _root.get_viewport_rect().size
	var center := vp * Vector2(0.5, 0.46) - _card.size * 0.5
	var k := t / maxf(fly_in_time, 0.01)
	var e := ease_back(k, 1.1)
	var x := lerpf(vp.x * 1.1, 0.0, e)
	var rot := lerpf(12.0, tilt_deg, ease_out(k))
	var out := 0.0
	if _out_at >= 0.0:
		out = clampf((t - _out_at) / maxf(fly_out_time, 0.01), 0.0, 1.0)
		x -= vp.x * 1.3 * out * out
		rot += -8.0 * out
	_card.position = center + Vector2(x, 0)
	_card.rotation = deg_to_rad(rot)
	# Имя въезжает слева чуть позже карточки
	var pk := ease_back((t - fly_in_time * 0.7) / 0.22, 1.4)
	var ps := _plate.get_combined_minimum_size()
	_plate.size = ps
	_plate.pivot_offset = ps * 0.5
	_plate.position = Vector2(lerpf(-ps.x - 40.0, vp.x * 0.09, pk) - vp.x * 1.3 * out * out, center.y + _card.size.y - ps.y * 0.55)
	_plate.rotation = deg_to_rad(2.0)
	_dim.color.a = 0.62 * clampf(t / 0.12, 0.0, 1.0) * (1.0 - out)
	# Вспышка в момент «удара» карточки о середину
	var f := (t - fly_in_time * 0.85) / maxf(flash_time, 0.01)
	_flash.color.a = (0.85 * (1.0 - f)) if f >= 0.0 and f <= 1.0 else 0.0
	if out >= 1.0:
		finish()
