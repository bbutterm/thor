extends Area3D
class_name Ladder
## Лестница (П7, «зал как путь»): пока Тор в объёме — без гравитации, вперёд — вверх, назад — вниз
## (Player.ladder, PlayerJumps._process_gravity). Объём выше верхней площадки на top_margin, чтобы сойти на неё.
## Генератор: ключ зала "ladders" [низ, высота, поворот Y] — объём, модель-лестница из досок без коллизии.

func _ready() -> void:
	collision_layer = 1 << 5
	collision_mask = 1 << 1
	monitorable = false
	body_entered.connect(func(b: Node) -> void:
		if b is Player:
			(b as Player).ladder = self)
	body_exited.connect(func(b: Node) -> void:
		if b is Player and (b as Player).ladder == self:
			var p := b as Player
			p.ladder = null
			# Сошёл наверх — без подброса (иначе перелетает узкую площадку)
			p.velocity.y = minf(p.velocity.y, 1.5))
