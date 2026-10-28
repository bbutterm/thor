extends RefCounted
class_name FX
## Общие эффекты «сочности»: hit-stop, всплывающий урон, вспышки, линии молний.

static var _hitstop_left: float = 0.0
static var _hitstop_scale: float = 1.0
static var _slow_left: float = 0.0
static var _slow_scale: float = 1.0
## Зарезервированные интервалы hit-stop, по Run.combat_clock. Перекрытие не суммируется.
static var _hitstop_bookings: Array[Dictionary] = []
static var _hitstop_last_clock: float = -1.0
## Кадр, в котором последний раз менялся Engine.time_scale, и масштаб, бывший до этого в начале кадра
static var _scale_frame: int = -1
static var _scale_before: float = 1.0

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static var _fx_mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _shrink_curve: Curve

const FX_SHADERS := {
	"unshaded": preload("res://shaders/fx_unshaded.gdshader"),
	"alpha": preload("res://shaders/fx_alpha.gdshader"),
	"alpha_nocull": preload("res://shaders/fx_alpha_nocull.gdshader"),
	"glow": preload("res://shaders/fx_glow.gdshader"),
}

## В GL Compatibility выделенный блок instance-переменных занимает 16 ячеек независимо от их числа.
## Номинальный буфер на 4096 ячеек даёт до 256 блоков; запас зависит от настроек и глобальных параметров.
## Снятие материала не гарантирует освобождения блока: ранее заданные параметры могут жить до удаления RID.
## При переполнении появляется «Too many instances using shader instance variables», и эффекты теряют параметры.
const INSTANCE_SLOTS_GL := 256

static var _iu_shaders: Dictionary = {}

# --- Затухание в GL Compatibility ---
# GeometryInstance3D.transparency там не работает: узел не становится прозрачнее, и все затухания эффектов
# (вспышки, кольца, искры, ихор) обрывались, а телеграфы, лужи, огонь, лава были сплошными пятнами.
# Узлы с материалами эффектов регистрируются, и раз в кадр (FX.tick) их transparency копируется в
# instance uniform fade (shaders/fx_common.gdshaderinc, fx_sprite). В Forward+ список пуст — работает сам движок.

static var _gl: int = -1
static var _fade_nodes: Array = []

# --- VFX-комплект владельца (sprites/vfx/*): текстурные эффекты на одном шейдере ---
# Правило фризов: на текстуру — один ShaderMaterial (shaders/fx_sprite.gdshader), создаётся при прогреве
# (ShaderWarmup → warmup_sprites) и живёт до конца игры; кадр, цвет, billboard — instance uniform.
# Узлы эффектов — из пулов с лимитами (cfg().*_limit): сверх лимита переиспользуется самый старый.
# Числа — data/vfx_tuning.tres (VfxTuning).

const VFX_DIR := "res://sprites/vfx/"
const TUNING_PATH := "res://data/vfx_tuning.tres"
const SPRITE_SHADER := preload("res://shaders/fx_sprite.gdshader")
## Полосы-атласы (data/ui_manifest.json → animations): кадров по X
const STRIPS := {"hit_flash": 6, "smoke": 8, "fire": 8}
## Наборы вариантов: vfx_<имя>_01.webp … _NN.webp
const VARIANTS := {"sparks": 12, "lightning": 4, "ichor_splash": 3, "ichor_splat": 3, "ice_shard": 5}
## Одиночные текстуры
const SINGLES := ["shockwave", "ice_patch", "crack_decal_small", "crack_decal_medium", "crack_decal_large"]
## Текстуры графики мира (assets/decals/, docs/world_art) на том же шейдере: затухающие декали из пулов
## (подпалина огня/взрыва — FX.scorch, лужа браги Свена — BrewPuddle). Статичные декали — WorldArt (без instance uniform).
const EXTRA_SPRITES := {
	"scorch": "res://assets/decals/scorch.webp",
	"puddle_mead": "res://assets/decals/puddle_mead.webp",
}

## Сколько материалов эффектов создано за игру (тест: после прогрева в бою не растёт)
static var materials_created: int = 0
static var _cfg: VfxTuning
static var _sprite_mats: Dictionary = {}
static var _holder: Node3D
static var _pools: Dictionary = {}

static var _last_glint_ms: int = -100000

# --- Фасад: реализация в модулях scripts/fx/fx_*.gd (вызовы FX.xxx в игре не меняются) ---

# FXTime (fx_time.gd)

