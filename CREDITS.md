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
| Арбалет и болт | Собраны кодом (`scripts/weapon_meshes.gd`) | — |
| Звуки оружия (выстрелы, перезарядка, арбалет, свитч, подбор, сундук) | Синтезированы `tools/make_sfx.py` | свои, CC0 |

Текстуры Quaternius уменьшены до 1024 px, чтобы репозиторий и сборка были легче.

Оригинальная демо-сцена кита (бластеры, летающие враги) перенесена в `_kit_original/` (Godot её не импортирует — там лежит `.gdignore`).

## Портреты персонажей
- `sprites/portraits/*.webp` — аниме-портреты 12 персонажей × 5 эмоций (1024×1536, WebP), комплект предоставлен владельцем проекта (26.10.2026). Стиль — `sprites/portraits/STYLE_GUIDE.md`.

