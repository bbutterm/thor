extends EnemyTraitHandler
## Трус: при HP < def.flee_hp убегает от Тора def.flee_time секунд (один раз) и зовёт соседей (будит в call_radius).

var fled := false
var flee_left := 0.0

func _trait_tick(delta: float) -> void:
	if not fled and enemy.health < enemy.max_health * def.flee_hp:
		fled = true
		flee_left = def.flee_time
		Perf.mark("trait_coward_flee")
		for e in enemy._enemies_now():
			var en := e as Enemy
			if en and en != enemy and is_instance_valid(en) and not en.is_dead \
					and en.global_position.distance_to(enemy.global_position) <= def.call_radius:
				en.alert_to_player()
		FX.ring(enemy.get_parent(), enemy.global_position, def.call_radius * 0.3, Color(def.color, 0.7), 0.4)
		Audio.sfx("zombie_groan" if FX.is_undead(enemy) else "", "sounds/sfx/enemy_growl.wav")
	if flee_left > 0.0:
		flee_left -= delta
		var away := enemy.global_position - enemy.player.global_position if enemy.player else Vector3.ZERO
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
		if not enemy._has_floor_ahead(away):
			away = away.rotated(Vector3.UP, PI * 0.5)
		enemy._forced_move = away
		enemy._forced_move_left = maxf(flee_left, 0.05)

func is_fleeing() -> bool:
	return flee_left > 0.0