## Замедление времени на долю секунды при попадании.
## Отсчёт идёт в реальном времени через FX.tick() из автозагрузки Run.
static func hitstop(duration: float, scale: float = 0.05) -> void:
	FXTime.hitstop(duration, scale)

## Замедление конца волны идёт отдельно от hit-stop и не превращается в длинную заморозку.
## Если стоп уже идёт, все 0.3 с замедления начинаются после него.
static func slowmo(duration: float, scale: float) -> void:
	FXTime.slowmo(duration, scale)

## Вызывается каждый кадр. Run передаёт delta / текущий time_scale; пересчитываем по масштабу,
## с которым движок на самом деле умножил delta этого кадра (см. real_delta).
static func tick(passed_real_delta: float) -> void:
	FXTime.tick(passed_real_delta)

## Реальная длительность кадра по delta из _process. Движок умножает delta на time_scale, каким он был
## В НАЧАЛЕ кадра; удары (и hit-stop) случаются в физике этого же кадра. Если делить на новый 0.05,
## первый же тик насчитывал 1/60 / 0.05 = 0.33 с и стоп заканчивался в кадре, где начался.
static func real_delta(scaled_delta: float) -> float:
	return FXTime.real_delta(scaled_delta)

static func _set_time_scale(s: float) -> void:
	FXTime._set_time_scale(s)

static func reset_time() -> void:
	FXTime.reset_time()

# FXBasic (fx_basic.gd)

## Всплывающая цифра урона в мире.
static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color = Color(1, 0.9, 0.3), big: bool = false) -> void:
	FXBasic.damage_number(parent, pos, amount, color, big)

## Молния между точками: текстурные ленты vfx_lightning_01..04 (по отрезку на cfg().lightning_segment м,
## каждая повёрнута к камере вокруг своей оси) и тонкая ломаная-сердцевина. Гаснет за lifetime с мерцанием.
static func lightning(parent: Node, from: Vector3, to: Vector3, lifetime: float = 0.25, color: Color = Color(0.55, 0.85, 1.0)) -> void:
	FXBasic.lightning(parent, from, to, lifetime, color)

## Вспышка-шар (удар, приземление).
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.3) -> void:
	FXBasic.burst(parent, pos, radius, color, lifetime)

## Плоское кольцо на земле (волна удара-приземления, телеграф босса).
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.35) -> void:
	FXBasic.ring(parent, pos, radius, color, lifetime)

## Разлёт частиц: искры от ударов, пыль от приземления, щепки.
static func sparks(parent: Node, pos: Vector3, color: Color, amount: int = 14, speed: float = 6.0, gravity: float = 14.0, size: float = 0.07, lifetime: float = 0.45) -> void:
	FXBasic.sparks(parent, pos, color, amount, speed, gravity, size, lifetime)

static func make_material(color: Color, roughness: float = 0.85, emission: float = 0.0) -> StandardMaterial3D:
	return FXBasic.make_material(color, roughness, emission)

# FXShared (fx_shared.gd)

## Общий материал эффекта. Новый материал на каждую вспышку — это компиляция пайплайна при каждом
## эффекте (замерено на Forward+). Поэтому на вид эффекта — один материал, цвет и яркость задаются
## на экземпляре (fx_apply), затухание — через GeometryInstance3D.transparency.
## Виды: "unshaded", "alpha", "alpha_nocull", "glow" (освещённый, светится).
static func fx_material(kind: String) -> ShaderMaterial:
	return FXShared.fx_material(kind)

## Узлы под root с текущим override/overlay, чей шейдер совпадает с текстовым признаком _has_iu.
## Это не занятые слоты: поверхностные материалы, next_pass, сохранённые параметры и удалённые из дерева RID
## здесь не учитываются; текстовый признак также может ошибаться (диагностика: Perf F3, тесты).
static func instance_uniform_users(root: Node) -> int:
	return FXShared.instance_uniform_users(root)

static func _has_iu(m: Material) -> bool:
	return FXShared._has_iu(m)

## Назначить эффекту общий материал вида kind и задать цвет/яркость экземпляра.
static func fx_apply(gi: GeometryInstance3D, kind: String, color: Color, energy: float = 1.0) -> void:
	FXShared.fx_apply(gi, kind, color, energy)

static func uses_fade_emulation() -> bool:
	return FXShared.uses_fade_emulation()

## Раз в кадр: transparency → fade у зарегистрированных узлов (только GL Compatibility).
static func sync_fades() -> void:
	FXShared.sync_fades()

## Общие меши эффектов единичного размера (масштабируются узлом) — не строим примитив на каждую вспышку.
static func shared_mesh(kind: String) -> Mesh:
	return FXShared.shared_mesh(kind)

