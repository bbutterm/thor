extends RefCounted
class_name ComicHooks
## Хуки из игрового кода (однострочные вызовы ComicFX.pop/on_*): какое слово и где — по событию, урону, оружию.
## Компонент ComicWords (этап 5 рефакторинга): числа и состояние — поля ComicWords (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — ComicFX.hooks; нужные снаружи функции есть и на ComicWords.

var cf: ComicWords

func _init(owner_node: ComicWords) -> void:
	cf = owner_node

## Показать слово события `event` над точкой мира. big — крупно на весь экран.
func pop(event: String, world_pos: Vector3, big: bool = false) -> void:
	cf._request(event, world_pos, big)

## Удар-приземление (player.gd → _do_slam_impact). height — высота падения, м.
func on_slam(center: Vector3, height: float) -> void:
	var big := height >= cf.big_slam_height
	if big:
		FX.hitstop(cf.big_slam_hitstop)
	if height < cf.slam_min_height:
		return
	cf._request("slam", cf.animator._ahead_of_camera(center), big)

## Попадание по врагу (enemy.gd → take_hit, после вычета здоровья). Слово — только у крита
## (тяжёлый 3-й удар комбо, `*_finisher`) по живому врагу; убийства разбирает on_enemy_killed.
func on_enemy_hit(enemy: Node3D, _damage: float, source: String) -> void:
	if not _is_finisher(source) or float(enemy.get("health")) <= 0.0:
		return
	cf._request(_melee_style(enemy), _head(enemy), false)

## Смерть врага (enemy.gd → _die): добивание финишером, мульти-килл, босс.
func on_enemy_killed(enemy: Node3D, source: String) -> void:
	var pos := _head(enemy)
	var recent: Array[float] = []
	for t in cf._kill_times:
		if cf._clock - t <= cf.multikill_window:
			recent.append(t)
	if recent.is_empty():
		cf._multi_level = 0
	recent.append(cf._clock)
	cf._kill_times = recent
	if enemy.get("kind") == Enemy.Kind.BOSS:
		cf._request("boss_kill", pos, true)
	if recent.size() >= cf.multikill_big_count and cf._multi_level < 2:
		cf._multi_level = 2
		FX.hitstop(FX.cfg().multikill_big_hitstop)
		cf._request("multikill", pos, true)
		_multikill_punch(enemy, cf.multikill_big_shake)
	elif recent.size() >= cf.multikill_count and cf._multi_level < 1:
		cf._multi_level = 1
		FX.hitstop(FX.cfg().multikill_hitstop)
		cf._request("multikill", pos, false)
		_multikill_punch(enemy, cf.multikill_shake)
	if _is_finisher(source):
		cf._request(_melee_style(enemy), pos, false, cf.finisher_kill_scale, 10)

## П3: мульти-килл ощущается — тряска камеры сильнее и короткий бас-удар.
func _multikill_punch(enemy: Node3D, shake: float) -> void:
	var p := enemy.get("player") as Player if enemy else null
	if p and is_instance_valid(p) and p.camera_fx:
		p.camera_fx.add_trauma(shake)
	Audio.play("sounds/sfx/multikill_bass.wav")

## Мьёльнир попал во врага (mjolnir_projectile.gd → _on_hit). Слово — на возврате или после рикошета.
func on_hammer_hit(_target: Object, pos: Vector3, returning: bool, bounces: int) -> void:
	if returning or bounces > 0:
		cf._request("hammer", pos + Vector3(0, 0.6, 0), false)

## Цепная молния Мьёльнира ударила врага (mjolnir_projectile.gd → _chain_lightning, после удара).
func on_lightning(target: Node3D) -> void:
	if cf.lightning_kill_only and not target.get("is_dead"):
		return
	cf._request("lightning", _head(target), false)

## Враг бьёт игрока (enemy.gd, перед player.take_damage). Слово — только от босса и если удар пройдёт.
func on_player_struck(enemy: Node3D, player: Node) -> void:
	if enemy.get("kind") != Enemy.Kind.BOSS or player == null or player.call("is_invulnerable"):
		return
	cf._request("player_hurt", Vector3.ZERO, false, 1.0, 0, true)

func _is_finisher(source: String) -> bool:
	return source == "axe_finisher" or source == "melee_finisher"

## Стиль мили игрока: "blade" (топор, клинки), "blunt" (дубина, молот), "pierce" (копьё).
func _melee_style(enemy: Node) -> String:
	var p: Node = enemy.get("player") as Node
	if p == null:
		p = cf.get_tree().get_first_node_in_group("player")
	var style := "blade"
	if p and is_instance_valid(p) and p.has_method("current_melee_style"):
		style = String(p.call("current_melee_style"))
	return style if cf._data.has(style) else "blade"

func _head(enemy: Node3D) -> Vector3:
	var s := float(enemy.get("model_scale")) if enemy.get("model_scale") != null else 1.0
	return enemy.global_position + Vector3(0, 1.6 * s, 0)
