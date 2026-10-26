extends Node3D
class_name ShopStall
## Ларёк Брокка и Эйтри (GDD 13) в зале-ларьке: прилавок из ящиков, навес на столбах, телега на колёсах,
## вывеска «РУНЫ • ШАУРМА • ЗАТОЧКА», два гнома (HumanoidModel, маленький масштаб, бороды, без боя).
## Подойти к прилавку и нажать E — экран покупки (RewardFlow.open_shop). Узел ставит генератор
## (tools/build_scenes.gd → зал shop_room), всё остальное собирается здесь при запуске.
## Начало координат — перед прилавком (там стоит игрок), ларёк — в сторону −Z.

const QV := "res://assets/quaternius/village/"
const QP := "res://assets/quaternius/props/"
const FONT := "res://fonts/RussoOne-Regular.ttf"
const SIGN_TEXT := "РУНЫ • ШАУРМА • ЗАТОЧКА"
## Масштаб гномов (человек Quaternius ≈ 1.8 м)
const DWARF_SCALE := 0.62
const POST := Color(0.36, 0.22, 0.12)
const CLOTH_A := Color(0.72, 0.16, 0.12)
const CLOTH_B := Color(0.92, 0.82, 0.62)

var brokk: HumanoidModel
var eitri: HumanoidModel

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("shop_stall")
	_build()

func can_interact() -> bool:
	return true

func prompt_text(_holder: WeaponHolder) -> String:
	return "[E] Ларёк Брокка и Эйтри"

func interact(_holder: WeaponHolder) -> void:
	var g := get_tree().current_scene as Game
	if g and g.rewards:
		g.rewards.open_shop()

func _model(path: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0, parent: Node3D = null) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var m := (load(path) as PackedScene).instantiate() as Node3D
	m.position = pos
	m.rotation_degrees.y = rot_y
	m.scale = Vector3.ONE * scl
	(parent if parent else self).add_child(m)
	return m

