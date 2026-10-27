extends Node
## Экспериментальная проверка безопасного объединения равных Skin.
## Только тест; игровые HumanoidModel и Skin-ресурсы не модифицируются.
const Exp := preload("res://tests/fixtures/skin_intern_experimental.gd")
var passes := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition:
		passes += 1
		print("[OK] ", label)
	else:
		failures.append(label)
		print("[FAIL] ", label)

func make_skin(shift: float = 0.0) -> Skin:
	var result := Skin.new()
	result.set_bind_count(2)
	result.set_bind_name(0, &"root")
	result.set_bind_name(1, &"hand_r")
	result.set_bind_pose(0, Transform3D.IDENTITY)
	result.set_bind_pose(1, Transform3D(Basis.IDENTITY, Vector3(shift, 0, 0)))
	return result

func _run() -> void:
	print("=== SKIN INTERN EXPERIMENT ===")
	var a := make_skin()
	var b := make_skin()
	var diff_pose := make_skin(0.0001)
	var diff_name := make_skin()
	diff_name.set_bind_name(1, &"hand_l")
	var diff_bone := make_skin()
	diff_bone.set_bind_bone(1, 1)
	var diff_count := make_skin()
	diff_count.set_bind_count(1)
	check(Exp.equal_binds(a, b), "копии с одинаковыми bind-позами совпадают")
	check(not Exp.equal_binds(a, diff_pose), "малейшее отличие матрицы не объединяется")
	check(not Exp.equal_binds(a, diff_name), "разные имена костей не объединяются")
	check(not Exp.equal_binds(a, diff_bone), "разные индексы костей не объединяются")
	check(not Exp.equal_binds(a, diff_count), "разное число костей не объединяется")
	var meshes: Array[MeshInstance3D] = []
	var records: Array[Dictionary] = []
	for skin in [a, b, diff_pose, diff_name, diff_bone, diff_count]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.skin = skin
		meshes.append(mi)
		records.append({"mesh": mi, "skin": skin, "geometry": mi.mesh,
			"material_override": mi.material_override, "overlay": mi.material_overlay})
	var stats: Dictionary = Exp.intern(records)
	check(stats.old_unique == 6 and stats.new_unique == 5 and stats.changed_meshes == 1, "объединена только равная пара")
	check(meshes[0].skin == meshes[1].skin and meshes[2].skin == diff_pose and meshes[3].skin == diff_name and meshes[4].skin == diff_bone and meshes[5].skin == diff_count, "разные Skin и данные остальных мешей сохранены")
	check(Exp.same_content(records), "геометрия, материалы и полные bind-позы сохранены")
	Exp.restore(records)
	check(meshes[0].skin == a and meshes[1].skin == b and meshes[2].skin == diff_pose, "A/B восстановил исходные Skin")
	for mi in meshes:
		mi.free()
	await _actual_models()
	print("ИТОГ: %d OK, %d FAIL" % [passes, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _actual_models() -> void:
	var examples := [
		["male", "base/Superhero_Male_FullBody.gltf", ["parts/Male_Peasant_Body.gltf", "parts/Male_Peasant_Arms.gltf", "parts/Male_Ranger_Legs.gltf", "parts/Male_Peasant_Feet.gltf", "hair/Hair_Beard.gltf", "hair/Hair_Long.gltf", "hair/Eyebrows_Regular.gltf"]],
		["female", "base/Superhero_Female_FullBody.gltf", ["parts/Female_Peasant_Body.gltf", "parts/Female_Peasant_Arms.gltf", "parts/Female_Ranger_Legs.gltf", "parts/Female_Peasant_Feet.gltf", "hair/Hair_Long.gltf", "hair/Eyebrows_Female.gltf"]],
	]
	for spec in examples:
		var model := HumanoidModel.new()
		model.body = spec[1]
		model.outfit = ""
		model.parts = PackedStringArray(spec[2])
		add_child(model)
		await get_tree().process_frame
		var records := Exp.snapshot(model.skeleton)
		check(not records.is_empty(), "%s: получены импортированные Skin" % spec[0])
		var stats: Dictionary = Exp.intern(records)
		print("  %s: meshes=%d, unique Skin %d → %d, changed=%d" % [spec[0], records.size(), stats.old_unique, stats.new_unique, stats.changed_meshes])
		check(stats.new_unique <= stats.old_unique and Exp.same_content(records), "%s: все поля Skin и геометрия идентичны" % spec[0])
		check(_same_effective_matrices(model.skeleton, records), "%s: матрицы деформации совпадают" % spec[0])
		if model.play("Zombie_Walk_Fwd_Loop", 0.0, 1.0):
			for position in [0.1, 0.35, 0.7]:
				model.anim.seek(position, true)
				check(_same_effective_matrices(model.skeleton, records), "%s: матрицы анимации t=%.2f совпадают" % [spec[0], position])
		else:
			check(false, "%s: доступна анимация ходьбы" % spec[0])
		Exp.restore(records)
		check(records.all(func(rec: Dictionary) -> bool: return (rec.mesh as MeshInstance3D).skin == rec.skin), "%s: оригинальные Skin восстановлены" % spec[0])
		model.queue_free()
		await get_tree().process_frame

func _same_effective_matrices(skeleton: Skeleton3D, records: Array[Dictionary]) -> bool:
	for rec in records:
		var previous: Skin = rec.skin
		var current: Skin = (rec.mesh as MeshInstance3D).skin
		if not Exp.equal_binds(previous, current):
			return false
		for i in previous.get_bind_count():
			var bone := skeleton.find_bone(previous.get_bind_name(i)) if previous.get_bind_name(i) != &"" else previous.get_bind_bone(i)
			if bone < 0 or bone >= skeleton.get_bone_count():
				return false
			var pose := skeleton.get_bone_global_pose(bone)
			if pose * previous.get_bind_pose(i) != pose * current.get_bind_pose(i):
				return false
	return true
