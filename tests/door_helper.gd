extends RefCounted
## Общие шаги тестов для дверей-наград (блок И): разобрать экран награды зала и войти в дверь.
## const DoorHelper := preload("res://tests/door_helper.gd")

static func wait(tree: SceneTree, sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await tree.physics_frame

## Закрыть экраны награды (трейт, руна, отдых, Локи…) первым доступным вариантом. Возвращает, что выбрано.
static func resolve_reward(tree: SceneTree, game: Game, prefer: String = "") -> String:
	var done: Array[String] = []
	for step in 8:
		if game.trait_pick.visible:
			game.trait_pick._open_time = -10.0
			game.trait_pick.choose(0, true)
			done.append("trait")
			await wait(tree, 0.8)
			continue
		if game.rune_pick.visible:
			game.rune_pick._open_time = -10.0
			game.rune_pick.choose(randi() % maxi(1, game.rune_pick._choices.size()))
			done.append("rune")
			await wait(tree, 0.3)
			continue
		var ch: ChoicePick = game.rewards.choice
		if ch.visible:
			var idx := ch.index_of(prefer) if prefer != "" else -1
			if idx < 0:
				for i in ch._choices.size():
					if bool(ch._choices[i].get("enabled", true)):
						idx = i
						break
			done.append("choice:" + str(ch._choices[idx].get("id", "")))
			ch.choose(idx, true)
			await wait(tree, 0.3)
			continue
		if not game.rewards.doors.is_empty():
			break
		await wait(tree, 0.3)
	return ", ".join(done)

## Войти в дверь (index по кругу) — физически, через триггер проёма. Возвращает id награды или "".
static func take_door(tree: SceneTree, game: Game, index: int) -> String:
	var doors: Array[RewardDoor] = game.rewards.doors
	if doors.is_empty():
		return ""
	var d := doors[index % doors.size()]
	var id := d.reward_id
	# Ждём, пока арка поднимется из пола
	await wait(tree, 0.9)
	game.player.global_position = d.trigger_position()
	game.player.velocity = Vector3(0, 0, -2)
	var room := game.room
	for i in 120:
		await tree.physics_frame
		if game.room != room:
			break
	await wait(tree, 0.3)
	return id
