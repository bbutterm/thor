extends Node
## Pixel comparison of the original instance-uniform flash and the GL prototype.
## The two identical meshes render at the same time in independent viewports.
## Requires a real GL Compatibility renderer; pass an optional output directory after --.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 320x180 \
##   res://tests/enemy_flash_equivalence.tscn -- /tmp/flash-equivalence

const SIZE := Vector2i(128, 128)
const CASES := [
	["damage", 0.65, 0.0, Color(0, 0, 0, 0)],
	["windup", 0.0, 0.55, Color(0, 0, 0, 0)],
	["elite", 0.0, 0.0, Color(0.3, 0.85, 0.15, 0.22)],
	["ice", 0.0, 0.0, Color(0.1, 0.75, 1.0, 0.55)],
	["fire_and_hit", 0.35, 0.2, Color(1.0, 0.22, 0.0, 0.5)],
	["mixed", 0.2, 0.4, Color(0.8, 0.2, 0.9, 0.3)],
]

var reference_view: SubViewport
var variant_view: SubViewport
var reference_mesh: MeshInstance3D
var variant_mesh: MeshInstance3D
var reference_material: ShaderMaterial
var variant_material: ShaderMaterial
var output_dir := ""
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		printerr("Requires real GL Compatibility; a headless/Dummy run cannot validate pixels")
		get_tree().quit(2)
		return
	print("Renderer: %s; adapter: %s; API: %s; Godot: %s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(), Engine.get_version_info().string])
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output_dir = args[0]
		DirAccess.make_dir_recursive_absolute(output_dir)
	reference_view = _make_viewport()
	variant_view = _make_viewport()
	reference_mesh = _make_mesh(reference_view)
	variant_mesh = _make_mesh(variant_view)
	reference_material = Enemy.FLASH_MATERIAL.duplicate() as ShaderMaterial
	variant_material = Enemy.FLASH_MATERIAL_GL.duplicate() as ShaderMaterial
	reference_mesh.material_overlay = reference_material
	variant_mesh.material_overlay = variant_material
	_run.call_deferred()

func _make_viewport() -> SubViewport:
	var view := SubViewport.new()
	view.size = SIZE
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0, 0, 4)
	view.add_child(camera)
	camera.current = true
	return view

func _make_mesh(view: SubViewport) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = 0.7
	shape.height = 1.6
	mesh.mesh = shape
	var base := StandardMaterial3D.new()
	base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base.albedo_color = Color(0.18, 0.26, 0.41)
	mesh.material_override = base
	view.add_child(mesh)
	return mesh

func _run() -> void:
	for outlined in [false, true]:
		reference_material.next_pass = Outline.material() if outlined else null
		variant_material.next_pass = Outline.material() if outlined else null
		for spec in CASES:
			var flash: float = spec[1]
			var glow: float = spec[2]
			var elite: Color = spec[3]
			reference_mesh.set_instance_shader_parameter("flash", flash)
			reference_mesh.set_instance_shader_parameter("glow", glow)
			reference_mesh.set_instance_shader_parameter("elite", elite)
			variant_material.set_shader_parameter("flash", flash)
			variant_material.set_shader_parameter("glow", glow)
			variant_material.set_shader_parameter("elite", elite)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_compare("%s_outline_%s" % [spec[0], "on" if outlined else "off"])
	print("=== ENEMY FLASH PIXEL COMPARISON: %d cases, %d failures ===" % [CASES.size() * 2, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _compare(label: String) -> void:
	var a := reference_view.get_texture().get_image()
	var b := variant_view.get_texture().get_image()
	if a == null or b == null or a.is_empty() or b.is_empty():
		printerr("[FAIL] ", label, ": empty render")
		failures += 1
		return
	if output_dir != "":
		a.save_png(output_dir.path_join(label + "_reference.png"))
		b.save_png(output_dir.path_join(label + "_variant.png"))
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var reference_bytes := a.get_data()
	var variant_bytes := b.get_data()
	if reference_bytes.size() != variant_bytes.size():
		printerr("[FAIL] ", label, ": different image sizes")
		failures += 1
		return
	var max_delta := 0
	var different_channels := 0
	for i in reference_bytes.size():
		var delta := absi(int(reference_bytes[i]) - int(variant_bytes[i]))
		max_delta = maxi(max_delta, delta)
		if delta > 1:
			different_channels += 1
	var rendered := a.get_pixel(SIZE.x >> 1, SIZE.y >> 1) != a.get_pixel(0, 0)
	var good := rendered and different_channels == 0
	print("[%s] %s: max_channel_delta=%d/255, channels_above_1=%d, rendered=%s" % [
		"OK" if good else "FAIL", label, max_delta, different_channels, rendered])
	if not good:
		failures += 1