# FXSpriteKit (fx_sprite_kit.gd)

## Настройки VFX (data/vfx_tuning.tres; нет файла — значения по умолчанию).
static func cfg() -> VfxTuning:
	return FXSpriteKit.cfg()

## Все ключи текстурных эффектов (для прогрева и тестов).
static func sprite_keys() -> PackedStringArray:
	return FXSpriteKit.sprite_keys()

static func variant_key(set_name: String, i: int) -> String:
	return FXSpriteKit.variant_key(set_name, i)

static func random_variant(set_name: String) -> String:
	return FXSpriteKit.random_variant(set_name)

## Общий материал текстуры vfx_<key>.webp. Создаётся один раз и не умирает (иначе выкинутся пайплайны).
static func sprite_material(key: String) -> ShaderMaterial:
	return FXSpriteKit.sprite_material(key)

## Все созданные материалы текстурных эффектов (тесты).
static func sprite_materials() -> Array:
	return FXSpriteKit.sprite_materials()

## Прогрев: по квадрату каждой текстуры перед камерой (ShaderWarmup, экран затемнён) во всех режимах billboard.
static func warmup_sprites(parent: Node3D, center: Vector3, right: Vector3) -> void:
	FXSpriteKit.warmup_sprites(parent, center, right)

## Сколько узлов в пуле вида kind (тесты: не больше лимита).
static func pool_size(kind: String) -> int:
	return FXSpriteKit.pool_size(kind)

## Сколько эффектов вида kind сейчас видно.
static func pool_active(kind: String) -> int:
	return FXSpriteKit.pool_active(kind)

## Узлы пула вида kind (тесты).
static func pool_nodes(kind: String) -> Array:
	return FXSpriteKit.pool_nodes(kind)

## Узел из пула: свободный, новый (пока меньше limit) или самый старый (его эффект обрывается).
static func _take(kind: String, parent: Node, limit: int) -> MeshInstance3D:
	return FXSpriteKit._take(kind, parent, limit)

## Общий материал текстурного эффекта key узлу не из пула (лужа браги и т. п.): оттенок, кадр 0, без billboard.
static func sprite_apply(gi: GeometryInstance3D, key: String, color: Color = Color.WHITE, energy: float = 1.0) -> void:
	FXSpriteKit.sprite_apply(gi, key, color, energy)

## Оттенок и яркость текстурного эффекта (instance uniform color: rgb — оттенок, a — яркость).
## Альфа цвета → прозрачность узла (у этого шейдера альфа экземпляра занята яркостью).
static func sprite_color(gi: GeometryInstance3D, color: Color, energy: float = 1.0) -> void:
	FXSpriteKit.sprite_color(gi, color, energy)

## Параметры текстурного эффекта (instance uniform vec4 sprite): кадр, режим billboard, поворот, скорость петли.
static func set_sprite(gi: GeometryInstance3D, frame: float, billboard: int = 0, spin: float = 0.0, anim_fps: float = 0.0) -> void:
	FXSpriteKit.set_sprite(gi, frame, billboard, spin, anim_fps)

static func sprite_frame(gi: GeometryInstance3D) -> float:
	return FXSpriteKit.sprite_frame(gi)

# FXImpacts (fx_impacts.gd)

## Анимированная вспышка попадания vfx_hit_flash (6 кадров за cfg().hit_flash_time).
static func hit_flash(parent: Node, pos: Vector3, size: float, color: Color = Color(1, 0.95, 0.8)) -> void:
	FXImpacts.hit_flash(parent, pos, size, color)

## Рисованная звезда-искра (случайная из vfx_sparks_01..12): вспыхивает, крутится, гаснет.
static func spark_star(parent: Node, pos: Vector3, color: Color, size: float) -> void:
	FXImpacts.spark_star(parent, pos, color, size)

## Брызги ихора нежити (vfx_ichor_splash_01..03): вылетают и гаснут.
static func ichor_splash(parent: Node, pos: Vector3, size: float) -> void:
	FXImpacts.ichor_splash(parent, pos, size)

## Пятно ихора на полу (vfx_ichor_splat_01..03): растекается, лежит cfg().splat_life, исчезает.
## Пул cfg().splat_limit — сверх него исчезает самое старое.
static func splat(parent: Node, pos: Vector3, size: float) -> void:
	FXImpacts.splat(parent, pos, size)

## Клуб дыма vfx_smoke (8 кадров за cfg().smoke_time): смерть, взрыв.
static func smoke(parent: Node, pos: Vector3, size: float, color: Color = Color(0.85, 0.83, 0.8)) -> void:
	FXImpacts.smoke(parent, pos, size, color)

