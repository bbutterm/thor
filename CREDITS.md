# CREDITS — откуда что взято

| Что | Источник | Лицензия |
|---|---|---|
| База проекта (контроллер-основа, автозагрузка звука, звуки, прицел, модели кита) | Kenney Starter Kit FPS — https://github.com/KenneyNL/Starter-Kit-FPS | Код MIT, ассеты CC0 |
| Звуки прыжков, приземления, шагов, смерти врагов | Kenney, из Starter Kit FPS | CC0 |
| Остальные звуки (топор, молот, молния, рывок, удар-приземление, двери, руны, босс…) | Синтезированы скриптом `tools/make_sfx.py` (шум + фильтры) | свои, CC0 |
| Шрифт интерфейса Russo One | Google Fonts — https://github.com/google/fonts/tree/main/ofl/russoone | SIL OFL 1.1 (`fonts/RussoOne-OFL.txt`) |
| Шрифт комиксовых слов-ударов Bangers | Google Fonts — https://github.com/google/fonts/tree/main/ofl/bangers (The Bangers Project Authors) | SIL OFL 1.1 (`fonts/Bangers-OFL.txt`) |
| Шрифт для рун (ᚠ ᛗ ᚦ…) Noto Sans Runic | Google Fonts / Noto — https://github.com/google/fonts/tree/main/ofl/notosansrunic | SIL OFL 1.1 (`fonts/NotoSansRunic-OFL.txt`) |
| Движок | Godot Engine 4.6 — https://godotengine.org | MIT |
| Физика | Jolt Physics (встроен в Godot 4.6) | MIT |
| Персонажи (драугры, шаманы, Хримтурс): Universal Base Characters + Modular Character Outfits – Fantasy | Quaternius — https://quaternius.com (копия: github.com/OpenAgentsInc/openagents, `assets/verse/characters/quaternius`) | CC0 (`assets/quaternius/characters/*-license.txt`) |
| Анимации персонажей: Universal Animation Library 1 и 2 (Standard) | Quaternius — https://quaternius.com/packs/universalanimationlibrary.html | CC0 |
| Стены, полы, ящики, текстуры дерева/камня: Medieval Village MegaKit (Standard) | Quaternius — https://quaternius.com/packs/medievalvillagemegakit.html (копия: github.com/Fialuxe/MouthOfGod_System) | CC0 (`assets/quaternius/village/LICENSE.txt`) |
| Бочки, факелы, знамёна: Fantasy Props MegaKit (часть) | Quaternius — https://quaternius.com/packs/fantasypropsmegakit.html (копия: github.com/OpenAgentsInc/openagents, `assets/verse/props/quaternius`) | CC0 (`assets/quaternius/props/license.txt`) |
| Оружие: топор, меч, копьё, коса, кинжал, круглый щит, лук, посох (Medieval Weapons Pack, RPG Pack), кирка (Kenney Survival Kit) | Quaternius / Kenney (копия: github.com/nrknithin/html-anime, `models/library`) — распакованы из meshopt, материалы заменены на наши | CC0 |
| Мьёльнир, дубина, вилы, факел, посох шамана | Собраны кодом (`scripts/weapon_meshes.gd`) в текстурах Quaternius | — |
| Огнестрел: пистолет, пистолет-пулемёт, автомат, обрез (Ultimate Gun Pack, FBX) | Quaternius — https://opengameart.org/content/low-poly-guns-pack (`assets/quaternius/guns/`), материалы заменены на наши | CC0 (`assets/quaternius/guns/LICENSE.txt`) |
| Корабль, причал, дома, скалы, кости (Pirate Kit, glTF) — корабль в «Причале с драккаром» | Quaternius — https://quaternius.com/packs/piratekit.html (`assets/quaternius/pirate/`) | CC0 (`assets/quaternius/pirate/LICENSE.txt`) |
| Волк, орёл (Animal Pack Vol.2, FBX) — запас для Йотунхейма и воронов, в игре пока не используются | Quaternius — https://opengameart.org/content/animated-animales-low-poly (`assets/quaternius/animals/`) | CC0 (`assets/quaternius/animals/LICENSE.txt`) |
| Скелеты Warrior/Rogue/Mage/Minion + оружие (Character Pack: Skeletons 1.1, бесплатный тир) и анимации Rig_Medium (Character Animations 1.1) — запас для Хельхейма, пока не используются | KayKit / Kay Lousberg — https://kaylousberg.itch.io/kaykit-skeletons, https://kaylousberg.itch.io/kaykit-character-animations (`assets/kaykit/`) | CC0 (`assets/kaykit/*/LICENSE.txt`) |
| Кладбище, склепы, надгробия, ограды, призрак, скелет (Graveyard Kit 5.0, GLB) — запас для Хельхейма, пока не используются | Kenney — https://kenney.nl/assets/graveyard-kit (`assets/kenney/graveyard/`) | CC0 (`assets/kenney/graveyard/LICENSE.txt`) |
| Арбалет и болт | Собраны кодом (`scripts/weapon_meshes.gd`) | — |
| Звуки оружия (выстрелы, перезарядка, арбалет, свитч, подбор, сундук) | Синтезированы `tools/make_sfx.py` | свои, CC0 |

Текстуры Quaternius уменьшены до 1024 px, чтобы репозиторий и сборка были легче.

Оригинальная демо-сцена кита (бластеры, летающие враги) перенесена в `_kit_original/` (Godot её не импортирует — там лежит `.gdignore`).

## Портреты персонажей
- `sprites/portraits/*.webp` — аниме-портреты 12 персонажей × 5 эмоций (1024×1536, WebP), комплект предоставлен владельцем проекта (26.10.2026). Стиль — `sprites/portraits/STYLE_GUIDE.md`.


| Мьёльнир (low-poly модель `Mjolnir_LP.fbx` + PBR-текстуры 2048², уменьшены до 1024²) | Прислал владелец 27.10.2026, лежит в `assets/mjolnir/` | ⚠️ **Автор и лицензия не указаны.** До релиза уточнить источник и разрешение на коммерческое использование. Без папки игра вернётся к рисованному молоту «RPG Items», без него — к процедурному. |
| Рисованное оружие «RPG Items» (топор, меч, молот — он же Мьёльнир, посох, щит; по два варианта) | Модели для Warcraft 3 (.mdx/.blp), прислал владелец 27.10.2026; конвертированы в .glb скриптом `tools/mdx2glb.py`, лежат в `assets/painted/rpg_items/` | ⚠️ **Автор и лицензия не подтверждены.** До релиза: найти автора и получить разрешение на коммерческое использование — или заменить. Отключить модели можно, убрав папку: тогда игра вернётся к Quaternius и процедурным моделям. |
