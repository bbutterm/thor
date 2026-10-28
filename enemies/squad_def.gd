extends Resource
class_name SquadDef
## Отряд-комбинация (GDD 12.6): состав, построение, откуда входит, задержка. Данные — enemies/squads/<id>.tres.
## В зале — маркер волны с kind = "squad" и метаданными "squad" (id) или "squad_options" (список id — зал
## берёт один случайно), необязательно "squad_override" {вид: количество} — подогнать состав под бюджет зала
## (вид не из отряда добавляется в передний ряд). Room._spawn_wave раскладывает маркер на маркеры участников
## (expand), центр строя считается при появлении первого участника (resolve_center): «сзади»/«сбоку» — от Тора.
## Поведение строя — роли EnemyTactics (щиты впереди, стрелки за ними — cover; свита вокруг шамана — escort;
## Раздутые за спинами — lurk).

enum Formation { LINE, RING, SCATTER }
enum Entry { MARKER, BEHIND, FLANK }

@export var id: String = ""
@export var title: String = ""
@export var members: Array[SquadMember] = []
@export var formation: Formation = Formation.LINE
@export var entry: Entry = Entry.MARKER
## Через сколько секунд после начала волны появляется (засада)
@export var delay: float = 0.0
## Шаг в шеренге (м), расстояние между рядами, радиус кольца, разброс россыпи
@export var spacing: float = 1.8
@export var row_gap: float = 2.5
@export var ring_radius: float = 3.2
@export var scatter_radius: float = 3.0
## «Сзади»/«сбоку»: на таком расстоянии от Тора
@export var entry_distance: float = 9.0

const DIR := "res://enemies/squads/"

static func find(squad_id: String) -> SquadDef:
	var path := DIR + squad_id + ".tres"
	return load(path) as SquadDef if ResourceLoader.exists(path) else null

static func all_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in ResourceLoader.list_directory(DIR):
		if f.get_extension() == "tres":
			out.append(f.get_basename())
	return out

## Состав с учётом подгонки зала: [{kind, count, role, row, speed_mult, anchor}].
## Подгонка {вид: n} задаёт итог вида (отдаётся первому участнику этого вида), новый вид — в передний ряд.
func roster(override: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for m in members:
		var c := m.count
		if override.has(m.kind):
			c = 0 if seen.has(m.kind) else int(override[m.kind])
		seen[m.kind] = true
		if c > 0:
			out.append({"kind": m.kind, "count": c, "role": m.role, "row": m.row, "speed_mult": m.speed_mult, "anchor": m.anchor})
	for k in override:
		if not seen.has(k) and int(override[k]) > 0:
			out.append({"kind": str(k), "count": int(override[k]), "role": "", "row": 0, "speed_mult": 1.0, "anchor": false})
	return out

## Сколько врагов каждого вида даст отряд (для проверок состава зала).
func totals(override: Dictionary = {}) -> Dictionary:
	var t := {}
	for r in roster(override):
		t[r.kind] = int(t.get(r.kind, 0)) + int(r.count)
	return t

## Выбрать отряд маркера: "squad" или случайный из "squad_options" (выбор запоминается на маркере).
static func for_marker(marker: Node) -> SquadDef:
	if marker.has_meta("_squad_id"):
		return find(str(marker.get_meta("_squad_id")))
	var squad_id := str(marker.get_meta("squad", ""))
	var options: Variant = marker.get_meta("squad_options", [])
	if options is Array and not (options as Array).is_empty():
		squad_id = str((options as Array).pick_random())
	marker.set_meta("_squad_id", squad_id)
	return find(squad_id)

## Разложить маркер отряда на маркеры участников (дети маркера отряда, метаданные kind/wave/роль/смещение строя).
## Каждый участник — отдельный маркер (count 1), кроме корма в россыпи (толпа count/spread).
func expand(marker: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in marker.get_children():
		if c.has_meta("squad_offset"):
			marker.remove_child(c)
			c.queue_free()
	if marker.has_meta("_squad_xform"):
		marker.remove_meta("_squad_xform")
	var override: Dictionary = marker.get_meta("squad_override", {})
	var wave := int(marker.get_meta("wave", 0))
	var rows := {0: 0, 1: 0, 2: 0}
	var row_sizes := {0: 0, 1: 0, 2: 0}
	var plan := roster(override)
	# Якорь — первым: свита при появлении уже знает, вокруг кого держаться
	plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a.anchor) and not bool(b.anchor))
	var ring_total := 0
	for r in plan:
		if formation == Formation.SCATTER and r.kind == "fodder":
			continue
		row_sizes[int(r.row)] += int(r.count)
		if not bool(r.anchor):
			ring_total += int(r.count)
	var ring_i := 0
	for r in plan:
		var crowd: bool = formation == Formation.SCATTER and r.kind == "fodder"
		var n: int = 1 if crowd else int(r.count)
		for i in n:
			var m := Marker3D.new()
			m.name = "%s_%d" % [r.kind, out.size()]
			m.set_meta("kind", r.kind)
			m.set_meta("wave", wave)
			if crowd:
				m.set_meta("count", int(r.count))
				m.set_meta("spread", scatter_radius)
			if str(r.role) != "":
				m.set_meta("tactic_role", str(r.role))
			if bool(r.anchor):
				m.set_meta("squad_anchor", true)
			if not is_equal_approx(float(r.speed_mult), 1.0):
				m.set_meta("speed_mult", float(r.speed_mult))
			if delay > 0.0:
				m.set_meta("not_before", delay)
			for key in ["entry_mode", "entry_target", "spread_axes", "entry_batch"]:
				if marker.has_meta(key):
					m.set_meta(key, marker.get_meta(key))
			var off := Vector3.ZERO
			match formation:
				Formation.LINE:
					var row := int(r.row)
					var k: int = rows[row]
					rows[row] += 1
					var x := (float(k) - (float(row_sizes[row]) - 1.0) * 0.5) * spacing
					var z := 0.0 if row == 0 else (-row_gap if row == 1 else -row_gap * 0.5)
					off = Vector3(x, 0, z)
				Formation.RING:
					if not bool(r.anchor):
						var a := TAU * float(ring_i) / maxf(1.0, float(ring_total))
						ring_i += 1
						off = Vector3(sin(a), 0, cos(a)) * ring_radius
				Formation.SCATTER:
					if not crowd:
						off = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * scatter_radius
			m.set_meta("squad_offset", off)
			marker.add_child(m)
			out.append(m)
	return out

