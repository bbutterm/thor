extends Node3D
class_name FloorDecal
## Статичная декаль на полу из комплекта владельца (assets/decals/: подпалина, лужа, следы великана, трещина,
## пятно ихора; или светящийся рунный круг — glow): квад в плоскости XZ узла, без коллизии и тени.
## Ставит генератор (ключ "decals" у зала: [декаль, позиция, поворот Y (град), размер м, (glow)]) и разовые
## скрипты ручных арен. Вид собирается при запуске: общий меш и общий материал WorldArt, без instance uniform.
## Затухающие следы боя (огонь, взрыв, ихор, удар-приземление) — пулы FX, не этот узел.

## Ключ декали — имя файла в assets/decals/ без расширения
@export var art: String = "scorch"
## Сторона квада, м
@export var size: float = 2.0
## Светится (сложение, без света) — рунные круги
@export var glow: bool = false

func _ready() -> void:
	add_to_group("floor_decals")
	if get_child_count() > 0:
		return
	if glow:
		WorldArt.floor_circle(self, art, size)
	else:
		WorldArt.floor_decal(self, art, size)
