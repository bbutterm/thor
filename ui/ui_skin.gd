extends RefCounted
class_name UISkin
## Скин интерфейса на графике владельца (sprites/ui/**, описание — sprites/ui/README_UI_VFX.md).
## Манифест data/ui_manifest.json читается один раз: путь, исходный размер, 9-slice, fill_rect полос HUD.
## Все координаты манифеста — в пикселях ИСХОДНИКА; текстура после импорта может быть меньше
## (process/size_limit в .import) — пересчёт через src_to_tex(id).
## texture(id) — текстура; stylebox(id, scale) — SkinStyleBox (9-slice с масштабом, ui/skin_style_box.gd);
## theme() — общая Theme (кнопки, панели, флажки, ползунки, полосы, прокрутка, всплывающие списки);
## apply(control) — тема + фильтрация с мипмапами (картинки 1024 px ужимаются в 3–4 раза без ряби).
## Нет манифеста или файла — texture() вернёт null, stylebox() — StyleBoxFlat в цветах UIStyle (игра не падает).

const MANIFEST_PATH := "res://data/ui_manifest.json"

## Видимая часть картинок (альфа > 24), пиксели исходника: x0, y0, x1, y1. Прозрачные поля вокруг рамки
## не должны съедать место под содержимое — SkinStyleBox рисует их за пределами контрола (grow).
## Для кнопок одной семьи берём «normal»: hover/pressed нарисованы на том же холсте.
const VISIBLE := {
	"button_main": [14, 15, 1010, 176],
	"button_secondary": [14, 21, 1010, 170],
	"button_danger": [14, 21, 1010, 170],
	"panel_dialogue": [56, 20, 968, 268],
	"panel_nameplate": [94, 21, 546, 138],
	"panel_shop": [144, 120, 879, 647],
	"panel_training": [165, 111, 859, 657],
	"slider_track": [154, 7, 613, 81],
}
## Где начинается содержимое — отступ от ВИДИМОГО края, пиксели исходника: left, top, right, bottom
const CONTENT := {
	"button_main": [118, 26, 118, 26],
	"button_secondary": [96, 24, 96, 24],
	"button_danger": [118, 24, 118, 24],
	"panel_dialogue": [136, 44, 136, 44],
	"panel_nameplate": [62, 22, 62, 22],
	"panel_shop": [110, 150, 110, 80],
	"panel_training": [96, 90, 100, 80],
	"slider_track": [40, 20, 40, 20],
}
## Поправки 9-slice (пиксели исходника). У slider_track поля манифеста (95) лежат в прозрачном крае
## и тянули бы торцы — рисуем только видимую часть (CROP), поля — от её края. Panel_training: верх 400
## держит перо, но в невысоком окне всё было бы углом — 300 хватает на верёвку и перо. Panel_shop: низ 170
## режет железные уголки (начинаются с y≈515) — тянулись бы по высоте, берём 260.
const SLICE_FIX := {
	"slider_track": [42, 20, 42, 20],
	"panel_training": [250, 300, 250, 160],
	"panel_shop": [250, 350, 250, 260],
}
## Рисовать только видимую часть VISIBLE (поля SLICE_FIX — от её края)
const CROP := ["slider_track"]

