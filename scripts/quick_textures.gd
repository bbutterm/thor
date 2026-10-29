extends RefCounted
class_name QuickTextures
## «Быстрая проверка», F6 (партия 10.1): рисованные текстуры залов владельца ↔ старые.
## Старые параметры материалов — data/quick_check_old_materials.json; новые — из самих .tres (запоминаются
## при первом переключении). Материалы залов общие (load кеширует ресурс), поэтому меняется сразу весь зал.

const OLD_PATH := "res://data/quick_check_old_materials.json"

static var _new: Dictionary = {}
static var showing_old: bool = false

static func apply(old: bool) -> void:
	if old == showing_old:
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(OLD_PATH)) if FileAccess.file_exists(OLD_PATH) else null
	if not data is Dictionary:
		return
	var mats: Dictionary = (data as Dictionary).get("materials", {})
	for path in mats:
		var mat := load(path) as ShaderMaterial
		if mat == null:
			continue
		var rec: Dictionary = mats[path]
		if not _new.has(path):
			var saved := {}
			for k in rec:
				saved[k] = mat.get_shader_parameter(k)
			_new[path] = saved
		for k in rec:
			if old:
				mat.set_shader_parameter(k, _old_value(k, rec[k]))
			else:
				mat.set_shader_parameter(k, (_new[path] as Dictionary)[k])
	showing_old = old

static func _old_value(key: String, v: Variant) -> Variant:
	if v == null:
		return null
	if key.ends_with("_tex"):
		return load(str(v))
	return str_to_var(str(v))
