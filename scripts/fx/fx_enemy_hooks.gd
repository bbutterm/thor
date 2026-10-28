extends RefCounted
class_name FXEnemyHooks
## Хуки эффектов врага и игрока: попадание и смерть врага (ихор у нежити), идеальный хват.
## Модуль фасада FX (этап 5 рефакторинга): только static-функции; состояние, константы и вызовы снаружи — через FX.

## Идеальный хват Мьёльнира (mjolnir_hand.gd): золотое кольцо vfx_perfect_catch на экране у руки.
static func perfect_catch(world_pos: Vector3) -> void:
	Perf.mark("fx_perfect_catch")
	if VfxScreen.instance and is_instance_valid(VfxScreen.instance):
		VfxScreen.instance.perfect_catch(world_pos)

## Нежить ли враг (брызги и пятна ихора): все, кроме смертных (Наёмник Локи) и ледяных (Йотунхейм).
## Переопределить — метаданные врага "ichor" (true/false).
static func is_undead(enemy: Node) -> bool:
	if enemy.has_meta("ichor"):
		return bool(enemy.get_meta("ichor"))
	if enemy.get("kind") == Enemy.Kind.MERC:
		return false
	var d := enemy.get("enemy_def") as EnemyDef
	return d == null or d.world != "jotunheim"

## Попадание по врагу (enemy.gd → take_hit): вспышка, у нежити — брызги ихора и пятно на полу.
static func enemy_hit(enemy: Node3D, damage: float, source: String, big: bool) -> void:
	if enemy == null or not enemy.is_inside_tree() or source == "fire" or damage <= 0.0:
		return
	var c := FXSpriteKit.cfg()
	var parent := enemy.get_parent()
	var ms := minf(_model_scale(enemy), 2.0)
	var chest := enemy.global_position + Vector3(0, 1.1 * ms, 0)
	var ranged := source == "ranged"
	var size := c.hit_flash_size * ms * (c.hit_flash_big_mult if big else 1.0) * (c.hit_flash_ranged_mult if ranged else 1.0)
	var col := Color(1.0, 0.92, 0.7)
	if source in ["hammer", "lightning"]:
		col = Color(0.7, 0.9, 1.0)
	elif ranged:
		col = Color(1.0, 0.95, 0.85)
	FXImpacts.hit_flash(parent, chest, size, col)
	if not is_undead(enemy):
		return
	var off := Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.2), randf_range(-0.25, 0.25))
	FXImpacts.ichor_splash(parent, chest + off, randf_range(c.ichor_splash_size.x, c.ichor_splash_size.y) * ms * (1.3 if big else 1.0) * (0.7 if ranged else 1.0))
	if big or randf() < c.splat_chance:
		FXImpacts.splat(parent, enemy.global_position + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)), randf_range(c.splat_size.x, c.splat_size.y) * ms)

## Смерть врага (enemy.gd → _die): у нежити — крупное пятно и брызги.
static func enemy_died(enemy: Node3D, _source: String) -> void:
	if enemy == null or not enemy.is_inside_tree() or not is_undead(enemy):
		return
	var c := FXSpriteKit.cfg()
	var parent := enemy.get_parent()
	var ms := minf(_model_scale(enemy), 2.0)
	# П3: корм разлетается на куски — брызги и пятно крупнее, ещё пара брызг вокруг
	var meat: bool = enemy.get("kind") == Enemy.Kind.FODDER and bool(enemy.get("gib_on_death"))
	var splat_mult := c.fodder_death_splat_mult if meat else 1.0
	var splash_mult := c.fodder_death_splash_mult if meat else 1.0
	FXImpacts.splat(parent, enemy.global_position, randf_range(c.splat_size.x, c.splat_size.y) * c.splat_death_mult * splat_mult * ms)
	FXImpacts.ichor_splash(parent, enemy.global_position + Vector3(0, 0.9 * ms, 0), c.ichor_splash_size.y * 1.3 * splash_mult * ms)
	if meat:
		for k in maxi(0, c.fodder_death_extra_splashes):
			var off := Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 1.3), randf_range(-0.6, 0.6)) * ms
			FXImpacts.ichor_splash(parent, enemy.global_position + off, randf_range(c.ichor_splash_size.x, c.ichor_splash_size.y) * ms)

static func _model_scale(enemy: Node) -> float:
	var s: Variant = enemy.get("model_scale")
	return float(s) if s != null else 1.0