## Центр и поворот строя (+Z смещений — к Тору). Считается один раз, при первом участнике.
func resolve_center(marker: Node3D, player: Node3D) -> Transform3D:
	if marker.has_meta("_squad_xform"):
		return marker.get_meta("_squad_xform")
	var center := marker.global_position
	if player and is_instance_valid(player) and entry != Entry.MARKER:
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.05 else Vector3.FORWARD
		var side := fwd.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		var dirs: Array[Vector3] = [-fwd, side, -side]
		if entry == Entry.FLANK:
			dirs = [side, -side, -fwd]
		var space := marker.get_world_3d().direct_space_state
		# Первая подходящая точка: сзади/сбоку на entry_distance, потом ближе; есть пол на высоте Тора
		# и свободная линия до него. Иначе (Тор у края зала) — из маркера.
		var found := false
		for k in [1.0, 0.6]:
			for dir in dirs:
				var cand: Vector3 = player.global_position + dir * entry_distance * k
				var ground := Loot.floor_point(marker, cand)
				var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, ground + Vector3.UP, 1)
				if ground != cand and absf(ground.y - player.global_position.y) < 1.5 and space.intersect_ray(ray).is_empty():
					center = ground + Vector3(0, 0.05, 0)
					found = true
					break
			if found:
				break
	var face := Vector3.FORWARD
	if player and is_instance_valid(player):
		face = player.global_position - center
		face.y = 0.0
		face = face.normalized() if face.length() > 0.05 else Vector3.FORWARD
	var xf := Transform3D(Basis.looking_at(-face, Vector3.UP), center)  # +Z базиса — к Тору
	marker.set_meta("_squad_xform", xf)
	return xf

## Где встать участнику m (маркер из expand).
func member_position(m: Node3D, player: Node3D) -> Vector3:
	var squad_marker := m.get_parent() as Node3D
	# Якорь на своей точке (шаман на уступе): "squad_anchor_pos" — в координатах узла маркеров зала
	if m.has_meta("squad_anchor") and squad_marker.has_meta("squad_anchor_pos"):
		var holder := squad_marker.get_parent() as Node3D
		var local: Vector3 = squad_marker.get_meta("squad_anchor_pos")
		return (holder.to_global(local) if holder else local) + Vector3(0, 0.05, 0)
	var xf := resolve_center(squad_marker, player)
	var off: Vector3 = m.get_meta("squad_offset", Vector3.ZERO)
	return xf * off
