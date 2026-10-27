extends CanvasLayer
## Автозагрузка «Perf» — поиск фризов. F3 — оверлей: график времени кадра, FPS, враги, частицы, физтела.
## Каждый кадр дольше hitch_ms пишется в user://hitches.log вместе с метками событий этого кадра
## (Perf.mark("spawn_wave") и т.п. из игрового кода). Работает и в релизной сборке.
## Путь к логу на Windows: %APPDATA%/ThorDostoynayaSmert/hitches.log (F4 — открыть папку, F5 — «Сообщить о лаге»: zip на рабочий стол).

const LOG_PATH := "user://hitches.log"
const HISTORY := 240

## Кадр дольше этого (мс) считается фризом и пишется в лог
@export var hitch_ms: float = 33.0

var _times: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0
var _last_usec: int = 0
var _marks: PackedStringArray = []
var _prev_marks: PackedStringArray = []
## Метки, которые ещё ни разу не встречались в забеге — «первый раз» часто и есть причина фриза
var _seen: Dictionary = {}
## Счётчики компиляций пайплайнов (Forward+/Mobile): draw — компиляция прямо при отрисовке (= фриз),
## surface/mesh — при появлении нового меша/материала, specialization — фоновая донастройка
const PSO_MONITORS := {
	"pso_canvas": Performance.PIPELINE_COMPILATIONS_CANVAS,
	"pso_mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"pso_surface": Performance.PIPELINE_COMPILATIONS_SURFACE,
	"pso_draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"pso_spec": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
}
var _pso_last: Dictionary = {}
var _log: FileAccess
var _panel: Control
var _graph: Control
var _label: Label
var _worst_ms: float = 0.0
var _hitch_count: int = 0
## Последние фризы — для тестов и оверлея
var hitches: Array[Dictionary] = []
var enabled_logging: bool = true
## Для тестов: писать каждый кадр [кадр, мс, события] — чтобы мерить всплески относительно соседних кадров
var record_all: bool = false
var frames: Array = []

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	_times.resize(HISTORY)
	_build()
	_panel.visible = false
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log:
		_log.store_line("# Тор: Достойная смерть — лог фризов (кадры > %d мс)" % int(hitch_ms))
		_log.store_line("# %s, %s, %s" % [Time.get_datetime_string_from_system(), OS.get_name(), RenderingServer.get_video_adapter_name()])
		_log.store_line("# время_с\tкадр_мс\tсобытия")
		_log.flush()

## Отметить событие текущего кадра. Первое появление события помечается «*».
func mark(event: String) -> void:
	if not _seen.has(event):
		_seen[event] = true
		_marks.append("*" + event)
	else:
		_marks.append(event)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F3:
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()
		KEY_F5:
			# «Сообщить о лаге»: zip с логом и сохранением на рабочий стол
			var path := report_lag()
			_flash(tr("Отчёт о лаге: %s") % path if path != "" else tr("Не удалось сохранить отчёт"))
			get_viewport().set_input_as_handled()
		KEY_F4:
			# Папка с логом фризов — чтобы прислать его
			OS.shell_open(ProjectSettings.globalize_path("user://"))
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
		return
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_check_pipelines()
	_times[_head] = ms
	_head = (_head + 1) % HISTORY
	_worst_ms = maxf(_worst_ms * 0.995, ms)
	if ms > hitch_ms and enabled_logging:
		_record(ms)
	if record_all:
		frames.append([Engine.get_process_frames(), ms, ",".join(_marks), ",".join(_prev_marks)])
	_prev_marks = _marks
	_marks = PackedStringArray()
	if _panel.visible:
		_update_label()
		_graph.queue_redraw()

func _check_pipelines() -> void:
	for key in PSO_MONITORS:
		var v := int(Performance.get_monitor(PSO_MONITORS[key]))
		var last: int = _pso_last.get(key, 0)
		var d := v - last if v >= last else v
		_pso_last[key] = v
		if d > 0:
			_marks.append("%s+%d" % [key, d])

func _record(ms: float) -> void:
	_hitch_count += 1
	# Интервал от прошлого _process до этого (Perf обрабатывается первым) — значит, метки в _marks
	# относятся ровно к измеренному кадру. Метки кадра до него тоже пишем: фриз часто приходит кадром
	# позже (рендер того, что только что создали, — компиляция шейдеров).
	var info := {"t": Time.get_ticks_msec() / 1000.0, "frame": Engine.get_process_frames(), "ms": ms, "events": ",".join(_marks), "prev": ",".join(_prev_marks)}
	hitches.append(info)
	if hitches.size() > 200:
		hitches.pop_front()
	if _log:
		_log.store_line("%.2f\t%.1f\t%s\t(до этого: %s)" % [info.t, ms, info.events, info.prev])
		_log.flush()

