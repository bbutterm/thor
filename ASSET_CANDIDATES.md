# Бесплатные модели-кандидаты (поиск 27.10.2026)

Критерии:
- **Лицензия.** Желательно CC0: можно продавать в Steam, не нужна атрибуция, лицензию не надо читать по пунктам. Иначе — лицензия, явно разрешающая коммерческое использование.
- **Стиль.** Стилизованный low-poly, как Quaternius, который уже в игре. Фотореализм (Poly Haven, Megascans) не подходит, кроме текстур и неба.
- **Риг.** Для персонажей важно, совместим ли он с **Universal Animation Library** (UAL). Его скелет и анимации уже используют все наши враги (`HumanoidModel`, 65 костей). Совместимый персонаж встаёт без переделки анимаций.

⚠️ Перед загрузкой в репозиторий у каждого пакета проверить лицензию на странице скачивания и положить её файл рядом с моделями. Источник записать в `CREDITS.md`.

## Уже есть у нас и не используется полностью

- **Medieval Village MegaKit (Quaternius, CC0)** — уже лежит в `assets/quaternius/village/`, 587 файлов. Сейчас из него берутся только стены, полы и текстуры. Неиспользуемые части: двери, оконные рамы, крыши (черепица, дерево, бревно), лестницы, балконы, навесы, трубы, заборы, телега. **Из этого можно прямо сейчас собрать дома «Деревни у фьорда» и длинный дом Ярла**, ничего не скачивая.
- **Fantasy Props MegaKit (Quaternius, CC0)** — у нас часть: бочки, факелы, знамёна, котёл, сундук, клетка, свечи. В полном пакете есть ещё мебель, оружие и утварь для ларька, таверны и склада медовухи.

## Мидгард (доделать нынешний мир)

| Что нужно | Кандидат | Лицензия | Подходит ли |
|---|---|---|---|
| Драккар, причал, лодки | **Quaternius Pirate Kit** (71 модель, корабли и окружение, есть анимированные персонажи) | CC0 | Стиль наш. Пиратские корабли — не драккар, но корпус и мачты можно взять, а нос-дракона, щиты по борту и парус перекрасить или собрать. Список моделей на странице не дан — скачать и посмотреть. |
| | **Quaternius Ships Pack** (старый) | CC0 | Набор кораблей, тоже проверить содержимое. |
| | **Kenney Watercraft Kit** (45+ лодок и кораблей) | CC0 | Стиль Kenney проще и «игрушечнее» нашего. Лодки для причала — да, главный корабль — вряд ли. |
| | T Allen Studios «Free Low Poly Longship» (itch.io) | Бесплатно, коммерческое использование разрешено, перераспространять модели нельзя (не CC0) | Единственный найденный настоящий драккар. FBX. Годится, если не выкладывать исходники модели. |
| Деревня, дома, рынок | **Medieval Village MegaKit** — уже есть (см. выше) | CC0 | Лучший вариант. |
| | Quaternius Medieval Village Pack (старый, 2020), Farm Buildings Pack | CC0 | Готовые цельные домики, если модульные собирать долго. |
| Колизей, арена, руины | **Quaternius Ultimate Modular Ruins Pack** (90 моделей: модульные руины, подземелья, пропсы) | CC0 | Арки, колонны, обломки — для колизея и для Йотунхейма и Хельхейма. |
| Природа (фьорд, скалы, ели) | **Quaternius Stylized Nature MegaKit** (116 моделей: 40 деревьев, 27 камней, растения; Standard и Pro — бесплатно) | CC0 | Стиль «Гибли» — мягче нашего, проверить на кадрах. Снега и льда нет. |
| | KayKit Forest Nature Pack | CC0 (бесплатный тир) | Запасной вариант. |

## Йотунхейм

| Что нужно | Кандидат | Лицензия | Подходит ли |
|---|---|---|---|
| Снежный волк (стаи) | **Quaternius Animal Pack Vol.2** — волк, орёл, собака, кот (анимированы) | CC0 | Волк есть, анимации свои (не UAL — у животных другой скелет). Белая перекраска. Орёл пригодится для воронов Одина. |
| | Quaternius Ultimate Animated Animal Pack (12 животных, 12+ анимаций каждое) | CC0 | Список животных на странице не дан — проверить, есть ли волк, медведь, олень. |
| Великаны (Хримтурс, ледяной щитоносец) | **Quaternius Bestiary — Dungeon Monsters Kit** (7 монстров с оружием, по 3 расцветки) | QAL — свободно для коммерческих проектов, бесплатно 60–70 % пакета (Standard) | **Совместим с UAL** — встанут на наш скелет и анимации. Состав монстров на странице не перечислен — проверить, есть ли тролль или огр. Лицензию QAL прочитать отдельно (это не CC0). |
| | Quaternius Ultimate Monsters (50 анимированных монстров), Animated Monster Pack, Easy Enemy Pack | CC0 | Мультяшнее нашего стиля. Скорее для морозных духов и мелочи, чем для великанов. |
| | Бесплатные тролли и огры (OpenGameArt «Troll 2», free3d «ogre») | Лицензии не указаны | Не брать, пока не прояснится лицензия. |
| Лёд, снег, сосульки | Готового бесплатного CC0-набора не нашлось. Есть: Low Poly Winter Nature Pack (nowhere0, itch.io), Low Poly Winter Forest Pack (tryall, itch.io) — бесплатно, лицензия на странице | Уточнить | **Проще сделать самим**: перекрасить камни и деревья Quaternius в снег (общий материал, как у нас) плюс процедурные сосульки. |

