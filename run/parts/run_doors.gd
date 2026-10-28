extends RefCounted
class_name RunDoors
## Двери-награды (блок И, GDD 15.1): порядок залов, награда зала, мирные залы, ларёк, предложения дверей.
## Компонент RunManager (этап 5 рефакторинга): числа и состояние — поля RunManager (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — Run.doors; нужные снаружи функции есть и на RunManager.

var rm: RunManager

func _init(owner_node: RunManager) -> void:
	rm = owner_node

## Порядок сцен: обязательные комнаты вне слота мини-босса и без повторов, остальные — случайно.
## Тесты могут задать room_order сами — двери тогда назначают только награды.
func _build_room_order() -> void:
	var n := rm.map.rooms if rm.map else rm.rooms_per_run
	rm.room_order.clear()
	if rm.map:
		rm.miniboss_rooms = PackedInt32Array([rm.map.miniboss_index()])
	var required: Array[String] = []
	if rm.map:
		for path in rm.map.required_rooms:
			if path not in RunManager.ROOM_SCENES:
				push_error("RunMap: обязательный зал отсутствует в ROOM_SCENES: %s" % path)
			elif path not in required:
				required.append(path)
	var slots: Array[int] = []
	for i in n:
		if i not in rm.miniboss_rooms:
			slots.append(i)
	if not required.is_empty():
		slots.shuffle()
	var placed := {}
	for path in required:
		if slots.is_empty():
			push_error("RunMap: недостаточно боевых слотов для обязательных залов")
			break
		placed[slots.pop_back()] = path
	var candidates: Array = []
	for path in RunManager.ROOM_SCENES:
		if path not in required:
			candidates.append(path)
	var pool: Array = []
	for i in n:
		if placed.has(i):
			rm.room_order.append(placed[i])
			continue
		if pool.is_empty():
			pool = candidates.duplicate()
			pool.shuffle()
			if pool.is_empty():
				push_error("RunMap: нет необязательных комнат для оставшихся слотов")
				break
			if not rm.room_order.is_empty() and pool[0] == rm.room_order[rm.room_order.size() - 1] and pool.size() > 1:
				pool.append(pool.pop_front())
		rm.room_order.append(pool.pop_front())
	rm.room_order.append(RunManager.BOSS_SCENE)

func reward_def(id: String) -> RewardDef:
	for r in rm.all_rewards:
		if r.id == id:
			return r
	return null

## Награда текущего зала (id RewardDef).
func current_reward() -> String:
	if rm.room_index < rm.room_rewards.size() and rm.room_rewards[rm.room_index] != "":
		return rm.room_rewards[rm.room_index]
	if rm.room_index == 0 and rm.map:
		return rm.map.first_room_reward
	if rm.room_index < rm.room_order.size() and rm.room_order[rm.room_index] == RunManager.BOSS_SCENE:
		return "boss"
	if rm.room_index in rm.miniboss_rooms:
		return "miniboss"
	return "combat"

## Тихий зал: без врагов (отдых, ларёк).
func is_peaceful_room() -> bool:
	if rm.is_boss_room() or rm.is_miniboss_room():
		return false
	var d := reward_def(current_reward())
	return d != null and not d.combat

## Можно ли вести дверь в ларёк (сцена зала-ларька уже есть).
func shop_available() -> bool:
	var d := reward_def("shop")
	return rm.map != null and d != null and d.enabled and ResourceLoader.exists(rm.map.shop_scene)

## Набор дверей после зачистки текущего зала: 2–3 награды (GDD 15.1), к мини-боссу и боссу — одна дверь.
func roll_door_offers() -> Array[String]:
	var out: Array[String] = []
	if not rm.forced_offers.is_empty():
		for id in rm.forced_offers.pop_front():
			out.append(str(id))
		return out
	var next := rm.room_index + 1
	var boss_index := rm.room_order.size() - 1
	if rm.map == null:
		out.append("boss" if next >= boss_index else "combat")
		return out
	# Тихая награда пропускает бой, а ларёк заменяет сцену; обязательный зал должен реально сыграться.
	var required_next := next < rm.room_order.size() and rm.room_order[next] in rm.map.required_rooms
	return rm.map.roll_offers(rm.all_rewards, next, boss_index, rm.reward_visits, current_reward(), shop_available() and not required_next, rm.mjolnir.anvil_available(), required_next)

## Игрок вошёл в дверь: следующий зал получит эту награду.
func choose_door(id: String) -> void:
	Perf.mark("door_choose")
	var next := rm.room_index + 1
	while rm.room_rewards.size() <= next:
		rm.room_rewards.append("")
	rm.room_rewards[next] = id
	rm.reward_visits[id] = int(rm.reward_visits.get(id, 0)) + 1