## «Сообщить о лаге» (GDD 23): zip на рабочий стол — лог фризов, сохранение, настройки, сведения о системе.
## Возвращает путь к архиву или "" при ошибке.
func report_lag() -> String:
	if _log:
		_log.flush()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = ProjectSettings.globalize_path("user://")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := dir.path_join("Thor_lag_%s.zip" % stamp)
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	for f in ["user://hitches.log", "user://save.json", "user://settings.cfg"]:
		if FileAccess.file_exists(f):
			zip.start_file(f.get_file())
			zip.write_file(FileAccess.get_file_as_bytes(f))
			zip.close_file()
	var info := PackedStringArray([
		"Тор: Достойная смерть — отчёт о лаге",
		"Время: %s" % Time.get_datetime_string_from_system(),
		"ОС: %s %s" % [OS.get_name(), OS.get_version()],
		"Процессор: %s, потоков %d" % [OS.get_processor_name(), OS.get_processor_count()],
		"Видеокарта: %s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()],
		"API: %s, рендерер: %s" % [RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_method()],
		"Godot: %s" % Engine.get_version_info().string,
		"Окно: %s" % str(DisplayServer.window_get_size()),
		"Фризов > %d мс за сессию: %d" % [int(hitch_ms), _hitch_count],
		"",
		"Последние фризы (время с, кадр мс, события):",
	])
	for h in hitches.slice(maxi(0, hitches.size() - 40)):
		info.append("%.2f\t%.1f\t%s\t(до: %s)" % [h.t, h.ms, h.events, h.prev])
	zip.start_file("system.txt")
	zip.write_file("\n".join(info).to_utf8_buffer())
	zip.close_file()
	zip.close()
	Perf.mark("lag_report")
	return path

func _update_label() -> void:
	var tree := get_tree()
	var enemies := tree.get_nodes_in_group("enemies").size()
	var root := tree.current_scene
	var particles := 0
	var rigid := 0
	var sleeping := 0
	if root:
		for n in root.find_children("*", "GPUParticles3D", true, false) + root.find_children("*", "CPUParticles3D", true, false):
			if (n as Node3D).visible:
				particles += 1
		for n in root.find_children("*", "RigidBody3D", true, false):
			rigid += 1
			if (n as RigidBody3D).sleeping:
				sleeping += 1
	_label.text = "FPS %d   кадр %.1f мс   худший %.1f мс\nврагов %d   частиц %d   физтел %d (спят %d)\nобъектов %d   draw calls %d\nфризов > %d мс: %d   лог (F4 — папка): %s" % [
		Engine.get_frames_per_second(), _times[(_head - 1 + HISTORY) % HISTORY], _worst_ms,
		enemies, particles, rigid, sleeping,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(hitch_ms), _hitch_count, ProjectSettings.globalize_path(LOG_PATH)]
	# Узлы с instance uniform (вспышки врагов, эффекты): в GL Compatibility их не больше 256 на сцену
	_label.text += "\ninstance uniform: %d / %d (GL)" % [FX.instance_uniform_users(tree.root), FX.INSTANCE_SLOTS_GL]

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 8)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_content_margin_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_label)
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(HISTORY * 2, 70)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.draw.connect(_draw_graph)
	box.add_child(_graph)

func _draw_graph() -> void:
	var h := _graph.size.y
	var scale := h / 50.0
	for ms_line in [16.7, 33.3]:
		var y: float = h - ms_line * scale
		_graph.draw_line(Vector2(0, y), Vector2(_graph.size.x, y), Color(1, 1, 1, 0.25))
	for i in HISTORY:
		var ms := _times[(_head + i) % HISTORY]
		var c := Color(0.4, 1, 0.4) if ms < 17.5 else (Color(1, 0.85, 0.3) if ms < hitch_ms else Color(1, 0.3, 0.3))
		_graph.draw_line(Vector2(i * 2, h), Vector2(i * 2, h - minf(ms, 50.0) * scale), c, 2.0)

## Короткое сообщение в углу экрана (поверх всего).
func _flash(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(12, 120)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

