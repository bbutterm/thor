extends RefCounted
class_name RunMjolnir
## Трейты Мьёльнира в забеге (блок Б4, GDD 10): правила, стихия и приёмы, уровни, несовместимость,
## связки, выбор из пула, наковальня, мини-босс.
## Компонент RunManager (этап 5 рефакторинга): числа и состояние — поля RunManager (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — Run.mjolnir; нужные снаружи функции есть и на RunManager.

var rm: RunManager

func _init(owner_node: RunManager) -> void:
	rm = owner_node

func mjolnir_trait_level(id: StringName) -> int:
	return int(rm.mjolnir_trait_levels.get(id, 0))

func rules() -> MjolnirRules:
	if rm.mjolnir_rules == null:
		rm.mjolnir_rules = MjolnirRules.new()
	return rm.mjolnir_rules

func mjolnir_trait_def(id: StringName) -> MjolnirTrait:
	for t in rm.all_mjolnir_traits + rm.all_mjolnir_combos:
		if t.id == id:
			return t
	return null

func owned_elements() -> Array[MjolnirTrait]:
	var out: Array[MjolnirTrait] = []
	for t in rm.mjolnir_traits:
		if t.is_element():
			out.append(t)
	return out

## Стихия молота (null — ещё не выбрана)
func owned_element() -> MjolnirTrait:
	var els := owned_elements()
	return els[0] if not els.is_empty() else null

func owned_techniques() -> Array[MjolnirTrait]:
	var out: Array[MjolnirTrait] = []
	for t in rm.mjolnir_traits:
		if t.is_technique():
			out.append(t)
	return out

## Активные связки: взяты и стихия, и приём связки
func active_combos() -> Array[MjolnirTrait]:
	var out: Array[MjolnirTrait] = []
	for c in rm.all_mjolnir_combos:
		if mjolnir_trait_level(c.combo_element) > 0 and mjolnir_trait_level(c.combo_technique) > 0:
			out.append(c)
	return out

## Связки, которые включатся, если взять t (для карточки «+ СВЯЗКА» на экране выбора)
func combos_completed_by(t: MjolnirTrait) -> Array[MjolnirTrait]:
	var out: Array[MjolnirTrait] = []
	if t == null or t.is_combo() or mjolnir_trait_level(t.id) > 0:
		return out
	var replaced := mjolnir_trait_conflict(t)
	for c in rm.all_mjolnir_combos:
		var other := c.combo_technique if c.combo_element == t.id else (c.combo_element if c.combo_technique == t.id else &"")
		if other != &"" and mjolnir_trait_level(other) > 0 and (replaced == null or replaced.id != other):
			out.append(c)
	return out

## Уровень lv трейта открыт в «Плане тренировок» (бывшие трейты-способы доставки: lightning_rod, sky_thunder…)
func mjolnir_level_in_pool(t: MjolnirTrait, lv: int) -> bool:
	var pid := t.level_pool_id(lv)
	return pid == "" or Save.is_in_pool("trait", pid)

## Можно ли поднять уровень взятого трейта (ларёк, повтор карточки)
func can_level_up(t: MjolnirTrait) -> bool:
	var lv := mjolnir_trait_level(t.id)
	return lv > 0 and lv < t.max_level and mjolnir_level_in_pool(t, lv + 1)

## Можно ли предложить t в выборе: новым (есть место и он открыт) или повышением уровня
func mjolnir_offer_ok(t: MjolnirTrait) -> bool:
	if t == null or t.is_combo() or not Save.is_in_pool("trait", str(t.id)):
		return false
	if mjolnir_trait_level(t.id) > 0:
		return can_level_up(t)
	if not mjolnir_level_in_pool(t, 1):
		return false
	if mjolnir_trait_conflict(t):
		return true  # заменит несовместимый (с подтверждением)
	if t.is_element():
		return owned_elements().size() < rules().max_elements
	return owned_techniques().size() < rules().max_techniques

## Активный трейт, который заменит t, или null. Приёмы — по группе и списку conflicts; стихия — только если
## стихию можно менять (MjolnirRules.element_swap) и место занято.
func mjolnir_trait_conflict(t: MjolnirTrait) -> MjolnirTrait:
	if t == null:
		return null
	for o in rm.mjolnir_traits:
		if o.id == t.id:
			continue
		if t.is_element() and o.is_element():
			if rules().element_swap and owned_elements().size() >= rules().max_elements:
				return o
			continue
		if t.is_element() or o.is_element():
			continue
		if t.conflicts_with(o):
			return o
	return null

## Выбор 1 из count (по умолчанию MjolnirRules.offer_count). kinds — только эти виды ("element" — наковальня).
## В одном наборе нет несовместимых приёмов; трейты на макс. уровне и закрытые не выпадают; уже взятый —
## повышение уровня, несовместимый — замена. Без kinds (мини-босс) — если можно и то и другое, есть оба вида.
func random_mjolnir_trait_choices(count: int = -1, kinds: Array = []) -> Array[MjolnirTrait]:
	if count < 0:
		count = rules().offer_count
	var pool: Array[MjolnirTrait] = []
	for t in rm.all_mjolnir_traits:
		if (kinds.is_empty() or t.kind in kinds) and mjolnir_offer_ok(t):
			pool.append(t)
	pool.shuffle()
	var out: Array[MjolnirTrait] = []
	if rules().mix_kinds and kinds.is_empty():
		for want in ["element", "technique"]:
			for t in pool:
				if t.kind == want:
					out.append(t)
					break
	for t in pool:
		if out.size() >= count:
			break
		if t in out:
			continue
		var clash := false
		for o in out:
			if t.conflicts_with(o) and not (t.is_element() or o.is_element()):
				clash = true
				break
		if not clash:
			out.append(t)
	while out.size() > count:
		out.pop_back()
	out.shuffle()
	return out

## Наковальня Эйтри может что-то дать: новая стихия или новый уровень своей
func anvil_available() -> bool:
	if not rules().anvil_enabled:
		return false
	for t in rm.all_mjolnir_traits:
		if t.is_element() and mjolnir_offer_ok(t):
			return true
	return false

## Взять трейт: новый — уровень 1 (несовместимый уходит), повтор — уровень выше.
## Возвращает связки, которые появились (они же — сигнал mjolnir_combo_unlocked).
func add_mjolnir_trait(t: MjolnirTrait) -> Array[MjolnirTrait]:
	Perf.mark("trait_pick")
	var before := active_combos()
	if rm.mjolnir_trait_levels.has(t.id):
		rm.mjolnir_trait_levels[t.id] = mini(mjolnir_trait_level(t.id) + 1, t.max_level)
	else:
		var old := mjolnir_trait_conflict(t)
		if old:
			rm.mjolnir_traits.erase(old)
			rm.mjolnir_trait_levels.erase(old.id)
		rm.mjolnir_traits.append(t)
		rm.mjolnir_trait_levels[t.id] = 1
	rm.mjolnir_traits_changed.emit(rm.mjolnir_traits)
	var fresh: Array[MjolnirTrait] = []
	for c in active_combos():
		if not c in before:
			fresh.append(c)
			Perf.mark("trait_combo")
			rm.mjolnir_combo_unlocked.emit(c)
	return fresh
