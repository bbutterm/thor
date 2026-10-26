extends Resource
class_name PassiveDef
## Пассивка или изъян тела (GDD 6). Данные — здесь, механика — в handler (BodyTraitHandler, скрипт рядом:
## run/passives/<id>.gd), как у трейтов Мьёльнира. implemented = false — механики пока нет,
## на экране выбора тела помечается «скоро». todo — что ещё не работает (видно на экране выбора серым).

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
## Изъян (отрицательная черта), а не пассивка
@export var is_flaw: bool = false
## Механика уже работает в игре
@export var implemented: bool = false
## Что из описания ещё не работает (ждёт другие системы) — пусто, если работает всё
@export var todo: String = ""
## Обработчик хуков (on_kill, on_hit, on_damaged, on_dash, on_slam, modify…). Пусто — черта только описательная
## (например, «Мало HP» — это уже числа тела).
@export var handler: BodyTraitHandler
