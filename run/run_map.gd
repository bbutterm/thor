extends Resource
class_name RunMap
## Структура мира (GDD 15.1): сколько залов, где мини-босс и ларёк, сколько дверей после зачистки,
## и числа наград за двери. Мидгард — run/maps/midgard.tres. Частоты наград — в run/rewards/*.tres.
## Логика выбора дверей — roll_offers(); состояние забега (награды залов, посещения) хранит Run.

@export var world_id: String = "midgard"
@export var title: String = "Мидгард"
## Залов в мире до босса (GDD 15.1: 7)
@export var rooms: int = 7
## Мини-босс — последней волной этого зала (номер с 1; GDD: «после 4-го зала»), за него трейт Мьёльнира
@export var miniboss_room: int = 4
## Награда первого зала (в него не входят через дверь)
@export var first_room_reward: String = "combat"

@export_group("Двери")
## Сколько дверей после зачистки (GDD 4: 2–3)
@export var doors_min: int = 2
@export var doors_max: int = 3
## Ларёк — гарантированно столько раз за мир (GDD 15.1: 1)
@export var shop_per_world: int = 1
## Самый ранний зал (номер с 1), куда может вести дверь ларька
@export var shop_earliest_room: int = 3
## Тихие залы (отдых, ларёк) не подряд
@export var no_peaceful_twice: bool = true
## Сцена зала-ларька (блок К); нет файла — ларёк не предлагается
@export var shop_scene: String = "res://rooms/shop_room.tscn"

@export_group("Небо и атмосфера")
## Панорама неба мира (equirect 2:1, assets/sky/<мир>.webp); пусто — небо сцены игры (процедурное).
## Путь, а не текстура: 4096×2048 грузится в фоне (AssetCache), а не при старте игры вместе с картой
@export_file("*.webp", "*.png", "*.jpg") var sky: String = ""
## Яркость панорамы и поворот вокруг вертикали, град (солнце панорамы — в сторону выхода)
@export var sky_energy: float = 1.0
@export var sky_rotation_deg: float = 0.0
## Экспозиция кадра (тонмаппинг): яркое небо-закат подсвечивает зал — подгоняем к прежней яркости
@export var exposure: float = 1.0
## Рассеянный свет: яркость и доля неба в нём (остальное — ambient_color)
@export var ambient_energy: float = 0.7
@export_range(0.0, 1.0) var ambient_sky_contribution: float = 1.0
@export var ambient_color: Color = Color(0.5, 0.45, 0.42)
## Дымка: цвет, плотность и насколько она закрывает небо (0 — небо чистое)
@export var fog_color: Color = Color(0.55, 0.45, 0.42)
@export var fog_density: float = 0.008
@export_range(0.0, 1.0) var fog_sky_affect: float = 1.0
## Атмосферные частицы залов (числа — data/world_art.tres): низкий туман у земли, пылинки, искры факелов и очага
@export var ground_fog: bool = false
@export var ground_fog_color: Color = Color(0.95, 0.84, 0.78, 0.3)
@export var dust_motes: bool = false
@export var torch_embers: bool = false

@export_group("Награды")
## Элитный бой: шанс элиты у каждого врага и предел элиты в зале (обычный зал — 0.1 / 1)
@export_range(0.0, 1.0) var elite_room_chance: float = 0.45
@export var elite_room_max: int = 3
## Элитный бой: серебро и Слава сверху к оружию (GDD 15.1: «оружие + 30 серебра + Слава»)
@export var elite_reward_silver: int = 30
@export var elite_reward_glory: int = 20
## Отдых: доля максимального HP (GDD 15.1: 40 %)
@export_range(0.0, 1.0) var rest_heal_fraction: float = 0.4
## Предел уровня руны (повтор руны = уровень; GDD 11: 1–3)
@export var rune_max_level: int = 3
## Благословение Фрейи: руна сразу этого уровня (GDD 15.1: 2)
@export var freya_rune_level: int = 2
## Сделка Локи: доля текущего HP за легендарное оружие (уровень 3)
@export_range(0.0, 1.0) var loki_hp_cost: float = 0.5
## Сделка Локи «кости»: шанс выигрыша (две руны), иначе — потеря доли текущего HP
@export_range(0.0, 1.0) var loki_dice_win_chance: float = 0.5
@export_range(0.0, 1.0) var loki_dice_hp_loss: float = 0.3

## Номер (с 0) зала с мини-боссом.
func miniboss_index() -> int:
	return miniboss_room - 1

## Набор дверей к залу next_index. rewards — все RewardDef, visits — сколько раз заходили (id → n),
## prev — награда зала, из которого выходим; boss_index — номер зала босса.
func roll_offers(rewards: Array, next_index: int, boss_index: int, visits: Dictionary, prev: String, shop_ok: bool) -> Array[String]:
	var out: Array[String] = []
	if next_index >= boss_index:
		out.append("boss")
		return out
	if next_index == miniboss_index():
		out.append("miniboss")
		return out
	var n := randi_range(mini(doors_min, doors_max), maxi(doors_min, doors_max))
	var peaceful_prev := false
	var pool: Array = []
	for r in rewards:
		var rd := r as RewardDef
		if rd == null or not rd.enabled:
			continue
		if rd.id == prev and not rd.combat:
			peaceful_prev = true
		if rd.weight > 0.0:
			pool.append(rd)
	# Ларёк гарантирован: пока не зашли нужное число раз — дверь ларька в каждом наборе с shop_earliest_room
	if shop_ok and int(visits.get("shop", 0)) < shop_per_world and next_index + 1 >= shop_earliest_room \
			and not (no_peaceful_twice and peaceful_prev):
		out.append("shop")
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for rd in pool:
			total += (rd as RewardDef).weight
		var x := randf() * total
		var pick: RewardDef = pool[pool.size() - 1]
		for rd in pool:
			x -= (rd as RewardDef).weight
			if x <= 0.0:
				pick = rd
				break
		pool.erase(pick)
		if no_peaceful_twice and peaceful_prev and not pick.combat:
			continue
		out.append(pick.id)
	out.shuffle()
	return out
