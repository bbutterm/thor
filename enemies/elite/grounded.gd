extends EliteHandler
## Заземлённый (С5): стихии Мьёльнира на него не действуют — ни урон стихии, ни состояния (горение, лёд, ток, ветер,
## земля). Сам молот, мили и удар-приземление бьют как обычно. Метку GROUNDED читает ElementStatus.of.

const GROUNDED := &"elite_grounded"
const ELEMENT_SOURCES := ["fire", "ice", "lightning", "earth", "wind"]

func _apply_stats() -> void:
	enemy.set_meta(GROUNDED, true)

func filter_damage(damage: float, _knockback: Vector3, source: String) -> float:
	if source in ELEMENT_SOURCES:
		Perf.mark("elite_grounded")
		return 0.0
	return damage