static var _manifest: Dictionary = {}
static var _loaded: bool = false
static var _tex: Dictionary = {}
static var _scaled: Dictionary = {}
static var _theme: Theme

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		push_warning("UISkin: нет манифеста %s" % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_manifest = (parsed as Dictionary).get("assets", {})

## Все id манифеста (UI и VFX)
static func ids() -> Array:
	_ensure()
	return _manifest.keys()

static func has(id: String) -> bool:
	_ensure()
	return _manifest.has(id)

static func entry(id: String) -> Dictionary:
	_ensure()
	return _manifest.get(id, {})

static func path(id: String) -> String:
	return str(entry(id).get("path", ""))

## Текстура по id (кэш). Нет id или файла — null.
static func texture(id: String) -> Texture2D:
	if _tex.has(id):
		return _tex[id]
	var p := path(id)
	var t: Texture2D = null
	if p != "" and ResourceLoader.exists(p):
		t = load(p) as Texture2D
	_tex[id] = t
	return t

## Исходный размер (манифест «size»), если нет — размер текстуры
static func source_size(id: String) -> Vector2:
	var s: Array = entry(id).get("size", [])
	if s.size() == 2:
		return Vector2(float(s[0]), float(s[1]))
	var t := texture(id)
	return t.get_size() if t else Vector2.ONE

## Пикселей текстуры на пиксель исходника (меньше 1, если импорт уменьшил картинку)
static func src_to_tex(id: String) -> float:
	var t := texture(id)
	if t == null:
		return 1.0
	return float(t.get_width()) / maxf(source_size(id).x, 1.0)

## Прямоугольник из манифеста (fill_rect, content_rect) в пикселях исходника
static func rect(id: String, key: String) -> Rect2:
	var r: Array = entry(id).get(key, [])
	if r.size() == 4:
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return Rect2()

static func nine_slice(id: String) -> Vector4:
	var fix: Array = SLICE_FIX.get(id, [])
	if fix.size() == 4:
		return Vector4(fix[0], fix[1], fix[2], fix[3])
	var n: Dictionary = entry(id).get("nine_slice", {})
	return Vector4(float(n.get("left", 0)), float(n.get("top", 0)), float(n.get("right", 0)), float(n.get("bottom", 0)))

## «button_main_hover» → «button_main» (семья для VISIBLE/CONTENT)
static func family(id: String) -> String:
	for suffix in ["_normal", "_hover", "_pressed"]:
		if id.ends_with(suffix):
			return id.substr(0, id.length() - suffix.length())
	return id

## StyleBox по id: 9-slice (если есть nine_slice), иначе картинка целиком (FIT).
## scale — экранных px на px исходника (кнопка 1024×192 при 0.3 — торцы ~36 px, высота — какая нужна);
## pad — доп. поля содержимого (px экрана). Прозрачные поля картинки выносятся за контрол.
static func stylebox(id: String, scale: float = 0.3, pad: float = 0.0) -> StyleBox:
	var t := texture(id)
	if t == null:
		var fb := UIStyle.panel_style()
		fb.content_margin_left += pad
		fb.content_margin_right += pad
		return fb
	var sb := SkinStyleBox.new()
	sb.texture = t
	var k := src_to_tex(id)
	sb.draw_scale = scale / k
	var n := nine_slice(id)
	sb.mode = SkinStyleBox.Mode.NINE if n != Vector4.ZERO else SkinStyleBox.Mode.FIT
	sb.slice = n * k
	var fam := family(id)
	var src := source_size(id)
	var vis: Array = VISIBLE.get(fam, [0, 0, src.x, src.y])
	if fam in CROP:
		sb.region = Rect2(Vector2(vis[0], vis[1]) * k, Vector2(vis[2] - vis[0], vis[3] - vis[1]) * k)
	elif sb.mode == SkinStyleBox.Mode.NINE:
		sb.grow = Vector4(vis[0], vis[1], src.x - vis[2], src.y - vis[3]) * scale
	var c: Array = CONTENT.get(fam, [])
	if c.size() == 4:
		sb.content_margin_left = c[0] * scale + pad
		sb.content_margin_top = c[1] * scale + pad
		sb.content_margin_right = c[2] * scale + pad
		sb.content_margin_bottom = c[3] * scale + pad
	elif sb.mode == SkinStyleBox.Mode.NINE:
		sb.content_margin_left = maxf(n.x - vis[0], 0.0) * scale + pad
		sb.content_margin_top = maxf(n.y - vis[1], 0.0) * scale + pad
		sb.content_margin_right = maxf(n.z - (src.x - vis[2]), 0.0) * scale + pad
		sb.content_margin_bottom = maxf(n.w - (src.y - vis[3]), 0.0) * scale + pad
	else:
		sb.set_content_margin_all(pad)
	return sb

## Загрузить заранее всё, что HUD может показать посреди боя (иконки Мьёльнира, оружия, трейтов, рун):
## иначе первая смена состояния молота или подбор оружия читали бы файл в бою. Зовёт HUD при загрузке игры
## (под затемнением).
static func preload_game() -> void:
	for id in ids():
		var p := path(id)
		if p.begins_with("res://sprites/ui/hud/") or p.begins_with("res://sprites/ui/icons/"):
			texture(id)

## Текстура, уменьшенная до size (иконки тем: ползунок, флажок рисуются в размер картинки).
## Уменьшаем один раз на CPU; в headless (нет данных картинки) — исходная текстура.
static func scaled_texture(id: String, size: Vector2i) -> Texture2D:
	var key := "%s@%dx%d" % [id, size.x, size.y]
	if _scaled.has(key):
		return _scaled[key]
	var t := texture(id)
	var out: Texture2D = t
	if t:
		var img := t.get_image()
		if img and not img.is_empty():
			img = img.duplicate() as Image
			if img.is_compressed():
				img.decompress()
			img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
			out = ImageTexture.create_from_image(img)
	_scaled[key] = out
	return out

## Тема + фильтрация. Вызывать на корневом Control экрана (CanvasLayer тему не передаёт).
static func apply(c: Control) -> void:
	c.theme = theme()
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Кнопка из комплекта: kind = main / secondary / danger (normal/hover/pressed; disabled — серый normal,
## фокус клавиатуры — подсветка hover поверх).
static func style_button(b: Button, kind: String = "main", scale: float = 0.3) -> void:
	var base := "button_" + kind
	if texture(base + "_normal") == null:
		return
	var normal := stylebox(base + "_normal", scale)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", stylebox(base + "_hover", scale))
	b.add_theme_stylebox_override("pressed", stylebox(base + "_pressed", scale))
	b.add_theme_stylebox_override("hover_pressed", stylebox(base + "_pressed", scale))
	b.add_theme_stylebox_override("disabled", _disabled(normal))
	b.add_theme_stylebox_override("focus", _focus(base, scale))

static func _disabled(normal: StyleBox) -> StyleBox:
	if normal is SkinStyleBox:
		return (normal as SkinStyleBox).tinted(Color(0.55, 0.55, 0.58, 0.8))
	return normal

static func _focus(base: String, scale: float) -> StyleBox:
	var f := stylebox(base + "_hover", scale)
	if f is SkinStyleBox:
		(f as SkinStyleBox).modulate = Color(1, 1, 1, 0.55)
	return f

## Иконка оружия по WeaponDef.id (ключи комплекта: weapon_<id>)
const WEAPON_ICON := {
	"rifle": "weapon_assault_rifle", "assault_rifle": "weapon_assault_rifle", "shotgun": "weapon_sawed_off",
	"sawed_off": "weapon_sawed_off", "nailgun": "weapon_nail_gun", "nail_gun": "weapon_nail_gun",
}
## Иконка трейта Мьёльнира по MjolnirTrait.id
## Стихии и приёмы (блок Б4) — картинки бывших трейтов: молния — цепная, земля — «Тяжесть».
## Приёмы и связки без картинок показывают руну-глиф в круге (запасной вид в HUD и на карточках).
const TRAIT_ICON := {
	"fire_trail": "trait_fire", "ice_trail": "trait_ice", "pull_to_hammer": "trait_pull", "sky_thunder": "trait_sky_lightning",
	"heaviness": "trait_heavy", "two_hammers": "trait_double",
	"fire": "trait_fire", "ice": "trait_ice", "lightning": "trait_chain_lightning", "earth": "trait_heavy",
}
## Иконка категории руны (RuneDef.category); у Мьёльнира своей категории в комплекте нет — молот
const RUNE_CATEGORY_ICON := {"mjolnir": "hud_mjolnir_ready"}

static func weapon_icon(weapon_id: String) -> Texture2D:
	return texture(WEAPON_ICON.get(weapon_id, "weapon_" + weapon_id))

static func trait_icon(trait_id: String) -> Texture2D:
	return texture(TRAIT_ICON.get(trait_id, "trait_" + trait_id))

static func rune_category_icon(category: String) -> Texture2D:
	return texture(RUNE_CATEGORY_ICON.get(category, "runecat_" + category))

## Общая тема интерфейса (строится один раз)
static func theme() -> Theme:
	if _theme:
		return _theme
	var th := Theme.new()
	th.default_font = UIStyle.font()
	th.default_font_size = 20
	_theme = th
	if texture("button_main_normal") == null:
		return th
	# Кнопки: основная, второстепенная, опасная, маленькая
	for pair in [["Button", "main", 0.3, 22], ["SecondaryButton", "secondary", 0.26, 20], ["DangerButton", "danger", 0.3, 22],
			["SmallButton", "secondary", 0.2, 17], ["OptionButton", "secondary", 0.24, 18]]:
		var type: String = pair[0]
		var base := "button_" + str(pair[1])
		var sc: float = pair[2]
		if type != "Button" and type != "OptionButton":
			th.set_type_variation(type, "Button")
		var normal := stylebox(base + "_normal", sc)
		th.set_stylebox("normal", type, normal)
		th.set_stylebox("hover", type, stylebox(base + "_hover", sc))
		th.set_stylebox("pressed", type, stylebox(base + "_pressed", sc))
		th.set_stylebox("hover_pressed", type, stylebox(base + "_pressed", sc))
		th.set_stylebox("disabled", type, _disabled(normal))
		th.set_stylebox("focus", type, _focus(base, sc))
		th.set_font_size("font_size", type, pair[3])
		th.set_color("font_color", type, UIStyle.TEXT)
		th.set_color("font_hover_color", type, UIStyle.GOLD)
		th.set_color("font_focus_color", type, UIStyle.GOLD)
		th.set_color("font_pressed_color", type, Color(1, 0.95, 0.8))
		th.set_color("font_hover_pressed_color", type, UIStyle.GOLD)
		th.set_color("font_disabled_color", type, Color(0.6, 0.58, 0.55))
		th.set_color("font_outline_color", type, Color(0, 0, 0, 0.8))
		th.set_constant("outline_size", type, 5)
	# Вкладки (SmallButton с toggle_mode): выбранная — золотом
	th.set_color("font_pressed_color", "SmallButton", UIStyle.GOLD)
	# Панели: тёмная «диалоговая» по умолчанию, деревянная — для окон (пауза, настройки)
	th.set_stylebox("panel", "PanelContainer", stylebox("panel_dialogue", 0.3, 6))
	th.set_stylebox("panel", "Panel", stylebox("panel_dialogue", 0.3, 6))
	th.set_type_variation("WoodPanel", "PanelContainer")
	th.set_stylebox("panel", "WoodPanel", stylebox("panel_training", 0.42, 6))
	th.set_type_variation("NamePlate", "PanelContainer")
	th.set_stylebox("panel", "NamePlate", stylebox("panel_nameplate", 0.34, 2))
	# Флажки и переключатели
	var on := scaled_texture("checkbox_checked", Vector2i(30, 30))
	var off := scaled_texture("checkbox_empty", Vector2i(30, 30))
	for type in ["CheckBox", "CheckButton"]:
		for icon in ["checked", "radio_checked"]:
			th.set_icon(icon, type, on)
			th.set_icon(icon + "_disabled", type, on)
		for icon in ["unchecked", "radio_unchecked"]:
			th.set_icon(icon, type, off)
			th.set_icon(icon + "_disabled", type, off)
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(4)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			th.set_stylebox(st, type, empty)
		th.set_color("font_color", type, UIStyle.TEXT)
		th.set_color("font_hover_color", type, UIStyle.GOLD)
		th.set_color("font_focus_color", type, UIStyle.GOLD)
		th.set_color("font_pressed_color", type, UIStyle.TEXT)
		th.set_color("font_hover_pressed_color", type, UIStyle.GOLD)
		th.set_color("font_outline_color", type, Color(0, 0, 0, 0.8))
		th.set_constant("outline_size", type, 4)
		th.set_constant("h_separation", type, 10)
		th.set_font_size("font_size", type, 19)
	# Ползунок: дорожка, золотая заливка, молот-ручка
	var track := stylebox("slider_track", 0.3)
	track.content_margin_top = 10
	track.content_margin_bottom = 10
	th.set_stylebox("slider", "HSlider", track)
	var fill := _slider_fill()
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", scaled_texture("slider_knob_normal", Vector2i(44, 26)))
	th.set_icon("grabber_highlight", "HSlider", scaled_texture("slider_knob_hover", Vector2i(44, 26)))
	th.set_icon("grabber_disabled", "HSlider", scaled_texture("slider_knob_pressed", Vector2i(44, 26)))
	th.set_constant("center_grabber", "HSlider", 0)
	# Полосы и прокрутка
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0, 0, 0, 0.55)
	pbg.set_corner_radius_all(4)
	th.set_stylebox("background", "ProgressBar", pbg)
	th.set_stylebox("fill", "ProgressBar", fill)
	var sc_bg := StyleBoxFlat.new()
	sc_bg.bg_color = Color(0, 0, 0, 0.35)
	sc_bg.set_corner_radius_all(4)
	sc_bg.content_margin_left = 5
	sc_bg.content_margin_right = 5
	var sc_gr := StyleBoxFlat.new()
	sc_gr.bg_color = Color(UIStyle.GOLD, 0.55)
	sc_gr.set_corner_radius_all(4)
	var sc_hi := sc_gr.duplicate() as StyleBoxFlat
	sc_hi.bg_color = UIStyle.GOLD
	th.set_stylebox("scroll", "VScrollBar", sc_bg)
	th.set_stylebox("grabber", "VScrollBar", sc_gr)
	th.set_stylebox("grabber_highlight", "VScrollBar", sc_hi)
	th.set_stylebox("grabber_pressed", "VScrollBar", sc_hi)
	# Всплывающие списки (OptionButton) и подсказки
	var pop := UIStyle.panel_style(Color(0.08, 0.065, 0.05, 0.98), Color(UIStyle.GOLD, 0.6), 6, 2)
	pop.set_content_margin_all(6)
	th.set_stylebox("panel", "PopupMenu", pop)
	var pop_hover := StyleBoxFlat.new()
	pop_hover.bg_color = Color(UIStyle.GOLD, 0.25)
	pop_hover.set_corner_radius_all(4)
	th.set_stylebox("hover", "PopupMenu", pop_hover)
	th.set_color("font_color", "PopupMenu", UIStyle.TEXT)
	th.set_color("font_hover_color", "PopupMenu", UIStyle.GOLD)
	th.set_font_size("font_size", "PopupMenu", 18)
	th.set_stylebox("panel", "TooltipPanel", pop)
	th.set_color("font_color", "TooltipLabel", UIStyle.TEXT)
	th.set_color("font_color", "Label", UIStyle.TEXT)
	var sep := StyleBoxLine.new()
	sep.color = Color(UIStyle.GOLD, 0.3)
	sep.thickness = 2
	th.set_stylebox("separator", "HSeparator", sep)
	return th

static func _slider_fill() -> StyleBox:
	var t := texture("slider_fill")
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = UIStyle.GOLD
		return f
	var sb := SkinStyleBox.new()
	sb.texture = t
	sb.mode = SkinStyleBox.Mode.NINE
	var k := src_to_tex("slider_fill")
	sb.slice = nine_slice("slider_fill") * k
	sb.draw_scale = 0.6 / k
	# Заливка лежит внутри деревянной дорожки
	sb.grow = Vector4(-9, -7, 0, -7)
	return sb
