extends RefCounted
class_name ComicAnimator
## Кадр слова: появление, тряска, исчезновение; проекция точки мира на экран.
## Компонент ComicWords (этап 5 рефакторинга): числа и состояние — поля ComicWords (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — ComicFX.animator; нужные снаружи функции есть и на ComicWords.

var cf: ComicWords

func _init(owner_node: ComicWords) -> void:
	cf = owner_node

func _animate(w: ComicWords.ComicWord, real: float, game: float) -> void:
	if w.warm_frames > 0:
		w.warm_frames -= 1
		w.modulate.a = 0.03
		if w.warm_frames == 0:
			cf._release(w)
		return
	w.age_real += real
	var tm := w.time_mult
	var pin := cf.pop_in_time * (1.4 if w.big else 1.0)
	var s := 1.0
	if w.age_real < pin:
		var k := w.age_real / pin
		if k < 0.6:
			s = cf.pop_overshoot * ease(k / 0.6, 0.4)
		else:
			s = lerpf(cf.pop_overshoot, 1.0, ease((k - 0.6) / 0.4, 0.6))
	else:
		w.age_game += game
	w.anim_scale = s
	var g := w.age_game
	var off := Vector2.ZERO
	var rot := 0.0
	var shake_end := cf.shake_time * tm
	if w.age_real >= pin and g < shake_end:
		var amp := 1.0 - g / shake_end
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * cf.shake_px * amp * (1.6 if w.big else 1.0)
		rot = deg_to_rad(randf_range(-cf.shake_deg, cf.shake_deg)) * amp
	var fade_start := (cf.shake_time + cf.hold_time) * tm
	var rise := 0.0
	w.modulate.a = 1.0
	if g > fade_start:
		var f := (g - fade_start) / (cf.fade_time * tm)
		if f >= 1.0:
			cf._release(w)
			return
		w.modulate.a = 1.0 - f
		rise = cf.rise_px * ease(f, 0.5) * (1.5 if w.big else 1.0)
	_place(w, rise, off, rot)

func _place(w: ComicWords.ComicWord, rise: float, off: Vector2, rot: float) -> void:
	var vp := cf.get_viewport().get_visible_rect().size
	var sc := w.base_scale * w.anim_scale * GameSettings.comic_scale
	w.scale = Vector2.ONE * maxf(sc, 0.001)
	w.rotation = w.tilt + rot
	var combo_lane := w.event == "combo" and w.big and not w.preview
	var combo_lane_start := vp.x * lerpf(0.4, 0.5, clampf((GameSettings.text_scale() - 1.0) / 0.6, 0.0, 1.0))
	if combo_lane:
		# Левую часть занимает реплика Одина. Ограничиваем только слово связки,
		# учитывая наклон и overshoot, чтобы буквы и всплеск помещались справа.
		var lane_half := maxf((vp.x - cf.screen_margin_px - combo_lane_start) * 0.5 - cf.shake_px * 1.6, 1.0)
		var half_width := (absf(cos(w.rotation)) * w.half.x + absf(sin(w.rotation)) * w.half.y) * 1.15 * w.scale.x
		if half_width > lane_half:
			w.scale *= lane_half / half_width
	var pos: Vector2
	if w.preview:
		pos = vp * Vector2(0.5, 0.16)
	elif combo_lane:
		pos = Vector2((combo_lane_start + vp.x - cf.screen_margin_px) * 0.5, vp.y * 0.42)
	elif w.big:
		pos = vp * Vector2(0.5, 0.42)
	elif w.screen:
		pos = vp * Vector2(0.5, 0.5) + w.jitter
	else:
		var cam := cf.get_viewport().get_camera_3d()
		if w.cam == null or not is_instance_valid(w.cam) or cam != w.cam:
			cf._release(w)
			return
		if cam.is_position_behind(w.world_pos):
			w.visible = false
			return
		w.visible = true
		var dist := cam.global_position.distance_to(w.world_pos)
		var dk := clampf(cf.distance_ref / maxf(dist, 0.1), cf.min_distance_scale, 1.0)
		w.scale *= dk
		pos = cam.unproject_position(w.world_pos) + (w.jitter + Vector2(0, -cf.world_lift_px)) * dk
	pos += off + Vector2(0, -rise)
	# Не даём слову уехать за край экрана
	var h := w.half * w.base_scale * GameSettings.comic_scale
	if combo_lane:
		h = w.half * w.scale.x
	var m := cf.screen_margin_px
	pos.x = vp.x * 0.5 if h.x * 2.0 + m * 2.0 > vp.x else clampf(pos.x, m + h.x, vp.x - m - h.x)
	pos.y = vp.y * 0.5 if h.y * 2.0 + m * 2.0 > vp.y else clampf(pos.y, m + h.y, vp.y - m - h.y)
	w.position = pos

## Точка перед камерой на уровне удара (удар-приземление — под ногами, оттуда слово не видно).
func _ahead_of_camera(center: Vector3) -> Vector3:
	var cam := cf.get_viewport().get_camera_3d()
	if cam == null:
		return center
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return center + fwd * 3.5 + Vector3(0, 0.9, 0)
