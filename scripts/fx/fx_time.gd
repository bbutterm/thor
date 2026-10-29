extends RefCounted
class_name FXTime
## Время эффектов: hit-stop, замедление, реальная длительность кадра при Engine.time_scale ≠ 1.
## Модуль фасада FX (этап 5 рефакторинга): только static-функции; состояние, константы и вызовы снаружи — через FX.

## Замедление времени на долю секунды при попадании.
## Отсчёт идёт в реальном времени через FX.tick() из автозагрузки Run.
static func hitstop(duration: float, scale: float = 0.05) -> void:
	if duration <= 0.0:
		return
	var now: float = Run.combat_clock
	if now < FX._hitstop_last_clock:
		FX._hitstop_bookings.clear()  # Run.start_run сбросил часы
	FX._hitstop_last_clock = now
	# Каждый ещё пересекающий окно интервал считаем целиком: верхняя граница
	# строгая и немного консервативная в начале следующего окна.
	var used := 0.0
	var kept: Array[Dictionary] = []
	for booking in FX._hitstop_bookings:
		if float(booking.end) > now - 1.0:
			kept.append(booking)
			used += float(booking.end) - float(booking.start)
	FX._hitstop_bookings = kept
	var extension := maxf(0.0, duration - FX._hitstop_left)
	var allowed := minf(extension, maxf(0.0, FXSpriteKit.cfg().hitstop_budget_per_second - used))
	if allowed > 0.0:
		var start := now + FX._hitstop_left
		FX._hitstop_bookings.append({"start": start, "end": start + allowed})
		FX._hitstop_left += allowed
	if FX._hitstop_left <= 0.0:
		return
	FX._hitstop_scale = minf(FX._hitstop_scale, clampf(scale, 0.001, 1.0))
	_set_time_scale(FX._hitstop_scale)

## Замедление конца волны идёт отдельно от hit-stop и не превращается в длинную заморозку.
## Если стоп уже идёт, все 0.3 с замедления начинаются после него.
static func slowmo(duration: float, scale: float) -> void:
	if duration <= 0.0:
		return
	FX._slow_left = maxf(FX._slow_left, duration)
	FX._slow_scale = minf(FX._slow_scale, clampf(scale, 0.001, 1.0))
	if FX._hitstop_left <= 0.0:
		_set_time_scale(FX._slow_scale)

## Вызывается каждый кадр. Run передаёт delta / текущий time_scale; пересчитываем по масштабу,
## с которым движок на самом деле умножил delta этого кадра (см. real_delta).
static func tick(passed_real_delta: float) -> void:
	FXShared.sync_fades()
	if FX._hitstop_left <= 0.0 and FX._slow_left <= 0.0:
		return
	var elapsed := real_delta(passed_real_delta * maxf(Engine.time_scale, 0.0001))
	if FX._hitstop_left > 0.0:
		FX._hitstop_left = maxf(0.0, FX._hitstop_left - elapsed)
		if FX._hitstop_left <= 0.0:
			FX._hitstop_scale = 1.0
	elif FX._slow_left > 0.0:
		FX._slow_left = maxf(0.0, FX._slow_left - elapsed)
		if FX._slow_left <= 0.0:
			FX._slow_scale = 1.0
	_set_time_scale(FX._hitstop_scale if FX._hitstop_left > 0.0 else (FX._slow_scale if FX._slow_left > 0.0 else 1.0))

## Реальная длительность кадра по delta из _process. Движок умножает delta на time_scale, каким он был
## В НАЧАЛЕ кадра; удары (и hit-stop) случаются в физике этого же кадра. Если делить на новый 0.05,
## первый же тик насчитывал 1/60 / 0.05 = 0.33 с и стоп заканчивался в кадре, где начался.
static func real_delta(scaled_delta: float) -> float:
	var s := FX._scale_before if Engine.get_process_frames() == FX._scale_frame else Engine.time_scale
	return scaled_delta / maxf(s, 0.0001)

static func _set_time_scale(s: float) -> void:
	var f := Engine.get_process_frames()
	if f != FX._scale_frame:
		FX._scale_frame = f
		FX._scale_before = Engine.time_scale
	# Скорость времени debug-панели (П8) — множитель поверх хит-стопа и замедлений
	Engine.time_scale = s * DebugBalance.time_mult

static func reset_time() -> void:
	FX._hitstop_left = 0.0
	FX._hitstop_scale = 1.0
	FX._slow_left = 0.0
	FX._slow_scale = 1.0
	FX._hitstop_bookings.clear()
	FX._hitstop_last_clock = -1.0
	_set_time_scale(1.0)
