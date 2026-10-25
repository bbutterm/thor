# CREDITS — откуда что взято

| Что | Источник | Лицензия |
|---|---|---|
| База проекта (контроллер-основа, автозагрузка звука, звуки, прицел, модели кита) | Kenney Starter Kit FPS — https://github.com/KenneyNL/Starter-Kit-FPS | Код MIT, ассеты CC0 |
| Звуки прыжков, приземления, шагов, смерти врагов | Kenney, из Starter Kit FPS | CC0 |
| Остальные звуки (топор, молот, молния, рывок, удар-приземление, двери, руны, босс…) | Синтезированы скриптом `tools/make_sfx.py` (шум + фильтры) | свои, CC0 |
| Шрифт интерфейса Russo One | Google Fonts — https://github.com/google/fonts/tree/main/ofl/russoone | SIL OFL 1.1 (`fonts/RussoOne-OFL.txt`) |
| Шрифт для рун (ᚠ ᛗ ᚦ…) Noto Sans Runic | Google Fonts / Noto — https://github.com/google/fonts/tree/main/ofl/notosansrunic | SIL OFL 1.1 (`fonts/NotoSansRunic-OFL.txt`) |
| Движок | Godot Engine 4.6 — https://godotengine.org | MIT |
| Физика | Jolt Physics (встроен в Godot 4.6) | MIT |
| Модели врагов, оружия, залов, бочек | Сгенерированы кодом из примитивов (заглушки) | — |

Паки Quaternius из мега-промпта в этом прогоне **не использованы**: сайты itch.io / quaternius.com недоступны из среды сборки без ручного скачивания. Как подключить — см. PROGRESS.md.

Оригинальная демо-сцена кита (бластеры, летающие враги) перенесена в `_kit_original/` (Godot её не импортирует — там лежит `.gdignore`).