## Взрыв (enemies/blast.gd: Раздутый, элита «Взрывной», взрывная бочка, Свен): вместо плоского шара-диска —
## вспышка-ядро vfx_hit_flash, короткий огненный шар из языков vfx_fire, клубы тёмного дыма, ударная волна
## vfx_shockwave по полу на радиус урона (радиус читается), звёзды-искры. Всё — пулы и общие материалы FX.
static func explosion(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.45, 0.15)) -> void:
	FXImpacts.explosion(parent, pos, radius, color)

## Дым взрыва (enemies/blast.gd): размер от радиуса.
static func blast_smoke(parent: Node, pos: Vector3, radius: float) -> void:
	FXImpacts.blast_smoke(parent, pos, radius)

## Пыль разбитой бочки (run/barrel_watch.gd): дым коричневатого оттенка.
static func barrel_dust(parent: Node, pos: Vector3) -> void:
	FXImpacts.barrel_dust(parent, pos)

## Блеск монеты серебра при вылете (run/silver_coin.gd): звёздочка vfx_sparks_*, не чаще cfg().coin_glint_interval.
static func coin_glint(parent: Node, pos: Vector3, color: Color) -> void:
	FXImpacts.coin_glint(parent, pos, color)

## «Пуф» исчезающего трупа (enemies/parts/enemy_visual.gd → _spawn_debris, когда тело сжимается).
static func corpse_smoke(body: Node3D) -> void:
	FXImpacts.corpse_smoke(body)

## Ударная волна vfx_shockwave по полу: кольцо растёт до радиуса удара и гаснет.
static func shockwave(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.92, 0.75)) -> void:
	FXImpacts.shockwave(parent, pos, radius, color)

## Трещина на полу (vfx_crack_decal_small/medium/large — по высоте падения), лежит cfg().crack_life.
static func crack(parent: Node, pos: Vector3, height: float) -> void:
	FXImpacts.crack(parent, pos, height)

## Подпалина на полу (assets/decals/scorch): след огня (fire_zone.gd) и взрыва (blast.gd). Лежит, пока горит огонь
## (burn), и ещё cfg().scorch_life, потом исчезает. Пул cfg().scorch_limit — сверх него исчезает самая старая.
static func scorch(parent: Node, pos: Vector3, radius: float, burn: float = 0.0) -> void:
	FXImpacts.scorch(parent, pos, radius, burn)

## Удар-приземление (player.gd → _do_slam_impact): волна по радиусу удара и трещина по высоте падения.
static func slam_impact(parent: Node, center: Vector3, radius: float, height: float) -> void:
	FXImpacts.slam_impact(parent, center, radius, height)

# FXElements (fx_elements.gd)

## Языки пламени vfx_fire (петля 8 кадров) в зоне огня — дочерние узлы зоны, гаснут вместе с ней.
static func fire_sprites(zone: Node3D, radius: float, duration: float) -> Array[MeshInstance3D]:
	return FXElements.fire_sprites(zone, radius, duration)

## Ледяная элита попала по Тору (enemies/elite/ice.gd): наледь под ногами на время замедления
## и кристаллы vfx_ice_shard_* вокруг — вырастают, стоят и уходят в пол.
static func ice_hit(parent: Node, pos: Vector3, duration: float) -> void:
	FXElements.ice_hit(parent, pos, duration)

# FXEnemyHooks (fx_enemy_hooks.gd)

## Идеальный хват Мьёльнира (mjolnir_hand.gd): золотое кольцо vfx_perfect_catch на экране у руки.
static func perfect_catch(world_pos: Vector3) -> void:
	FXEnemyHooks.perfect_catch(world_pos)

## Нежить ли враг (брызги и пятна ихора): все, кроме смертных (Наёмник Локи) и ледяных (Йотунхейм).
## Переопределить — метаданные врага "ichor" (true/false).
static func is_undead(enemy: Node) -> bool:
	return FXEnemyHooks.is_undead(enemy)

## Попадание по врагу (enemy.gd → take_hit): вспышка, у нежити — брызги ихора и пятно на полу.
static func enemy_hit(enemy: Node3D, damage: float, source: String, big: bool) -> void:
	FXEnemyHooks.enemy_hit(enemy, damage, source, big)

## Смерть врага (enemy.gd → _die): у нежити — крупное пятно и брызги.
static func enemy_died(enemy: Node3D, _source: String) -> void:
	FXEnemyHooks.enemy_died(enemy, _source)
