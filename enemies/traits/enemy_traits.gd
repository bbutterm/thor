extends RefCounted
class_name EnemyTraits
## Выдача черт мобов (GDD 12.6): данные enemies/traits/*.tres (EnemyTraitDef), обработчики — enemies/traits/*.gd.
## Room._spawn_enemy зовёт maybe_assign после Loot.maybe_make_elite: элита, корм и боссы черту не получают.

const DIR := "res://enemies/traits/"
## Значок черты прячется дальше стольких метров от камеры
static var icon_hide_distance: float = 22.0
## Высота значка над ногами (× model_scale)
static var icon_height: float = 2.35

static var _defs: Array[EnemyTraitDef] = []

static func defs() -> Array[EnemyTraitDef]:
	if _defs.is_empty():
		for f in ResourceLoader.list_directory(DIR):
			var clean := f.trim_suffix(".remap")
			if clean.ends_with(".tres"):
				var d := load(DIR + clean) as EnemyTraitDef
				if d and d.enabled:
					_defs.append(d)
	return _defs

static func get_def(id: String) -> EnemyTraitDef:
	for d in defs():
		if d.id == id:
			return d
	return null

static func random_def() -> EnemyTraitDef:
	var list := defs()
	var total := 0.0
	for d in list:
		total += maxf(0.0, d.weight)
	var r := randf() * total
	for d in list:
		r -= maxf(0.0, d.weight)
		if r <= 0.0:
			return d
	return list[list.size() - 1] if not list.is_empty() else null

## Может ли враг получить черту: боец или особый, не элита, не босс, без черты.
static func eligible(enemy: Enemy) -> bool:
	return enemy.kind != Enemy.Kind.BOSS and enemy.kind != Enemy.Kind.FODDER \
		and not enemy.has_meta("elite") and not enemy.has_meta("miniboss") and not enemy.has_meta("enemy_trait")

## С шансом chance дать черту, если в зале их меньше max_per_room (счётчик — метаданные зала "traited").
static func maybe_assign(room: Node, enemy: Enemy, chance: float, max_per_room: int) -> EnemyTraitDef:
	if chance <= 0.0 or not eligible(enemy):
		return null
	var n: int = room.get_meta("traited", 0)
	if n >= max_per_room or randf() >= chance:
		return null
	var d := random_def()
	if d == null:
		return null
	room.set_meta("traited", n + 1)
	assign(enemy, d)
	return d

## Дать черту (до или после add_child врага).
static func assign(enemy: Enemy, d: EnemyTraitDef) -> void:
	Perf.mark("enemy_trait")
	enemy.set_meta("enemy_trait", d.id)
	var mark := Node3D.new()
	mark.name = "TraitMark"
	var mi := MeshInstance3D.new()
	mi.name = "Icon"
	mi.mesh = FX.shared_mesh(d.icon_shape)
	FX.fx_apply(mi, "glow", d.color, 2.2)
	mi.scale = d.icon_scale
	mi.rotation_degrees = d.icon_rotation
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mark.add_child(mi)
	enemy.add_child(mark)
	mark.position = Vector3(0, icon_height * enemy.model_scale, 0)
	if d.handler:
		var h := d.handler.new() as EnemyTraitHandler
		if h:
			h.setup(enemy, d)

static func handler_of(enemy: Enemy) -> EnemyTraitHandler:
	for c in enemy.get_children():
		if c is EnemyTraitHandler:
			return c
	return null

## Образцы значков для прогрева (ShaderWarmup): все фигуры на материале glow.
static func warmup_sample(parent: Node3D, pos: Vector3) -> void:
	var shapes := ["sphere", "box", "ring", "wedge"]
	for i in shapes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = FX.shared_mesh(shapes[i])
		FX.fx_apply(mi, "glow", Color(1, 1, 1), 2.0)
		mi.scale = Vector3.ONE * 0.08
		parent.add_child(mi)
		mi.position = pos + Vector3((i - 1.5) * 0.12, 0, 0)
