extends EnemyTraitHandler
## Крикун: заметив Тора, будит всех врагов в радиусе shout_radius (один раз).

var shouted := false
var woken := 0

func _trait_tick(_delta: float) -> void:
	if shouted or not enemy.is_alert_to_player():
		return
	shout()

func shout() -> void:
	shouted = true
	Perf.mark("trait_shout")
	for e in enemy._enemies_now():
		var en := e as Enemy
		if en and en != enemy and is_instance_valid(en) and not en.is_dead \
				and en.global_position.distance_to(enemy.global_position) <= def.shout_radius:
			if not en.is_alert_to_player():
				woken += 1
			en.alert_to_player()
	FX.ring(enemy.get_parent(), enemy.global_position + Vector3(0, 1.8 * enemy.model_scale, 0), 2.5, Color(def.color, 0.8), 0.5)
	Audio.sfx("zombie_groan" if FX.is_undead(enemy) else "", "sounds/sfx/enemy_growl.wav")
