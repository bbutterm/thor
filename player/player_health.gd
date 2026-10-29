extends RefCounted
class_name PlayerHealth
## Здоровье: урон по Тору, неуязвимость, лечение, плата здоровьем, смерть, щит Сиф и второе дыхание.
## Компонент игрока (этап 2 рефакторинга): числа и состояние — поля Player (их ставят сцена, тела
## и тесты), здесь только логика. Доступ — player.vitals; публичные функции есть и на Player.

var p: Player

func _init(player: Player) -> void:
	p = player

func is_invulnerable() -> bool:
	return p._invuln_left > 0.0 or p.is_dead

func take_damage(amount: float, knockback: Vector3 = Vector3.ZERO, ignore_invuln: bool = false) -> void:
	Perf.mark("player_hurt")
	if p.is_dead:
		return
	if is_invulnerable() and not ignore_invuln:
		return
	# Пассивки/изъяны тела могут уменьшить урон (скальд: первый удар в зале не ранит)
	for h in p.body_handlers:
		amount = h.on_damaged(p, amount)
	if amount <= 0.0:
		p._invuln_left = 0.25
		RunTracker.pending_source = ""
		return
	amount = _rune_on_damaged(amount)
	amount = Oaths.on_damaged(amount)  # Клятва гордыни: первый удар в зале двойной; учёт «зал без урона»
	if amount <= 0.0:
		p._invuln_left = 0.25
		return
	p.health -= amount
	# Берсерк: Тора не сбивают — удары не отбрасывают
	if not (p.style and p.style.is_stun_immune()):
		p.velocity += knockback
	# Урон сбивает шкалу стиля
	if p.style:
		p.style.on_damaged(amount)
	p._invuln_left = 0.25
	p.camera_fx.add_trauma(clampf(amount / 30.0, 0.15, 0.6))
	Run.register_player_hit()
	p.hurt.emit(amount)
	p.health_changed.emit(maxf(p.health, 0.0), p.max_health)
	Audio.play("sounds/sfx/player_hurt.wav")
	Audio.thor_pain()
	if p.health <= 0.0 and not _rune_second_wind():
		_die()

## Плата здоровьем (сделка Локи, «Кот в мешке»): без защиты рун/тела, не убивает (остаётся ≥ 1 HP).
func pay_health(amount: float) -> void:
	if p.is_dead or amount <= 0.0:
		return
	p.health = maxf(1.0, p.health - amount)
	p.camera_fx.add_trauma(0.2)
	p.hurt.emit(amount)
	p.health_changed.emit(p.health, p.max_health)
	Audio.play("sounds/sfx/player_hurt.wav")

func heal(amount: float) -> void:
	# Изъян Берсерка: лечение −50 %
	amount *= float(p.modify_stat(&"heal_mult", 1.0))
	amount *= Oaths.heal_mult()  # Клятва ярости
	p.health = minf(p.max_health, p.health + amount)
	p.health_changed.emit(p.health, p.max_health)

func _die() -> void:
	p.is_dead = true
	p.input_enabled = false
	p.skills.weapon_skill_cancel_motion()
	p.dash._end_ram()
	p.is_sliding = false
	p.footsteps.stream_paused = true
	var tw := p.create_tween()
	tw.tween_property(p.head, "position:y", 0.25, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(p.camera, "rotation:z", deg_to_rad(35), 0.6)
	p.died.emit()

## Лечение за убийство: базовое + бонус за добивание мили.
func kill_heal(source: String) -> float:
	return p.heal_per_kill + (p.melee_kill_heal if source.begins_with("melee") else 0.0)

func _on_kill_registered(source: String) -> void:
	if p.is_dead:
		return
	# Клык Фенрира: лечение за добивание мили
	if source.begins_with("melee") and Run.rune_level("fenrir_fang") > 0:
		heal(Run.rune_value("fenrir_fang"))
	for h in p.body_handlers:
		h.on_kill(p, source)

## Входящий урон: «Стеклянная пушка» (×1.5), «Шкура медведя» (−%), «Щит Сиф» принимает урон первым.
func _rune_on_damaged(amount: float) -> float:
	if Run.rune_level("loki_glass") > 0:
		amount *= 1.5
	amount *= 1.0 - minf(0.6, Run.rune_value("bear_skin"))
	if p.shield > 0.0:
		var absorbed := minf(p.shield, amount)
		p.shield -= absorbed
		amount -= absorbed
		p.health_changed.emit(p.health, p.max_health)
	return amount

## «Второе дыхание»: один раз за забег встать с частью HP вместо смерти.
func _rune_second_wind() -> bool:
	if p._second_wind_used or Run.rune_level("second_wind") == 0:
		return false
	p._second_wind_used = true
	p.health = p.max_health * Run.rune_value("second_wind")
	p._invuln_left = 1.5
	p.health_changed.emit(p.health, p.max_health)
	FX.ring(p.get_parent(), p.global_position, 3.0, Color(0.5, 1.0, 0.6, 0.9), 0.5)
	FX.hitstop(0.15)
	p.camera_fx.add_trauma(0.4)
	Perf.mark("second_wind")
	Odin.say("second_wind")
	return true

## «Щит Сиф» восстанавливается между волнами (Game → Room.wave_started).
func refill_shield() -> void:
	if p.shield_max > 0.0 and p.shield < p.shield_max:
		p.shield = p.shield_max
		p.health_changed.emit(p.health, p.max_health)