func _build() -> void:
	var body := Node3D.new()
	body.name = "Stall"
	body.position = Vector3(0, 0, -1.0)
	add_child(body)
	# Прилавок — три ящика в ряд и два сверху по краям
	for x in [-1.15, 0.0, 1.15]:
		_model(QV + "Prop_Crate.gltf", Vector3(x, 0, 0), randf_range(-6, 6), 1.0, body)
	_model(QV + "Prop_Crate.gltf", Vector3(-1.9, 0, -1.0), 12.0, 0.85, body)
	_model(QV + "Prop_Crate.gltf", Vector3(1.9, 0, -1.0), -8.0, 0.85, body)
	# Товар на прилавке: котёл с шаурмой, свитки рун, зелья, сундучок, книги
	_model(QP + "Cauldron.gltf", Vector3(-1.1, 1.06, 0.0), 0.0, 0.55, body)
	_model(QP + "Scroll_1.gltf", Vector3(0.05, 1.06, 0.15), 30.0, 1.6, body)
	_model(QP + "Potion_1.gltf", Vector3(0.45, 1.06, -0.1), 0.0, 1.8, body)
	_model(QP + "Book_Stack_1.gltf", Vector3(1.15, 1.06, 0.0), -20.0, 1.2, body)
	_model(QP + "CandleStick_Triple.gltf", Vector3(-0.4, 1.06, -0.2), 0.0, 1.0, body)
	# Телега на колёсах за прилавком («ларёк на колёсах»)
	_model(QV + "Prop_Wagon.gltf", Vector3(0.0, 0, -2.6), 90.0, 1.0, body)
	# Столбы и полосатый тканевый навес (общий меш и материал эффектов — без новых материалов)
	for x in [-2.3, 2.3]:
		for z in [0.45, -1.6]:
			_box(body, Vector3(x, 1.5, z), Vector3(0.16, 3.0 if z > 0 else 3.3, 0.16), POST)
		var lamp := _model(QP + "Lantern_Wall.gltf", Vector3(x * 0.92, 2.1, 0.55), 0.0, 0.8, body)
		if lamp:
			lamp.name = "Lantern"
	var awning := Node3D.new()
	awning.name = "Awning"
	awning.position = Vector3(0, 2.75, -0.45)
	awning.rotation_degrees.x = 30.0
	body.add_child(awning)
	for i in 6:
		_box(awning, Vector3(-2.0 + i * 0.8, 0, 0), Vector3(0.8, 0.06, 2.5), CLOTH_A if i % 2 == 0 else CLOTH_B)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 2.4
	light.omni_range = 8.0
	light.position = Vector3(0, 2.4, 0.8)
	body.add_child(light)
	# Вывеска: доска и надпись
	var board := MeshInstance3D.new()
	board.name = "SignBoard"
	board.mesh = FX.shared_mesh("box")
	FX.fx_apply(board, "glow", Color(0.32, 0.18, 0.08), 0.35)
	board.scale = Vector3(4.4, 0.62, 0.08)
	board.position = Vector3(0, 3.35, 0.45)
	body.add_child(board)
	var sign := make_sign_label()
	sign.position = Vector3(0, 3.35, 0.51)
	body.add_child(sign)
	# Твёрдый прилавок (ящики-модели без коллизии)
	var sb := StaticBody3D.new()
	sb.name = "Counter"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.6, 1.1, 1.1)
	cs.shape = bs
	cs.position = Vector3(0, 0.55, 0)
	sb.add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(2.2, 1.6, 4.0)
	cs2.shape = bs2
	cs2.position = Vector3(0, 0.8, -2.6)
	sb.add_child(cs2)
	body.add_child(sb)
	# Гномы за прилавком
	# Гномы по бокам прилавка (за ящиками их не видно — ростом они ниже прилавка)
	brokk = _dwarf("Brokk", Color(0.75, 0.45, 0.22), Vector3(-2.95, 0, 0.55), "Hair_Beard.gltf")
	eitri = _dwarf("Eitri", Color(0.5, 0.5, 0.55), Vector3(2.95, 0, 0.45), "Hair_Beard.gltf")
	body.add_child(brokk)
	body.add_child(eitri)
	brokk.rotation_degrees.y = 18.0
	eitri.rotation_degrees.y = -22.0
	# Наковальня Эйтри — котёл-«горн» и ящик рядом
	_model(QV + "Prop_Crate.gltf", Vector3(3.0, 0, -0.75), 25.0, 0.6, body)
	brokk.play("Idle_Loop", 0.0)
	eitri.play("Idle_Loop", 0.0, 0.8)

## Брусок: общий меш-коробка и общий освещённый материал эффектов, цвет — на экземпляре.
func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = FX.shared_mesh("box")
	FX.fx_apply(m, "glow", col, 0.12)
	m.scale = size
	m.position = pos
	parent.add_child(m)
	return m

static func make_sign_label() -> Label3D:
	var l := Label3D.new()
	l.name = "Sign"
	l.text = SIGN_TEXT
	l.font_size = 64
	l.pixel_size = 0.0055
	l.outline_size = 10
	l.modulate = Color(1.0, 0.78, 0.35)
	l.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	var f := load(FONT) as Font
	if f:
		l.font = f
	return l

func _dwarf(n: String, cloth: Color, pos: Vector3, hair: String) -> HumanoidModel:
	var h := HumanoidModel.new()
	h.name = n
	h.outfit = "outfits/Male_Peasant.gltf"
	h.hair = "hair/" + hair
	h.parts = PackedStringArray(["hair/Eyebrows_Regular.gltf"])
	h.cloth_tint = cloth
	h.skin_tint = Color(1.0, 0.86, 0.76)
	h.scale = Vector3.ONE * DWARF_SCALE
	h.position = pos
	return h

## Кивнуть (покупка): гном подпрыгивает.
func nod(who: String = "brokk") -> void:
	var h := brokk if who == "brokk" else eitri
	if h == null:
		return
	var y := h.position.y
	var tw := h.create_tween()
	tw.tween_property(h, "position:y", y + 0.15, 0.08)
	tw.tween_property(h, "position:y", y, 0.12)