## Хельхейм

| Что нужно | Кандидат | Лицензия | Подходит ли |
|---|---|---|---|
| Скелеты (корм, собираются заново) | **KayKit Character Pack: Skeletons** — бесплатно: Warrior, Rogue, Mage, Minion с оружием и щитами; платно +Golem (босс-размер) и Necromancer | CC0 | **Отлично подходит по смыслу**: можно разбирать на кости. Скелет KayKit — не UAL, анимации — из бесплатного KayKit Character Animations. Стиль чуть мультяшнее Quaternius — проверить на кадрах. |
| Склеп, кладбище, костяной мост | **Kenney Graveyard Kit** (80–90 моделей: надгробия, гробы, ограды, склепы, персонажи) | CC0 | Стиль Kenney, но для пропсов годится. |
| | **KayKit Halloween Bits** (кладбище и жуть) | CC0 (бесплатный тир) | Пропсы. |
| | KayKit Dungeon Pack (модульное подземелье) | CC0 | Склеп и тронный зал Хель. |
| | Quaternius Modular Dungeon(s) Pack, Ultimate Modular Ruins | CC0 | То же, в нашем стиле. |
| Призраки, плакальщица, падшая валькирия | Бесплатного CC0 не нашлось. На маркетплейсах есть платные (RenderHub, TurboSquid) | — | **Делать из наших персонажей**: та же модель Quaternius с полупрозрачным общим материалом-призраком (оверлей, как вспышка удара) и крыльями-плоскостями для валькирии. |
| Червь Нидхёгга | Бесплатного не нашлось | — | Процедурно: цепочка сегментов (шары или цилиндры) — для «вырывается из-под земли» этого хватит. |

## Иггдрасиль и Один

- Ветви и облака — Stylized Nature MegaKit (деревья) плюс крупные процедурные ветви-платформы.
- Один — наш персонаж Quaternius (Universal Base Characters и Fantasy Outfits): шорты, свисток, плащ. Есть портрет-референс.
- Вороны — орёл из Animal Pack Vol.2, перекрашенный в чёрный.

## Тела смертных и NPC

- Сейчас все — Quaternius Universal Base Characters и Modular Character Outfits – Fantasy.
- Ещё на скелете UAL: Quaternius Ultimate Modular Men/Women Pack (CC0).
- **KayKit Adventurers** (бесплатно, CC0, 75 анимаций) — другой скелет и более мультяшный стиль. Брать, только если нравится вид.

## Текстуры, небо, звук

- **Poly Haven** и **ambientCG** — CC0-текстуры и HDRI-небо (закат Мидгарда, северное сияние Йотунхейма). Текстуры перекрасить и упростить под наш стиль.
- **Kenney** — CC0-звуки (Impact, RPG audio) как замена части синтезированных.

## Что бы я скачал первым

1. **Ничего** — сначала собрать дома деревни и длинный дом из уже лежащего Medieval Village MegaKit.
2. **Quaternius Pirate Kit** — посмотреть корабль для «Причала с драккаром». Если не подойдёт — T Allen Longship (не CC0, но с разрешением на коммерческое использование).
3. **Quaternius Bestiary** — проверить состав. Великаны на UAL дадут Йотунхейму врагов почти без работы с анимациями. Прочитать лицензию QAL.
4. **KayKit Skeletons** — для Хельхейма.
5. **Quaternius Animal Pack Vol.2** — волк для Йотунхейма и вороны.

## Источники

- Quaternius — каталог пакетов: https://quaternius.com/ (Medieval Village MegaKit, Fantasy Props MegaKit, Pirate Kit, Ships Pack, Ultimate Modular Ruins, Stylized Nature MegaKit, Bestiary — Dungeon Monsters Kit, Ultimate Monsters, Ultimate Animated Animal Pack, Ultimate Modular Men/Women)
- Quaternius Medieval Village MegaKit: https://quaternius.com/packs/medievalvillagemegakit.html
- Quaternius Pirate Kit: https://quaternius.com/packs/piratekit.html
- Quaternius Bestiary: https://quaternius.com/packs/bestiarydungeonmonsterskit.html
- Quaternius Stylized Nature MegaKit: https://quaternius.com/packs/stylizednaturemegakit.html
- Quaternius Ultimate Modular Ruins: https://quaternius.com/packs/ultimatemodularruins.html
- Quaternius Ultimate Animated Animals: https://quaternius.com/packs/ultimateanimatedanimals.html
- Quaternius Ultimate Monsters: https://quaternius.com/packs/ultimatemonsters.html
- Quaternius Animal Pack Vol.2 (волк): https://opengameart.org/content/animated-animales-low-poly
- KayKit (все пакеты): https://kaylousberg.itch.io/ — Skeletons: https://kaylousberg.itch.io/kaykit-skeletons, Adventurers: https://kaylousberg.itch.io/kaykit-adventurers, Dungeon Remastered: https://kaylousberg.itch.io/kaykit-dungeon-remastered
- Kenney Watercraft Kit: https://kenney.nl/assets/watercraft-kit, Pirate Kit: https://opengameart.org/content/pirate-kit, Graveyard Kit: https://opengameart.org/content/graveyard-kit, Castle Kit: https://kenney.nl/assets/castle-kit
- T Allen Studios, Free Low Poly Longship: https://t-allen-studios.itch.io/free-low-poly-longship
- Зимние наборы: https://nowhere0.itch.io/low-poly-winter-nature-pack, https://tryall.itch.io/low-poly-winter-forest-pack
